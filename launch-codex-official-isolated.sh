#!/bin/bash
set -euo pipefail

OFFICIAL_APP="/Volumes/disk1/Apps/Codex.app"
REAL_USER_HOME="/Users/namobuddha"
ISOLATED_HOME="/Volumes/disk1/data_namobuddha/codex_official_home"
ISOLATED_LOGS="/Volumes/disk1/data_namobuddha/codex_official_logs"
RESOURCES="$OFFICIAL_APP/Contents/Resources"
PLUGIN_SOURCE="$ISOLATED_HOME/plugins/cache/openai-bundled/browser/26.1016.62342"
CLIENT="$PLUGIN_SOURCE/scripts/browser-client.mjs"

NODE="$RESOURCES/cua_node/bin/node"
NODE_REPL="$RESOURCES/cua_node/bin/node_repl"

CLIENT_SHA256="97669f77b3ca7114a2df05d55646416ea34b28100c07213ef9f643803449ef2f"

mkdir -p "$ISOLATED_HOME" "$ISOLATED_LOGS"

# Use /usr/bin/open with clean HOME to avoid .agy_profiles symlink trap
exec /usr/bin/open \
  --env "HOME=$REAL_USER_HOME" \
  --env "CODEX_HOME=$ISOLATED_HOME" \
  --env "NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S=$CLIENT_SHA256" \
  --env "CODEX_ELECTRON_RESOURCES_PATH=$RESOURCES" \
  --env "CODEX_BROWSER_USE_NODE_PATH=$NODE" \
  --env "CODEX_NODE_REPL_PATH=$NODE_REPL" \
  --env "CODEX_CLI_PATH=$RESOURCES/codex-cli/CodexCLI.app/Contents/MacOS/codex" \
  -a "$OFFICIAL_APP"
