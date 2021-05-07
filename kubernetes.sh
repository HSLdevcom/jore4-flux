#!/bin/bash

set -eu

# List of the allowed stages
AZURE_STAGES=("playg" "dev" "test" "prod")

function az_login {
  echo "Logging in the $1 environment"

  az login
  az account set --subscription "jore4"
  az aks get-credentials --resource-group "hsl-jore4-$1" --name "hsl-jore4-$1-cluster" --overwrite-existing
  kubectl config set-context --current --namespace=hsl-jore4
}

function check_context {
  echo "Checking whether $1 context is active"

  CURRENT_CONTEXT=$(kubectl config current-context)

  if [[ " ${AZURE_STAGES[*]} " =~ $1 ]]; then
    if [[ "$CURRENT_CONTEXT" != "hsl-jore4-$1-cluster" ]]; then
      echo >&2 "You are currently logged in to the context '$CURRENT_CONTEXT'!"
      echo >&2 "You should first log in to $1 context to continue."
      exit 1
    else
      echo "$1 context is active, no need to login"
    fi
  else
    echo "Unknown stage: '$1'"
    exit 1
  fi
}

function deploy_CRDs {
  check_context "$1"

  echo "(Re)deploying flux custom resource definitions to the $1 environment"

  kubectl apply -f crd/flux-crd.yaml

  echo "(Re)deploying secret store custom resource definitions to the $1 environment"

  helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
  helm repo update
  helm upgrade --install csi-secrets-store csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --namespace secret-store --create-namespace --version "0.0.18"
}

function deploy_cluster {
  check_context "$1"

  echo "(Re)deploying cluster to the $1 environment"

  # bundle and configure all resources for flux and deploy
  kustomize build "clusters/$1" | kubectl apply -f -
}

function usage {
  echo "
  Usage $0 <command>

  login [<stage>]
    Logs in to Azure and to the selected Kubernetes environment context.

  check [<stage>]
    Checks whether you are currently logged in to the given context.

  deploy:crd [<stage>]
    Deploys the Custom Resource Definitions for the cluster. These CRDs are dependencies for the
    cluster, so should be deployed before the apps.

  deploy:cluster [<stage>]
    Deploys fluxcd and all the configured applications (e.g. hsl-jore4) for the selected
    environment. Flux automatically redeploys itself and/or the apps when the cluster yaml
    configuration changes.

  help
    Show this usage information
  "
}

case $1 in
login)
  az_login "$2"
  ;;

check)
  check_context "$2"
  ;;

deploy:crd)
  deploy_CRDs "$2"
  ;;

deploy:cluster)
  deploy_cluster "$2"
  ;;

help)
  usage
  ;;

*)
  usage
  ;;
esac
