#!/bin/bash

set -eu

function generate_manifests {
  echo "Generating Kubernetes manifests with gomplate"

  GOMPLATE_CMD="docker run --rm -v $(pwd):/tmp hairyhenderson/gomplate@sha256:8e46d887a73ef5d90fde1f1a7d679fa94cf9f6dfc686b0b1a581858faffb1e16 \
    --template templates=/tmp/generate/templates/resources/ \
    -d common=/tmp/generate/values/common.yaml"
  TEMPLATES_DIR="/tmp/generate/templates"
  OUTPUT_DIR="/tmp/clusters"
  STAGES=("playg" "dev" "test" "prod" "e2e")

  # generate manifests for each stage
  for STAGE in "${STAGES[@]}"; do
    $GOMPLATE_CMD \
      --input-dir "$TEMPLATES_DIR/kubernetes-all" \
      --output-dir "/tmp/clusters/$STAGE" \
      -d "env=/tmp/generate/values/$STAGE.yaml" \
      -c "Values=merge:env|common"
  done

  # generate additions to e2e stage (e.g. test databases)
  $GOMPLATE_CMD \
    --input-dir "$TEMPLATES_DIR/kubernetes-e2e-only" \
    --output-dir "$OUTPUT_DIR/e2e" \
    -d "env=/tmp/generate/values/e2e.yaml" \
    -c "Values=merge:env|common"
}

function super_linter {
  echo "Running Super-Linter"

  docker run --rm -e RUN_LOCAL=true -e VALIDATE_KUBERNETES_KUBEVAL=false -e VALIDATE_JSCPD=false -v "$(pwd)":/tmp/lint github/super-linter:v4
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
