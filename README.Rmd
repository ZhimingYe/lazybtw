<!-- README.md is generated from README.Rmd. Please edit README.Rmd first. -->

# lazybtw

> A lightweight, local, read-only R context bridge for LLM tools

## Relationship to Posit's `btw`

`lazybtw` is a fork of Posit Software, PBC's excellent [`btw`](https://github.com/posit-dev/btw) package.

The upstream `btw` package focuses on helping R users create LLM-friendly descriptions of R objects, package documentation, workspace state, files, git state, and project context. `lazybtw` keeps that foundation and adds a simpler local workflow for coding agents on remote servers and headless environments.

In short:

- upstream **`btw`**: rich R-to-LLM context generation and tools;
- **`lazybtw`**: a fork that adds a persistent local “dish” plus a standalone read-only C MCP server.

This fork is experimental and is not an official Posit product.

## What problem does lazybtw solve?

How is this different from Posit Assistant and Positron Assistant? Those tools use proprietary assistant endpoints and are primarily optimized for Anthropic's model family. Even though Posit advertises support for many platforms, the actual experience has often been unsatisfactory for first-class models such as GPT and DeepSeek. Posit also has an understandable commercial reason to promote its own proprietary Posit AI service. At the same time, compatibility with OpenAI-compatible endpoints has remained difficult in practice: configuration is complex, and many "OpenAI-compatible" providers still require provider-specific handling for reasoning and tool-call loops. DeepSeek and Kimi, for example, both expose OpenAI-compatible surfaces that are different enough from the vanilla OpenAI flow that an agent client must preserve provider-specific reasoning state; in DeepSeek thinking-mode tool workflows, the previous `reasoning_content` has to be passed back, and some agent loops may even need to preserve an empty reasoning payload after a tool result in order to continue correctly. A small team like Positron's may understandably lack the capacity to chase every such protocol variation. That kind of proprietary direction can make sense for a commercial company, but there should also be a way for data scientists to use the first-class programming-agent scaffolds that programmers already use widely. Claude Code, Codex, and similar frameworks have already proved powerful for Python-based data analysis, and they can be used with each user's own legitimate subscription plan. `lazybtw` exists to make that style of workflow practical for R.

Clipboard-based workflows are painful on SSH servers, containers, HPC nodes, VS Code remote sessions, and coding-agent environments.

`lazybtw` lets R write useful context to disk, then lets Claude Code / VS Code / Continue read that context through MCP without starting R.

```text
R session
  ├─ lazybtw::dish_start()
  ├─ lazybtw::btw(...), lazybtw::dish_add(...)
  └─ writes private local files
       sessions/*.json
       dishes/*.ndjson

standalone lazybtw-mcp executable
  ├─ stdio MCP server
  ├─ reads the dish files only
  └─ exposes read-only tools to Claude Code / MCP clients
```

## New features in this fork

### 1. Persistent local dish

`lazybtw` records LLM context in a local NDJSON store:

```r
library(lazybtw)

dish_start()
dish_add("Important analysis context")
dish()
```

Useful helpers:

```r
dish_status()
dish_path()
dish_clear(confirm = FALSE)
```

### 2. Clipboard-free fallback

When `btw()` generates context, `lazybtw` can still save that context to the dish even if clipboard copy fails.

```r
library(lazybtw)

dish_start()
btw(mtcars)
dish(limit = 5)
```

This is useful on machines where clipboard access is unavailable.

### 3. R session tracking

Each R session gets a small session metadata file and a matching dish file.

```r
dish_sessions()
dish_sessions(active_only = TRUE)
```

The result includes session id, pid, alive status, entry count, project path, updated time, and dish path.

### 4. Session cleanup

Dead/stale sessions are cleaned automatically when a new dish session is created.

Manual cleanup:

```r
dish_cleanup()
```

Remove everything:

```r
dish_cleanup(all = TRUE)
```

By default, cleanup removes both stale session metadata and the corresponding dish file.

### 5. Standalone C MCP server

The MCP server is now a separate executable:

```text
lazybtw-mcp
```

It does **not** start R. It does **not** use `renv`. It does **not** use `Rscript`, `pkgload`, or `mcptools`.

It only reads local dish/session files and exposes two MCP tools:

- `List_R_Sessions` — list active R sessions with lazybtw context;
- `Inspect_R_lang_Context` — read recent context from the latest or selected R session.

### 6. MCP config helper

`mcp_config()` prints ready-to-copy MCP client configuration:

```r
mcp_config("claude-code")
mcp_config("claude-desktop")
mcp_config("vscode")
mcp_config("continue")
```

### 7. Auto-start helper

Add automatic dish startup to `.Rprofile`:

```r
use_rprofile("project")
```

This inserts an idempotent block like:

```r
if (interactive() && requireNamespace("lazybtw", quietly = TRUE)) {
  lazybtw::dish_start()
}
```

## Foolproof installation guide

### Step 1: Install from a local checkout

If you are in the package directory, use:

```r
install.packages("pak")
pak::pak(".")
```

Or install by absolute path:

```r
install.packages("pak")
pak::pak("/ifs1/User/yezhiming/R_Claude_CodeSupport/lazybtw")
```

Replace that path with wherever your `lazybtw` checkout lives.

A valid package directory should contain:

```text
DESCRIPTION
NAMESPACE
R/
exec/
configure
```

### Step 2: Confirm the R package works

```r
library(lazybtw)

dish_start()
dish_add("hello from R")
dish()
```

