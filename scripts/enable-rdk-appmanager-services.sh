#!/bin/sh

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

# The following files are required to be dynamically created at runtime with
# the help of cloud services. Due to limitations of the RDK reference build
# to have such cloud instance support, create required files at first boot.

# RDK AppManager & App Gateway related status files
ENABLE_APP_MANAGER_FILE="/opt/ai2managers"
ENABLE_APP_GATEWAY_FILE="/opt/appgatewayenabled"

log() {
    echo "[APPMANAGER-ENABLE] $*"
}

create_if_missing() {
    file_path="$1"

    if [ -f "$file_path" ]; then
        log "'$file_path' detected. Already enabled."
        return
    fi

    log "Creating '$file_path' to enable service."
    if ! touch "$file_path"; then
        log "Error: Failed to create '$file_path'."
        exit 1
    fi
}

# Check for required command binaries and exit if not found.
REQUIRED_BINS="touch"
for bin in $REQUIRED_BINS; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        log "Error: '$bin' not found in PATH."
        exit 1
    fi
done

create_if_missing "$ENABLE_APP_MANAGER_FILE"
create_if_missing "$ENABLE_APP_GATEWAY_FILE"

exit 0
