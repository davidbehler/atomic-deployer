#!/bin/sh
LOG_HISTORY=()
CLEANUP_WHEN_ERROR="1"
VERBOSE="1"
REPOSITORY=""
POST_CLONE_HOOK=""

START_TIMESTAMP=$(date +%s)
START_DATE=`date '+%Y-%m-%d'`
SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

LOG_PATH="$SCRIPT_PATH/logs";
LOG_FILE="$LOG_PATH/$START_DATE.log"
RELEASES_PATH="$SCRIPT_PATH/releases"
CURRENT_RELEASE_PATH="$RELEASES_PATH/current"
SHARED_PATH="$SCRIPT_PATH/shared"

CONFIG_FILE_NAME=".env"

function run_command_exit_on_error {
    COMMAND=${1}
    RESULT=$($COMMAND)
    STATUS=$?

    if [ -z $STATUS ]; then
        exit_with_error "Running ${1} failed: $RESULT"
    fi
}

function check_if_program_exists {
    run_command_exit_on_error "command -v ${1}" "${1} is required but not installed. Aborting."
}

function log {
    local LOG_LEVEL="MISC"
    local DATETIME=`date '+%Y-%m-%d %H:%M:%S'`

    if [ ! -z "$2" ]; then
        LOG_LEVEL=${2}
    fi

    LOG_HISTORY+=("$DATETIME - $1")

    if [ ! -z "${LOG_FILE}" ]; then
        echo "$DATETIME - $LOG_LEVEL - $1" >> ${LOG_FILE}
    fi

    if [ "$VERBOSE" = "1" ]; then
        write_to_shell "${1}" "${LOG_LEVEL}"
    fi
}

function log_info {
    log "${1}" "INFO"
}

function log_error {
    log "${1}" "ERROR"
}

function log_notice {
    log "${1}" "NOTICE"
}

function write_to_shell {
    local COLOR="\033[0m"
    local NO_COLOR=${COLOR}

    case "$2" in
        ERROR)
            # red
            COLOR="\033[0;31m"
            ;;
        NOTICE)
            # brown/orange
            COLOR="\033[0;33m"
            ;;
        INFO)
            # black
            COLOR="\033[0;30m"
            ;;
        *)
    esac

    printf "${COLOR}${DATETIME}: ${1}${NO_COLOR} \n"
}

function exit_with_error {
    local ERROR_TEXT="$1 $2"
    # any exit code > 0 is an error
    local EXIT_CODE=1

    log_error "${ERROR_TEXT}"

    if [ ! -z "$2" ]; then
        local EXIT_CODE=${2}
    fi

    if [ "$CLEANUP_WHEN_ERROR" = "1" ]; then
        cleanup
    fi

    if [ "${EXIT_CODE}" -gt "0" ]; then
        exit ${EXIT_CODE}
    fi
}

function cleanup {
    log_info "Cleanup started"

    if [ ! -z "$RELEASE_PATH" ]; then
        if [ -d "$RELEASE_PATH" ]; then
            rm -R $RELEASE_PATH
        fi
    fi

    log_info "Cleanup done"
}

function ensure_folder_exists {
    log_info "Making sure $1 exists"

    run_command_exit_on_error "mkdir -p $1"
}

function create_atomic_symlink {
    SOURCE="$1"
    TARGET="$2"

    if [ -d "$TARGET" ]; then
        run_command_exit_on_error "rm $TARGET"
    fi

    run_command_exit_on_error "ln -s $SOURCE $TARGET"
}

for ARGUMENT in "$@"; do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
        RELEASES_PATH)
            RELEASES_PATH=${VALUE}
            ;;
        SHARED_PATH)
            SHARED_PATH=${VALUE}
            ;;
        CLEANUP_WHEN_ERROR)
            CLEANUP_WHEN_ERROR=${VALUE}
            ;;
        VERBOSE)
            VERBOSE=${VALUE}
            ;;
        REPOSITORY)
            REPOSITORY=${VALUE}
            ;;
        POST_CLONE_HOOK)
            POST_CLONE_HOOK=${VALUE}
            ;;
        CONFIG_FILE_NAME)
            CONFIG_FILE_NAME=${VALUE}
            ;;
        *)
    esac
done

if [ -f "$SCRIPT_PATH/$CONFIG_FILE_NAME" ]; then
    source "$SCRIPT_PATH/$CONFIG_FILE_NAME"
fi

DEPLOY_RELEASE_PATH="$RELEASES_PATH/release-$START_DATE-$START_TIMESTAMP"

ensure_folder_exists $LOG_PATH
ensure_folder_exists $RELEASES_PATH

PROGRAMS_TO_CHECK=(mkdir ln git composer)

log_info "Checking requirements"

for PROGRAM_TO_CHECK in "${PROGRAMS_TO_CHECK[@]}"; do
    check_if_program_exists $PROGRAM_TO_CHECK
done

if [ -z "$REPOSITORY" ]; then
    exit_with_error "No repository set"
fi

log_info "Cloning repository"
run_command_exit_on_error "git clone $REPOSITORY $DEPLOY_RELEASE_PATH"

if [ ! -z "$POST_CLONE_HOOK" ]; then
    if [ -f "$DEPLOY_RELEASE_PATH/$POST_CLONE_HOOK" ]; then
        log_info "Calling $POST_CLONE_HOOK in release"

        run_command_exit_on_error "$DEPLOY_RELEASE_PATH/$POST_CLONE_HOOK SHARED_PATH=$SHARED_PATH"

        log_info "Post-clone hook completed"
    fi
fi

log_info "Replacing current release"

create_atomic_symlink "$DEPLOY_RELEASE_PATH" "$CURRENT_RELEASE_PATH"

exit 0