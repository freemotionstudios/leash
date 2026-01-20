#!/usr/bin/env bash
#
# Build script for custom leash image
# This script builds a custom leash image with additional tools and non-root user support
#
# Usage:
#   ./build/build-custom-image.sh [OPTIONS] [VERSION]
#
# Options:
#   --user USER        Custom user name (default: leash)
#   --uid UID          Custom user UID (default: 1000)
#   --gid GID          Custom user GID (default: 1000)
#   --base-image IMG   Base leash image to use (default: leash/runtime-base:latest)
#   --tag TAG          Custom tag for the built image (default: ghcr.io/strongdm/leash-custom:VERSION)
#   --push             Push the image after building
#   --help, -h         Show this help message
#
# Environment Variables:
#   CUSTOM_LEASH_IMAGE  Target image repository (default: ghcr.io/strongdm/leash-custom)
#   CUSTOM_USER         Custom user name (default: leash)
#   CUSTOM_UID          Custom user UID (default: 1000)
#   CUSTOM_GID          Custom user GID (default: 1000)
#   BASE_LEASH_IMAGE    Base leash image (default: leash/runtime-base:latest)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"
VERSION_SCRIPT="${REPO_ROOT}/build/versionator.py"

# Default values
DEFAULT_USER="${CUSTOM_USER:-leash}"
DEFAULT_UID="${CUSTOM_UID:-1000}"
DEFAULT_GID="${CUSTOM_GID:-1000}"
DEFAULT_BASE_IMAGE="${BASE_LEASH_IMAGE:-leash/runtime-base:latest}"
DEFAULT_TARGET_IMAGE="${CUSTOM_LEASH_IMAGE:-ghcr.io/strongdm/leash-custom}"

# Configurable values
CUSTOM_USER="${DEFAULT_USER}"
CUSTOM_UID="${DEFAULT_UID}"
CUSTOM_GID="${DEFAULT_GID}"
BASE_IMAGE="${DEFAULT_BASE_IMAGE}"
TARGET_IMAGE="${DEFAULT_TARGET_IMAGE}"
PUSH_IMAGE=0
CUSTOM_TAG=""

log() {
    local level="$1"
    shift
    local caller="${FUNCNAME[1]:-main}"
    local line="${BASH_LINENO[0]:-0}"
    printf '%s\n' "${level}: ${SCRIPT_NAME}:${caller}:${line}: $*" 1>&2
}

log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }
die() { log_error "$@"; exit 1; }

require_cmd() {
    local missing=0
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "required command not found: ${cmd}"
            missing=1
        fi
    done
    if ((missing)); then
        exit 1
    fi
}

usage() {
    cat <<'EOF'
Usage: build-custom-image.sh [OPTIONS] [VERSION]

Build a custom leash image with additional tools and non-root user support.

Options:
  --user USER        Custom user name (default: leash)
  --uid UID          Custom user UID (default: 1000)
  --gid GID          Custom user GID (default: 1000)
  --base-image IMG   Base leash image to use (default: leash/runtime-base:latest)
  --tag TAG          Custom tag for the built image (overrides VERSION)
  --push             Push the image after building
  -h, --help         Show this help message

VERSION is the tag/identifier used for the built image. If omitted, the script
falls back to VERSION env or build/versionator.py output.

Environment Variables:
  CUSTOM_LEASH_IMAGE  Target image repository (default: ghcr.io/strongdm/leash-custom)
  CUSTOM_USER         Custom user name (default: leash)
  CUSTOM_UID          Custom user UID (default: 1000)
  CUSTOM_GID          Custom user GID (default: 1000)
  BASE_LEASH_IMAGE    Base leash image (default: leash/runtime-base:latest)

Examples:
  # Build custom image with default settings
  ./build/build-custom-image.sh

  # Build with custom user and UID
  ./build/build-custom-image.sh --user myuser --uid 1001

  # Build and push to registry
  ./build/build-custom-image.sh --push v1.0.0

  # Build with custom base image
  ./build/build-custom-image.sh --base-image public.ecr.aws/s5i7k8t3/strongdm/leash:latest
EOF
}

sanitize_tag() {
    local tag="$1"
    tag=$(printf '%s' "$tag" | tr '[:upper:]' '[:lower:]')
    tag=$(printf '%s' "$tag" | tr -c 'a-z0-9._-' '-')
    tag=$(printf '%s' "$tag" | sed 's/--*/-/g')
    while [[ "$tag" == -* ]]; do tag="${tag#-}"; done
    while [[ "$tag" == *- ]]; do tag="${tag%-}"; done
    if [ -z "$tag" ]; then
        tag="dev-$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
    fi
    printf '%s' "$tag"
}

