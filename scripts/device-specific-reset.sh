#!/usr/bin/env sh

set -eu

##########################################################################
# If not stated otherwise in this file or this component's LICENSE
# file the following copyright and licenses apply:
#
# Copyright 2025 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

RESET_TYPE="${1:-}"
ACTION="${2:-}"

DRY_RUN="${DRY_RUN:-0}"
STRICT_MODE="${STRICT_MODE:-1}"

. /etc/device.properties

# Space-separated, configurable deletion roots.
# Each configured root must be under /opt.
# Example:
#   ALLOWED_DELETE_ROOTS="/opt/apps /opt/secure /opt/cache"
ALLOWED_DELETE_ROOTS="${ALLOWED_DELETE_ROOTS:-/opt}"

log() {
    printf '%s [device-specific-reset] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

require_var() {
    [ -n "$2" ] || fail "Missing required variable: $1"
}

# Collapses repeated slashes, strips trailing slashes, resolves . and ..
normalize_path() {
    _p="$1"
    _result=""
    _remainder="${_p}"
    while [ -n "${_remainder}" ]; do
        case "${_remainder}" in
            /*)
                _remainder="${_remainder#/}"
                [ -z "${_result}" ] && _result="/"
                continue
                ;;
        esac
        _component="${_remainder%%/*}"
        if [ "${_component}" = "${_remainder}" ]; then
            _remainder=""
        else
            _remainder="${_remainder#*/}"
        fi
        case "${_component}" in
            ""|".") continue ;;
            "..")
                case "${_result}" in
                    "/") ;;
                    *) _result="${_result%/*}"
                       [ -z "${_result}" ] && _result="/"
                       ;;
                esac
                ;;
            *)
                if [ "${_result}" = "/" ]; then
                    _result="/${_component}"
                else
                    _result="${_result}/${_component}"
                fi
                ;;
        esac
    done
    [ -z "${_result}" ] && _result="/"
    printf '%s\n' "${_result}"
}

