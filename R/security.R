# Private local storage helpers for lazybtw dish files.

lazybtw_data_dir <- function() {
  dir <- getOption("lazybtw.data_dir", NULL)
  if (is.null(dir)) {
    dir <- Sys.getenv("LAZYBTW_DATA_DIR", unset = NA_character_)
    if (is.na(dir) || !nzchar(dir)) {
      dir <- NULL
    }
  }
  if (is.null(dir)) {
    dir <- tools::R_user_dir("lazybtw", "data")
  }
  normalizePath(dir, mustWork = FALSE)
}

lazybtw_paths <- function(base_dir = lazybtw_data_dir()) {
  list(
    base = base_dir,
    sessions = file.path(base_dir, "sessions"),
    dishes = file.path(base_dir, "dishes"),
    locks = file.path(base_dir, "locks")
  )
}

ensure_private_dir <- function(path) {
  if (!dir.exists(path)) {
    ok <- dir.create(path, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    if (!ok && !dir.exists(path)) {
      stop("Could not create lazybtw directory: ", path, call. = FALSE)
    }
  }
  if (!dir.exists(path)) {
    stop("lazybtw path is not a directory: ", path, call. = FALSE)
  }
  if (.Platform$OS.type != "windows") {
    Sys.chmod(path, mode = "0700", use_umask = FALSE)
  }
  invisible(normalizePath(path, mustWork = FALSE))
}

ensure_private_file <- function(path) {
  parent <- dirname(path)
  if (!dir.exists(parent)) {
    ensure_private_dir(parent)
  }
  if (dir.exists(path)) {
    stop("lazybtw file path is a directory: ", path, call. = FALSE)
  }
  if (!file.exists(path)) {
    ok <- file.create(path)
    if (!ok && !file.exists(path)) {
      stop("Could not create lazybtw file: ", path, call. = FALSE)
    }
  }
  if (.Platform$OS.type != "windows") {
    Sys.chmod(path, mode = "0600", use_umask = FALSE)
  }
  invisible(normalizePath(path, mustWork = FALSE))
}

ensure_lazybtw_dirs <- function() {
  paths <- lazybtw_paths()
  ensure_private_dir(paths$base)
  ensure_private_dir(paths$sessions)
  ensure_private_dir(paths$dishes)
  ensure_private_dir(paths$locks)
  invisible(paths)
}

current_uid <- function() {
  info <- Sys.info()[["user"]]
  if (is.na(info)) NULL else info
}

check_safe_path <- function(path, must_exist = TRUE) {
  if (must_exist && !file.exists(path)) {
    return(FALSE)
  }

  if (.Platform$OS.type == "windows") {
    return(TRUE)
  }

  info <- file.info(path, extra_cols = TRUE)
  if (!nrow(info) || is.na(info$mode)) {
    return(FALSE)
  }
  if (isTRUE(info$isdir) && !dir.exists(path)) {
    return(FALSE)
  }

  user <- current_uid()
  if (!is.null(user) && "uname" %in% names(info) && !is.na(info$uname) && !identical(info$uname, user)) {
    return(FALSE)
  }

  # Reject group/world-writable files or directories.
  mode <- as.integer(info$mode)
  if (bitwAnd(mode, strtoi("022", 8L)) != 0L) {
    return(FALSE)
  }

  TRUE
}
