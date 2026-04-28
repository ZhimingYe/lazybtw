test_that("lazybtw-mcp C executable speaks MCP over stdio", {
  skip_on_os("windows")

  repo <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = TRUE)
  exe <- file.path(repo, "exec", "lazybtw-mcp")
  src <- file.path(repo, "exec", "lazybtw-mcp.c")

  if (!file.exists(exe) || file.info(exe)$mtime < file.info(src)$mtime) {
    status <- system2(file.path(repo, "exec", "build-lazybtw-mcp.sh"), stdout = TRUE, stderr = TRUE)
    expect_true(file.exists(exe), info = paste(status, collapse = "\n"))
  }

  smoke <- withr::local_tempdir()
  data_dir <- file.path(smoke, "data")
  sessions_dir <- file.path(data_dir, "sessions")
  dishes_dir <- file.path(data_dir, "dishes")
  dir.create(sessions_dir, recursive = TRUE)
  dir.create(dishes_dir, recursive = TRUE)
  Sys.chmod(c(data_dir, sessions_dir, dishes_dir), "0700")

  dish <- file.path(dishes_dir, "smoke.ndjson")
  session <- file.path(sessions_dir, "smoke.json")
  writeLines(c(
    '{"id":"1","time":"2026-04-28T00:00:00+0800","session_id":"smoke","source":"manual","kind":"text","label":"first","text":"hello from unit dish","truncated":false,"meta":{},"sha256":"x"}',
    '{"id":"2","time":"2026-04-28T00:00:01+0800","session_id":"smoke","source":"clipboard","kind":"btw","label":"second","text":"latest unit context","truncated":false,"meta":{},"sha256":"y"}'
  ), dish, useBytes = TRUE)
  writeLines(sprintf(
    '{"session_id":"smoke","pid":%d,"created_at":"2026-04-28T00:00:00+0800","updated_at":"2026-04-28T00:00:01+0800","project":"%s","dish_path":"%s"}',
    Sys.getpid(), repo, dish
  ), session, useBytes = TRUE)
  Sys.chmod(c(dish, session), "0600")

  msg <- function(x) {
    body <- jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")
    paste0("Content-Length: ", nchar(body, type = "bytes"), "\r\n\r\n", body)
  }
  input <- paste0(
    msg(list(jsonrpc = "2.0", id = 1, method = "initialize", params = list())),
    msg(list(jsonrpc = "2.0", id = 2, method = "tools/list", params = list())),
    msg(list(jsonrpc = "2.0", id = 3, method = "tools/call", params = list(name = "List_R_Sessions", arguments = list()))),
    msg(list(jsonrpc = "2.0", id = 4, method = "tools/call", params = list(name = "Inspect_R_lang_Context", arguments = list(limit = 2))))
  )

  in_file <- file.path(smoke, "in.bin")
  out_file <- file.path(smoke, "out.bin")
  writeChar(input, in_file, eos = NULL, useBytes = TRUE)

  env <- c(paste0("LAZYBTW_DATA_DIR=", data_dir))
  raw_lines <- system2(exe, stdin = in_file, stdout = TRUE, stderr = TRUE, env = env)
  expect_equal(attr(raw_lines, "status") %||% 0L, 0L, info = paste(raw_lines, collapse = "\n"))

  raw <- paste(raw_lines, collapse = "\n")
  expect_match(raw, "lazybtw", fixed = TRUE)
  expect_match(raw, "List_R_Sessions", fixed = TRUE)
  expect_match(raw, "Inspect_R_lang_Context", fixed = TRUE)
  expect_match(raw, "smoke", fixed = TRUE)
  expect_match(raw, "hello from unit dish", fixed = TRUE)
  expect_match(raw, "latest unit context", fixed = TRUE)
})
