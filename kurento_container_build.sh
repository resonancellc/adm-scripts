#!/bin/bash -x

# This tool is intended to build Docker images
#
# PARAMETERS
#
# PUSH_IMAGES
#     If "yes", images will be pushed to registry.
#     Optional. Default: "no".
#
# BUILD_ARGS
#     Build arguments to pass as `docker build --build-arg $BUILD_ARG`
#     Format: BUILD_ARGS="NODE_VERSION=4.x JDK=jdk-8"
#     Optional. Default: None.
#
# TAG
#     Tag name used for the Docker image.
#     Optional. Default: Image version defined in 'version.yml'.
#
# EXTRA_TAGS
#     Additional tags to apply to the Docker image.
#     Format: EXTRA_TAGS="apha beta latest"
#     Optional. Default: Extra tags defined in 'version.yml'.
#
# TAG_COMMIT
#     If "yes", an extra tag will be added with the current commit.
#     Optional. Default: "yes".
#
#     NOTE: Tagging with current commit from the 'kurento-docker' repo
#     is not useful, because it provides no information about the actual
#     commit of the software that goes inside the image.
#     So, this feature won't be used for KMS images. It is left as
#     enabled by default because that's what the script did before having
#     this parameter.
#
# DOCKERFILE
#     Location of Dockerfile to build the image.
#     Optional. Default: "Dockerfile".
#
# IMAGE_NAME
#     Name of image to build.
#     Optional. Default: Image name defined in 'version.yml'.
#
# IMAGE_NAME_PREFIX
#     A prefix to be prepended to the image name.
#     Optional. Default: None.
#
# IMAGE_NAME_SUFFIX
#     A suffix to be appended to the image name.
#     Optional. Default: None.

[[ -z "$PUSH_IMAGES" ]] && PUSH_IMAGES="no"
[[ -z "$TAG_COMMIT" ]] && TAG_COMMIT="yes"

if [[ -z "$DOCKERFILE" ]]; then
    FOLDER="$(dirname "$DOCKERFILE")"
else
    FOLDER="$PWD"
fi

# shellcheck source=parse_yaml.sh
. parse_yaml.sh
eval $(parse_yaml "$FOLDER/version.yml" "")
commit="$(git rev-parse --short HEAD)"

[[ -z "$DOCKERFILE" ]] && DOCKERFILE="Dockerfile"
[[ -z "$IMAGE_NAME" ]] && IMAGE_NAME="${image_name:-}"
[[ -z "$IMAGE_NAMESPACE" ]] && IMAGE_NAMESPACE="${image_namespace:-}"
[[ -z "$IMAGE_AUTHORS" ]] && IMAGE_AUTHORS="${image_authors:-}"
[[ -z "$TAG" ]] && TAG="${image_version:-}"
echo "Extra tags in version.yml: ${image_extra_tags[*]}"
[[ -z "$EXTRA_TAGS" ]] && EXTRA_TAGS="${image_extra_tags[*]}"

IMAGE_NAME="${IMAGE_NAME_PREFIX:-}${IMAGE_NAME}${IMAGE_NAME_SUFFIX:-}"

BUILD_NAME="$(echo "$IMAGE_NAME" | cut -d/ -f2)"

# If there's a generate.sh script, assume we need to dynamically generate the Dockerfile using it
# This is the case of selenium images
if [[ -f generate.sh ]]; then
    echo "Generating Dockerfile..."
    [[ -z "${image_parent_version}" ]] && image_parent_version="$TAG"
    [[ -z "${image_namespace}" ]] && image_namespace="kurento"
    [[ -z "${image_authors}" ]] && image_authors="Kurento Team"
    ./generate.sh "${image_parent_version}" "${image_namespace}" "${image_authors}"
fi

# If there's a kurento-generate.sh script, assume we need to fix the FROM line inside the Dockerfie
# in order to use our own generates Docker Images
if [[ -f kurento-generate.sh ]]; then
    echo "Applying Kurento customization..."
    if [[ $FOLDER == *"Debug"* ]]; then
        ./kurento-generate.sh "${image_parent_version}" "${image_namespace}" "${image_authors}"
    else
        ./kurento-generate.sh
    fi
fi

# Build using a tag composed of the original tag and the short commit id
for BUILD_ARG in ${BUILD_ARGS:-}; do
    build_args+=("--build-arg $BUILD_ARG")
done

docker build --no-cache --rm=true ${build_args[@]} -t "$BUILD_NAME" -f "$DOCKERFILE" "$FOLDER" || {
    echo "ERROR: Command failed: docker build"
    exit 1
}

# Tag the resulting image
docker tag "$BUILD_NAME" "${IMAGE_NAME}:${TAG}"

# Additional tag with the current commit
if [[ "$TAG_COMMIT" == "yes" ]]; then
    docker tag "$BUILD_NAME" "${IMAGE_NAME}:${TAG}-${commit}"
fi

# Apply any additional tags
echo "Extra tags: $EXTRA_TAGS"
for EXTRA_TAG in ${EXTRA_TAGS}; do
    docker tag "$BUILD_NAME" "${IMAGE_NAME}:${EXTRA_TAG}"
done

echo "### DOCKER IMAGES"
docker images | grep "$IMAGE_NAME"

echo "#### SPACE AVAILABLE"
df -h

# Push
if [[ "$PUSH_IMAGES" == "yes" ]]; then
    docker login -u "$KURENTO_DOCKERHUB_USER" -p "$KURENTO_DOCKERHUB_PASSWD"

    docker push "${IMAGE_NAME}:${TAG}"

    if [[ "$TAG_COMMIT" == "yes" ]]; then
        docker push "${IMAGE_NAME}:${TAG}-${commit}"
    fi

    for EXTRA_TAG in ${EXTRA_TAGS}; do
        docker push "${IMAGE_NAME}:${EXTRA_TAG}"
    done

    docker logout
fi

# Remove dangling images
if [ "$(docker images -f "dangling=true" -q | wc -l)" -ne 0 ]; then
    docker rmi "$(docker images -f "dangling=true" -q)" || exit 0
fi
