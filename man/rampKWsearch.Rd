% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/GeneralFunctions.R
\name{rampKWsearch}
\alias{rampKWsearch}
\title{The function does key word search from given synonym on within databases}
\usage{
rampKWsearch(word, database, conpass, dbname = "ramp", username = "root")
}
\arguments{
\item{word}{string value that describe the keyword user want to search}

\item{database}{string value that describe where the user want to search
for key word}

\item{conpass}{password for database access (string)}

\item{dbname}{name of the mysql database (default is "ramp")}

\item{username}{username for database access (default is "root")}
}
\value{
If there is at least one itmes in database vaguely matching key
word, it will return a data frame that contains all search result. Otherwise
it will return a string value to inform user.
}
\description{
The function does key word search from given synonym on within databases
}
