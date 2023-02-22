#!/bin/bash

## specially handled ENV vars
# HELM_BINARY - custom path to helm binary
# HELM_TEMPLATE_OPTIONS - helm template --help
# HELMFILE_BINARY - custom path to helmfile binary
# HELMFILE_GLOBAL_OPTIONS - helmfile --help
# HELMFILE_TEMPLATE_OPTIONS - helmfile template --help
# HELMFILE_HELMFILE - a complete helmfile.yaml (ignores standard helmfile.yaml and helmfile.d if present based on strategy)
# HELMFILE_HELMFILE_STRATEGY - REPLACE or INCLUDE
# HELMFILE_INIT_SCRIPT_FILE - path to script to execute during the init phase
# HELMFILE_CACHE_CLEANUP - run helmfile cache cleanup on init
# HELMFILE_USE_CONTEXT_NAMESPACE - do not set helmfile namespace to ARGOCD_APP_NAMESPACE (for multi-namespace apps)
# HELM_DATA_HOME - perform variable expansion

# NOTE: only 1 -f value/file/dir is used by helmfile, while you can specific -f multiple times
# only the last one matters and all previous -f arguments are irrelevant

# NOTE: helmfile pukes if both helmfile.yaml and helmfile.d are present (and -f isn't explicity used)

## standard build environment
## https://argoproj.github.io/argo-cd/user-guide/build-environment/
# ARGOCD_APP_NAME - name of application
# ARGOCD_APP_NAMESPACE - destination application namespace.
# ARGOCD_APP_REVISION - the resolved revision, e.g. f913b6cbf58aa5ae5ca1f8a2b149477aebcbd9d8
# ARGOCD_APP_SOURCE_PATH - the path of the app within the repo
# ARGOCD_APP_SOURCE_REPO_URL the repo's URL
# ARGOCD_APP_SOURCE_TARGET_REVISION - the target revision from the spec, e.g. master.

## cmp
# - https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/
# - https://github.com/argoproj/argo-cd/blob/master/docs/proposals/parameterized-config-management-plugins.md
# - https://github.com/argoproj/argo-cd/blob/master/docs/proposals/parameterized-config-management-plugins.md#how-will-the-cmp-know-what-parameter-values-are-set
#
# if parameter is absent in the application spec (not present), ENV var is not set at all
# boolean params are currently (2.6) still free-form strings to the user

# each manifest generation cycle calls git reset/clean before (between init and generate it is NOT ran)
# init is called before every manifest generation
# it can be used to download dependencies, etc, etc

# does not have "v" in front
# KUBE_VERSION="<major>.<minor>"
# KUBE_API_VERSIONS="v1,apps/v1,..."

# error/exit on any failure
set -e

# debugging execution
#
# Enable this only if you are debugging an issue.
# Leaving this on causes excessive space consumption on etcd database.
# See https://github.com/travisghansen/argo-cd-helmfile/issues/28
if [[ "${DEBUG}" == "1" ]]; then
  set -x
fi

echoerr() { printf "%s\n" "$*" >&2; }

# https://unix.stackexchange.com/questions/294835/replace-environment-variables-in-a-file-with-their-actual-values
variable_expansion() {
  # prefer envsubst if available, fallback to perl
  if [[ $(which envsubst) ]]; then
    echo -n "${@}" | envsubst
  else
    echo -n "${@}" | perl -pe 's/\$(\{)?([a-zA-Z_]\w*)(?(1)\})/$ENV{$2}/g'
  fi
}

print_env_vars() {
  while IFS='=' read -r -d '' n v; do
    printf "'%s'='%s'\n" "$n" "$v"
  done < <(env -0)
}

#truthy_test ${FOO:-false} && echo "yes \$FOO"
truthy_test() {
  val="${1}"
  if [[ $val == true ]]; then
    return 0
  fi

  if [[ ${val} -eq 1 ]]; then
    return 0
  fi

  if [[ ${val,,} == "1" ]]; then
    return 0
  fi

  if [[ ${val,,} == "true" ]]; then
    return 0
  fi

  if [[ ${val,,} == "yes" ]]; then
    return 0
  fi

  return 1
}

# exit immediately if no phase is passed in
if [[ -z "${1}" ]]; then
  echoerr "invalid invocation"
  exit 1
fi

SCRIPT_NAME=$(basename "${0}")

