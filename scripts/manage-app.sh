#!/bin/bash
set -E

## source common.sh in the same directory

cd "$(dirname "$0")"
source common.sh

CMD="install"   
PRODUCT="neoon"
DOMAIN="https://neoon.local"
ENVID="local"
TENANT="neoon"
VERSION="0.2.2"
CLUSTERROLE_CHART_VERSION="${ENV_CLUSTERROLE_CHART_VERSION:-1.0.0}"

function create_cert {
    local namespace=${1}
    local host=${2}
    local tmp_dir=${3}
    local kubeconfig_path=${4}

    mkcert -cert-file ${tmp_dir}/cert.pem -key-file ${tmp_dir}/key.pem "*.${host}" "${host}" 1>&2
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    mkcert --install 1>&2
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    kubectl delete secret tls "${host}" \
        --namespace ${namespace} \
        --kubeconfig="${kubeconfig_path}" \
        --ignore-not-found \
        1>&2

    if [[ $? -ne 0 ]]; then
    exit 1
    fi
    kubectl create secret tls "${host}" \
        --namespace ${namespace} \
        --kubeconfig="${kubeconfig_path}" \
        --key ${tmp_dir}/key.pem \
        --cert ${tmp_dir}/cert.pem \
        1>&2
    if [[ $? -ne 0 ]]; then
    exit 1
  fi
}

function install_app(){
    local product=$1
    local domain=$2
    local envID=$3
    local tenant=$4
    local version=$5
    local helm_repo_name=$6
    local temp_dir=$7
    local kubeconfig_path=$8
    local env=$9
    local chartSets=${10}
    local action=${11}

    local namespace=${product}-${envID}
    local host=$(echo ${domain} | sed 's/https:\/\///')    
    local helm_status=$(helm status -n ${namespace} ${product} 2>/dev/null | grep STATUS | awk '{print $2}') 

    ## 1. check current helm chart clusterrole status. If status "deployed" then skip installation. Else install
    helm_status=$(helm status -n kube-public clusterrole 2>/dev/null | grep STATUS | awk '{print $2}')    
    if [[ "$helm_status" == "deployed" ]]; then
        _log_color "info" "clusterrole helm chart is already deployed. Skip installation"
    else
        _log_color "info" "clusterrole helm chart is not deployed. Installing in kube-public namespace..."

        helm upgrade --install --wait --timeout 100s -n kube-public clusterrole ${helm_repo_name}/clusterrole \
            --kubeconfig="${kubeconfig_path}" \
            --version "${CLUSTERROLE_CHART_VERSION:-1.0.0}" \
            1>&2  
    fi  
    
    ## 2. Install or update helm chart product
    ## if action=="install" then create a namespace
    if [[ "${action}" == "install" ]]; then
        if [[ "$helm_status" == "deployed" ]]; then
            _log_color "info" "${product^} helm chart is already deployed. Skip installation"
            return 1
        else
            k8s_create_namespace ${kubeconfig_path} ${namespace}
            create_cert ${namespace} ${host} ${temp_dir}  ${kubeconfig_path}

            _log_color "info" "${product} helm chart is not deployed. Installing..."
        fi
    elif [[ "${action}" == "update" ]]; then
        ##  get a version of already installed helm chart
        helm_current_version=$(helm list -n ${namespace} -o json | grep ${product} | jq '.[]'.chart | xargs | awk -F '-' '{print $NF}')   
        echo "helm_current_version: $helm_current_version"

        if [[ $(echo "${version} ${helm_current_version}" | awk '{ if ($1 <= $2) print "true"; else print "false" }') == "true" ]]; then
            _log_color "warning" "The current version ${helm_current_version} of the installed helm chart is greater than or equal to the new version ${version} of the helm chart to be installed. Skip installation"
            return 1
        else
            _log_color "info" "Updating ${PRODUCT} from version=${helm_current_version} to the new version=${version}..."
        fi
    else
        _log_color "critical" "Unknown manage-app action [${action}]. Exit."
        return 1
    fi

    ## install or update helm chart
    _log_color "debug" "helm upgrade --install --wait --timeout 1200s -n ${namespace} ${product} ${helm_repo_name}/${product} \
    --kubeconfig=\"${kubeconfig_path}\" \
    --version \"${version}\" \
    --set \"${chartSets}\"  \
    --values ${temp_dir}/${product}/values.yaml \
    --values values/minikube-values.yalm \
    --values ${temp_dir}/${product}/release.yaml \
    1>&2"

    helm upgrade --install --wait --timeout 1200s -n ${namespace} ${product} ${helm_repo_name}/${product} \
    --kubeconfig="${kubeconfig_path}" \
    --version "${version}" \
    --set "${chartSets}"  \
    --values ${temp_dir}/${product}/values.yaml \
    --values values/minikube-values.yaml \
    --values ${temp_dir}/${product}/release.yaml \
    1>&2 

}


