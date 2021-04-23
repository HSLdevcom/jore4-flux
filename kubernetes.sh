#!/bin/bash

set -eu

# Path where to find Kind config from.
# Can be overwritten with "--kindconfig=../path/to/config.yaml"
KIND_CONFIG="./kind-cluster.yaml"

# List of the stages and where they are hosted
AZURE_STAGES=("playg" "dev" "test" "prod")
KIND_STAGES=("e2e")

# read command line parameters
for ARGUMENT in "$@"; do
  KEY=$(echo "$ARGUMENT" | cut -f1 -d=)
  VALUE=$(echo "$ARGUMENT" | cut -f2 -d=)
  case $KEY in
    --kindconfig)
      KIND_CONFIG="$VALUE";
      ;;
  esac
done

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
    [[ "$CURRENT_CONTEXT" == "hsl-jore4-$1-cluster" ]] ||
    {
      echo >&2 "You are currently logged in to the context '$CURRENT_CONTEXT'!"
      echo >&2 "You should first log in to $1 context to continue."
      exit 1
    }
  elif [[ " ${KIND_STAGES[*]} " =~ $1 ]]; then
    [[ "$CURRENT_CONTEXT" == "kind-jore4-$1-cluster" ]] ||
    {
      echo >&2 "You are currently logged in to the context '$CURRENT_CONTEXT'!"
      echo >&2 "You should first log in to $1 context to continue."
      exit 1
    }
  else
    echo "Unknown stage: '$1'"
    exit 1
  fi

  echo "$1 context is active, no need to login"
}

function deploy_Kind_CRDs {
  # using nginx ingress controller for Kind
  # https://kind.sigs.k8s.io/docs/user/ingress/#ingress-nginx
  echo "(Re)deploying nginx ingress controller custom resource definitions to the $1 environment"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/ed5aee7659bdd9a5f018ef56ddd2de664b2d96e7/deploy/static/provider/kind/deploy.yaml

  # Have to wait for the nginx ingress controller to be ready, otherwise the JORE4 Ingress
  # deployment will fail
  echo "Waiting for ingress controller to be ready in $1 environment"
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s
}

function deploy_Azure_CRDs {
  # using built-in AGIC ingress controller for Azure (no need to install)

  echo "(Re)deploying flux custom resource definitions to the $1 environment"

  kubectl apply -f crd/flux-crd.yaml

  echo "(Re)deploying secret store custom resource definitions to the $1 environment"

  helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
  helm repo update
  helm upgrade --install csi-secrets-store csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --namespace secret-store --create-namespace --version "0.0.18"
}

function deploy_CRDs {
  check_context "$1"

  if [[ ! " ${AZURE_STAGES[*]} " =~ $1 ]]; then
    deploy_Kind_CRDs "$1"
  else
    deploy_Azure_CRDs "$1"
  fi
}

function deploy_cluster {
  check_context "$1"

  echo "(Re)deploying cluster to the $1 environment"

  # bundle and configure all resources for flux and deploy
  kustomize build "clusters/$1" | kubectl apply -f -
}

function kind_start {
  kind create cluster --name jore4-e2e-cluster --config="$KIND_CONFIG" || echo "Kind cluster is already up and running"

  # It's necessary to wait for the Kind nodes to be ready before start using them, otherwise the
  # nginx ingress controller won't find the one with the label "ingress-ready"
  echo "Waiting for Kind nodes to be ready"
  kubectl wait --for=condition=ready node --all --timeout=90s
}

function kind_stop {
  kind delete cluster --name jore4-e2e-cluster
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

  start:kind [--kindconfig=../path/to/config.yaml]
    Start a local Kubernetes cluster in Kind with the name 'jore4-e2e-cluster'. You may configure
    the path where the cluster config is found from.

  stop:kind
    Delete the 'jore4-e2e-cluster' Kind cluster.

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

kind:start)
  kind_start
  ;;

kind:stop)
  kind_stop
  ;;

help)
  usage
  ;;

*)
  usage
  ;;
esac