# export vars unprefixed
# ARGOCD_ENV_
# https://argo-cd.readthedocs.io/en/latest/operator-manual/upgrading/2.3-2.4/
if [[ true ]]; then
  while IFS='=' read -r -d '' n v; do
    if [[ "${n}" = ARGOCD_ENV_* ]]; then
      export ${n##ARGOCD_ENV_}="${v}"
    fi
  done < <(env -0)
fi

# immediately correct PATH if necessary
export PATH=$(variable_expansion "${PATH}")

# export params unprefixed (prefer these over ENV vars above)
# PARAM_
# https://github.com/argoproj/argo-cd/blob/master/docs/proposals/parameterized-config-management-plugins.md#how-will-the-cmp-know-what-parameter-values-are-set
if [[ true ]]; then
  while IFS='=' read -r -d '' n v; do
    if [[ "${n}" = PARAM_* ]]; then
      export ${n##PARAM_}="${v}"
    fi
  done < <(env -0)
fi

# immediately correct PATH if necessary
export PATH=$(variable_expansion "${PATH}")

# expand nested variables
if [[ "${HELMFILE_GLOBAL_OPTIONS}" ]]; then
  HELMFILE_GLOBAL_OPTIONS=$(variable_expansion "${HELMFILE_GLOBAL_OPTIONS}")
fi

if [[ "${HELMFILE_TEMPLATE_OPTIONS}" ]]; then
  HELMFILE_TEMPLATE_OPTIONS=$(variable_expansion "${HELMFILE_TEMPLATE_OPTIONS}")
fi

if [[ "${HELM_TEMPLATE_OPTIONS}" ]]; then
  HELM_TEMPLATE_OPTIONS=$(variable_expansion "${HELM_TEMPLATE_OPTIONS}")
fi

if [[ "${HELMFILE_INIT_SCRIPT_FILE}" ]]; then
  HELMFILE_INIT_SCRIPT_FILE=$(variable_expansion "${HELMFILE_INIT_SCRIPT_FILE}")
fi

if [[ "${HELM_DATA_HOME}" ]]; then
  export HELM_DATA_HOME=$(variable_expansion "${HELM_DATA_HOME}")
fi

phase=$1

# setup the env
# HELM_HOME is deprecated with helm-v3, uses XDG dirs
export HELM_HOME="/tmp/__${SCRIPT_NAME}__/apps/${ARGOCD_APP_NAME}"
export HELMFILE_HELMFILE_HELMFILED="${PWD}/.__${SCRIPT_NAME}__helmfile.d"

if [[ ! -d "/tmp/__${SCRIPT_NAME}__/bin" ]]; then
  mkdir -p "/tmp/__${SCRIPT_NAME}__/bin"
fi

# set binary paths and base options
if [[ "${HELM_BINARY}" ]]; then
  helm="${HELM_BINARY}"
else
  helm="$(which helm)"
fi

if [[ "${HELMFILE_BINARY}" ]]; then
  helmfile="${HELMFILE_BINARY}"
else
  if [[ $(which helmfile) ]]; then
    helmfile="$(which helmfile)"
  else
    LOCAL_HELMFILE_BINARY="/tmp/__${SCRIPT_NAME}__/bin/helmfile"
    if [[ ! -x "${LOCAL_HELMFILE_BINARY}" ]]; then
      case $(uname -m) in
        "x86")
          GO_ARCH=386
          ;;
        "x86_64")
          GO_ARCH=amd64
          ;;
        "aarch64")
          GO_ARCH=arm64
          ;;
        *)
          echoerr "unknow arch to download helmfile"
          exit 1
          ;;
      esac
      HELMFILE_VERSION=${HELMFILE_VERSION:-v0.150.0}
      wget -O- "${LOCAL_HELMFILE_BINARY}" "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION:1}_linux_${GO_ARCH}.tar.gz" | tar zxv -C $(dirname "${LOCAL_HELMFILE_BINARY}") helmfile
      if [[ "$(dirname "${LOCAL_HELMFILE_BINARY}")"/helmfile != "${LOCAL_HELMFILE_BINARY}" ]]; then
        mv "$(dirname "${LOCAL_HELMFILE_BINARY}")"/helmfile "${LOCAL_HELMFILE_BINARY}"
      fi
      chmod +x "${LOCAL_HELMFILE_BINARY}"
    fi
    helmfile="${LOCAL_HELMFILE_BINARY}"
  fi
fi

helmfile="${helmfile} --helm-binary ${helm} --no-color --allow-no-matching-release"

if [[ "${ARGOCD_APP_NAMESPACE}" ]]; then
  truthy_test ${HELMFILE_USE_CONTEXT_NAMESPACE:-false} || {
    helmfile="${helmfile} --namespace ${ARGOCD_APP_NAMESPACE}"
  }
fi

if [[ "${HELMFILE_GLOBAL_OPTIONS}" ]]; then
  helmfile="${helmfile} ${HELMFILE_GLOBAL_OPTIONS}"
fi

