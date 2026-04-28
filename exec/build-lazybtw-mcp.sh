#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cc -O2 -Wall -Wextra -o lazybtw-mcp lazybtw-mcp.c
chmod +x lazybtw-mcp
printf '%s\n' "$(pwd)/lazybtw-mcp"
