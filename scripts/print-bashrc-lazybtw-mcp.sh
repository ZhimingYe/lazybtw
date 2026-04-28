#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat <<EOT
# lazybtw standalone MCP executable
export PATH="$repo_root/exec:\$PATH"
EOT