function delete_app(){
    local product=$1
    local domain=$2
    local envID=$3
    local tenant=$4
    local version=$5
    local kubeconfig_path=$6

    local namespace=${product}-${envID}

     _log_color "info" "${product} helm chart will be deleted."
    
    ## delete app helm
    helm delete ${product} \
        --wait \
        --timeout 200s \
        --namespace ${namespace} \
        --kubeconfig="${kubeconfig_path}" \
        1>&2
    
    ## delete clusterrole helm
    helm delete clusterrole \
        --wait \
        --timeout 200s \
        --namespace kube-public \
        --kubeconfig="${kubeconfig_path}" \
        1>&2 
    
    ## delete namespace
    kubectl delete namespace $namespace \
        --kubeconfig="${kubeconfig_path}" \
        --force \
        --grace-period=0 \
        1>&2
}

function show_help() {
    echo "Usage: $0 [options]"
    echo "Args:"
    echo "-------------------- Required --------------------"
    echo "  -c, --command   Command (install|delete|update|recreate). Default: install"
    echo "  -p, --product           Product name. Default: neoon"
    echo "  -d, --domain            Domain name. Default: https://neoon.local"
    echo "  -e, --envID             Environment ID. Default: local"
    echo "  -t, --tenant            Tenant name. Default: neoon"
    echo "  -v, --version           Version. Default: 0.2.2"
    echo "  --loglevel            Log level (debug|info|warning|critical). Default: info"    
    echo 
    echo "  -h, --help            Show this help message and exit"
    exit 1
}

