.lazybtw_env <- new.env(parent = emptyenv())
.lazybtw_env$session <- NULL

session_id_generate <- function() {
  stamp <- format(Sys.time(), "%Y%m%d")
  seed <- paste(Sys.getpid(), Sys.time(), stats::runif(1), paste(sample.int(1e9, 4), collapse = "-"))
  suffix <- substr(digest::digest(seed, algo = "sha256"), 1, 8)
  paste0("r-", stamp, "-", suffix)
}

session_validate_id <- function(session_id) {
  if (!is.character(session_id) || length(session_id) != 1L || is.na(session_id) || !nzchar(session_id)) {
    stop("`session_name` must be a non-empty string.", call. = FALSE)
  }
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", session_id)) {
    stop("`session_name` may only contain letters, numbers, '.', '_', and '-'.", call. = FALSE)
  }
  session_id
}

session_file <- function(session_id) {
  session_id <- session_validate_id(session_id)
  file.path(lazybtw_paths()$sessions, paste0(session_id, ".json"))
}

session_write <- function(info) {
  ensure_lazybtw_dirs()
  path <- session_file(info$session_id)
  tmp <- paste0(path, ".tmp-", Sys.getpid(), "-", substr(digest::digest(stats::runif(1)), 1, 8))
  on.exit(unlink(tmp), add = TRUE)
  jsonlite::write_json(info, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null")
  ensure_private_file(tmp)
  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
  }
  ensure_private_file(path)
  invisible(info)
}

session_create <- function(
  session_name = NULL,
  project = getwd(),
  max_entries = getOption("lazybtw.dish.max_entries", 100L),
  max_entry_bytes = getOption("lazybtw.dish.max_entry_bytes", 64L * 1024L),
  max_total_bytes = getOption("lazybtw.dish.max_total_bytes", 5L * 1024L * 1024L),
  cleanup = TRUE
) {
  check_bool(cleanup)
  if (isTRUE(cleanup)) {
    session_cleanup(remove_dishes = TRUE)
  }
  max_entries <- lazybtw_check_limit(max_entries, "max_entries", min = 1L)
  max_entry_bytes <- lazybtw_check_limit(max_entry_bytes, "max_entry_bytes", min = 1L)
  max_total_bytes <- lazybtw_check_limit(max_total_bytes, "max_total_bytes", min = 1L)

  ensure_lazybtw_dirs()

  session_id <- session_validate_id(session_name %||% session_id_generate())
  dish_path <- file.path(lazybtw_paths()$dishes, paste0(session_id, ".ndjson"))
  ensure_private_file(dish_path)

  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  info <- list(
    session_id = session_id,
    pid = Sys.getpid(),
    created_at = now,
    updated_at = now,
    project = normalizePath(project, mustWork = FALSE),
    dish_path = normalizePath(dish_path, mustWork = FALSE),
    r_version = as.character(getRversion()),
    platform = R.version$platform,
    max_entries = as.integer(max_entries),
    max_entry_bytes = as.integer(max_entry_bytes),
    max_total_bytes = as.integer(max_total_bytes)
  )

  session_write(info)
  .lazybtw_env$session <- info
  invisible(info)
}

session_current <- function(auto_start = FALSE) {
  info <- .lazybtw_env$session

  if (!is.null(info) && auto_start) {
    paths <- lazybtw_paths()
    dish_dir <- normalizePath(paths$dishes, mustWork = FALSE)
    info_dish_dir <- normalizePath(dirname(info$dish_path), mustWork = FALSE)
    stale <- !identical(info_dish_dir, dish_dir) || !file.exists(info$dish_path)
    if (stale) {
      info <- NULL
      .lazybtw_env$session <- NULL
    }
  }

  if (is.null(info) && auto_start) {
    info <- session_create(cleanup = TRUE)
  }
  info
}

session_touch <- function(info = session_current(auto_start = FALSE)) {
  if (is.null(info)) {
    return(invisible(NULL))
  }
  info$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  .lazybtw_env$session <- info
  session_write(info)
  invisible(info)
}

session_read <- function(path) {
  if (!check_safe_path(path)) {
    return(NULL)
  }
  tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL)
}

session_list <- function(active_only = TRUE) {
  ensure_lazybtw_dirs()
  files <- list.files(lazybtw_paths()$sessions, pattern = "[.]json$", full.names = TRUE)
  sessions <- lapply(files, session_read)
  sessions <- sessions[!vapply(sessions, is.null, logical(1))]
  if (!length(sessions)) {
    return(list())
  }

  sessions <- sessions[vapply(sessions, session_is_safe, logical(1))]
  if (active_only && length(sessions)) {
    sessions <- sessions[vapply(sessions, session_is_alive, logical(1))]
  }
  if (!length(sessions)) {
    return(list())
  }

  sessions[order(vapply(sessions, function(x) x$updated_at %||% "", character(1)), decreasing = TRUE)]
}

session_cleanup <- function(all = FALSE, remove_dishes = TRUE) {
  check_bool(all)
  check_bool(remove_dishes)

  ensure_lazybtw_dirs()
  files <- list.files(lazybtw_paths()$sessions, pattern = "[.]json$", full.names = TRUE)
  removed <- character()

  for (file in files) {
    info <- session_read(file)
    remove <- isTRUE(all) || is.null(info) || !session_is_safe(info) || !session_is_alive(info)
    if (!remove) {
      next
    }

    if (isTRUE(remove_dishes) && !is.null(info)) {
      dish_path <- info$dish_path %||% NULL
      if (!is.null(dish_path) && file.exists(dish_path) && check_safe_path(dish_path)) {
        unlink(dish_path)
        removed <- c(removed, dish_path)
      }
    }

    unlink(file)
    removed <- c(removed, file)
  }

  invisible(unique(removed))
}


session_is_alive <- function(info) {
  pid <- suppressWarnings(as.integer(info$pid %||% NA_integer_))
  if (is.na(pid) || pid <= 0L) {
    return(FALSE)
  }

  # tools::pskill(pid, 0) checks process existence on Unix-alike systems.
  # On platforms where this is not supported, keep the session rather than
  # hiding potentially valid context.
  ok <- tryCatch(tools::pskill(pid, signal = 0L), error = function(e) NA)
  if (is.na(ok)) {
    return(TRUE)
  }
  isTRUE(ok)
}

session_entry_count <- function(info) {
  path <- info$dish_path %||% NULL
  if (is.null(path) || !file.exists(path) || !check_safe_path(path)) {
    return(0L)
  }
  dish_store_count(path)
}

session_is_safe <- function(info) {
  path <- info$dish_path %||% NULL
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    return(FALSE)
  }
  check_safe_path(path) && check_safe_path(dirname(path))
}


lazybtw_check_limit <- function(x, arg, min = 1L) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < min) {
    stop("`", arg, "` must be a number greater than or equal to ", min, ".", call. = FALSE)
  }
  as.integer(x)
}
