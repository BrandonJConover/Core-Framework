#!/bin/bash

set -euo pipefail

# Override these for another exported client, for example:
# OPENRSC_CLIENT_PORT=43596 bash Deployment_Scripts/deploy-openrsc-client.sh
OPENRSC_CLIENT_HOST="${OPENRSC_CLIENT_HOST:-10.8.0.1}"
OPENRSC_CLIENT_PORT="${OPENRSC_CLIENT_PORT:-43594}"

cd /opt/openrsc

#ant -f server/build.xml compile_core
#ant -f server/build.xml compile_plugins
ant -f Client_Base/build.xml compile
ant -f PC_Launcher/build.xml compile

# PC Client
cp -f Client_Base/*.jar /opt/website-downloads/

# Launcher
cp -rf PC_Launcher/*.jar /opt/website-downloads/

# Set file permissions within the Website downloads folder
chmod +x /opt/website-downloads/*.jar
# Cache copy and file permissions
cp -a -rf "Client_Base/Cache/." "/opt/website-downloads/"
cd '/opt/website-downloads/' || exit
printf '%s\n' "$OPENRSC_CLIENT_HOST" > ip.txt
printf '%s\n' "$OPENRSC_CLIENT_PORT" > port.txt

# Performs md5 hashing of all files in cache and writes to a text file for the launcher to read
find -type f \( -not -name "MD5.SUM" \) -exec md5sum '{}' \; >MD5.SUM
