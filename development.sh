#!/bin/bash

set -eu

function generate_kustomize_patches {
  echo "Generating Kustomize patches with gomplate"

  GOMPLATE_CMD="docker run --rm -v $(pwd):/tmp hairyhenderson/gomplate@sha256:8e46d887a73ef5d90fde1f1a7d679fa94cf9f6dfc686b0b1a581858faffb1e16"
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kustomize-patches --output-dir /tmp/clusters/playg --context Values=/tmp/generate/values/playg.yaml
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kustomize-patches --output-dir /tmp/clusters/dev --context Values=/tmp/generate/values/dev.yaml
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kustomize-patches --output-dir /tmp/clusters/test --context Values=/tmp/generate/values/test.yaml
  $GOMPLATE_CMD --input-dir /tmp/generate/templates/kustomize-patches --output-dir /tmp/clusters/prod --context Values=/tmp/generate/values/prod.yaml
  $GOMPLATE_CMD --template templates=/tmp/generate/templates/resources/ --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/playg -c "Values=merge:common|env" -d "common=/tmp/generate/values/common.yaml" -d "env=/tmp/generate/values/playg.yaml"
  $GOMPLATE_CMD --template templates=/tmp/generate/templates/resources/ --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/dev -c "Values=merge:common|env" -d "common=/tmp/generate/values/common.yaml" -d "env=/tmp/generate/values/dev.yaml"
  $GOMPLATE_CMD --template templates=/tmp/generate/templates/resources/ --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/test -c "Values=merge:common|env" -d "common=/tmp/generate/values/common.yaml" -d "env=/tmp/generate/values/test.yaml"
  $GOMPLATE_CMD --template templates=/tmp/generate/templates/resources/ --input-dir /tmp/generate/templates/kubernetes --output-dir /tmp/clusters/prod -c "Values=merge:common|env" -d "common=/tmp/generate/values/common.yaml" -d "env=/tmp/generate/values/prod.yaml"
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
