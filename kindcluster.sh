#!/bin/bash

set -euo pipefail

# Path where to find Kind config from.
# Can be overwritten with "--kindconfig=../path/to/config.yaml"
KIND_CONFIG="./kind-cluster.yaml"

KIND_CLUSTER_NAME="jore4-local-cluster"

# read command line parameters
for ARGUMENT in "$@"; do
  KEY=$(echo "$ARGUMENT" | cut -f1 -d=)
  VALUE=$(echo "$ARGUMENT" | cut -f2 -d=)
  case $KEY in
  --kindconfig)
    KIND_CONFIG="$VALUE"
    ;;
  --cluster)
    CLUSTER_DIR="$VALUE"
    ;;
  esac
done

function kind_login {
  echo "Switching to the Kind Kubernetes context"

  kubectl config use-context "kind-$KIND_CLUSTER_NAME"
  kubectl config set-context --current --namespace=hsl-jore4
}

function check_context {
  echo "Checking whether Kind context is active"

  CURRENT_CONTEXT=$(kubectl config current-context)

  if [[ "$CURRENT_CONTEXT" != "kind-$KIND_CLUSTER_NAME" ]]; then
    echo >&2 "You are currently logged in to the context '$CURRENT_CONTEXT'!"
    echo >&2 "You should first log in to Kind Kubernetes context to continue."
    exit 1
  else
    echo "Kind context is active, no need to change"
  fi
}

function deploy_CRDs {
  check_context

  # using nginx ingress controller for Kind
  # https://kind.sigs.k8s.io/docs/user/ingress/#ingress-nginx
  echo "(Re)deploying nginx ingress controller custom resource definitions"
  NGINX_INGRESS_VERSION=ed5aee7659bdd9a5f018ef56ddd2de664b2d96e7
  kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$NGINX_INGRESS_VERSION/deploy/static/provider/kind/deploy.yaml"

  # killing the unnecessary ingress-nginx-admission webhook validation because it slows down the startup
  kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission

  # Have to wait for the nginx ingress controller to be ready, otherwise the JORE4 Ingress
  # deployment will fail
  echo "Waiting for ingress controller to be ready"
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s
}

function deploy_cluster {
  check_context

  if [[ -z "${CLUSTER_DIR:-}" ]]; then
    echo >&2 "You must define which cluster directory to deploy with the --cluster parameter!"
    exit 1
  fi

  echo "(Re)deploying applications to the cluster"

  # bundle and configure all resources
  kustomize build "$CLUSTER_DIR" | kubectl apply -f -
}

function kind_start {
  kind create cluster --name "$KIND_CLUSTER_NAME" --config="$KIND_CONFIG" || echo "Kind cluster is already up and running"

  # It's necessary to wait for the Kind nodes to be ready before start using them, otherwise the
  # nginx ingress controller won't find the one with the label "ingress-ready"
  echo "Waiting for Kind nodes to be ready"
  kubectl wait --for=condition=ready node --all --timeout=90s
}

function stop {
  kind delete cluster --name "$KIND_CLUSTER_NAME"
}

function start {
  kind_start
  deploy_CRDs
  deploy_cluster
}

function usage {
  echo "
  Usage $0 <command>

  login
    Sets the Kind Kubernetes context as active.

  check
    Checks whether the Kind Kubernetes context is active.

  deploy:crd
    Deploys the Custom Resource Definitions for the cluster. These CRDs are dependencies for the
    cluster, so should be deployed before the apps.

  deploy:cluster --cluster=../path/to/cluster
    Deploys the configured applications (e.g. hsl-jore4) to the Kind cluster from
    the selected folder

  kind:start [--kindconfig=../path/to/config.yaml]
    Start up a local Kubernetes cluster in Kind with the name '$KIND_CLUSTER_NAME'. You may
    configure the path where the cluster config is found from.

  stop
    Delete the '$KIND_CLUSTER_NAME' Kind cluster. This also kills all the running applications
    running in the cluster.

  start
    Does the full setup: starts Kind, deploys CRDs and also deploys applications.

  help
    Show this usage information
  "
}

case $1 in
login)
  kind_login
  ;;

check)
  check_context
  ;;

deploy:crd)
  deploy_CRDs
  ;;

deploy:cluster)
  deploy_cluster
  ;;

kind:start)
  kind_start
  ;;

stop)
  stop
  ;;

start)
  start
  ;;

help)
  usage
  ;;

*)
  usage
  ;;
esac