if [[ -v HELMFILE_HELMFILE ]]; then
  helmfile="${helmfile} -f ${HELMFILE_HELMFILE_HELMFILED}"
  HELMFILE_HELMFILE_STRATEGY=${HELMFILE_HELMFILE_STRATEGY:=REPLACE}
fi

# these should work for both v2 and v3
helm_full_version=$(${helm} version --short --client | cut -d " " -f2)
helm_major_version=$(echo "${helm_full_version%+*}" | cut -d "." -f1 | sed 's/[^0-9]//g')
helm_minor_version=$(echo "${helm_full_version%+*}" | cut -d "." -f2 | sed 's/[^0-9]//g')
helm_patch_version=$(echo "${helm_full_version%+*}" | cut -d "." -f3 | sed 's/[^0-9]//g')

# fix scenarios where KUBE_VERSION is improperly set with trailing +
# https://github.com/argoproj/argo-cd/issues/8249
KUBE_VERSION=$(echo "${KUBE_VERSION}" | sed 's/[^0-9\.]*//g')

# set home variable to ensure apps do NOT overlap settings/repos/etc
export HOME="${HELM_HOME}"

echoerr "$(${helm} version --short --client)"
echoerr "$(${helmfile} --version)"

case $phase in
  "parameters")
    echoerr "starting parameters"
    cat <<-"EOF"
