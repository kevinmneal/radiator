% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/vcf.R
\name{clean_ad}
\alias{clean_ad}
\title{clean_ad}
\usage{
clean_ad(x, split.vec, parallel.core = parallel::detectCores() - 1)
}
\description{
Clean allele depth field in VCF.
AD column: splitting coverage info into ALLELE_REF_DEPTH and ALLELE_ALT_DEPTH
}
\keyword{internal}
