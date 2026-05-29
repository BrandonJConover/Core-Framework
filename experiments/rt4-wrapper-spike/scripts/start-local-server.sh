#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SERVER_DIR="$REPO_ROOT/2009scape-web/2009scape/Server"
SERVER_JAR="$REPO_ROOT/2009scape-web/2009scape/builddir/server.jar"
GENERATED_CONFIG="$REPO_ROOT/2009scape-web/2009scape/builddir/local-wrapper.conf"
SERVER_CONFIG="${RT4_SERVER_CONFIG:-$GENERATED_CONFIG}"

JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 11)}"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

if [[ ! -f "$SERVER_JAR" ]]; then
  bash "$SCRIPT_DIR/build-local-server.sh"
fi

if [[ "${RT4_SEED_BANK_FIXTURE:-1}" != "0" ]]; then
  bash "$SCRIPT_DIR/seed-local-bank-fixture.sh"
fi

if [[ "$SERVER_CONFIG" == "$GENERATED_CONFIG" ]]; then
  mkdir -p "$(dirname "$GENERATED_CONFIG")"
  cp "$SERVER_DIR/worldprops/default.conf" "$GENERATED_CONFIG"
  perl -0pi -e '
    s/log_level = "verbose"/log_level = "cautious"/;
    s/write_logs = true/write_logs = false/;
    s/watchdog_enabled = true/watchdog_enabled = false/;
    s/connectivity_check_url = "[^"]*"/connectivity_check_url = ""/;
    s/debug = true/debug = false/;
    s/enable_default_clan = true/enable_default_clan = false/;
    s/enable_bots = true/enable_bots = false/;
    s/max_adv_bots = 100/max_adv_bots = 0/;
    s/enable_doubling_money_scammers = true/enable_doubling_money_scammers = false/;
    s/bots_influence_ge_price = true/bots_influence_ge_price = false/;
    s/revenant_population = 30/revenant_population = 0/;
  ' "$GENERATED_CONFIG"
fi

cd "$SERVER_DIR"
if [[ "$SERVER_CONFIG" == "$GENERATED_CONFIG" ]]; then
  SERVER_CONFIG_ARG="../builddir/local-wrapper.conf"
else
  SERVER_CONFIG_ARG="$SERVER_CONFIG"
fi

exec java -Dnashorn.args=--no-deprecation-warning -jar "$SERVER_JAR" "$SERVER_CONFIG_ARG"
