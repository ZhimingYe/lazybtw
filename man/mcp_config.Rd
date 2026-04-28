% Generated manually for lazybtw MVP
\name{mcp_config}
\alias{mcp_config}
\alias{use_rprofile}
\title{Configure lazybtw MCP and R startup}
\usage{
mcp_config(
  client = c("claude-code", "claude-desktop", "vscode", "continue"),
  print = TRUE
)

use_rprofile(path = "project")
}
\arguments{
\item{client}{MCP client configuration format.}
\item{print}{Whether to print the JSON snippet.}
\item{path}{\file{.Rprofile} path to update, or \code{"project"}/\code{"user"}.}
}
\value{
\code{mcp_config()} returns the JSON string invisibly. \code{use_rprofile()} returns the updated \file{.Rprofile} path invisibly.
}
\description{
\code{mcp_config()} prints a JSON snippet for configuring the standalone read-only \code{lazybtw-mcp} stdio MCP server. The MCP server is a C executable that reads local lazybtw dish files directly; it does not start R, renv, pkgload, or mcptools. \code{use_rprofile()} adds an idempotent startup block that calls \code{lazybtw::dish_start()} in interactive R sessions.
}
\examples{
mcp_config("claude-code", print = FALSE)
}
\keyword{utilities}
