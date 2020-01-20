#!/bin/bash

set -e
set -x

if [[ -f "Chart.yaml" && $(cat Chart.yaml | egrep "^apiVersion:" | cut -d " " -f2- | tr -d '[:blank:]') == "v2" ]]; then
  HELM_BINARY="helm-v3"
fi

HELM_BINARY="${HELM_BINARY:=helm-v2}"
helm="$(which ${HELM_BINARY})"

# helm version
# these commands should work for both v2 and v3
helm_full_version=$(${helm} version --short --client | cut -d " " -f2)
helm_major_version=$(echo "${helm_full_version}" | cut -d "." -f1 | sed 's/[^0-9]//g')

# replace init behavior
if [[ ${helm_major_version} -eq 3 && "${1}" == "init" ]]; then
  HOME=${HELM_HOME} ${helm} repo add stable https://kubernetes-charts.storage.googleapis.com
  exit 0
fi

# re-arrange the --name argument to v3 style syntax
# remove --kube-version argument (replaced in v3 with --kube-api-versions)
if [[ ${helm_major_version} -eq 3 && "${1}" == "template" ]]; then
  TMP=("$@")
  NAME=${TMP[3]}
  TMP[1]="${NAME}"
  TMP[2]="."
  unset TMP[3]
  ARGS=$(echo "${TMP[@]}" | sed 's/--kube-version\s[\.0-9]*//g')
else
  ARGS="${@}"
fi

HOME=${HELM_HOME} ${helm} ${ARGS}
