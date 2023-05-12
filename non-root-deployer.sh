#!/usr/bin/env bash
CLEANUP_WHEN_ERROR="1"
VERBOSE="1"
REPOSITORY=""
REPOSITORY_SSH_KEY_PATH=""
POST_CLONE_HOOK=""
POST_UPDATE_HOOK=""
KEEP_RELEASES_COUNT=10
FORCE_DEPLOYMENT="0"
START_TIMESTAMP=$(date +%s)
START_DATE=`date '+%Y-%m-%d'`
SCRIPT_PATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

LOG_PATH="$SCRIPT_PATH/logs";
LOG_FILE="$LOG_PATH/$START_DATE.log"
RELEASES_PATH="$SCRIPT_PATH/releases"
CURRENT_RELEASE_PATH="$RELEASES_PATH/current"
SHARED_PATH="$SCRIPT_PATH/shared"

CONFIG_FILE_NAME=".env"

cd "$SCRIPT_PATH"

function run_command_exit_on_error {
    COMMAND=${1}
    RESULT=$($COMMAND)
    STATUS=$?

    if [ $STATUS -ne "0" ]; then
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

function update_current_release {
    SOURCE="$1"
    TARGET="$CURRENT_RELEASE_PATH"

    log_info "Replacing current release"

    if [ -d "$TARGET" ]; then
        run_command_exit_on_error "rm $TARGET"
    fi

    run_command_exit_on_error "ln -sf $SOURCE $TARGET"
}

function cleanup_old_releases {
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    FILES=($(/bin/ls -t "$RELEASES_PATH"))

    SKIPPED_DIRECTORIES=0

    for ENTRY in ${FILES[@]}
    do
        if [ -d "$RELEASES_PATH/$ENTRY" ]; then
            if [ "$SKIPPED_DIRECTORIES" -lt "$KEEP_RELEASES_COUNT" ]; then
                SKIPPED_DIRECTORIES=$((SKIPPED_DIRECTORIES+1))
            else
                rm -rf "$RELEASES_PATH/$ENTRY"
            fi
        fi
    done

    IFS=$SAVEIFS
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
        DEPLOY_RELEASE_PATH)
            DEPLOY_RELEASE_PATH=${VALUE}
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
        REPOSITORY_SSH_KEY_PATH)
            REPOSITORY_SSH_KEY_PATH=${VALUE}
            ;;
        POST_CLONE_HOOK)
            POST_CLONE_HOOK=${VALUE}
            ;;
        POST_UPDATE_HOOK)
            POST_UPDATE_HOOK=${VALUE}
            ;;
        CONFIG_FILE_NAME)
            CONFIG_FILE_NAME=${VALUE}
            ;;
        KEEP_RELEASES_COUNT)
            KEEP_RELEASES_COUNT=${VALUE}
            ;;
        FORCE_DEPLOYMENT)
            FORCE_DEPLOYMENT=${VALUE}
            ;;
        *)
    esac
done

if [ -f "$SCRIPT_PATH/$CONFIG_FILE_NAME" ]; then
    source "$SCRIPT_PATH/$CONFIG_FILE_NAME"
fi

if [ ! -z "$DEPLOY_RELEASE_PATH" ]; then
    DEPLOY_RELEASE_PATH="$RELEASES_PATH/release-$START_DATE-$START_TIMESTAMP"
fi

ensure_folder_exists $LOG_PATH
ensure_folder_exists $SHARED_PATH
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

if [ ! -z "$REPOSITORY_SSH_KEY_PATH" ]; then
    export GIT_SSH_COMMAND="ssh -i $REPOSITORY_SSH_KEY_PATH -o IdentitiesOnly=yes"
fi

run_command_exit_on_error "git clone --depth 1 $REPOSITORY $DEPLOY_RELEASE_PATH"

SHOULD_CONTINUE_WITH_DEPLOYMENT="0"

if [ "$FORCE_DEPLOYMENT" == "1" ]; then
    SHOULD_CONTINUE_WITH_DEPLOYMENT="1"
else
    if [ -d "$CURRENT_RELEASE_PATH" ]; then
        CURRENT_COMMIT_ID=`git --git-dir $CURRENT_RELEASE_PATH/.git rev-parse HEAD`
        CLONED_COMMIT_ID=`git --git-dir $DEPLOY_RELEASE_PATH/.git rev-parse HEAD`

        if [ "$CURRENT_COMMIT_ID" != "$CLONED_COMMIT_ID" ]; then
            SHOULD_CONTINUE_WITH_DEPLOYMENT="1"
        fi
    else
        SHOULD_CONTINUE_WITH_DEPLOYMENT="1"
    fi
fi

if [ "$SHOULD_CONTINUE_WITH_DEPLOYMENT" == "0" ]; then
    exit_with_error "COMMIT IDs are identical, nothing to do. Cleaning up...."

    rm -rf "$DEPLOY_RELEASE_PATH"
else
    if [ ! -z "$POST_CLONE_HOOK" ]; then
        if [ -f "$DEPLOY_RELEASE_PATH/$POST_CLONE_HOOK" ]; then
            log_info "Calling $POST_CLONE_HOOK in release"

            run_command_exit_on_error "$DEPLOY_RELEASE_PATH/$POST_CLONE_HOOK SHARED_PATH=$SHARED_PATH"

            log_info "Post-clone hook completed"
        else
            exit_with_error "$DEPLOY_RELEASE_PATH/$POST_CLONE_HOOK not found"
        fi
    fi

    update_current_release "$DEPLOY_RELEASE_PATH"

    cleanup_old_releases

    if [ ! -z "$POST_UPDATE_HOOK" ]; then
        if [ -f "$DEPLOY_RELEASE_PATH/$POST_UPDATE_HOOK" ]; then
            log_info "Calling $POST_UPDATE_HOOK in release"

            run_command_exit_on_error "$DEPLOY_RELEASE_PATH/$POST_UPDATE_HOOK"

            log_info "Post-update hook completed"
        else
            exit_with_error "$DEPLOY_RELEASE_PATH/$POST_UPDATE_HOOK not found"
        fi
    fi
fi

exit 0