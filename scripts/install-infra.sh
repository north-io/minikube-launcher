#!/bin/bash
set -E

## source common.sh in the same directory

cd "$(dirname "$0")"
source common.sh

_log_color "info" "Install infra..."


function show_help() {
    echo "Usage: $0 [options]"
    echo "Args:"
    echo "-------------------- Required --------------------"
    echo "  -u, --username        Username for docker access"
    echo "  -p, --password        Password for docker access"
    echo "-------------------- Optional --------------------"  
    echo "  --keycloak-chart-version             Keycloak chart  version"
    echo "  --helm-nexus-repo-install   Helm repository install"
    echo "  --helm-nexus-repo-name      Helm repository name"
    echo "  --helm-nexus-repo_url       Helm repository url"        
    echo "  --helm-nexus-repo-username  Helm repository username"
    echo "  --helm-nexus-repo-password  Helm repository password"
    echo "  --keycloak-operator-chart-version    Keycloak Operator chart  version"
    echo "  --redis-operator-chart-version       Redis Operator chart  version"
    echo "  --postgres-operator-chart-version    Postgres Operator chart  version"  
    echo "  --loglevel            Log level (debug|info|warning|critical). Default: info"
    echo 
    echo "  -h, --help            Show this help message and exit"
    exit 1
}


function install_helm_repo() {
    local repo_name=$1
    local repo_url=$2
    local repo_username=$3
    local repo_password=$4

    _log_color "info" "Installing helm repo..."
    _log_color "info" "helm repo add $repo_name $repo_url"
    if [[ -n "$repo_username" ]] && [[ -n "$repo_password" ]]; then
        helm repo add \
        --force-update $repo_name $repo_url \
        --username $repo_username \
        --password $repo_password
    else
        helm repo add --force-update $repo_name $repo_url
    fi

    if [[ $? -ne 0 ]]; then
        _log_color "critical" "helm repo add $repo_name $repo_url failed"
        exit 1
    fi

    ## check if repo is added
    helm repo list | grep $repo_name

    ## update repo
    helm repo update
}