[
  {
    "name": "HELM_TEMPLATE_OPTIONS",
    "title": "HELM_TEMPLATE_OPTIONS",
    "tooltip": "helm template --help"
  },
  {
    "name": "HELMFILE_BINARY",
    "title": "HELMFILE_BINARY",
    "tooltip": "custom path to helmfile binary"
  },
  {
    "name": "HELMFILE_GLOBAL_OPTIONS",
    "title": "HELMFILE_GLOBAL_OPTIONS",
    "tooltip": "helmfile --help"
  },
  {
    "name": "HELMFILE_HELMFILE",
    "title": "HELMFILE_HELMFILE",
    "tooltip": "a complete helmfile.yaml (ignores standard helmfile.yaml and helmfile.d if present based on strategy)"
  },
  {
    "name": "HELMFILE_HELMFILE_STRATEGY",
    "title": "HELMFILE_HELMFILE_STRATEGY",
    "tooltip": "REPLACE or INCLUDE"
  },
  {
    "name": "HELMFILE_INIT_SCRIPT_FILE",
    "title": "HELMFILE_INIT_SCRIPT_FILE",
    "tooltip": "path to script to execute during the init phase"
  },
  {
    "name": "HELMFILE_CACHE_CLEANUP",
    "title": "HELMFILE_CACHE_CLEANUP",
    "tooltip": "run helmfile cache cleanup on init",
    "itemType": "boolean"
  },
  {
    "name": "HELMFILE_USE_CONTEXT_NAMESPACE",
    "title": "HELMFILE_USE_CONTEXT_NAMESPACE",
    "tooltip": "do not set helmfile namespace to ARGOCD_APP_NAMESPACE (for multi-namespace apps)",
    "itemType": "boolean"
  },
  {
    "name": "HELM_DATA_HOME",
    "title": "HELM_DATA_HOME",
    "tooltip": "perform variable expansion"
  }
]
EOF
    exit 0
    ;;

  "discover")
    echoerr "starting discover"
    test -n "$(find . -type d -name "helmfile.d")" && {
      echo "valid helmfile content discovered"
      exit 0
    }
    test -n "$(find . -type f -name "helmfile.yaml")" && {
      echo "valid helmfile content discovered"
      exit 0
    }
    echoerr "no valid helmfile content discovered"
    exit 1
    ;;

  "init")
    echoerr "starting init"

    truthy_test "${HELMFILE_CACHE_CLEANUP:-false}" && {
      ${helmfile} cache cleanup
    }

    # ensure dir(s)
    # rm -rf "${HELM_HOME}"
    if [[ ! -d "${HELM_HOME}" ]]; then
      mkdir -p "${HELM_HOME}"
    fi

    if [[ -v HELMFILE_HELMFILE ]]; then
      rm -rf "${HELMFILE_HELMFILE_HELMFILED}"
      mkdir -p "${HELMFILE_HELMFILE_HELMFILED}"

      case "${HELMFILE_HELMFILE_STRATEGY}" in
        "INCLUDE")
          if [[ -f "helmfile.yaml" && -d "helmfile.d" ]]; then
            echoerr "configuration conlict error: you can have either helmfile.yaml or helmfile.d, but not both"
          fi

          if [[ -f "helmfile.yaml" ]]; then
            cp -a "helmfile.yaml" "${HELMFILE_HELMFILE_HELMFILED}/"
          fi

          if [[ -d "helmfile.d" ]]; then
            cp -ar "helmfile.d/"* "${HELMFILE_HELMFILE_HELMFILED}/"
          fi
          ;;
        "REPLACE") ;;

        *)
          echoerr "invalid \$HELMFILE_HELMFILE_STRATEGY: ${HELMFILE_HELMFILE_STRATEGY}"
          exit 1
          ;;
      esac

      # ensure custom file is processed last
      echo "${HELMFILE_HELMFILE}" >"${HELMFILE_HELMFILE_HELMFILED}/ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ__argocd__helmfile__.yaml"
    fi

    if [[ ! -d ".__${SCRIPT_NAME}__helmfile.d" ]]; then
      mkdir -p "${HELM_HOME}"
    fi

    if [[ ${helm_major_version} -eq 2 ]]; then
      ${helm} init --client-only
    fi

    if [[ ${helm_major_version} -eq 3 ]]; then
      # https://github.com/roboll/helmfile/issues/1015#issuecomment-563488649
      export HELMFILE_HELM3="1"
    fi

    if [ ! -z "${HELMFILE_INIT_SCRIPT_FILE}" ]; then
      HELMFILE_INIT_SCRIPT_FILE=$(realpath "${HELMFILE_INIT_SCRIPT_FILE}")
      bash "${HELMFILE_INIT_SCRIPT_FILE}"
    fi

    # https://github.com/roboll/helmfile/issues/1064
    ${helmfile} repos
    ;;

  "generate")
    echoerr "starting generate"

    INTERNAL_HELMFILE_TEMPLATE_OPTIONS=
    INTERNAL_HELM_TEMPLATE_OPTIONS=

    # helmfile args
    # --environment default, -e default       specify the environment name. defaults to default
    # --namespace value, -n value             Set namespace. Uses the namespace set in the context by default, and is available in templates as {{ .Namespace }}
    # --selector value, -l value              Only run using the releases that match labels. Labels can take the form of foo=bar or foo!=bar.
    #                                         A release must match all labels in a group in order to be used. Multiple groups can be specified at once.
    #                                         --selector tier=frontend,tier!=proxy --selector tier=backend. Will match all frontend, non-proxy releases AND all backend releases.
    #                                         The name of a release can be used as a label. --selector name=myrelease
    # --allow-no-matching-release             Do not exit with an error code if the provided selector has no matching releases.

    # apply custom args passed from helmfile down to helm
    # https://github.com/helm/helm/pull/7054/files (--is-upgrade added to v3)
    # --args --kube-version=1.16,--api-versions=foo
    #
    # v2
    # --is-upgrade               set .Release.IsUpgrade instead of .Release.IsInstall
    # --kube-version string      kubernetes version used as Capabilities.KubeVersion.Major/Minor (default "1.9")
    # v3
    # -a, --api-versions stringArray   Kubernetes api versions used for Capabilities.APIVersions
    # --no-hooks                   prevent hooks from running during install
    # --skip-crds                  if set, no CRDs will be installed. By default, CRDs are installed if not already present

    if [[ ${helm_major_version} -eq 2 && "${KUBE_VERSION}" ]]; then
      INTERNAL_HELM_TEMPLATE_OPTIONS="${INTERNAL_HELM_TEMPLATE_OPTIONS} --kube-version=${KUBE_VERSION}"
    fi

    # support added for --kube-version in 3.6
    # https://github.com/helm/helm/pull/9040
    if [[ ${helm_major_version} -eq 3 && ${helm_minor_version} -ge 6 && "${KUBE_VERSION}" ]]; then
      INTERNAL_HELM_TEMPLATE_OPTIONS="${INTERNAL_HELM_TEMPLATE_OPTIONS} --kube-version=${KUBE_VERSION}"
    fi

    if [[ ${helm_major_version} -eq 3 && "${KUBE_API_VERSIONS}" ]]; then
      INTERNAL_HELM_API_VERSIONS=""
      for v in ${KUBE_API_VERSIONS//,/ }; do
        INTERNAL_HELM_API_VERSIONS="${INTERNAL_HELM_API_VERSIONS} --api-versions=$v"
      done
      INTERNAL_HELM_TEMPLATE_OPTIONS="${INTERNAL_HELM_TEMPLATE_OPTIONS} ${INTERNAL_HELM_API_VERSIONS}"
    fi

    ${helmfile} \
      template \
      --skip-deps ${INTERNAL_HELMFILE_TEMPLATE_OPTIONS} \
      --args "${INTERNAL_HELM_TEMPLATE_OPTIONS} ${HELM_TEMPLATE_OPTIONS}" \
      ${HELMFILE_TEMPLATE_OPTIONS}
    ;;

  *)
    echoerr "invalid invocation"
    exit 1
    ;;
esac
