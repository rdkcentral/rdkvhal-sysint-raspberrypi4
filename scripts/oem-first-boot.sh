#!/bin/bash

if [ -f /opt/persistent/first-boot-done ]; then
    echo "'first-boot-done' detected. seems not fresh boot."
    exit 0
fi
echo "This is the first boot. Performing setup..."
mkdir -p /opt/www/authService

if [ ! -f /opt/www/authService/partnerId3.dat ]; then
    touch /opt/www/authService/partnerId3.dat
fi

if [ ! -f /opt/bspcomplete.ini ]; then
    touch /opt/bspcomplete.ini
fi

# Create the flag file to indicate the script has run
mkdir -p /opt/persistent
touch /opt/persistent/first-boot-done