main() {

    ## === Reflector ===
    local helm_reflector_repo_name="emberstack"
    local helm_reflector_repo_url="https://emberstack.github.io/helm-charts/"
    local helm_reflector_chart_version="7.1.262"
    local reflector_image_repository="docker-base.north.io/emberstack/kubernetes-reflector"
    local reflector_image_tag="7.1.262"
    local reflector_install=true

    ## === Docker Secret ===
    local username
    local password
    local docker_registries="https://docker-base.north.io/ https://docker-prod.north.io/"     
    local dockerPullSecretName="docker.north.io"   
    local dockerPullSecretEnable=true

    ## === Helm Nexus Repo ===
    local helm_nexus_repo_name="nexus-prod"
    local helm_nexus_repo_url="https://nexus.north.io/repository/helm-prod/"
    local helm_nexus_repo_install=false
    local helm_nexus_repo_username=""
    local helm_nexus_repo_password=""

    ## === Keycloak Operator ===
    local keycloakOperatorChartVersion="0.1.0"
    local keycloakHelmRepoName="${helm_nexus_repo_name}/keycloak-operator"
    local keycloakHelmChartName="keycloak-operator"

    ## === Redis Operator ===
    local redisOperatorChartVersion="3.2.8"
    local redisOperatorHelmRepoName="${helm_nexus_repo_name}/redis-operator"
    local redisOperatorHelmChartName="redis-operator"

    ## === Postgres Operator ===
    local postgresOperatorChartVersion="5.4.1"
    local postgresOperatorHelmRepoName="oci://registry.developers.crunchydata.com/crunchydata/pgo"
    local postgresOperatorHelmChartName="postgres-operator"


    local helm_status=""


    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    ## parse arguments
    # Loop through the arguments
    while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--username)
        if [ -n "$2" ]; then
            username=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
            if [[ ! $username =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
            echo "--username should be a string. Exit"
            exit 1
            fi
            shift
        else
            _log_color "critical" "Error: --username requires a value (string)."
            exit 1
        fi
        shift
        ;;

        -p|--password)
        if [ -n "$2" ]; then
            password=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
            shift
        else
            _log_color "critical" "Error: --password requires a value (string)."
            exit 1
        fi
        shift
        ;;

        --helm-nexus-repo-install)
        helm_nexus_repo_install=true
        shift
        ;;
        
        --helm-nexus-repo-name)
            if [ -n "$2" ]; then
                helm_nexus_repo_name=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $helm_nexus_repo_name =~ ^[a-zA-Z][a-zA-Z0-9-]+$ ]]; then
                echo "--helm-nexus-repo-name should be a string. Exit"
                exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --helm-nexus-repo-name requires a value (string)."
                exit 1
            fi
            shift
            ;;


        --helm-nexus-repo-username)
            if [ -n "$2" ]; then
                helm_nexus_repo_username=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $helm_nexus_repo_username =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
                echo "--helm-nexus-repo-username should be a string. Exit"
                exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --helm-nexus-repo-username requires a value (string)."
                exit 1
            fi
            shift
            ;;

        --helm-nexus-repo-password)
            if [ -n "$2" ]; then
                helm_nexus_repo_password=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                shift
            else
                _log_color "critical" "Error: --helm-nexus-repo-password requires a value (string)."
                exit 1
            fi
            shift
            ;;

        --reflector-install)
        reflector_install=true
        shift
        ;;
        

        --keycloak-operator-chart-version)
        if [ -n "$2" ]; then
            keycloakOperatorChartVersion=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
            if [[ ! $keycloakOperatorChartVersion =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "--keycloak-operator-chart-version should match a mask [d.d.d]. Exit"
            exit 1
            fi
            shift
        else
            _log_color "critical" "Error: --keycloak-operator-chart-version requires a value (string)."
            exit 1
        fi
        shift
        ;;

        --postgres-operator-chart-version)
            if [ -n "$2" ]; then
                postrgesOpratorChartVersion=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $postrgesOpratorChartVersion =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "--postgres-operator-chart-version should match a mask [d.d.d]. Exit"
                exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --postgres-operator-chart-version requires a value (string)."
                exit 1
            fi
            shift
            ;;

        --redis-operator-chart-version)
            if [ -n "$2" ]; then
                redisOperatorChartVersion=$(echo "$2" | sed 's/^"\(.*\)"$/\1/')
                if [[ ! $redisOperatorChartVersion =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "--redis-operator-chart-version should match a mask [d.d.d]. Exit"
                exit 1
                fi
                shift
            else
                _log_color "critical" "Error: --redis-operator-chart-version requires a value (string)."
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

    ## get a minikube kubeconfig
    local kubeconfig_path="${tmp_dir}/kubeconfig"
    
    get_kubeconfig_by_context ${kubeconfig_path} minikube

    ### ============================= check required arguments =============================
    ## if count of arguments is less than 2 - show help and exit
    _log_color "debug" "username: $username"
    _log_color "debug" "password: $password"

    if [[ -z "$username" ]] || [[ -z "$password" ]]; then
        show_help
        exit 1
    fi


    ## =============================  helm_nexus_repo_install =============================
        if [[ "$helm_nexus_repo_install" == "true" ]]; then

        ### check helm credentials
        if [[ -z "$helm_nexus_repo_username" ]] || [[ -z "$helm_nexus_repo_password" ]]; then
            helm_nexus_repo_username=$username
            helm_nexus_repo_password=$password
        fi

        _log_color "debug" "helm_nexus_repo_name: $helm_nexus_repo_name"
        _log_color "debug" "helm_nexus_repo_url: $helm_nexus_repo_url"
        _log_color "debug" "helm_nexus_repo_username: $helm_nexus_repo_username"
        _log_color "debug" "helm_nexus_repo_password: $helm_nexus_repo_password"


        install_helm_repo $helm_nexus_repo_name $helm_nexus_repo_url $helm_nexus_repo_username $helm_nexus_repo_password
    fi

    ## ============================= Reflector =============================
    if [[ $reflector_install == true ]]; then
        _log_color "info" "Installing reflector helm repo..."
        install_helm_repo $helm_reflector_repo_name $helm_reflector_repo_url

        _log_color "info" "Installing reflector to the cluster..."
        ## 1. create namespace
        kubectl create namespace reflector \
        --kubeconfig="${kubeconfig_path}" \
        --dry-run=client -o yaml \
        | kubectl apply -f - 1>&2

        ## 2. add dockerconfigjson to namespace
        _log_color "info" "Adding dockerconfigjson to reflector namespace..."
        add_dockerconfigjson_to_namespace ${kubeconfig_path} reflector ${dockerPullSecretName} $username $password "$docker_registries" true
        
        ## 3. check current helm chart status. If status "deployed" then skip installation. Else install
        helm_status=$(helm status -n reflector reflector 2>/dev/null | grep STATUS | awk '{print $2}')    
        if [[ "$helm_status" == "deployed" ]]; then
            _log_color "info" "Reflector helm chart is already deployed. Skip installation"
        else
            _log_color "info" "Reflector helm chart is not deployed. Installing..."
            
            helm upgrade --install --wait --timeout 120s -n reflector reflector $helm_reflector_repo_name/reflector \
            --kubeconfig="${kubeconfig_path}" \
            --version "${helm_reflector_chart_version}" \
            --set "image.repository=${reflector_image_repository}"  \
            --set "image.tag=${reflector_image_tag:-latest}"  \
            --set "imagePullSecrets[0].name=${dockerPullSecretName}" \
            1>&2            
        fi
    fi

    ## ============================= Keycloak Operator =============================
    local keycloakOperatorChartSets="vaultSecretDocker.enabled=false,\
secretDocker.enabled=false,\
imagePullSecrets[0].name=${dockerPullSecretName}"
    k8s_install_chart ${kubeconfig_path} ${keycloakHelmRepoName} ${keycloakHelmChartName} ${keycloakOperatorChartVersion} "${keycloakOperatorChartSets}"

    ## ============================= Redis Operator =============================
    local redisOperatorChartSets="vaultSecretDocker.enabled=false,\
secretDocker.enabled=false,\
imagePullSecrets[0].name=${dockerPullSecretName},\
image.repository=docker-base.north.io/redis/operator,\
image.tag=1.2.4-patch-388b3528"
    k8s_install_chart  ${kubeconfig_path} ${redisOperatorHelmRepoName} ${redisOperatorHelmChartName} ${redisOperatorChartVersion} "${redisOperatorChartSets}"

    ## ============================= Postgres Operator =============================
    local postgresOperatorChartSets="\
controllerImages.cluster=docker-base.north.io/crunchydata/postgres-operator:ubi8-5.3.1-0,\
controllerImages.upgrade=docker-base.north.io/crunchydata/postgres-operator-upgrade:ubi8-5.3.1-0,\
imagePullSecrets[0].name=${dockerPullSecretName},\
relatedImages.postgres_15.image=docker-base.north.io/crunchydata/crunchy-postgres:ubi8-15.3-3,\
relatedImages.postgres_14.image=docker-base.north.io/crunchydata/crunchy-postgres:ubi8-14.8-3,\
relatedImages."postgres_15_gis_3.3".image=docker-base.north.io/crunchydata/crunchy-postgres-gis:ubi8-15.2-3.3-0,\
relatedImages.pgbackrest.image=docker-base.north.io/crunchydata/crunchy-pgbackrest:ubi8-2.41-2,\
relatedImages.pgexporter.image=docker-base.north.io/crunchydata/crunchy-postgres-exporter:ubi8-5.3.1-0,\
relatedImages.pgupgrade.image=docker-base.north.io/crunchydata/crunchy-upgrade:ubi8-5.3.1-0"
    k8s_install_chart  ${kubeconfig_path} ${postgresOperatorHelmRepoName} ${postgresOperatorHelmChartName} ${postgresOperatorChartVersion} "${postgresOperatorChartSets}"


}

main "$@"