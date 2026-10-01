#' The catalogue of CCAMLR and neighbouring spatial sources
#'
#' One row per source: an id, a group, the kind (vector or raster), where it
#' lives, the layer or file name there, its CRS, whether the server
#' advertises it, whether the harvest snapshots it, a priority (1 is the
#' first layers a CCAMLR user would reach for), a title and notes.
#'
#' Unadvertised layers (readable from the CCAMLR WFS but not listed in its
#' GetCapabilities) are left out unless asked for: ask the Secretariat
#' before using or redistributing them.
#'
#' @param group Groups to keep, or `NULL` for all (see `unique(cc_catalog()$group)`).
#' @param priority Keep rows at this priority or better (1, 2 or 3).
#' @param unadvertised Include layers the server does not advertise.
#' @return A data frame.
#' @export
#' @examples
#' cc_catalog(priority = 1)[, c("id", "kind", "title")]
cc_catalog <- function(group = NULL, priority = 3, unadvertised = FALSE) {
  x <- utils::read.csv(catalog_path(), stringsAsFactors = FALSE)
  if (!unadvertised) x <- x[x$advertised, , drop = FALSE]
  if (!is.null(group)) x <- x[x$group %in% group, , drop = FALSE]
  x <- x[x$priority <= priority, , drop = FALSE]
  rownames(x) <- NULL
  x
}

#' The GDAL data source name for a catalogue entry
#'
#' A DSN is a recipe, not a copy: a string that sf, terra or gdalraster
#' opens directly. Vector layers from the CCAMLR WFS are requested as
#' GeoJSON in EPSG:6932, which the server reprojects to when a layer is
#' stored in ESRI:102020 (the same projection, under a code GDAL does not
#' know).
#'
#' @param id A catalogue id.
#' @param date For dated sources (`bremen_asi_amsr2`): a `Date`, or text
#'   `as.Date()` reads. `NULL` is yesterday.
#' @param snapshot `TRUE` for the harvested copy (GeoParquet or COG) at
#'   `getOption("ccamlrcat.snapshot")`, instead of the live source.
#' @return A character string.
#' @export
#' @examples
#' cc_dsn("statistical_areas")
#' cc_dsn("gebco_2026")
#' cc_dsn("bremen_asi_amsr2", date = "2026-09-30")
cc_dsn <- function(id, date = NULL, snapshot = FALSE) {
  row <- cc_row(id)
  if (snapshot) {
    if (!isTRUE(row$harvest)) {
      stop("`", id, "` is not harvested; use the live source (snapshot = FALSE).",
           call. = FALSE)
    }
    ext <- if (row$kind == "vector") ".parquet" else ".tif"
    return(paste0("/vsicurl/", snapshot_base(), "/", row$id, ext))
  }
  switch(row$source,
    "ccamlr-wfs" = paste0(ccamlr_ows, "?service=WFS&version=1.0.0&request=GetFeature",
                          "&typeName=", row$layer,
                          "&outputFormat=application/json&srsName=EPSG:6932"),
    "ccamlr-wcs" = paste0("WCS:", ccamlr_ows, "?version=2.0.1&coverage=", row$layer),
    "ccamlr-www" = paste0("/vsicurl/https://gis.ccamlr.org/geoserver/www/", row$layer),
    "source-coop" = paste0("/vsicurl/https://data.source.coop/ausantarctic/gebco/", row$layer),
    "bremen" = bremen_dsn(row$layer, date),
    stop("`", id, "` (", row$source, ") has no GDAL source name: ", row$notes, call. = FALSE)
  )
}

#' Read one catalogue entry
#'
#' Vectors come back as sf data frames (with 'sf'), rasters as
#' `SpatRaster` (with 'terra'). Nothing is downloaded beyond what the
#' reader asks for: a remote COG stays remote until it is drawn or read.
#'
#' @inheritParams cc_dsn
#' @param ... Passed to [sf::st_read()] or [terra::rast()].
#' @return An sf data frame or a `SpatRaster`.
#' @export
#' @examples
#' \dontrun{
#' asd <- cc_read("statistical_areas")
#' bathy <- cc_read("gebco_2026")
#' }
cc_read <- function(id, date = NULL, snapshot = FALSE, ...) {
  row <- cc_row(id)
  dsn <- cc_dsn(id, date = date, snapshot = snapshot)
  if (row$kind == "vector") {
    need("sf")
    sf::st_read(dsn, quiet = TRUE, ...)
  } else {
    need("terra")
    terra::rast(dsn, ...)
  }
}

#' Read several catalogue entries into a named list
#'
#' The list is ready for `aobview::view()`, which draws a list in order,
#' first at the bottom, with the names as layer labels. Entries that fail to
#' read are dropped with a warning, so one slow or missing layer does not
#' stop the rest.
#'
#' @param ids Catalogue ids, in drawing order (bottom first).
#' @param ... Passed to [cc_read()] for every entry (`date`, `snapshot`).
#' @return A named list of sf data frames and `SpatRaster`s.
#' @export
#' @examples
#' \dontrun{
#' x <- cc_layers(c("gebco_2026", "statistical_areas", "mpas", "coastline_v1"))
#' aobview::view(x)
#' }
cc_layers <- function(ids, ...) {
  out <- lapply(ids, function(id) {
    tryCatch(cc_read(id, ...), error = function(e) {
      warning("`", id, "` was not read: ", conditionMessage(e), call. = FALSE)
      NULL
    })
  })
  names(out) <- ids
  out[!vapply(out, is.null, TRUE)]
}

## ---- internals -------------------------------------------------------------

ccamlr_ows <- "https://gis.ccamlr.org/geoserver/ows"

## The installed catalogue, or the source tree's when the package is not
## installed (the harvest script sources this file from the source root).
catalog_path <- function() {
  p <- system.file("extdata", "catalog.csv", package = "ccamlrcat")
  if (!nzchar(p)) p <- getOption("ccamlrcat.catalog", file.path("inst", "extdata", "catalog.csv"))
  p
}

cc_row <- function(id) {
  if (!is.character(id) || length(id) != 1L || is.na(id)) {
    stop("`id` must be one catalogue id.", call. = FALSE)
  }
  x <- cc_catalog(unadvertised = TRUE)
  row <- x[x$id == id, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop("`", id, "` is not in the catalogue; see cc_catalog().", call. = FALSE)
  }
  as.list(row)
}

snapshot_base <- function() {
  base <- getOption("ccamlrcat.snapshot")
  if (is.null(base) || !nzchar(base)) {
    stop("No snapshot location: set options(ccamlrcat.snapshot = \"https://...\").",
         call. = FALSE)
  }
  sub("/+$", "", base)
}

## Bremen ASI AMSR2 daily GeoTIFFs, Antarctic 6.25 km grid. Month folders
## are lower-case English abbreviations, fixed here so the locale does not
## matter.
bremen_dsn <- function(template, date = NULL) {
  date <- if (is.null(date)) Sys.Date() - 1L else as.Date(date)
  if (length(date) != 1L || is.na(date)) stop("`date` must be one date.", call. = FALSE)
  months <- c("jan", "feb", "mar", "apr", "may", "jun",
              "jul", "aug", "sep", "oct", "nov", "dec")
  ymd <- format(date, "%Y%m%d")
  paste0("/vsicurl/https://data.seaice.uni-bremen.de/amsr2/asi_daygrid_swath/s6250/",
         format(date, "%Y"), "/", months[as.integer(format(date, "%m"))], "/Antarctic/",
         sub("{date}", ymd, template, fixed = TRUE))
}

need <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Package '", pkg, "' is needed for this; install it.", call. = FALSE)
  }
}
