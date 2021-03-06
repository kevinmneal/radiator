# tidy_genind ------------------------------------------------------------------
#' @name tidy_genind
#' @title Tidy a genind object to a tidy dataframe
#' @description Tidy genind object from
#' \href{https://github.com/thibautjombart/adegenet}{adegenet} to a tidy dataframe.
#' Used internally in \href{https://github.com/thierrygosselin/radiator}{radiator}
#' and might be of interest for users.

#' @param data (path or object) A genind object in the global environment or
#' path to a genind file that will be open with \code{readRDS}.

#' @param keep.allele.names Allows to keep allele names for the tidy dataset.
#' Requires the alleles to be numeric. To have this argument in
#' \pkg{radiator} \code{\link{tidy_genomic_data}} or
#' \pkg{radiator} \code{\link{genomic_converter}}
#' use it at the end. \code{...} in those function looks for it.
#' Default: \code{keep.allele.names = FALSE}.

#' @param tidy (logical) Generate a tidy dataset.
#' Default: \code{tidy = TRUE}.


#' @param gds (optional, logical) To write a radiator gds object.
#' Currently, for biallelic datasets only.
#' Default: \code{gds = TRUE}.

#' @param write (optional, logical) To write in the working directory the tidy
#' data. The file is written with \code{radiator_genind_DATE@TIME.rad}.
#' Default: \code{write = FALSE}.

#' @inheritParams radiator_common_arguments


#' @export
#' @rdname tidy_genind
#' @references Jombart T (2008) adegenet: a R package for the multivariate
#' analysis of genetic markers. Bioinformatics, 24, 1403-1405.
#' @references Jombart T, Ahmed I (2011) adegenet 1.3-1:
#' new tools for the analysis of genome-wide SNP data.
#' Bioinformatics, 27, 3070-3071.


#' @author Thierry Gosselin \email{thierrygosselin@@icloud.com}


