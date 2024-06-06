LOGLEVEL_DEFAULT="info"


#create function for logging depending on LOGLEVEL
if [[ -z $LOGLEVEL ]]; then
  LOGLEVEL=$LOGLEVEL_DEFAULT
fi


_log() {
  messagelevel=$1
  # $1 - loglevel internal
  # $2 - message

  #if count of args is not equal 2 - set messagelevel to "debug" and message to $1
  if [[ $# -ne 2 ]]; then
    messagelevel="info"
    message=$1
  else
    messagelevel=$1
    message=$2
  fi


  if [[ $LOGLEVEL == "debug" ]]; then
    echo -e "${messagelevel^^}: ${message}"
  ##  if LOGLEVEL is info and messagelevel in list of allowed values: info|warning|critical
  elif [[ $LOGLEVEL == "info" ]] && [[ $messagelevel =~ ^(info|warning|critical)$ ]]; then
    echo -e "${messagelevel^^}: ${message}"
  elif [[ $LOGLEVEL == "warning" ]] && [[ $messagelevel =~ ^(warning|critical)$ ]]; then
    echo -e "${messagelevel^^}: ${message}"    
  elif [[ $LOGLEVEL == "critical" ]] && [[ $messagelevel =~ ^(critical)$ ]]; then
    echo -e "${messagelevel^^}: ${message}"    
  fi
}

# function return colorized output depending on $1



# modified function _log with color difference
# red for critical
# yellow for warning
# green for info
# blue for debug


_log_color() {

    #if count of args is not equal 2 - set messagelevel to "debug" and message to $1
    if [[ $# -ne 2 ]]; then
        messagelevel="info"
        message=$1
    else
        messagelevel=$1
        message=$2
    fi

    # set color depending on messagelevel
    case $messagelevel in
        debug)
            color="\e[0m"
            ;;
        info)
            color="\e[32m"
            ;;
        warning)
            color="\e[33m"
            ;;
        critical)
            color="\e[31m"
            ;;
        *)
            color="\e[0m"
            ;;
    esac

    # $1 - loglevel internal
    # $2 - message
    if [[ $LOGLEVEL == "debug" ]]; then
        echo -e "${color}${messagelevel^^}: ${message}\e[0m"
    ##  if LOGLEVEL is info and messagelevel in list of allowed values: info|warning|critical
    elif [[ $LOGLEVEL == "info" ]] && [[ $messagelevel =~ ^(info|warning|critical)$ ]]; then
        echo -e "${color}${messagelevel^^}: ${message}\e[0m"
    elif [[ $LOGLEVEL == "warning" ]] && [[ $messagelevel =~ ^(warning|critical)$ ]]; then
        echo -e "${color}${messagelevel^^}: ${message}\e[0m"    
    elif [[ $LOGLEVEL == "critical" ]] && [[ $messagelevel =~ ^(critical)$ ]]; then
        echo -e "${color}${messagelevel^^}: ${message}\e[0m"    
    fi
}


function k8s_create_namespace(){
    local kubeconfig_path=$1
    local namespace=$2

    if kubectl --kubeconfig="${kubeconfig_path}" get ns $namespace &>/dev/null; then
        return 0
    fi

    kubectl create namespace $namespace \
    --kubeconfig="${kubeconfig_path}" \
    --dry-run=client -o yaml \
    | kubectl apply -f - \
        --kubeconfig="${kubeconfig_path}" \
        1>&2

}

