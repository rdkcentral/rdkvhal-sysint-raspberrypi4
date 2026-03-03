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

PERSISTENT_DIR="/opt/persistent"
AUTH_SERVICE_DIR="/opt/www/authService"
PARTNER_ID_FILE="$AUTH_SERVICE_DIR/partnerId3.dat"
DEVICE_ID_FILE="$AUTH_SERVICE_DIR/deviceid.dat"
FIRST_BOOT_FLAG="$PERSISTENT_DIR/first-boot-done"
BSP_COMPLETE_FILE="/opt/bspcomplete.ini"

log() {
    echo "[OEM-FIRST-BOOT] $*"
}

# Check for required command binaries and exit if not found.
REQUIRED_BINS="uuidgen mfr_util mkdir touch tr"
for bin in $REQUIRED_BINS; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        log "Error: '$bin' not found in PATH."
        exit 1
    fi
done

if [ -f "$FIRST_BOOT_FLAG" ]; then
    log "'first-boot-done' detected. Not a fresh boot."
    exit 0
fi

log "This is the first boot. Performing setup..."

mkdir -p "$AUTH_SERVICE_DIR" "$PERSISTENT_DIR"

# PartnerID is used in Conf payloads.
if [ ! -f "$PARTNER_ID_FILE" ]; then
    if ! echo "community" > "$PARTNER_ID_FILE"; then
        log "Error: Failed to write '$PARTNER_ID_FILE'."
        exit 1
    fi
fi

# DeviceID is used in XCast as UUID.
if [ ! -f "$DEVICE_ID_FILE" ]; then
    serial="$(mfr_util --MfgSerialnumber 2>/dev/null | tr -d '\r\n')"
    if [ -z "$serial" ]; then
        log "Error: Failed to retrieve serial number from mfr_util."
        exit 1
    fi
    if ! uuidgen --sha1 --namespace @dns --name "$serial" > "$DEVICE_ID_FILE"; then
        log "Error: Failed to write '$DEVICE_ID_FILE'."
        exit 1
    fi
fi

if [ ! -f "$BSP_COMPLETE_FILE" ]; then
    if ! touch "$BSP_COMPLETE_FILE"; then
        log "Error: Failed to create '$BSP_COMPLETE_FILE'."
        exit 1
    fi
fi

if ! touch "$FIRST_BOOT_FLAG"; then
    log "Error: Failed to create '$FIRST_BOOT_FLAG'."
    exit 1
fi
log "First boot related setup is completed."
