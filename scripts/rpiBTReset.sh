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

# Must be run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[BT-RESET][ERROR] This script must be run as root." >&2
    exit 1
fi

REQUIRED_BINS="rfkill sleep"

for bin in $REQUIRED_BINS; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "[BT-RESET][ERROR] Required command '$bin' not found in PATH." >&2
        exit 1
    fi
done

echo "[BT-RESET] Resetting Bluetooth adapter..."

rfkill block bluetooth || {
    echo "[BT-RESET][ERROR] Failed to block Bluetooth." >&2
    exit 1
}

sleep 0.5

rfkill unblock bluetooth || {
    echo "[BT-RESET][ERROR] Failed to unblock Bluetooth." >&2
    exit 1
}

sleep 0.5
echo "[BT-RESET] Done"