main() {

    ## === Helm Nexus Repo ===
    local helm_nexus_repo_name="nexus-prod"

    local tmp_dir
    local env
    local minikube_ip


    ## parse arguments
    # Loop through the arguments
    while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--command)
            if [ -n "$2" ]; then
                CMD=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $CMD =~ ^(install|delete|update|recreate)$ ]]; then
                _log_color "critical" "--command should be in list of allowed values: install|delete|update|recreate . Exit"
                exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --command requires a value (string)."
                exit 1
            fi
            shift
            ;;
      
        -p|--product)
            if [ -n "$2" ]; then
                PRODUCT=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $PRODUCT =~ ^(neoon|geodaas)$ ]]; then
                _log_color "critical" "--command should be in list of allowed values: neoon|geodaas . Exit"
                exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --product requires a value (string)."
                exit 1
            fi
            shift
            ;;

        -d|--domain)
            if [ -n "$2" ]; then
                DOMAIN=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                shift
            else
                _log_color "critical" "Error: --domain requires a value (string)."
                exit 1
            fi
            shift
            ;;

        -e|--envID)
            if [ -n "$2" ]; then
                ENVID=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $ENVID =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
                    echo "--envID should be a string. Exit"
                    exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --envID requires a value (string)."
                exit 1
            fi
            shift
            ;;

        -t|--tenant)
            if [ -n "$2" ]; then
                TENANT=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $TENANT =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
                    echo "--tenant should be a string. Exit"
                    exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --tenant requires a value (string)."
                exit 1
            fi
            shift
            ;;            

        -v|--version)
            if [ -n "$2" ]; then
                VERSION=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "--version should match a mask [d.d.d]. Exit"
                exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --versionn requires a value (string)."
                exit 1
            fi
            shift
            ;;

        --loglevel)
            # Check if an option value is provided
            if [ -n "$2" ]; then
                LOGLEVEL=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $LOGLEVEL =~ ^(debug|info|warning|critical)$ ]]; then
                _log_color "critical" "--loglevel should be in list of allowed values: debug|info|warning|critical. Exit"
                exit 1
                fi
                shift
            fi
            shift
            ;;

        -h|--help)
            show_help
            exit 0
            ;;

        *)
            _log_color "critical"ho "Unknown argument: $1"
            exit 1
            ;;
    esac
    done

    _log_color "info" "${CMD} application ${PRODUCT}\n Domain:${DOMAIN}\n EnvID:${ENVID}\n Tenant:${TENANT}\n Version:${VERSION}"

    ## === Neoon ===
    local namespace=${PRODUCT}-${ENVID}
    local chartSets
    local host=$(echo ${DOMAIN} | sed 's/https:\/\///')

    chartSets="global.envId=${ENVID},\
global.ingHost=${host},\
global.theme=neoon"

    ## ===================


    ## create a temporary directory
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    ## get a minikube kubeconfig
    local kubeconfig_path="${tmp_dir}/kubeconfig"
    get_kubeconfig_by_context ${kubeconfig_path} minikube    

    ## check ARGS
    if [[ -z $CMD ]]; then
        _log_color "critical" "CMD is required."
        exit 1
    fi

    env=minikube


    if [[ $env == 'minikube' ]]; then
        if [[ `which mkcert &>/dev/null` ]]; then
            _log_color "critical" "MKCERT is not installed. Please install it first."
            exit 1
        fi
    fi

    if [ -z "$VERSION" ] || [ "$VERSION" == "null" ]; then
        _log_color "critical" "Error: Version is required. Exit."            
    fi

    ## 1. download helm charts to the temporary directory
    _log_color "info" "Downloading helm charts version ${VERSION}..."
    helm repo update 1>&2
    helm pull ${helm_nexus_repo_name}/${PRODUCT} --version "${VERSION}" --untar  --untardir ${tmp_dir} 1>&2

    ## 2. manage an app
    case $CMD in
        install)
            # echo "ChartSets: $chartSets"
            install_app ${PRODUCT} ${DOMAIN} ${ENVID} ${TENANT} ${VERSION} ${helm_nexus_repo_name} ${tmp_dir} ${kubeconfig_path} ${env} "${chartSets}" "${CMD}"
            minikube_ip=$(minikube ip)
            add_hosts ${minikube_ip} ${host}
            ;;
        delete)
            delete_app ${PRODUCT} ${DOMAIN} ${ENVID} ${TENANT} ${VERSION} ${kubeconfig_path}
            ;;
        update)
            install_app ${PRODUCT} ${DOMAIN} ${ENVID} ${TENANT} ${VERSION} ${helm_nexus_repo_name} ${tmp_dir} ${kubeconfig_path} ${env} "${chartSets}" "${CMD}"
            ;;
        recreate)
            _log_color "info" "Recreating ${PRODUCT}..."
            delete_app ${PRODUCT} ${DOMAIN} ${ENVID} ${TENANT} ${VERSION} ${kubeconfig_path}
            install_app ${PRODUCT} ${DOMAIN} ${ENVID} ${TENANT} ${VERSION} ${helm_nexus_repo_name} ${tmp_dir} ${kubeconfig_path} ${env} "${chartSets}" "install"
            ;;
        *)
            _log_color "critical" "Unknown product: ${PRODUCT}. Exit"
            exit 1
            ;;
    esac


}

main "$@"