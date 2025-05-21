#!/bin/sh

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
DEVICE_ID_FILE="$AUTH_SERVICE_DIR/deviceId3.dat"

FIRST_BOOT_FLAG="$PERSISTENT_DIR/first-boot-done"
BSP_COMPLETE_FILE="/opt/bspcomplete.ini"

# Check for required command binaries and exit if not found.
REQUIRED_BINS="uuidgen mfr_util mkdir touch echo"
for bin in $REQUIRED_BINS; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "Error: Required command '$bin' not found in PATH."
        exit 1
    fi
done

if [ -f "$PERSISTENT_DIR/first-boot-done" ]; then
    echo "'first-boot-done' detected. seems not a fresh boot."
    exit 0
fi

echo "This is the first boot. Performing setup..."
mkdir -p "$AUTH_SERVICE_DIR"

if [ ! -f "$PARTNER_ID_FILE" ]; then
    echo "community" > "$PARTNER_ID_FILE"
fi

if [ ! -f "$AUTH_SERVICE_DIR/deviceid.dat" ]; then
    uuidgen --sha1 --namespace @dns --name $(mfr_util --MfgSerialnumber) > "$DEVICE_ID_FILE"
fi

if [ ! -f "$BSP_COMPLETE_FILE" ]; then
    touch "$BSP_COMPLETE_FILE"
fi

# Create the flag file to indicate the script has run
mkdir -p "$PERSISTENT_DIR"
touch "$FIRST_BOOT_FLAG"
echo "First boot related setup is completed."