You should see `hello from R` in the printed dish context.

### Step 3: Confirm the MCP executable exists

In R:

```r
system.file("exec", "lazybtw-mcp", package = "lazybtw")
```

That should print a non-empty path ending in:

```text
lazybtw/exec/lazybtw-mcp
```

On Unix-like systems, source installation runs the package-level `configure` script, which compiles:

```text
exec/lazybtw-mcp.c -> exec/lazybtw-mcp
```

Normally you do **not** compile it manually.

Only manually rebuild during development or if the executable is missing:

```bash
cd /path/to/lazybtw
./configure
# or
./exec/build-lazybtw-mcp.sh
```

### Step 4: Generate MCP configuration

In R:

```r
library(lazybtw)
mcp_config("claude-code")
```

It prints JSON like:

```json
{
  "mcpServers": {
    "lazybtw": {
      "type": "stdio",
      "command": "/absolute/path/to/lazybtw-mcp",
      "args": []
    }
  }
}
```

The important part is `command`. It must point to the compiled `lazybtw-mcp` executable.

### Step 5: Add to Claude Code

Use the command path printed by `mcp_config()`:

```bash
claude mcp add -s project lazybtw -- /absolute/path/to/lazybtw-mcp
```

For this local checkout, it may look like:

```bash
claude mcp add -s project lazybtw -- /ifs1/User/yezhiming/R_Claude_CodeSupport/lazybtw/exec/lazybtw-mcp
```

Check the connection:

```bash
claude mcp get lazybtw
```

Success looks like:

```text
Status: ✓ Connected
```

### Step 6: Use it

In R:

```r
library(lazybtw)

dish_start()
dish_add("I am analyzing mtcars")
btw(mtcars)
```

In Claude Code, ask it to use the MCP tools:

```text
List_R_Sessions
Inspect_R_lang_Context
```

Claude should be able to read recent R context without launching R.


## Encourage Claude to use lazybtw MCP

Claude Code will not always know that R context is available unless you tell it. To make Claude more proactive, add a project instruction file such as `AGENTS.md` or `CLAUDE.md` in your project root.

Recommended instruction block:

```md
## lazybtw MCP usage

This project uses the `lazybtw` MCP server to read R session context.

When the user asks about R code, R objects, analysis results, data frames, errors, plots, packages, or the current R workflow, proactively use the lazybtw MCP tools before answering.

Available tools:

- `List_R_Sessions`: list active R sessions that have lazybtw dish context.
- `Inspect_R_lang_Context`: inspect recent context from the latest or selected R session.

Default behavior:

1. If the task is related to current R state, first call `List_R_Sessions`.
2. Then call `Inspect_R_lang_Context` on the most recent active session.
3. Use the returned context as the source of truth for current R objects and analysis state.
4. If no session/context is found, ask the user to run:

```r
library(lazybtw)
dish_start()
btw(<object>)
# or
dish_add("relevant context")
```

Do not assume live R state without checking lazybtw when the answer depends on current R context.
```

A short prompt also works during a chat:

```text
Please first use the lazybtw MCP tools `List_R_Sessions` and `Inspect_R_lang_Context`, then answer using the current R context.
```

## Where does lazybtw store data?

By default, R uses:

```r
tools::R_user_dir("lazybtw", "data")
```

On Linux this is commonly:

```text
~/.local/share/R/lazybtw
```

Layout:

```text
~/.local/share/R/lazybtw/
├── sessions/
│   └── <session_id>.json
└── dishes/
    └── <session_id>.ndjson
```

You can force a specific data directory with:

```r
Sys.setenv(LAZYBTW_DATA_DIR = "/path/to/lazybtw-data")
```

or:

```r
options(lazybtw.data_dir = "/path/to/lazybtw-data")
```

For MCP clients, set `LAZYBTW_DATA_DIR` in the MCP server environment if needed.

## Security model

`lazybtw-mcp` is read-only.

It can inspect context already written by `lazybtw`. It cannot send commands to R, execute R code, modify R objects, install packages, or open a network port in stdio mode.

Local storage is private by default on Unix-like systems:

- directories are set to `0700`;
- session/dish files are set to `0600`;
- unsafe files are ignored;
- dead sessions are ignored or cleaned.

Do not put secrets, credentials, tokens, or sensitive data into dish entries.

## Troubleshooting

### `MCP server connection timed out`

Check:

```bash
claude mcp get lazybtw
```

Make sure `command` points to an existing executable:

```bash
ls -l /absolute/path/to/lazybtw-mcp
```

If missing, rebuild:

```bash
cd /path/to/lazybtw
./configure
```

### MCP connects but sees no R context

Start a dish and add context in R:

```r
library(lazybtw)
dish_start()
dish_add("hello")
dish_sessions()
```

Then call `Inspect_R_lang_Context` again from the MCP client.

### Old/dead sessions are confusing things

Clean them:

```r
dish_cleanup()
```

Or wipe everything:

```r
dish_cleanup(all = TRUE)
```

## Main functions

- `btw()` — generate LLM-friendly R context;
- `dish_start()` — start a local dish session;
- `dish_add()` — append text to the current dish;
- `dish()` — read recent dish context;
- `dish_sessions()` — list tracked R sessions;
- `dish_cleanup()` — clean dead/stale sessions;
- `mcp_config()` — print MCP client config;
- `use_rprofile()` — auto-start dish in interactive R sessions.
