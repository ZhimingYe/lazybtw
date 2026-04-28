#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

./exec/build-lazybtw-mcp.sh >/dev/null

smoke_dir="$repo_root/.lazybtw-mcp-smoke"
rm -rf "$smoke_dir"
mkdir -p "$smoke_dir/data/sessions" "$smoke_dir/data/dishes"
chmod 700 "$smoke_dir/data" "$smoke_dir/data/sessions" "$smoke_dir/data/dishes"
trap 'rm -rf "$smoke_dir"' EXIT

pid=$$
dish="$smoke_dir/data/dishes/smoke.ndjson"
sess="$smoke_dir/data/sessions/smoke.json"
cat > "$dish" <<'JSON'
{"id":"1","time":"2026-04-28T00:00:00+0800","session_id":"smoke","source":"manual","kind":"text","label":"first","text":"hello from dish","truncated":false,"meta":{},"sha256":"x"}
{"id":"2","time":"2026-04-28T00:00:01+0800","session_id":"smoke","source":"clipboard","kind":"btw","label":"second","text":"latest context line","truncated":false,"meta":{},"sha256":"y"}
JSON
cat > "$sess" <<JSON
{"session_id":"smoke","pid":$pid,"created_at":"2026-04-28T00:00:00+0800","updated_at":"2026-04-28T00:00:01+0800","project":"$repo_root","dish_path":"$dish"}
JSON
chmod 600 "$dish" "$sess"

python3 - <<'PY' > "$smoke_dir/in.bin"
import json, sys
msgs = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}},
    {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}},
    {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"List_R_Sessions","arguments":{}}},
    {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"Inspect_R_lang_Context","arguments":{"limit":2}}},
    {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"Inspect_R_lang_Context","arguments":{"session_id":"missing","limit":2}}},
]
for msg in msgs:
    body = json.dumps(msg, separators=(",", ":")).encode()
    sys.stdout.buffer.write(b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
PY

LAZYBTW_DATA_DIR="$smoke_dir/data" ./exec/lazybtw-mcp < "$smoke_dir/in.bin" > "$smoke_dir/out.bin"

python3 - <<'PY'
import json
from pathlib import Path
raw = Path('.lazybtw-mcp-smoke/out.bin').read_bytes()
pos = 0
responses = []
while pos < len(raw):
    header_end = raw.find(b"\r\n\r\n", pos)
    assert header_end != -1, "missing MCP header terminator"
    headers = raw[pos:header_end].decode()
    length = None
    for line in headers.split("\r\n"):
        if line.lower().startswith("content-length:"):
            length = int(line.split(":", 1)[1].strip())
    assert length is not None, "missing content-length"
    start = header_end + 4
    body = raw[start:start + length]
    assert len(body) == length, "truncated body"
    responses.append(json.loads(body))
    pos = start + length

assert [r["id"] for r in responses] == [1, 2, 3, 4, 5]
assert responses[0]["result"]["serverInfo"]["name"] == "lazybtw"
tool_names = [t["name"] for t in responses[1]["result"]["tools"]]
assert "List_R_Sessions" in tool_names
assert "Inspect_R_lang_Context" in tool_names
sessions_text = responses[2]["result"]["content"][0]["text"]
assert "smoke" in sessions_text and "entries" in sessions_text
context_text = responses[3]["result"]["content"][0]["text"]
assert "latest context line" in context_text
assert "hello from dish" in context_text
missing_text = responses[4]["result"]["content"][0]["text"]
assert "No lazybtw R context session" in missing_text
print("C MCP protocol smoke OK")
PY

# R helper smoke: no full tests, just load config and check it points at C executable.
env -u CONDA_PREFIX -u CONDA_DEFAULT_ENV -u CONDA_PROMPT_MODIFIER -u CONDA_SHLVL \
  -u CONDA_EXE -u CONDA_PYTHON_EXE -u _CONDA_EXE -u _CONDA_ROOT \
  PATH="/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/bin" \
  Rscript --vanilla - <<'RS'
source("renv/activate.R")
devtools::load_all(quiet = TRUE)
json <- mcp_config("claude-code", print = FALSE)
stopifnot(grepl("lazybtw-mcp", json, fixed = TRUE))
stopifnot(!grepl("Rscript", json, fixed = TRUE))
stopifnot(!exists("mcp_stdio", asNamespace("lazybtw"), inherits = FALSE))
cat("R config smoke OK\n")
RS

echo "All lazybtw MCP smoke checks passed."
