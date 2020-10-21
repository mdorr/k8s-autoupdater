# Kubernetes Autoupdater

Automatically updates Kubernetes deployments with the latest versions of their respective images.

## Building the autoupdater image

Use the included [Dockerfile](/Dockerfile) to build the image:

```bash
docker build -t autoupdater -f Dockerfile
```

## Installing in K8S

See the supplied [Sample Files](/k8s). You need to modify the following files:

- **[autoupdater-cronjob.yml](/k8s/autoupdater-cronjob.yml)**: Update the `image` line to point to the correct location of the autoupdater image, typically at dockerhub: {your_organization}/autoupdater. 
- **[autoupdater-dockerhub.yml](/k8s/autoupdater-dockerhub.yml)**: Add a valid docker hub token with permissions to pull the `autoupdater` image
- **[autoupdater-secrets.yml](/k8s/autoupdater-secrets.yml)**: Add valid (base64-encoded) docker hub credentials to retrieve the latest versions for all images that should be updated. These can be different from the docker hub account pulling the `autoupdater` image.

With those changes in place, apply all kubernetes definitions files. This will set up a service user with permissions to perform the updates, a namespace for the autoupdater images, and a cronjob running the autoupdater process once per hour.

## Marking containers for updates

To mark deployments for automatic updates, set the label `"automatically-update-images": "true"` on your deployment. If this label is set to "false", or if it is not present, the deployment will not be considered by the autoupdater.

## Manually run the update process

You can manually run the update process with the following command:

```
kubectl -n autoupdater create job --from=cronjob/autoupdater-cronjob autoupdater-job-$(date +%s) -n autoupdater
```

Note: The $(date +%s) part of the name is there to ensure a unique number as part of the job name.


## Update process details

This will update all selected deployments by checking Docker Hub for the newest published tag. It will ignore the latest tag and only consider properly named tags. That tag is then set on the deployment.

To determine the newest tag, the tool will look at the date of the tag being published. It does not compare the tag version numbers directly.

Once the newest tag from dockerhub is determined, it will be compared to the currently deployed tag. If the dockerhub tag is higher (as defined by semantic versioning), the deployment will be updated with the new tag from dockerhub.