function add_dockerconfigjson_to_namespace() {
    local kubeconfig_path=$1
    local namespace=$2
    local secret_name=$3
    local docker_username=$4
    local docker_password=$5
    local docker_registries=$6
    local reflected=${7:-true}

    local first_docker_registry=$(echo $docker_registries | cut -d' ' -f1)

    ## check namespace is exist
    k8s_create_namespace ${kubeconfig_path} $namespace

    local json_payload=""
    local json_data=""
    json_payload=$(kubectl create secret docker-registry $secret_name \
        --kubeconfig="${kubeconfig_path}" \
        --docker-server="${first_docker_registry}" \
        --docker-username=$docker_username \
        --docker-password=$docker_password \
        --dry-run=client -o json)


    if [[ $? -eq 0 ]]; then
        json_data=$(echo $json_payload | jq -r '.data.".dockerconfigjson"' | base64 -d)
        json_auth_data=$(echo $json_data | jq -r ".auths.\"${first_docker_registry}\"")
    
        ## for each docker_registries except first one add a new registry to the auths
        for registry in $(echo $docker_registries | cut -d' ' -f2-); do
            json_data=$(echo $json_data | jq --arg registry "$registry" --argjson payload "$json_auth_data" '.auths += {$registry: $payload}')
        done
    fi

    ## replace the auths with new one
    json_payload=$(echo $json_payload | jq --arg data "$(echo $json_data | base64)" '.data[".dockerconfigjson"]=$data')

    ## apply manifest to the cluster (create secret)
    echo $json_payload | kubectl apply -f - \
    -n $namespace \
    --kubeconfig="${kubeconfig_path}" \
     1>&2

    ## if reflected then annotate the secret
    if [[ "$reflected" == "true" ]]; then
        kubectl annotate secret $secret_name \
        -n $namespace \
        --kubeconfig="${kubeconfig_path}" \
        reflector.v1.k8s.emberstack.com/reflection-allowed=true \
        reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces=".*" \
        reflector.v1.k8s.emberstack.com/reflection-auto-enabled=true \
        reflector.v1.k8s.emberstack.com/reflection-auto-namespaces=".*" \
        1>&2
    fi

    return 0
}


function k8s_install_chart {
    local kubeconfig_path=$1
    local reponame=$2
    local chartName=$3
    local chartVersion=$4
    local chartSets=$5
    

    local namespace="${chartName}"
    

    local helm_status
    
    echo "Installing ${chartName}..."

    ## create namespace if not exist
    k8s_create_namespace ${kubeconfig_path} $namespace

    
    ## 3. check current helm chart status. If status "deployed" then skip installation. Else install
    helm_status=$(helm status -n ${namespace} ${chartName} 2>/dev/null | grep STATUS | awk '{print $2}')    
    if [[ "$helm_status" == "deployed" ]]; then
        _log_color "info" "${chartName} helm chart is already deployed. Skip installation"
    else
        _log_color "info" "${chartName} helm chart is not deployed. Installing..."
        
        helm upgrade --install --wait --timeout 120s -n ${namespace} ${chartName} ${reponame} \
        --kubeconfig="${kubeconfig_path}" \
        --version "${chartVersion}" \
        --set "${chartSets}"  \
        1>&2            
    fi
}

function get_kubeconfig_by_context() {
    local kubeconfig_path=$1
    local context=$2
    
    ##check is direcotry exists else exit
    if [[ ! -d $(dirname $kubeconfig_path) ]]; then
        _log_color "critical" "Directory $(dirname $kubeconfig_path) does not exist. Exit"
        exit 1
    fi
    
    kubectl config use-context ${context:-minikube}
    kubectl config view --minify --flatten > "${kubeconfig_path}"
    return 0
}

function add_hosts {
  local ip=$1
  local host=$2
  # if we don't have correct host and ip in hosts
  if ! grep "$ip $host" /etc/hosts &>/dev/null; then
    # maybe we have only host?
    if grep " ${host}" /etc/hosts &>/dev/null; then
      # delete all incorrect records
      sudo bash -c "sed -i -n '/ ${host}/!p' /etc/hosts" 1>&2
      sudo bash -c "echo \"$ip $host\" >> /etc/hosts" 1>&2
    else
      sudo bash -c "echo \"$ip $host\" >> /etc/hosts" 1>&2
    fi
  fi
}