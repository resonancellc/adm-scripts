#!/usr/bin/env bash

#/
#/ Clone a Git repository.
#/
#/ Arguments:
#/
#/   1: Repository name.
#/      Optional.
#/      Default: $KURENTO_PROJECT
#/
#/   2: Branch, tag or commit hash.
#/      Optional.
#/      Default: $JOB_GIT_REF, or "master".
#/
#/   3: Destination directory.
#/      Optional.
#/      Default: Repository name.
#/

# ------------ Shell setup ------------

# Shell options for strict error checking
set -o errexit -o errtrace -o pipefail -o nounset

# Logging functions
# These disable and re-enable debug mode (only if it was already set)
# Source: https://superuser.com/a/1141026
shopt -s expand_aliases  # This trick requires enabling aliases in Bash
BASENAME="$(basename "$0")"  # Complete file name
echo_and_restore() {
    echo "[${BASENAME}] $*"
    case "$flags" in (*x*) set -x ; esac
}
alias   log='{ flags="$-"; set +x; } 2>/dev/null; echo_and_restore'
alias error='{ flags="$-"; set +x; } 2>/dev/null; echo_and_restore ERROR'

# Trap functions
on_error() { ERROR=1; }
trap on_error ERR
on_exit() {
    (( ${ERROR-${?}} )) && error || log "SUCCESS"
    log "------------ END ------------"
}
trap on_exit EXIT

# Print help message
usage() { grep '^#/' "$0" | cut -c 4-; exit 0; }
expr match "${1-}" '^\(-h\|--help\)$' >/dev/null && usage

# Enable debug mode
set -o xtrace

log "++++++++++++ BEGIN ++++++++++++"



# ------------ Script start ------------

# Load arguments, with default fallbacks
CLONE_NAME="${1:-${KURENTO_PROJECT}}"
CLONE_REF="${2:-${JOB_GIT_REF:-master}}"
CLONE_DIR="${3:-${CLONE_NAME}}"

# Internal variables
CLONE_URL="${KURENTO_GIT_REPOSITORY}/${CLONE_NAME}.git"

log "Git clone: ${CLONE_URL} (${CLONE_REF})"

if [ -z "${GIT_KEY:+x}" ]; then
    git clone "${CLONE_URL}" "${CLONE_DIR}" \
    || error "Command failed: git clone"
else
    ssh-agent bash -c "\
      ssh-add ${GIT_KEY} || exit 1; \
      git clone "${CLONE_URL}" "${CLONE_DIR}" || exit 1;" \
    || error "Command failed: ssh-agent bash -c git clone"
fi

cd "${CLONE_DIR}/"

git fetch . refs/changes/*:refs/changes/* \
|| error "Command failed: git fetch"

git checkout "${CLONE_REF}" \
|| error "Command failed: git checkout"

if [ -f .gitmodules ]; then
    if [ -z "${GIT_KEY:+x}" ]; then
        git submodule update --init --recursive \
        || error "Command failed: git submodule update"
    else
        ssh-agent bash -c "\
          ssh-add ${GIT_KEY} || exit 1; \
          git submodule update --init --recursive || exit 1;" \
        || error "Command failed: ssh-agent bash -c git submodule update"
    fi
fi