main() {
    cd "${REPO_ROOT}"

    require_cmd docker git python3

    local -a positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user)
                CUSTOM_USER="$2"
                shift 2
                ;;
            --uid)
                CUSTOM_UID="$2"
                shift 2
                ;;
            --gid)
                CUSTOM_GID="$2"
                shift 2
                ;;
            --base-image)
                BASE_IMAGE="$2"
                shift 2
                ;;
            --tag)
                CUSTOM_TAG="$2"
                shift 2
                ;;
            --push)
                PUSH_IMAGE=1
                shift
                ;;
            -h|--help)
                usage
                return 0
                ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    positional+=("$1")
                    shift
                done
                break
                ;;
            -*)
                die "unknown option: $1"
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    if ((${#positional[@]} > 1)); then
        die "too many positional arguments"
    fi

    local version="${positional[0]:-${VERSION:-}}"
    if [ -z "${version}" ]; then
        if ! version="$("${VERSION_SCRIPT}" tag)"; then
            die "failed to resolve version via ${VERSION_SCRIPT}"
        fi
    fi
    if [ -z "${version}" ]; then
        die "version argument or VERSION env var is required"
    fi

    version="$(sanitize_tag "${version}")"

    # If custom tag is provided, use it; otherwise use version
    local image_tag
    if [ -n "${CUSTOM_TAG}" ]; then
        image_tag="${CUSTOM_TAG}"
    else
        image_tag="${version}"
    fi

    # Get git metadata
    local commit
    commit="$(git rev-parse --short=7 HEAD 2>/dev/null || echo dev)"
    local build_date
    build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local channel="${RELEASE_CHANNEL:-main}"
    local git_url
    git_url="$(git config --get remote.origin.url 2>/dev/null || echo unknown)"

    # Ensure base image exists
    log_info "Checking if base image ${BASE_IMAGE} exists locally..."
    if ! docker image inspect "${BASE_IMAGE}" >/dev/null 2>&1; then
        log_info "Base image ${BASE_IMAGE} not found locally"
        
        # Check if it's a local base image that needs to be built
        if [[ "${BASE_IMAGE}" == "leash/runtime-base:latest" ]]; then
            log_info "Building leash/runtime-base:latest..."
            make -C "${REPO_ROOT}" docker-base
        else
            die "Base image ${BASE_IMAGE} not found. Please build or pull it first."
        fi
    fi

    local full_image_tag="${TARGET_IMAGE}:${image_tag}"
    
    log_info "Building custom leash image:"
    log_info "  Base image:    ${BASE_IMAGE}"
    log_info "  Target image:  ${full_image_tag}"
    log_info "  User:          ${CUSTOM_USER} (UID: ${CUSTOM_UID}, GID: ${CUSTOM_GID})"
    log_info "  Version:       ${version}"
    log_info "  Commit:        ${commit}"
    log_info "  Channel:       ${channel}"

    # Build the custom image
    DOCKER_BUILDKIT=1 docker build \
        -f Dockerfile.custom \
        --target custom-final \
        --build-arg BASE_LEASH_IMAGE="${BASE_IMAGE}" \
        --build-arg CUSTOM_USER="${CUSTOM_USER}" \
        --build-arg CUSTOM_UID="${CUSTOM_UID}" \
        --build-arg CUSTOM_GID="${CUSTOM_GID}" \
        --build-arg VERSION="${version#v}" \
        --build-arg COMMIT="${commit}" \
        --build-arg BUILD_DATE="${build_date}" \
        --build-arg CHANNEL="${channel}" \
        --build-arg GIT_REMOTE_URL="${git_url}" \
        -t "${full_image_tag}" \
        -t "${TARGET_IMAGE}:latest" \
        .

    log_info "Successfully built ${full_image_tag}"

    # Push if requested
    if (( PUSH_IMAGE )); then
        log_info "Pushing ${full_image_tag}..."
        docker push "${full_image_tag}"
        docker push "${TARGET_IMAGE}:latest"
        log_info "Successfully pushed ${full_image_tag}"
    fi

    # Save image ID to dev file for local development
    local image_id
    image_id="$(docker images -q "${full_image_tag}" | head -n1)"
    if [ -n "${image_id}" ]; then
        printf '%s\n' "${image_id}" > "${REPO_ROOT}/.dev-docker-leash-custom"
        log_info "Saved image ID to .dev-docker-leash-custom"
    fi

    log_info "Build complete!"
    log_info ""
    log_info "To use this custom image:"
    log_info "  leash --leash-image ${full_image_tag} -- codex"
    log_info ""
    log_info "Or set in environment:"
    log_info "  export LEASH_IMAGE=${full_image_tag}"
    log_info "  leash -- codex"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
