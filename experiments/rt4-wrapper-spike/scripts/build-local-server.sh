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
sh mvnw -q dependency:build-classpath -Dmdep.outputFile=target/local-wrapper-classpath.txt

find src/main -name '*.java' > target/local-wrapper-java-sources.txt
javac --release 11 \
  -cp "target/classes:target/kotlin-ic/compile/classes:$(cat target/local-wrapper-classpath.txt)" \
  -d target/classes \
  @target/local-wrapper-java-sources.txt

server_jars=(target/*-with-dependencies.jar)
jar uf "${server_jars[0]}" -C target/classes .
jar uf "${server_jars[0]}" -C target/kotlin-ic/compile/classes .

mkdir -p "$BUILDDIR"
cp "${server_jars[0]}" "$BUILDDIR/server.jar"

echo "Built local 2009scape server jar:"
echo "  $BUILDDIR/server.jar"
