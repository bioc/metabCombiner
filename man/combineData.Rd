% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/generics.R, R/methods-featdata.R
\name{combineData}
\alias{combineData}
\alias{combineData,metabCombiner-method}
\title{Obtain All Feature Data}
\usage{
combineData(object)

\S4method{combineData}{metabCombiner}(object)
}
\arguments{
\item{object}{\code{metabCombiner} object}
}
\value{
A data.frame containing meta-data columns as well as sample + extra
columns for each of the constituent data sets.
}
\description{
Obtain all meta-data (m/z, RT, Q, id, adduct) alongside their
respective sample (+ extra) values for aligned features. This is a
(quasi)merge of the /code{/link{combinedTable}} and /code{/link{featData}}
tables and methods.
}
\examples{
data(plasma30)
data(plasma20)

p30 <- metabData(head(plasma30,500), samples = "CHEAR")
p20 <- metabData(head(plasma20,500), samples = "Red")

p.comb <- metabCombiner(p30, p20)
p.comb.table <- combineData(p.comb)

}
