#!/bin/bash

set -eu

# Path where to find Kind config from.
# Can be overwritten with "--kindconfig=../path/to/config.yaml"
KIND_CONFIG="./kind-cluster.yaml"

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

  kubectl config use-context kind-jore4-local-cluster
  kubectl config set-context --current --namespace=hsl-jore4
}

function check_context {
  echo "Checking whether Kind context is active"

  CURRENT_CONTEXT=$(kubectl config current-context)

  if [[ "$CURRENT_CONTEXT" != "kind-jore4-local-cluster" ]]; then
    echo >&2 "You are currently logged in to the context '$CURRENT_CONTEXT'!"
    echo >&2 "You should first log in to Kind Kubernetes context to continue."
    exit 1
  else
    echo "kind-jore4-local-cluster context is active, no need to change"
  fi
}

function deploy_CRDs {
  check_context

  # using nginx ingress controller for Kind
  # https://kind.sigs.k8s.io/docs/user/ingress/#ingress-nginx
  echo "(Re)deploying nginx ingress controller custom resource definitions"
  NGINX_INGRESS_VERSION=ed5aee7659bdd9a5f018ef56ddd2de664b2d96e7
  kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$NGINX_INGRESS_VERSION/deploy/static/provider/kind/deploy.yaml"

  # Have to wait for the nginx ingress controller to be ready, otherwise the JORE4 Ingress
  # deployment will fail
  echo "Waiting for ingress controller to be ready"
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s
}

function deploy_cluster {
  check_context

  if [[ -z "${CLUSTER_DIR:-}" ]]; then
    echo >&2 "You must define which cluster directory to deploy with the --cluster parameter!"
    exit 1
  fi

  echo "(Re)deploying applications to the cluster"

  # bundle and configure all resources for flux and deploy
  kustomize build "$CLUSTER_DIR" | kubectl apply -f -
}

function kind_start {
  kind create cluster --name jore4-local-cluster --config="$KIND_CONFIG" || echo "Kind cluster is already up and running"

  # It's necessary to wait for the Kind nodes to be ready before start using them, otherwise the
  # nginx ingress controller won't find the one with the label "ingress-ready"
  echo "Waiting for Kind nodes to be ready"
  kubectl wait --for=condition=ready node --all --timeout=90s
}

function kind_stop {
  kind delete cluster --name jore4-local-cluster
}

function setup_all {
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
    Start a local Kubernetes cluster in Kind with the name 'jore4-local-cluster'. You may configure
    the path where the cluster config is found from.

  kind:stop
    Delete the 'jore4-local-cluster' Kind cluster.

  setup:all
    Does the full setup: starts kind, deploys CRDs and also deploys applications.

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
  deploy_cluster "$2"
  ;;

kind:start)
  kind_start
  ;;

kind:stop)
  kind_stop
  ;;

setup:all)
  setup_all
  ;;

help)
  usage
  ;;

*)
  usage
  ;;
esac
