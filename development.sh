#!/bin/bash
echo bla
set -eu

function generate_manifests {
  echo "Cleanup generated manifests"
  rm -rf ./clusters

  echo "Generating Kubernetes manifests with gomplate"

  TEMPLATES_DIR="/tmp/generate/templates"
  VALUES_DIR="/tmp/generate/values"
  OUTPUT_DIR="/tmp/clusters"

  AZURE_STAGES=("playg" "dev" "test" "prod")
  LOCAL_STAGES=("e2e")
  ALL_STAGES=("${AZURE_STAGES[@]}" "${LOCAL_STAGES[@]}")

  GOMPLATE_CMD="docker run --rm -v $(pwd):/tmp hairyhenderson/gomplate@sha256:8e46d887a73ef5d90fde1f1a7d679fa94cf9f6dfc686b0b1a581858faffb1e16 \
    --template templates=$TEMPLATES_DIR/resources/ \
    -d common=$VALUES_DIR/common.yaml"

  # generate default manifests for all stages
  for STAGE in "${ALL_STAGES[@]}"; do
    $GOMPLATE_CMD \
      --input-dir "$TEMPLATES_DIR/kubernetes-all" \
      --output-dir "$OUTPUT_DIR/$STAGE" \
      -d "env=$VALUES_DIR/$STAGE.yaml" \
      -c "Values=merge:env|common"
  done

  # generate additions to azure stages (e.g. flux sync)
  for STAGE in "${AZURE_STAGES[@]}"; do
    $GOMPLATE_CMD \
      --input-dir "$TEMPLATES_DIR/kubernetes-azure-only" \
      --output-dir "$OUTPUT_DIR/$STAGE" \
      -d "env=$VALUES_DIR/$STAGE.yaml" \
      -c "Values=merge:env|common"
  done

  # generate additions to local stages (e.g. test databases)
  for STAGE in "${LOCAL_STAGES[@]}"; do
    $GOMPLATE_CMD \
      --input-dir "$TEMPLATES_DIR/kubernetes-local-only" \
      --output-dir "$OUTPUT_DIR/$STAGE" \
      -d "env=$VALUES_DIR/$STAGE.yaml" \
      -c "Values=merge:env|common"
  done

  echo "Generating docker-compose file and secrets with gomplate"

  $GOMPLATE_CMD \
    --input-dir "$TEMPLATES_DIR/docker-compose" \
    --output-dir "$OUTPUT_DIR/docker-compose" \
    -d "env=$VALUES_DIR/e2e.yaml" \
    -c "Values=merge:env|common"
}

function super_linter {
  echo "Running Super-Linter"

  docker run --rm -e RUN_LOCAL=true -e VALIDATE_KUBERNETES_KUBEVAL=false -e VALIDATE_JSCPD=false -e VALIDATE_GITHUB_ACTIONS=false -v "$(pwd)":/tmp/lint github/super-linter:v4
}

function toc {
  echo "Refreshing Table of Contents"

  npx doctoc README.md
}

function usage {
  echo "
  Usage $0 <command>

  generate
    Generates Kubernetes and docker-compose manifests for all stages using gomplate yaml templates.

  lint
    Runs Github's Super-Linter for the whole codebase to lint all files.

  toc
    Refreshes the Table of Contents in the README.

  help
    Show this usage information
  "
}

case $1 in
generate)
  generate_manifests
  ;;

lint)
  super_linter
  ;;

toc)
  toc
  ;;

help)
  usage
  ;;

*)
  usage
  ;;
esac
