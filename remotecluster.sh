#!/bin/bash

set -euo pipefail

# the ref/branch where the e2e cluster scripts can be found from
E2E_SCRIPTS_VERSION=${E2E_SCRIPTS_VERSION:-e2e}
echo "E2E_SCRIPTS_VERSION=$E2E_SCRIPTS_VERSION"

echo "Creating temporary directory for cluster definition"
tmp_dir=$(mktemp -d e2e-kustomize-XXXXXXXXXX)

# Making sure that the temp directory is cleaned up even if the script fails
cleanup() {
  echo "Cleaning up"
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "Downloading helper script"
curl "https://raw.githubusercontent.com/HSLdevcom/jore4-flux/$E2E_SCRIPTS_VERSION/kindcluster.sh" --output "$tmp_dir/kindcluster.sh"
chmod u+x "$tmp_dir/kindcluster.sh"

# Loading the base e2e cluster definition, then patch it:
# - FRONTEND_DOCKER_IMAGE env variable is defined, the frontend image in the Kind cluster will be
# replaced with image in the value, e.g. FRONTEND_DOCKER_IMAGE="hsldevcom/jore4-ui:abc"
# - BACKEND_DOCKER_IMAGE env variable is defined, the frontend image in the Kind cluster will be
# replaced with image in the value, e.g. BACKEND_DOCKER_IMAGE="hsldevcom/jore4-backend:def"
echo "Customizing cluster definition"
cat <<EOT >"$tmp_dir/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # have to use the go-getter url format: https://github.com/hashicorp/go-getter#url-format
  - github.com/HSLdevcom/jore4-flux/clusters/e2e?ref=$E2E_SCRIPTS_VERSION

patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: jore4-frontend
    namespace: hsl-jore4
  spec:
    template:
      spec:
        containers:
        - name: jore4-frontend-image
          ${FRONTEND_DOCKER_IMAGE:+image: $FRONTEND_DOCKER_IMAGE}
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: jore4-backend
    namespace: hsl-jore4
  spec:
    template:
      spec:
        containers:
        - name: jore4-backend-image
          ${BACKEND_DOCKER_IMAGE:+image: $BACKEND_DOCKER_IMAGE}
EOT

echo "Downloading Kind config"
curl "https://raw.githubusercontent.com/HSLdevcom/jore4-flux/$E2E_SCRIPTS_VERSION/kind-cluster.yaml" --output "$tmp_dir/kind-cluster.yaml"

echo "Starting Kind and deploying the cluster"
"$tmp_dir/kindcluster.sh" start --kindconfig="$tmp_dir/kind-cluster.yaml" --cluster="$tmp_dir"
