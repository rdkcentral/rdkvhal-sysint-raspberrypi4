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

if [ -f /opt/persistent/first-boot-done ]; then
    echo "'first-boot-done' detected. seems not a fresh boot."
    exit 0
fi
echo "This is the first boot. Performing setup..."
mkdir -p /opt/www/authService

if [ ! -f /opt/www/authService/partnerId3.dat ]; then
    echo "community" > /opt/www/authService/partnerId3.dat
fi

if [ ! -f /opt/bspcomplete.ini ]; then
    touch /opt/bspcomplete.ini
fi

# Create the flag file to indicate the script has run
mkdir -p /opt/persistent
touch /opt/persistent/first-boot-done
echo "First boot related setup is completed."
