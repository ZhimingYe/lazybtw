write_to_clipboard <- function(x, what = "{.pkg lazybtw}") {
  tryCatch(
    {
      dish_add(
        text = x,
        source = "clipboard",
        kind = "generated-output",
        label = what,
        meta = list()
      )
    },
    error = function(e) {
      cli::cli_alert_warning(
        "Could not add output to lazybtw::dish(): {conditionMessage(e)}"
      )
    }
  )

  if (!is_interactive() || !clipr::clipr_available()) {
    if (is_interactive()) {
      cli::cli_alert_warning(
        "Clipboard is not available; output was added to lazybtw::dish()."
      )
      cli::cat_line(x)
    }
    return(invisible(x))
  }

  # nocov start
  tryCatch(
    {
      clipr::write_clip(x)
      cli::cli_alert_success(
        sprintf("%s copied to the clipboard and added to lazybtw::dish()!", what)
      )
    },
    error = function(e) {
      cli::cli_alert_warning(
        "Clipboard write failed; output was still added to lazybtw::dish()."
      )
      e
    }
  )
  # nocov end

  invisible(x)
}
