#!/bin/bash

echo "$DOCKER_PASSWORD" | docker login         -u "$DOCKER_USERNAME" --password-stdin
echo "$GHCR_PASSWORD"   | docker login ghcr.io -u "$GHCR_USERNAME"   --password-stdin

export DOCKER_ORG="travisghansen"
export DOCKER_PROJECT="argo-cd-helmfile"
export DOCKER_REPO="${DOCKER_ORG}/${DOCKER_PROJECT}"

export GHCR_ORG="travisghansen"
export GHCR_PROJECT="argo-cd-helmfile"
export GHCR_REPO="ghcr.io/${GHCR_ORG}/${GHCR_PROJECT}"

if [[ $GITHUB_REF == refs/tags/* ]]; then
  export GIT_TAG=${GITHUB_REF#refs/tags/}
else
  export GIT_BRANCH=${GITHUB_REF#refs/heads/}
fi

if [[ -n "${GIT_TAG}" ]]; then
  docker buildx build --progress plain --pull --push --platform "${DOCKER_BUILD_PLATFORM}" -t ${DOCKER_REPO}:${GIT_TAG} -t ${GHCR_REPO}:${GIT_TAG} .
elif [[ -n "${GIT_BRANCH}" ]]; then
  if [[ "${GIT_BRANCH}" == "master" ]]; then
    docker buildx build --progress plain --pull --push --platform "${DOCKER_BUILD_PLATFORM}" -t ${DOCKER_REPO}:latest -t ${GHCR_REPO}:latest .
  else
    docker buildx build --progress plain --pull --push --platform "${DOCKER_BUILD_PLATFORM}" -t ${DOCKER_REPO}:${GIT_BRANCH} -t ${GHCR_REPO}:${GIT_BRANCH} .
  fi
else
  :
fi
