#!/bin/bash

set -eu

function generate_kustomize_patches {
  echo "Generating Kubernetes manifests with gomplate"

  GOMPLATE_CMD="docker run --rm -v $(pwd):/tmp hairyhenderson/gomplate@sha256:8e46d887a73ef5d90fde1f1a7d679fa94cf9f6dfc686b0b1a581858faffb1e16 --template templates=/tmp/generate/templates/resources/ -c \"Values=merge:common|env\" -d \"common=/tmp/generate/values/common.yaml\""
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/e2e -d "env=/tmp/generate/values/e2e.yaml"
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/playg -d "env=/tmp/generate/values/playg.yaml"
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/dev -d "env=/tmp/generate/values/dev.yaml"
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/test -d "env=/tmp/generate/values/test.yaml"
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/prod -d "env=/tmp/generate/values/prod.yaml"

  echo "Generating docker-compose file with gomplate"
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/docker-compose --output-dir /tmp/clusters/docker-compose -d "env=/tmp/generate/values/e2e.yaml"
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
    Generates Kustomize patches for playg, dev, test and prod stages using gomplate yaml templates.

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
  generate_kustomize_patches
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