validate_allowed_roots() {
    [ -n "${ALLOWED_DELETE_ROOTS}" ] || fail "ALLOWED_DELETE_ROOTS is empty"

    _normalized_roots=""
    for _root in ${ALLOWED_DELETE_ROOTS}; do
        case "${_root}" in
            /*) ;;
            *)
                fail "Configured root is not absolute: ${_root}"
                ;;
        esac

        # Strip trailing slashes to prevent pattern-match issues
        while [ "${_root}" != "/" ] && [ "${_root}" != "${_root%/}" ]; do
            _root="${_root%/}"
        done

        # Only permit configured roots under /opt.
        case "${_root}" in
            /opt|/opt/*) ;;
            *)
                fail "Configured root not allowed (must be under /opt): ${_root}"
                ;;
        esac

        # Basic unsafe pattern guard for root config as well.
        case "${_root}" in
            "/"|"/."|"/.."|"."|".."|*"/../"*|*"/./"*|*"//"*|*[!A-Za-z0-9._/+@-]*)
                fail "Configured root has unsafe form: ${_root}"
                ;;
        esac

        _normalized_roots="${_normalized_roots:+${_normalized_roots} }${_root}"
    done
    ALLOWED_DELETE_ROOTS="${_normalized_roots}"
}

is_under_allowed_root() {
    _target="$1"
    for _root in ${ALLOWED_DELETE_ROOTS}; do
        case "${_target}" in
            "${_root}"|"${_root}"/*) return 0 ;;
        esac
    done
    return 1
}

is_equal_to_allowed_root() {
    _target="$1"
    for _root in ${ALLOWED_DELETE_ROOTS}; do
        [ "${_target}" = "${_root}" ] && return 0
    done
    return 1
}

# Reject if any existing component in the resolved path is a symlink.
reject_symlink_components() {
    _target="$1"
    _acc=""

    set -f
    _oldifs="${IFS}"
    IFS='/'
    # shellcheck disable=SC2086
    set -- ${_target}
    IFS="${_oldifs}"
    set +f

    for _part in "$@"; do
        [ -n "${_part}" ] || continue
        _acc="${_acc}/${_part}"
        if [ -L "${_acc}" ]; then
            fail "Symlink component not allowed in target path: ${_acc}"
        fi
    done
}

purge_path() {
    # $1: label
    # $2: raw path
    _label="$1"
    _path="$2"

    [ -n "${_path}" ] || fail "Empty path for ${_label}"

    case "${_path}" in
        /*) ;;
        *) fail "${_label} is not an absolute path: '${_path}'" ;;
    esac

    case "${_path}" in
        "/"|"/."|"/.."|"."|".."|*"/../"*|*"/./"*|*"//"*|*[!A-Za-z0-9._/+@-]*)
            fail "Refusing unsafe path for ${_label}: '${_path}'"
            ;;
    esac

    _resolved="$(normalize_path "${_path}")" || fail "Failed to resolve path for ${_label}: '${_path}'"

    case "${_resolved}" in
        "/"|"/."|"/..")
            fail "Resolved path is unsafe for ${_label}: '${_resolved}'"
            ;;
    esac

    if [ "${STRICT_MODE}" = "1" ]; then
        is_under_allowed_root "${_resolved}" || \
            fail "Target for ${_label} is outside configured roots: '${_resolved}'"

        is_equal_to_allowed_root "${_resolved}" && \
            fail "Refusing to delete configured root itself for ${_label}: '${_resolved}'"

        reject_symlink_components "${_resolved}"
    fi

    if [ -e "${_resolved}" ]; then
        if [ "${DRY_RUN}" = "1" ]; then
            log "[TEST-RUN] Would remove ${_label}: ${_resolved}"
        else
            log "Removing ${_label}: ${_resolved}"
            rm -rf -- "${_resolved}"
        fi
    else
        log "Skip ${_label}: not present (${_resolved})"
    fi
}

stop_services() {
    # Placeholder for service stop/disable
    log "STOP-SERVICE handled successfully"
}

clean_common() {
    purge_path "APP_PREINSTALL_DIRECTORY" "${APP_PREINSTALL_DIRECTORY-}"
    purge_path "APP_DOWNLOAD_DIRECTORY" "${APP_DOWNLOAD_DIRECTORY-}"
    purge_path "DEFAULT_APP_STORAGE_PATH" "${DEFAULT_APP_STORAGE_PATH-}"
}

clean_factory() {
    log "CLEAN-CONFIG invoked for FACTORY reset"

    validate_allowed_roots

    require_var "DAC_APP_PATH" "${DAC_APP_PATH-}"
    require_var "APP_PREINSTALL_DIRECTORY" "${APP_PREINSTALL_DIRECTORY-}"
    require_var "APP_DOWNLOAD_DIRECTORY" "${APP_DOWNLOAD_DIRECTORY-}"
    require_var "DEFAULT_APP_STORAGE_PATH" "${DEFAULT_APP_STORAGE_PATH-}"

    purge_path "DAC_APP_PATH" "${DAC_APP_PATH-}"
    clean_common

    log "FACTORY CLEAN-CONFIG completed"
}

clean_warehouse() {
    log "CLEAN-CONFIG invoked for WAREHOUSE reset"

    validate_allowed_roots

    require_var "APP_PREINSTALL_DIRECTORY" "${APP_PREINSTALL_DIRECTORY-}"
    require_var "APP_DOWNLOAD_DIRECTORY" "${APP_DOWNLOAD_DIRECTORY-}"
    require_var "DEFAULT_APP_STORAGE_PATH" "${DEFAULT_APP_STORAGE_PATH-}"

    clean_common

    log "WAREHOUSE CLEAN-CONFIG completed"
}

[ -n "${RESET_TYPE}" ] && [ -n "${ACTION}" ] || fail "Missing or invalid arguments"

case "${RESET_TYPE}:${ACTION}" in
    FACTORY:STOP-SERVICE|WAREHOUSE:STOP-SERVICE)
        stop_services
        ;;
    FACTORY:CLEAN-CONFIG)
        clean_factory
        ;;
    WAREHOUSE:CLEAN-CONFIG)
        clean_warehouse
        ;;
    FACTORY:*)
        fail "Unknown action '${ACTION}' for FACTORY"
        ;;
    WAREHOUSE:*)
        fail "Unknown action '${ACTION}' for WAREHOUSE"
        ;;
    *)
        fail "Unknown reset type '${RESET_TYPE}'"
        ;;
esac