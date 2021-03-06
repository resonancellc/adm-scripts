#!/usr/bin/env bash

#/ CI job - Generate RPC API client module from the current project.
#/
#/ This script is meant to be called from the "Execute shell" section of all
#/ Jenkins jobs which want to generate RPC API client code for their projects.
#/
#/
#/ Arguments
#/ ---------
#/
#/ --java
#/
#/   Generate client code for Java.
#/
#/ --js
#/
#/   Generate client code for JavaScript.
#/
#/ Either '--java' or '--js' must be provided.
#/
#/
#/ Variables
#/ ---------
#/
#/ This script expects some environment variables to be exported.
#/
#/ * Variable(s) from job parameters (with "This project is parameterized"):
#/
#/ JOB_GIT_NAME
#/
#/   Git branch or tag that should be checked out, if it exists.
#/
#/
#/ * Variable(s) from job Multi-Configuration ("Matrix") Project axis:
#/
#/ JOB_DISTRO
#/
#/   Name of the Ubuntu distribution where this job is run.
#/   E.g.: "xenial", "bionic".
#/
#/
#/ * Variable(s) from job Custom Tools (with "Install custom tools"):
#/
#/ KURENTO_SCRIPTS_HOME
#/
#/   Jenkins path to 'adm-scripts', containing all Kurento CI scripts.



# Shell setup
# -----------

BASEPATH="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"  # Absolute canonical path
# shellcheck source=bash.conf.sh
source "$BASEPATH/bash.conf.sh" || exit 1

# Trace all commands
set -o xtrace



# Parse call arguments
# --------------------

CFG_JAVA="false"
CFG_JS="false"

while [[ $# -gt 0 ]]; do
    case "${1-}" in
        --java)
            CFG_JAVA="true"
            ;;
        --js)
            CFG_JS="true"
            ;;
        *)
            log "ERROR: Unknown argument '${1-}'"
            log "Run with '--help' to read usage details"
            exit 1
            ;;
    esac
    shift
done



# Apply config restrictions
# -------------------------

if [[ "$CFG_JAVA" != "true" ]] && [[ "$CFG_JS" != "true" ]]; then
    log "ERROR: Either '--java' or '--js' must be provided"
    exit 1
fi

log "CFG_JAVA=$CFG_JAVA"
log "CFG_JS=$CFG_JS"



# Job setup
# ---------

# Check out the requested branch
"${KURENTO_SCRIPTS_HOME}/kurento_git_checkout_name.sh" \
    --name "$JOB_GIT_NAME" --fallback "$JOB_DISTRO"



# Build
# -----

if [[ "$CFG_JAVA" == "true" ]]; then
    GEN_SCRIPT="kurento_generate_java_module.sh"
elif [[ "$CFG_JS" == "true" ]]; then
    GEN_SCRIPT="kurento_generate_js_module.sh"
fi

RUN_COMMANDS=(
    "dpkg --install ./*.*deb || { apt-get update && apt-get install --yes --fix-broken --no-remove; }"
    $GEN_SCRIPT
)

export CONTAINER_IMAGE="kurento/kurento-ci-buildtools:xenial"
"${KURENTO_SCRIPTS_HOME}/kurento_ci_container_job_setup.sh" "${RUN_COMMANDS[@]}"