tidy_genind <- function(
  data,
  keep.allele.names = FALSE,
  tidy = TRUE,
  gds = TRUE,
  write = FALSE,
  verbose = FALSE
) {

  # Checking for missing and/or default arguments ------------------------------
  if (missing(data)) rlang::abort("data argument required")
  if (is.vector(data)) data <- readRDS(data)
  if (class(data)[1] != "genind") rlang::abort("Input is not a genind object")
  if (verbose) message("genind info:")
  strata <- tibble::tibble(INDIVIDUALS = rownames(data@tab))
  if (is.null(data@pop)) {
    if (verbose) message("    strata: no")
    if (verbose) message("    'pop' will be added")
    strata %<>% dplyr::mutate(STRATA = "pop")
  } else {
    if (verbose) message("    strata: yes")
    strata$STRATA = data@pop
  }

  biallelic <- max(unique(data@loc.n.all)) == 2
  if (!biallelic) gds <- FALSE

  if (gds) {
    # prepare genind
    alt.alleles <- tibble::tibble(
      MARKERS_ALLELES = colnames(data@tab),
      COUNT = colSums(x = data@tab, na.rm = TRUE)
    ) %>%
      dplyr::mutate(
        MARKERS = stringi::stri_extract_first_regex(str = colnames(data@tab), pattern = "^[^.]+"),
        ALLELES = stringi::stri_extract_last_regex(str = colnames(data@tab), pattern = "(?<=\\.).*")
      ) %>%
      dplyr::arrange(MARKERS, COUNT, ALLELES) %>%
      dplyr::mutate(REF = rep(c("ALT", "REF"), n() / 2))

    # check that REF/ALT are A, C, G, T before going further
    # any(unique(alt.alleles$ALLELES) %in% c("A", "C", "G", "T"))
    # any(unique(c("A", "DD", "G")) %in% c("A", "C", "G", "T"))

    ref.alt <- dplyr::select(alt.alleles, MARKERS, REF, ALLELES) %>%
      data.table::as.data.table(.) %>%
      data.table::dcast.data.table(
        data = .,
        formula = MARKERS ~ REF,
        value.var = "ALLELES"
      ) %>%
      tibble::as_tibble(.)

    alt.alleles %<>% dplyr::filter(REF == "ALT") %$% MARKERS_ALLELES

    geno <- tibble::as_tibble(t(data@tab), rownames = "MARKERS") %>%
      dplyr::filter(MARKERS %in% alt.alleles) %>%
      dplyr::mutate(
        MARKERS = stringi::stri_extract_first_regex(str = MARKERS, pattern = "^[^.]+"),
        VARIANT_ID = as.integer(factor(MARKERS))) %>%
      dplyr::arrange(VARIANT_ID)

    alt.alleles <- NULL
    markers.meta <- dplyr::select(geno, VARIANT_ID, MARKERS) %>%
      dplyr::left_join(ref.alt, by = "MARKERS")
    ref.alt <- NULL

    suppressWarnings(
      geno %<>%
        dplyr::select(-MARKERS) %>%
        tibble::column_to_rownames(.data = ., var = "VARIANT_ID")
    )

    gds.filename <- radiator_gds(
      data.source = "genind",
      genotypes = geno,
      strata = strata,
      biallelic = TRUE,
      markers.meta = markers.meta,
      filename = NULL,
      verbose = verbose
    )
    if (verbose) message("Written: GDS filename: ", gds.filename)
  }# End gds genind

  if (tidy) {
    if (write) {
      filename.temp <- generate_filename(extension = "rad")
      filename.short <- filename.temp$filename.short
      filename.genind <- filename.temp$filename
    }

    A2 <- TRUE %in% unique(stringi::stri_detect_fixed(str = sample(colnames(data@tab), 100), pattern = ".A2"))

    if (biallelic && A2) {
      # changed adegenet::indNames to rownames(data@tab) to lower dependencies
      data <- tibble::as_tibble(data@tab) %>%
        tibble::add_column(.data = ., INDIVIDUALS = rownames(data@tab), .before = 1) %>%
        tibble::add_column(.data = ., POP_ID = data@pop) %>%
        dplyr::select(POP_ID, INDIVIDUALS, dplyr::ends_with(match = ".A2")) %>%
        # tidyr::gather(data = ., key = MARKERS, value = GT_BIN, -c(POP_ID, INDIVIDUALS)) %>%
        data.table::as.data.table(.) %>%
        data.table::melt.data.table(
          data = .,
          id.vars = c("INDIVIDUALS", "POP_ID"),
          variable.name = "MARKERS",
          value.name = "GT_BIN"
        ) %>%
        tibble::as_tibble(.) %>%
        dplyr::mutate(
          MARKERS = stringi::stri_replace_all_fixed(
            str = MARKERS, pattern = ".A2", replacement = "", vectorize_all = FALSE),
          GT_VCF = dplyr::if_else(GT_BIN == 0, "0/0",
                                  dplyr::if_else(GT_BIN == 1, "0/1", "1/1"), missing = "./."),
          GT = dplyr::if_else(GT_BIN == 0, "001001", dplyr::if_else(GT_BIN == 1, "001002", "002002") , missing = "000000")
        )
    } else {

      if (keep.allele.names) {
        message("Alleles names are kept if all numeric and padded with 0 if length < 3")
        data <- tibble::as_tibble(data@tab) %>%
          tibble::add_column(.data = ., INDIVIDUALS = rownames(data@tab), .before = 1) %>%
          tibble::add_column(.data = ., POP_ID = data@pop) %>%
          # tidyr::gather(data = ., key = MARKERS_ALLELES, value = COUNT, -c(POP_ID, INDIVIDUALS)) %>%
          data.table::as.data.table(.) %>%
          data.table::melt.data.table(
            data = .,
            id.vars = c("INDIVIDUALS", "POP_ID"),
            variable.name = "MARKERS_ALLELES",
            value.name = "COUNT"
          ) %>%
          tibble::as_tibble(.) %>%
          dplyr::filter(COUNT > 0 | is.na(COUNT)) %>%
          tidyr::separate(data = ., col = MARKERS_ALLELES, into = c("MARKERS", "ALLELES"), sep = "\\.")

        check.alleles <- unique(stringi::stri_detect_regex(str = unique(data$ALLELES), pattern = "[0-9]"))
        check.alleles <- length(check.alleles) == 1 && check.alleles

        if (check.alleles) {
          data <- data %>%
            dplyr::mutate(
              ALLELES = stringi::stri_pad_left(str = ALLELES, pad = "0", width = 3)
            )
        } else {
          data <- data %>%
            dplyr::mutate(
              ALLELES = as.numeric(factor(ALLELES)),
              ALLELES = stringi::stri_pad_left(str = ALLELES, pad = "0", width = 3)
            )
        }

      } else {
        message("Alleles names for each markers will be converted to factors and padded with 0")
        data <- tibble::as_tibble(data@tab) %>%
          tibble::add_column(.data = ., INDIVIDUALS = rownames(data@tab), .before = 1) %>%
          tibble::add_column(.data = ., POP_ID = data@pop) %>%
          # tidyr::gather(data = ., key = MARKERS_ALLELES, value = COUNT, -c(POP_ID, INDIVIDUALS)) %>%
          data.table::as.data.table(.) %>%
          data.table::melt.data.table(
            data = .,
            id.vars = c("INDIVIDUALS", "POP_ID"),
            variable.name = "MARKERS_ALLELES",
            value.name = "COUNT"
          ) %>%
          tibble::as_tibble(.) %>%
          dplyr::filter(COUNT > 0 | is.na(COUNT)) %>%
          tidyr::separate(data = ., col = MARKERS_ALLELES, into = c("MARKERS", "ALLELES"), sep = "\\.") %>%
          dplyr::mutate(
            ALLELES = as.numeric(factor(ALLELES)),
            ALLELES = stringi::stri_pad_left(str = ALLELES, pad = "0", width = 3)
          )
      }


      # #If the genind was coded with allele 0, this will generate missing data with this code
      # allele.zero <- TRUE %in% stringi::stri_detect_regex(str = unique(data3$ALLELES), pattern = "^0$")
      # if (allele.zero) stop("alleles in this multiallelic genind were coded as 0 and won't work with this script")

      #Isolate missing genotype
      missing.hom <- dplyr::filter(data, is.na(COUNT)) %>%
        dplyr::distinct(POP_ID, INDIVIDUALS, MARKERS) %>%
        dplyr::mutate(GT = rep("000000", n())) %>%
        dplyr::ungroup(.)

      #Isolate all Homozygote genotypes and combine with the missings
      missing.hom <- dplyr::filter(data, COUNT == 2) %>%
        dplyr::group_by(POP_ID, INDIVIDUALS, MARKERS) %>%
        dplyr::summarise(GT = stringi::stri_join(ALLELES, ALLELES, sep = "")) %>%
        dplyr::ungroup(.) %>%
        dplyr::bind_rows(missing.hom)

      #Isolate all Het genotypes and combine
      data <- dplyr::filter(data, COUNT != 2) %>%#this will also remove the missing
        dplyr::group_by(POP_ID, INDIVIDUALS, MARKERS) %>%
        dplyr::summarise(GT = stringi::stri_join(ALLELES, collapse = "")) %>%
        dplyr::ungroup(.) %>%
        dplyr::bind_rows(missing.hom)
      missing.hom <- NULL
    }#End for multi-allelic

    if (write) {
      radiator::write_rad(data = data, path = filename.genind)
      if (verbose) message("File written: ", filename.short)
    }
  }# End tidy genind

  return(data)
} # End tidy_genind


