dish_text_truncate <- function(text, max_bytes) {
  text <- paste(as.character(text), collapse = "\n")
  truncated <- FALSE
  max_bytes <- suppressWarnings(as.integer(max_bytes))
  if (is.na(max_bytes) || max_bytes < 1L) {
    max_bytes <- 1L
  }

  if (is.finite(max_bytes) && nchar(text, type = "bytes") > max_bytes) {
    truncated <- TRUE
    raw <- charToRaw(enc2utf8(text))
    raw <- raw[seq_len(min(length(raw), max_bytes))]
    text <- ""
    while (length(raw) > 0L) {
      candidate <- rawToChar(raw)
      candidate <- suppressWarnings(iconv(candidate, from = "UTF-8", to = "UTF-8", sub = ""))
      if (!is.na(candidate) && nchar(candidate, type = "bytes") <= max_bytes) {
        text <- candidate
        break
      }
      raw <- raw[-length(raw)]
    }
  }
  list(text = text, truncated = truncated)
}

dish_store_read <- function(path, limit = Inf) {
  if (!file.exists(path) || file.info(path)$size == 0) {
    return(list())
  }
  if (!check_safe_path(path)) {
    warning("Dish file is not safe to read: ", path, call. = FALSE)
    return(list())
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(lines)]
  if (is.infinite(limit)) {
    # keep all lines
  } else {
    limit <- suppressWarnings(as.integer(limit))
    if (!is.na(limit) && limit > 0L) {
    lines <- utils::tail(lines, limit)
    } else {
      lines <- character()
    }
  }
  records <- lapply(lines, function(line) {
    tryCatch(jsonlite::fromJSON(line, simplifyVector = TRUE), error = function(e) NULL)
  })
  records[!vapply(records, is.null, logical(1))]
}

dish_store_write <- function(path, records) {
  ensure_private_file(path)
  lines <- vapply(records, jsonlite::toJSON, character(1), auto_unbox = TRUE, null = "null")
  tmp <- paste0(path, ".tmp-", Sys.getpid(), "-", substr(digest::digest(stats::runif(1)), 1, 8))
  on.exit(unlink(tmp), add = TRUE)
  writeLines(lines, tmp, useBytes = TRUE)
  ensure_private_file(tmp)
  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
  }
  ensure_private_file(path)
  invisible(path)
}

dish_store_prune <- function(path, max_entries, max_total_bytes) {
  records <- dish_store_read(path)
  if (!length(records)) {
    return(invisible(path))
  }

  if (is.finite(max_entries) && length(records) > max_entries) {
    records <- utils::tail(records, max_entries)
  }

  if (is.finite(max_total_bytes)) {
    repeat {
      lines <- vapply(records, jsonlite::toJSON, character(1), auto_unbox = TRUE, null = "null")
      size <- sum(nchar(lines, type = "bytes")) + length(lines)
      if (size <= max_total_bytes || length(records) <= 1L) {
        break
      }
      records <- records[-1]
    }
  }

  dish_store_write(path, records)
  invisible(path)
}

dish_store_append <- function(path, record, max_entries, max_total_bytes) {
  ensure_private_file(path)
  line <- jsonlite::toJSON(record, auto_unbox = TRUE, null = "null")
  cat(line, "\n", file = path, append = TRUE, sep = "")
  ensure_private_file(path)
  dish_store_prune(path, max_entries = max_entries, max_total_bytes = max_total_bytes)
  invisible(record)
}

dish_store_clear <- function(path) {
  ensure_private_file(path)
  writeLines(character(), path)
  ensure_private_file(path)
  invisible(path)
}

dish_store_count <- function(path) {
  length(dish_store_read(path))
}
