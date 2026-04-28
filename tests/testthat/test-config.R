test_that("mcp_config returns Claude-style lazybtw C stdio JSON", {
  json <- mcp_config("claude-code", print = FALSE)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_match(parsed$mcpServers$lazybtw$command, "lazybtw-mcp", fixed = TRUE)
  expect_equal(parsed$mcpServers$lazybtw$args, list())
})

test_that("mcp_config supports vscode format", {
  json <- mcp_config("vscode", print = FALSE)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_equal(parsed$servers$lazybtw$type, "stdio")
  expect_match(parsed$servers$lazybtw$command, "lazybtw-mcp", fixed = TRUE)
})

test_that("mcp_config prints when requested", {
  out <- capture.output(json <- mcp_config("claude-desktop", print = TRUE))
  expect_match(paste(out, collapse = "\n"), "lazybtw-mcp", fixed = TRUE)
  expect_match(json, "lazybtw-mcp", fixed = TRUE)
})

test_that("use_rprofile writes an idempotent startup block", {
  path <- file.path(withr::local_tempdir(), ".Rprofile")

  suppressMessages(first <- use_rprofile(path))
  lines <- readLines(path, warn = FALSE)
  expect_equal(first, path)
  expect_true(any(grepl("lazybtw::dish_start", lines, fixed = TRUE)))

  suppressMessages(second <- use_rprofile(path))
  lines2 <- readLines(path, warn = FALSE)
  expect_equal(second, path)
  expect_equal(sum(grepl("lazybtw::dish_start", lines2, fixed = TRUE)), 1)
})
