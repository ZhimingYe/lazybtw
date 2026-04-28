#' Configure lazybtw for local MCP clients
#'
#' @description
#' `mcp_config()` prints a JSON snippet for configuring the read-only
#' `lazybtw` stdio MCP server in local MCP clients.
#'
#' `use_rprofile()` adds a small, idempotent startup block to an `.Rprofile`
#' file so interactive R sessions automatically call [dish_start()].
#'
#' @param client MCP client configuration format. Currently supports
#'   `"claude-code"`/`"claude-desktop"`, `"vscode"`, and `"continue"`.
#' @param print Whether to print the JSON snippet to the console.
#' @param path `.Rprofile` path to update. Use `"project"` for `./.Rprofile`
#'   or `"user"` for `~/.Rprofile`.
#'
#' @return `mcp_config()` returns the JSON string invisibly. `use_rprofile()`
#'   returns the updated `.Rprofile` path invisibly.
#'
#' @export
mcp_config <- function(
  client = c("claude-code", "claude-desktop", "vscode", "continue"),
  print = TRUE
) {
  client <- match.arg(client)
  check_bool(print)

  server <- list(type = "stdio", command = lazybtw_mcp_command(), args = list())

  config <- switch(
    client,
    `claude-code` = list(mcpServers = list(lazybtw = server)),
    `claude-desktop` = list(mcpServers = list(lazybtw = server)),
    vscode = list(servers = list(lazybtw = server)),
    continue = list(experimental = list(modelContextProtocolServers = list(
      list(transport = c(list(name = "lazybtw", type = "stdio"), server))
    )))
  )

  json <- jsonlite::toJSON(config, auto_unbox = TRUE, pretty = TRUE, null = "null")
  json <- as.character(json)
  if (isTRUE(print)) {
    cat(json, "\n", sep = "")
  }
  invisible(json)
}

#' @rdname mcp_config
#' @export
use_rprofile <- function(path = "project") {
  path <- rprofile_path(path)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  block <- c(
    "# >>> lazybtw dish startup >>>",
    "if (interactive() && requireNamespace(\"lazybtw\", quietly = TRUE)) {",
    "  lazybtw::dish_start()",
    "}",
    "# <<< lazybtw dish startup <<<"
  )

  existing <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
  if (!any(grepl("^# >>> lazybtw dish startup >>>$", existing))) {
    lines <- c(existing, if (length(existing) && nzchar(utils::tail(existing, 1))) "" else NULL, block)
    writeLines(lines, path, useBytes = TRUE)
    cli::cli_alert_success("Added lazybtw dish startup to {.path {path}}.")
  } else {
    cli::cli_alert_info("lazybtw dish startup is already present in {.path {path}}.")
  }

  invisible(path)
}

rprofile_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("`path` must be a non-empty string.", call. = FALSE)
  }

  switch(
    path,
    project = file.path(getwd(), ".Rprofile"),
    user = path.expand("~/.Rprofile"),
    path.expand(path)
  )
}

lazybtw_mcp_command <- function() {
  command <- Sys.which("lazybtw-mcp")
  if (nzchar(command)) {
    return(unname(command))
  }

  installed <- system.file("exec", "lazybtw-mcp", package = "lazybtw", mustWork = FALSE)
  if (nzchar(installed) && file.exists(installed)) {
    return(normalizePath(installed, mustWork = FALSE))
  }

  local <- file.path(getwd(), "exec", "lazybtw-mcp")
  normalizePath(local, mustWork = FALSE)
}
