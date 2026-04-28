test_that("btw() works without clipboard access", {
  withr::local_envvar(list(CLIPR_ALLOW = FALSE))
  withr::local_options(list(
    rlang_interactive = TRUE,
    lazybtw.data_dir = withr::local_tempdir()
  ))

  # When clipboard is not available, we echo the prompt context
  expect_snapshot(
    btw("Interactive call but clipboard not available")
  )

  # Unless, clipboard is FALSE
  expect_silent(
    expect_equal(
      format(btw("Hello world", clipboard = FALSE)),
      "## User\nHello world"
    )
  )
})

test_that("write_to_clipboard adds output to dish when clipboard is unavailable", {
  withr::local_envvar(list(CLIPR_ALLOW = FALSE))
  withr::local_options(list(
    rlang_interactive = FALSE,
    lazybtw.data_dir = withr::local_tempdir()
  ))

  expect_invisible(write_to_clipboard("dish only", what = "test output"))

  df <- dish(format = "data.frame")
  expect_equal(nrow(df), 1)
  expect_equal(df$text, "dish only")
  expect_equal(df$source, "clipboard")
  expect_equal(df$kind, "generated-output")
  expect_equal(df$label, "test output")
})
