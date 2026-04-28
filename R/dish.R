#' Start a local lazybtw dish session
#'
#' @param session_name Optional stable session name. If `NULL`, lazybtw
#'   generates a unique session id.
#' @param project Project directory recorded in session metadata.
#' @param max_entries Maximum number of dish entries to retain per session.
#' @param max_entry_bytes Maximum UTF-8 bytes to retain for a single dish entry.
#' @param max_total_bytes Maximum bytes to retain across the dish file.
#' @param cleanup Whether to remove dead/stale lazybtw sessions before starting
#'   the new session.
#'
#' @export
dish_start <- function(
  session_name = NULL,
  project = getwd(),
  max_entries = getOption("lazybtw.dish.max_entries", 100L),
  max_entry_bytes = getOption("lazybtw.dish.max_entry_bytes", 64L * 1024L),
  max_total_bytes = getOption("lazybtw.dish.max_total_bytes", 5L * 1024L * 1024L),
  cleanup = TRUE
) {
  session_create(
    session_name = session_name,
    project = project,
    max_entries = max_entries,
    max_entry_bytes = max_entry_bytes,
    max_total_bytes = max_total_bytes,
    cleanup = cleanup
  )
}

#' Add text to the current lazybtw dish
#'
#' @param text Text to add to the dish.
#' @param source Source label for the entry, such as `"manual"` or
#'   `"clipboard"`.
#' @param kind Entry kind, such as `"text"` or `"btw"`.
#' @param label Optional human-readable entry label.
#' @param meta Optional metadata list stored with the entry.
#'
#' @export
dish_add <- function(text, source = "manual", kind = "text", label = NULL, meta = list()) {
  if (!is.list(meta)) {
    stop("`meta` must be a list.", call. = FALSE)
  }
  source <- paste(as.character(source), collapse = "/")
  kind <- paste(as.character(kind), collapse = "/")
  label <- if (is.null(label)) NULL else paste(as.character(label), collapse = "/")
  info <- session_current(auto_start = TRUE)
  clipped <- dish_text_truncate(text, info$max_entry_bytes %||% getOption("lazybtw.dish.max_entry_bytes", 64L * 1024L))

  record <- list(
    id = substr(digest::digest(paste(info$session_id, Sys.time(), stats::runif(1)), algo = "sha256"), 1, 16),
    time = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z"),
    session_id = info$session_id,
    source = source,
    kind = kind,
    label = label,
    text = clipped$text,
    truncated = clipped$truncated,
    meta = c(list(project = info$project, pid = info$pid), meta),
    sha256 = digest::digest(clipped$text, algo = "sha256")
  )

  tryCatch(
    {
      dish_store_append(
        info$dish_path,
        record,
        max_entries = info$max_entries %||% getOption("lazybtw.dish.max_entries", 100L),
        max_total_bytes = info$max_total_bytes %||% getOption("lazybtw.dish.max_total_bytes", 5L * 1024L * 1024L)
      )
      session_touch(info)
    },
    error = function(e) {
      warning("Could not add output to lazybtw dish: ", conditionMessage(e), call. = FALSE)
    }
  )

  invisible(record)
}

#' Read the current lazybtw dish
#'
#' @param limit Maximum number of recent entries to read.
#' @param format Output format: markdown text, a data frame, or JSON.
#'
#' @export
dish <- function(limit = 20L, format = c("markdown", "data.frame", "json")) {
  format <- match.arg(format)
  limit <- lazybtw_check_limit(limit, "limit", min = 1L)
  info <- session_current(auto_start = TRUE)
  records <- dish_store_read(info$dish_path, limit = limit)

  switch(
    format,
    markdown = dish_format_markdown(info, records),
    data.frame = dish_format_data_frame(records),
    json = jsonlite::toJSON(records, auto_unbox = TRUE, pretty = TRUE, null = "null")
  )
}

#' Clear the current lazybtw dish
#'
#' @param confirm Whether to ask before clearing.
#'
#' @export
dish_clear <- function(confirm = interactive()) {
  info <- session_current(auto_start = TRUE)
  if (isTRUE(confirm)) {
    answer <- readline("Clear lazybtw dish for current session? [y/N] ")
    if (!tolower(answer) %in% c("y", "yes")) {
      return(invisible(FALSE))
    }
  }
  dish_store_clear(info$dish_path)
  session_touch(info)
  invisible(TRUE)
}

