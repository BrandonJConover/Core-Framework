#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SERVER_DIR="$REPO_ROOT/2009scape-web/2009scape/Server"
BUILDDIR="$REPO_ROOT/2009scape-web/2009scape/builddir"

JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 11)}"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

cd "$SERVER_DIR"
sh mvnw clean package -Dmaven.test.skip=true

mkdir -p "$BUILDDIR"
cp target/*-with-dependencies.jar "$BUILDDIR/server.jar"

echo "Built local 2009scape server jar:"
echo "  $BUILDDIR/server.jar"
