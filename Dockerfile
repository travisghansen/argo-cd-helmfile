# https://github.com/argoproj/argo-cd/blob/master/Dockerfile
#
# docker build --pull -t foobar .
# docker run --rm -ti             --entrypoint bash foobar
# docker run --rm -ti --user root --entrypoint bash foobar

ARG BASE_IMAGE=docker.io/library/ubuntu:22.04

FROM $BASE_IMAGE

LABEL org.opencontainers.image.source https://github.com/travisghansen/argo-cd-helmfile

ENV DEBIAN_FRONTEND=noninteractive
ENV ARGOCD_USER_ID=999

ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN echo "I am running on final $BUILDPLATFORM, building for $TARGETPLATFORM"

USER root

RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates \
    git git-lfs \
    wget \
    jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN groupadd -g $ARGOCD_USER_ID argocd && \
    useradd -r -u $ARGOCD_USER_ID -g argocd argocd && \
    mkdir -p /home/argocd && \
    chown argocd:0 /home/argocd && \
    chmod g=u /home/argocd

# aws
# https://www.educative.io/collection/page/6630002/6521965765984256/6553354502668288
#
#ARG INSTALL_AWS_TOOLS
#RUN apt-get update && apt-get install --no-install-recommends -y \
#    awscli \
#    && \
#    apt-get clean && \
#    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# az cli
# https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt
#
#ARG INSTALL_AZURE_TOOLS
#RUN apt-get update && apt-get install --no-install-recommends -y \
#    ca-certificates curl apt-transport-https lsb-release gnupg \
#    && \
#    mkdir -p /etc/apt/keyrings && \
#    curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/keyrings/microsoft.gpg > /dev/null && \
#    chmod go+r /etc/apt/keyrings/microsoft.gpg && \
#    AZ_REPO=$(lsb_release -cs) && \
#    echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list && \
#    apt-get update && apt-get install --no-install-recommends -y \
#    azure-cli && \
#    apt-get clean && \
#    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*


# gcloud cli
# https://cloud.google.com/sdk/docs/install#deb
#
#ARG INSTALL_GCLOUD_TOOLS
#RUN apt-get update && apt-get install --no-install-recommends -y \
#    apt-transport-https ca-certificates gnupg \
#    && \
#    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
#    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
#    apt-get update && apt-get install --no-install-recommends -y \
#    google-cloud-cli && \
#    apt-get clean && \
#    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# binary versions
ARG AGE_VERSION="v1.1.1"
# install via apt for now
#ARG JQ_VERSION="1.6"
ARG HELM2_VERSION="v2.17.0"
ARG HELM3_VERSION="v3.12.3"
ARG HELMFILE_VERSION="0.157.0"
ARG KUSTOMIZE5_VERSION="5.1.1"
ARG SOPS_VERSION="v3.8.0"
ARG YQ_VERSION="v4.35.1"

# relevant for kubectl if installed
ARG KUBESEAL_VERSION="0.24.0"
# curl -v -L 'https://dl.k8s.io/release/stable.txt'
ARG KUBECTL_VERSION="v1.28.2"
ARG KREW_VERSION="v0.4.4"

# wget -qO "/usr/local/bin/jq"       "https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64" && \
RUN \
    GO_ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/') && \
    wget -qO-                          "https://get.helm.sh/helm-${HELM2_VERSION}-linux-${GO_ARCH}.tar.gz" | tar zxv --strip-components=1 -C /tmp linux-${GO_ARCH}/helm && mv /tmp/helm /usr/local/bin/helm-v2 && \
    wget -qO-                          "https://get.helm.sh/helm-${HELM3_VERSION}-linux-${GO_ARCH}.tar.gz" | tar zxv --strip-components=1 -C /tmp linux-${GO_ARCH}/helm && mv /tmp/helm /usr/local/bin/helm-v3 && \
    wget -qO "/usr/local/bin/sops"     "https://github.com/mozilla/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${GO_ARCH}" && \
    wget -qO-                          "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-${GO_ARCH}.tar.gz" | tar zxv --strip-components=1 -C /usr/local/bin age/age age/age-keygen && \
    wget -qO-                          "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_${GO_ARCH}.tar.gz" | tar zxv -C /usr/local/bin helmfile && \
    wget -qO "/usr/local/bin/yq"       "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${GO_ARCH}" && \
    wget -qO "/usr/local/bin/kubectl"  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${GO_ARCH}/kubectl" && \
    wget -qO-                          "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/krew-linux_${GO_ARCH}.tar.gz" | tar zxv -C /tmp ./krew-linux_${GO_ARCH} && mv /tmp/krew-linux_${GO_ARCH} /usr/local/bin/kubectl-krew && \
    wget -qO-                          "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${GO_ARCH}.tar.gz" | tar zxv -C /usr/local/bin kubeseal && \
    wget -qO-                          "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE5_VERSION}/kustomize_v${KUSTOMIZE5_VERSION}_linux_${GO_ARCH}.tar.gz" | tar zxv -C /usr/local/bin kustomize && \
    true

COPY src/*.sh /usr/local/bin/

RUN \
    ln -sf /usr/local/bin/helm-v3 /usr/local/bin/helm && \
    chown root:root /usr/local/bin/* && chmod 755 /usr/local/bin/*

ENV USER=argocd
USER $ARGOCD_USER_ID

WORKDIR /home/argocd/cmp-server/config/
COPY plugin.yaml ./
WORKDIR /home/argocd

# repo-server containers use /helm-working-dir (empty dir volume helm-working-dir)
#
# HELM_CACHE_HOME=/helm-working-dir
# HELM_CONFIG_HOME=/helm-working-dir
# HELM_DATA_HOME=/helm-working-dir
#
ENV HELM_CACHE_HOME=/home/argocd/helm/cache
#ENV HELM_CONFIG_HOME=/home/argocd/helm/config
ENV HELM_DATA_HOME=/home/argocd/helm/data
ENV KREW_ROOT=/home/argocd/krew
ENV PATH="${KREW_ROOT}/bin:$PATH"

# plugin versions
ARG HELM_DIFF_VERSION="3.6.0"
ARG HELM_GIT_VERSION="0.14.3"
ARG HELM_SECRETS_VERSION="4.3.0"

RUN \
  helm-v3 plugin install https://github.com/databus23/helm-diff   --version ${HELM_DIFF_VERSION} && \
  helm-v3 plugin install https://github.com/aslafy-z/helm-git     --version ${HELM_GIT_VERSION} && \
  helm-v3 plugin install https://github.com/jkroepke/helm-secrets --version ${HELM_SECRETS_VERSION} && \
  kubectl krew update && \
  mkdir -p ${KREW_ROOT}/bin && \
  true

# array is exec form, string is shell form
# this binary in injected via a shared folder with the repo server
#ENTRYPOINT [/var/run/argocd/argocd-cmp-server]
