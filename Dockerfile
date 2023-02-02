# https://github.com/argoproj/argo-cd/blob/master/Dockerfile
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

ARG HELM_VERSION="v3.11.0"
ARG HELMFILE_VERSION="0.150.0"

USER root

RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates \
    wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN groupadd -g $ARGOCD_USER_ID argocd && \
    useradd -r -u $ARGOCD_USER_ID -g argocd argocd && \
    mkdir -p /home/argocd && \
    chown argocd:0 /home/argocd && \
    chmod g=u /home/argocd

RUN \
    GO_ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/') && \
    wget -qO- "https://get.helm.sh/helm-${HELM_VERSION}-linux-${GO_ARCH}.tar.gz" | tar zxv --strip-components=1 -C /usr/local/bin linux-${GO_ARCH}/helm && \
    wget -qO- "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_${GO_ARCH}.tar.gz" | tar zxv -C /usr/local/bin helmfile
    

COPY src/*.sh /usr/local/bin/

RUN \
    chown root:root /usr/local/bin/* && chmod 755 /usr/local/bin/*

ENV USER=argocd
USER $ARGOCD_USER_ID

WORKDIR /home/argocd/cmp-server/config/
COPY plugin.yaml ./
WORKDIR /home/argocd

# array is exec form, string is shell form
ENTRYPOINT [/var/run/argocd/argocd-cmp-server]