# write_genind ------------------------------------------------------------------

#' @name write_genind
#' @title Write a genind object from a tidy data frame or GDS file or object.

#' @description Write a genind object from a tidy data frame.
#' Used internally in \href{https://github.com/thierrygosselin/radiator}{radiator}
#' and \href{https://github.com/thierrygosselin/assigner}{assigner}
#' and might be of interest for users.

#' @inheritParams radiator_common_arguments

#' @param write (logical, optional) To write in the working directory the genind
#' object. The file is written with \code{radiator_genind_DATE@TIME.RData} and
#' can be open with load or readRDS.
#' Default: \code{write = FALSE}.

#' @export
#' @rdname write_genind

#' @references Jombart T (2008) adegenet: a R package for the multivariate
#' analysis of genetic markers. Bioinformatics, 24, 1403-1405.
#' @references Jombart T, Ahmed I (2011) adegenet 1.3-1:
#' new tools for the analysis of genome-wide SNP data.
#' Bioinformatics, 27, 3070-3071.


#' @author Thierry Gosselin \email{thierrygosselin@@icloud.com}


write_genind <- function(data, write = FALSE, verbose = FALSE) {

  # Checking for missing and/or default arguments ------------------------------
  if (missing(data)) rlang::abort("Input file missing")

  # File type detection----------------------------------------------------------
  data.type <- radiator::detect_genomic_format(data)


  # Import data ---------------------------------------------------------------

  if (data.type %in% c("SeqVarGDSClass", "gds.file")) {
    if (data.type == "gds.file") {
      data <- radiator::read_rad(data, verbose = verbose)
    }
    data <- gds2tidy(gds = data, parallel.core = parallel::detectCores() - 1)
    data.type <- "tbl_df"
  } else {
    want <- c("MARKERS", "POP_ID", "INDIVIDUALS", "REF", "ALT", "GT", "GT_BIN")
    data <- suppressWarnings(radiator::tidy_wide(data = data, import.metadata = TRUE) %>%
                               dplyr::select(dplyr::one_of(want)) %>%
                               dplyr::arrange(POP_ID, INDIVIDUALS))
  }


  if (is.factor(data$POP_ID)) {
    pop.levels <- levels(data$POP_ID)
  } else {
    pop.levels <- unique(data$POP_ID)
  }
  # Make sure that POP_ID and INDIVIDUALS are character
  # data <- dplyr::mutate_at(.tbl = data, .vars = c("POP_ID", "INDIVIDUALS"), .funs = as.character)
  data$INDIVIDUALS <- as.character(data$INDIVIDUALS)
  data$POP_ID <- as.character(data$POP_ID)

  # Isolate the strata
  # we convert pop_id to factor because adegenet does it automatically...
  pop.num <- unique(stringi::stri_detect_regex(str = pop.levels, pattern = "^[0-9]+$"))
  if (length(pop.num) == 1 && pop.num) pop.levels <- as.character(sort(as.numeric(pop.levels)))

  # When GT_BIN available
  if (tibble::has_name(data, "GT_BIN")) {
    if (tibble::has_name(data, "REF")) {
      data <- suppressWarnings(
        dplyr::select(.data = data, MARKERS, POP_ID, INDIVIDUALS, REF, ALT, GT_BIN) %>%
          dplyr::mutate(A1 = abs(GT_BIN - 2)) %>%
          dplyr::rename(A2 = GT_BIN) %>%
          data.table::as.data.table(.) %>%
          data.table::melt.data.table(
            data = .,
            id.vars = c("INDIVIDUALS", "POP_ID", "MARKERS", "REF", "ALT"),
            variable.name = "ALLELES",
            measure.vars = c("A1", "A2"),
            value.name = "n"
          ) %>%
          tibble::as_tibble(.) %>%
          dplyr::mutate(
            ALLELES = dplyr::case_when(
              ALLELES == "A1" ~ REF,
              ALLELES == "A2" ~ ALT
            ),
            REF = NULL,
            ALT = NULL,
            MARKERS_ALLELES = stringi::stri_join(MARKERS, ALLELES, sep = ".")) %>%
          dplyr::select(-MARKERS, -ALLELES) %>%
          data.table::as.data.table(.) %>%
          data.table::dcast.data.table(
            data = .,
            formula = POP_ID + INDIVIDUALS ~ MARKERS_ALLELES,
            value.var = "n",
            fun.aggregate = length
          ) %>%
          tibble::as_tibble(.) %>%
          dplyr::mutate(POP_ID = factor(as.character(POP_ID), levels = pop.levels)) %>%# xvalDapc doesn't accept pop as ordered factor
          dplyr::arrange(POP_ID, INDIVIDUALS))
    } else {
      data <- suppressWarnings(
        dplyr::select(.data = data, MARKERS, POP_ID, INDIVIDUALS, GT_BIN) %>%
          dplyr::mutate(A1 = abs(GT_BIN - 2)) %>%
          dplyr::rename(A2 = GT_BIN) %>%
          data.table::as.data.table(.) %>%
          data.table::melt.data.table(
            data = .,
            id.vars = c("INDIVIDUALS", "POP_ID", "MARKERS"),
            variable.name = "ALLELES",
            value.name = "n"
          ) %>%
          tibble::as_tibble(.) %>%
          # tidyr::gather(data = ., key = ALLELES, value = n, -c(INDIVIDUALS, POP_ID, MARKERS)) %>%
          dplyr::mutate(MARKERS_ALLELES = stringi::stri_join(MARKERS, ALLELES, sep = ".")) %>%
          dplyr::select(-MARKERS, -ALLELES) %>%
          data.table::as.data.table(.) %>%
          data.table::dcast.data.table(
            data = .,
            formula = POP_ID + INDIVIDUALS ~ MARKERS_ALLELES,
            value.var = "n"
          ) %>%
          tibble::as_tibble(.) %>%
          # dplyr::group_by(POP_ID, INDIVIDUALS) %>%
          # tidyr::spread(data =., key = MARKERS_ALLELES, value = n) %>%
          # dplyr::ungroup(.) %>%
          dplyr::mutate(POP_ID = factor(as.character(POP_ID), levels = pop.levels)) %>%# xvalDapc doesn't accept pop as ordered factor
          dplyr::arrange(POP_ID, INDIVIDUALS))
    }
  } else {
    missing.geno <- dplyr::ungroup(data) %>%
      dplyr::select(MARKERS, INDIVIDUALS, GT) %>%
      dplyr::filter(GT == "000000") %>%
      dplyr::select(MARKERS, INDIVIDUALS) #%>%  dplyr::mutate(MISSING = rep("blacklist", n()))

    data <- suppressWarnings(
      dplyr::ungroup(data) %>%
        dplyr::select(MARKERS, INDIVIDUALS, GT, POP_ID) %>%
        dplyr::filter(GT != "000000") %>%
        dplyr::mutate(
          A1 = stringi::stri_sub(str = GT, from = 1, to = 3),
          A2 = stringi::stri_sub(str = GT, from = 4, to = 6)
        ) %>%
        dplyr::select(-GT) %>%
        # tidyr::gather(
        #   data = .,
        #   key = ALLELES,
        #   value = GT,
        #   -c(MARKERS, INDIVIDUALS, POP_ID)
        # ) %>%
        data.table::as.data.table(.) %>%
        data.table::melt.data.table(
          data = .,
          id.vars = c("INDIVIDUALS", "POP_ID", "MARKERS"),
          variable.name = "ALLELES",
          value.name = "GT"
        ) %>%
        tibble::as_tibble(.) %>%
        dplyr::arrange(MARKERS, POP_ID, INDIVIDUALS, GT) %>%
        dplyr::count(x = ., POP_ID, INDIVIDUALS, MARKERS, GT) %>%
        dplyr::ungroup(.) %>%
        tidyr::complete(data = ., tidyr::nesting(INDIVIDUALS, POP_ID), tidyr::nesting(MARKERS, GT), fill = list(n = 0)) %>%
        dplyr::mutate(MARKERS_ALLELES = stringi::stri_join(MARKERS, GT, sep = ".")) %>%
        dplyr::anti_join(missing.geno, by = c("MARKERS", "INDIVIDUALS")) %>%
        dplyr::select(-MARKERS, -GT) %>%
        dplyr::mutate(POP_ID = factor(as.character(POP_ID), levels = pop.levels)) %>%# xvalDapc doesn't accept pop as ordered factor
        dplyr::arrange(MARKERS_ALLELES, INDIVIDUALS) %>%
        # dplyr::group_by(POP_ID, INDIVIDUALS) %>%
        # tidyr::spread(data =., key = MARKERS_ALLELES, value = n) %>%
        # dplyr::ungroup(.) %>%
        data.table::as.data.table(.) %>%
        data.table::dcast.data.table(
          data = .,
          formula = POP_ID + INDIVIDUALS ~ MARKERS_ALLELES,
          value.var = "n"
        ) %>%
        tibble::as_tibble(.) %>%
        dplyr::arrange(POP_ID, INDIVIDUALS))
  }

  strata.genind <- dplyr::distinct(.data = data, INDIVIDUALS, POP_ID) %>%
    dplyr::mutate(INDIVIDUALS = factor(INDIVIDUALS, levels = unique(data$INDIVIDUALS)))

  # genind arguments common to all data.type
  ind <- data$INDIVIDUALS
  pop <- data$POP_ID
  data <-  dplyr::ungroup(data) %>%
    dplyr::select(-c(INDIVIDUALS, POP_ID))
  suppressWarnings(rownames(data) <- ind)

  # genind constructor
  prevcall <- match.call()
  res <- adegenet::genind(
    tab = data,
    pop = pop,
    prevcall = prevcall,
    ploidy = 2,
    type = "codom",
    strata = strata.genind,
    hierarchy = NULL
  )
  data <- NULL

  if (write) {
    filename.temp <- generate_filename(extension = "genind")
    filename.short <- filename.temp$filename.short
    filename.genind <- filename.temp$filename
    saveRDS(object = res, file = filename.genind)
    if (verbose) message("File written: ", filename.short)
  }

  return(res)
} # End write_genind
