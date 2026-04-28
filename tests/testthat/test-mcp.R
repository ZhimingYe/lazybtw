test_that("R-side MCP server is removed", {
  expect_false(exists("mcp_stdio", asNamespace("lazybtw"), inherits = FALSE))
})
