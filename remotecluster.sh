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
# - UI_DOCKER_IMAGE env variable is defined, the ui image in the Kind cluster will be
# replaced with image in the value, e.g. UI_DOCKER_IMAGE="hsldevcom/jore4-ui:abc"
# - HASURA_DOCKER_IMAGE env variable is defined, the hasura image in the Kind cluster will be
# replaced with image in the value, e.g. HASURA_DOCKER_IMAGE="hsldevcom/jore4-hasura:def"
# - AUTH_DOCKER_IMAGE env variable is defined, the auth backend image in the Kind cluster will be
# replaced with image in the value, e.g. AUTH_DOCKER_IMAGE="hsldevcom/jore4-auth:ghi"
# - MBTILES_DOCKER_IMAGE env variable is defined, the mbtiles server image in the Kind cluster will be
# replaced with image in the value, e.g. MBTILES_DOCKER_IMAGE="hsldevcom/jore4-mbtiles-server:jkl"
# - IMPORTER_DOCKER_IMAGE env variable is defined, the jore3 importer image in the Kind cluster will be
# replaced with image in the value, e.g. IMPORTER_DOCKER_IMAGE="hsldevcom/jore4-jore3-importer:mno"
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
    name: jore4-ui
    namespace: hsl-jore4
  spec:
    template:
      spec:
        containers:
        - name: jore4-ui-image
          ${UI_DOCKER_IMAGE:+image: $UI_DOCKER_IMAGE}
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: jore4-hasura
    namespace: hsl-jore4
  spec:
    template:
      spec:
        containers:
        - name: jore4-hasura-image
          ${HASURA_DOCKER_IMAGE:+image: $HASURA_DOCKER_IMAGE}
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: jore4-auth
    namespace: hsl-jore4
  spec:
    template:
      spec:
        containers:
        - name: jore4-auth-image
          ${AUTH_DOCKER_IMAGE:+image: $AUTH_DOCKER_IMAGE}
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: jore4-mbtiles
    namespace: hsl-jore4
  spec:
    template:
      spec:
        containers:
        - name: jore4-mbtiles-image
          ${MBTILES_DOCKER_IMAGE:+image: $MBTILES_DOCKER_IMAGE}
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: jore4-jore3importer
    namespace: hsl-jore4
  spec:
    template:
      spec:
        containers:
        - name: jore4-jore3importer-image
          ${IMPORTER_DOCKER_IMAGE:+image: $IMPORTER_DOCKER_IMAGE}
EOT

echo "Downloading Kind config"
curl "https://raw.githubusercontent.com/HSLdevcom/jore4-flux/$E2E_SCRIPTS_VERSION/kind-cluster.yaml" --output "$tmp_dir/kind-cluster.yaml"

echo "Starting Kind and deploying the cluster"
"$tmp_dir/kindcluster.sh" start --kindconfig="$tmp_dir/kind-cluster.yaml" --cluster="$tmp_dir"
