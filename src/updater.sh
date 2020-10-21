#!/bin/bash

# Get all deployments that are to be updated. This will produce output like this:
# namespace1#deployment1#imageName1#image1:tag1
# namespace2#deployment2#imageName2#image2:tag2
DEPLOYMENTS=$(kubectl get deployments -A -l automatically-update-images=true -o json | jq -r '.items|.[]|[{deploymentName: .metadata.name, namespace: .metadata.namespace, imageName: .spec.template.spec.containers|.[].name, image: .spec.template.spec.containers|.[].image}]' | jq -r '.[]|.namespace + "#" + .deploymentName + "#" + .imageName + "#" + .image')

# Authenticate with docker hub
DOCKERHUB_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${DOCKERHUB_USERNAME}'", "password": "'${DOCKERHUB_PASSWORD}'"}' https://hub.docker.com/v2/users/login/ | jq -r .token)

for d in ${DEPLOYMENTS}
do
  echo "=== Checking deployment ${d} ==="
  # split the strings we generated earlier from kubectl output
  NAMESPACE="$(cut -d'#' -f1 <<<"$d")"
  DEPLOYMENT_NAME="$(cut -d'#' -f2 <<<"$d")"
  # IMAGE_NAME is what it is called in the k8s deployment spec, which may be different from the dockerhub name (=IMAGE_SOURCE)
  IMAGE_NAME="$(cut -d'#' -f3 <<<"$d")"
  # for dockerhub, we don't need the tag: org/img:1.2.3 -> org/img
  IMAGE_SOURCE="$(cut -d':' -f1 <<<"$(cut -d'#' -f4 <<<"$d")")" 

  # Grab the newest tag that is not `latest`. We cannot use the string-to-time conversion utlities jq offers since the dockerhub timestamps are not in the right format; however, we can use lexical search to sort and grab the first result
  LATEST_TAG=$(curl -s -H "Authorization: JWT ${DOCKERHUB_TOKEN}" https://hub.docker.com/v2/repositories/${IMAGE_SOURCE}/tags/\?page_size=10000 | jq -r '.results|[.[]|select(.name|contains("latest")|not)]|sort_by("last_updated")|.[0]|.name')

  # Get the deployed image tag
  DEPLOYED_IMAGE_NAME=$(kubectl -n ${NAMESPACE} get deployment ${DEPLOYMENT_NAME} -o jsonpath='{$.spec.template.spec.containers[?(@.name=="'${IMAGE_NAME}'")].image}')
  DEPLOYED_IMAGE_TAG="$(cut -d':' -f2 <<<"$DEPLOYED_IMAGE_NAME")"

  # If DEPLOYED_IMAGE_TAG is empty, log this and don't update anything
  if [[ -z "${DEPLOYED_IMAGE_TAG// }" ]]
  then
    echo "Cannot determine tag of currently deployed image. Skipping update"
    continue
  fi

  # If LATEST_TAG is empty, log and don't update anything
  if [[ -z "${LATEST_TAG// }" ]]
  then
    echo "Cannot determine latest tag from dockerhub. Skipping update"
    continue
  fi

  # Compare the tags and determine which one is newer. 
  NEWEST_VERSION=$(echo -e "$DEPLOYED_IMAGE_TAG\n$LATEST_TAG" | sort -V | tail -n1)

  if [ $NEWEST_VERSION == $DEPLOYED_IMAGE_TAG ]
  then
    echo "Deployed version tag ${DEPLOYED_IMAGE_TAG} is newer than or equal to docker hub tag ${LATEST_TAG}. Skipping update."
    continue
  else
    echo "Docker hub tag ${LATEST_TAG} is newer than deployed version tag ${DEPLOYED_IMAGE_TAG}. Performing update."
    # Build and execute update command
    UPDATE_COMMAND="kubectl set image deployment/${DEPLOYMENT_NAME} ${IMAGE_NAME}=${IMAGE_SOURCE}:${LATEST_TAG} -n ${NAMESPACE}"
    echo "Executing ${UPDATE_COMMAND}"
    $UPDATE_COMMAND
  fi
done