#' Return status for the current lazybtw dish
#'
#' @export
dish_status <- function() {
  info <- session_current(auto_start = TRUE)
  file_info <- file.info(info$dish_path)
  list(
    session_id = info$session_id,
    dish_path = info$dish_path,
    entries = dish_store_count(info$dish_path),
    size = if (is.na(file_info$size)) 0 else unname(file_info$size),
    updated_at = info$updated_at,
    project = info$project
  )
}


#' List lazybtw dish sessions
#'
#' @param active_only Whether to include only sessions whose recorded R process
#'   still appears to be alive.
#'
#' @export
dish_sessions <- function(active_only = FALSE) {
  check_bool(active_only)
  sessions <- session_list(active_only = active_only)
  if (!length(sessions)) {
    return(data.frame(
      session_id = character(),
      pid = integer(),
      alive = logical(),
      entries = integer(),
      updated_at = character(),
      project = character(),
      dish_path = character(),
      stringsAsFactors = FALSE
    ))
  }

  data.frame(
    session_id = vapply(sessions, function(x) x$session_id %||% NA_character_, character(1)),
    pid = vapply(sessions, function(x) as.integer(x$pid %||% NA_integer_), integer(1)),
    alive = vapply(sessions, session_is_alive, logical(1)),
    entries = vapply(sessions, session_entry_count, integer(1)),
    updated_at = vapply(sessions, function(x) x$updated_at %||% NA_character_, character(1)),
    project = vapply(sessions, function(x) x$project %||% NA_character_, character(1)),
    dish_path = vapply(sessions, function(x) x$dish_path %||% NA_character_, character(1)),
    stringsAsFactors = FALSE
  )
}

#' Clean up lazybtw dish sessions
#'
#' @param all Whether to remove all lazybtw session records. The default only
#'   removes dead, corrupt, or unsafe sessions.
#' @param remove_dishes Whether to also remove the dish files for removed
#'   sessions.
#'
#' @export
dish_cleanup <- function(all = FALSE, remove_dishes = TRUE) {
  removed <- session_cleanup(all = all, remove_dishes = remove_dishes)
  invisible(removed)
}

#' Return the current lazybtw dish path
#'
#' @export
dish_path <- function() {
  info <- session_current(auto_start = TRUE)
  info$dish_path
}

dish_format_markdown <- function(info, records) {
  header <- c(
    "# R language context",
    "",
    paste0("Session: ", info$session_id),
    paste0("Project: ", info$project),
    paste0("PID: ", info$pid),
    paste0("Updated: ", info$updated_at),
    "",
    "## Recent context",
    ""
  )

  if (!length(records)) {
    return(paste(c(header, "No lazybtw dish context has been recorded yet."), collapse = "\n"))
  }

  records <- rev(records)
  body <- unlist(lapply(seq_along(records), function(i) {
    rec <- records[[i]]
    title <- paste0("### ", i, ". ", rec$source %||% "unknown", " / ", rec$kind %||% "text", " / ", rec$time %||% "")
    label <- rec$label %||% NULL
    if (!is.null(label) && nzchar(label)) {
      title <- paste0(title, " / ", label)
    }
    truncated <- if (isTRUE(rec$truncated)) "\n\n_Entry was truncated._" else ""
    c(title, "", md_code_block("", rec$text %||% ""), truncated, "")
  }), use.names = FALSE)

  paste(c(header, body), collapse = "\n")
}

dish_format_data_frame <- function(records) {
  if (!length(records)) {
    return(data.frame())
  }
  data.frame(
    id = vapply(records, function(x) x$id %||% NA_character_, character(1)),
    time = vapply(records, function(x) x$time %||% NA_character_, character(1)),
    session_id = vapply(records, function(x) x$session_id %||% NA_character_, character(1)),
    source = vapply(records, function(x) x$source %||% NA_character_, character(1)),
    kind = vapply(records, function(x) x$kind %||% NA_character_, character(1)),
    label = vapply(records, function(x) x$label %||% NA_character_, character(1)),
    text = vapply(records, function(x) x$text %||% NA_character_, character(1)),
    truncated = vapply(records, function(x) isTRUE(x$truncated), logical(1)),
    sha256 = vapply(records, function(x) x$sha256 %||% NA_character_, character(1)),
    stringsAsFactors = FALSE
  )
}
