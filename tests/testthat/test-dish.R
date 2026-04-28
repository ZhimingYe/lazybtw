test_that("dish MVP writes, reads, clears, and reports status", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))

  info <- dish_start(session_name = "r-test", max_entries = 10, max_entry_bytes = 1000)
  expect_equal(info$session_id, "r-test")
  expect_true(file.exists(dish_path()))

  rec <- dish_add("hello dish", source = "test", kind = "text", label = "greeting")
  expect_equal(rec$text, "hello dish")

  md <- dish()
  expect_match(md, "# R language context", fixed = TRUE)
  expect_match(md, "hello dish", fixed = TRUE)

  df <- dish(format = "data.frame")
  expect_equal(nrow(df), 1)
  expect_equal(df$text, "hello dish")

  status <- dish_status()
  expect_equal(status$entries, 1)
  expect_true(status$size > 0)

  expect_true(dish_clear(confirm = FALSE))
  expect_equal(dish_status()$entries, 0)
})

test_that("dish_add lazily starts and truncates entries", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))

  dish_start(session_name = "r-truncate", max_entry_bytes = 10)
  rec <- dish_add(paste(rep("x", 100), collapse = ""))
  expect_true(rec$truncated)
  expect_lte(nchar(rec$text, type = "bytes"), 10)
})

test_that("dish prunes old entries", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))

  dish_start(session_name = "r-prune", max_entries = 2)
  dish_add("one")
  dish_add("two")
  dish_add("three")

  df <- dish(format = "data.frame")
  expect_equal(nrow(df), 2)
  expect_equal(df$text, c("two", "three"))
})

test_that("session_list filters dead sessions and sorts by updated_at", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))

  dish_start(session_name = "r-alive-old")
  dish_add("alive old")
  Sys.sleep(0.01)
  dish_start(session_name = "r-alive-new")
  dish_add("alive new")

  dead <- session_create(session_name = "r-dead")
  dead$pid <- 999999999L
  session_write(dead)

  sessions <- session_list()
  ids <- vapply(sessions, function(x) x$session_id, character(1))
  expect_false("r-dead" %in% ids)
  expect_equal(ids[1], "r-alive-new")
  expect_true(all(c("r-alive-old", "r-alive-new") %in% ids))
})

test_that("dish truncation handles multibyte text with tiny limits", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))

  dish_start(session_name = "r-multibyte", max_entry_bytes = 1)
  rec <- dish_add("你好")
  expect_true(rec$truncated)
  expect_lte(nchar(rec$text, type = "bytes"), 1)
})

test_that("session names are validated and cannot traverse paths", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))

  expect_error(dish_start(session_name = "../evil"), "session_name")
  expect_error(dish_start(session_name = ""), "session_name")
})

test_that("dish_store_read keeps all records with infinite limit and ignores corrupt lines", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))
  info <- dish_start(session_name = "r-corrupt")
  dish_add("one")
  dish_add("two")
  cat("not json\n", file = info$dish_path, append = TRUE)

  records <- dish_store_read(info$dish_path, limit = Inf)
  expect_equal(length(records), 2)
  expect_equal(vapply(records, function(x) x$text, character(1)), c("one", "two"))
})

test_that("dish_start automatically cleans dead sessions and dish files", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))

  dead <- session_create(session_name = "r-dead-auto", cleanup = FALSE)
  dish_store_append(dead$dish_path, list(text = "dead"), max_entries = 10, max_total_bytes = 10000)
  dead$pid <- 999999999L
  session_write(dead)
  expect_true(file.exists(dead$dish_path))
  expect_true(file.exists(session_file("r-dead-auto")))

  dish_start(session_name = "r-alive-auto")

  expect_false(file.exists(dead$dish_path))
  expect_false(file.exists(session_file("r-dead-auto")))
  expect_true(file.exists(session_file("r-alive-auto")))
})

test_that("public dish session cleanup and listing helpers work", {
  local_dir <- withr::local_tempdir()
  withr::local_options(list(lazybtw.data_dir = local_dir))

  dish_start(session_name = "r-public-alive", cleanup = FALSE)
  dish_add("alive")

  dead <- session_create(session_name = "r-public-dead", cleanup = FALSE)
  dish_store_append(dead$dish_path, list(text = "dead"), max_entries = 10, max_total_bytes = 10000)
  dead$pid <- 999999999L
  session_write(dead)

  all_sessions <- dish_sessions(active_only = FALSE)
  expect_true(all(c("r-public-alive", "r-public-dead") %in% all_sessions$session_id))

  active_sessions <- dish_sessions(active_only = TRUE)
  expect_true("r-public-alive" %in% active_sessions$session_id)
  expect_false("r-public-dead" %in% active_sessions$session_id)

  removed <- dish_cleanup()
  expect_true(any(grepl("r-public-dead", removed, fixed = TRUE)))
  expect_false(file.exists(dead$dish_path))
  expect_false(file.exists(session_file("r-public-dead")))
  expect_true(file.exists(session_file("r-public-alive")))
})
