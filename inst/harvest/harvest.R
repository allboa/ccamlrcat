## Snapshot the harvestable CCAMLR layers to cloud-ready files.
##
##   Rscript inst/harvest/harvest.R [out_dir] [--check]
##
## Vectors become GeoParquet in EPSG:6932, rasters become COGs, one file per
## catalogue id, plus manifest.csv (one row per id: status, size, md5,
## feature count, time). --check only probes each source and writes the
## manifest, as a link check. One failing layer never stops the run.
##
## Needs the GDAL command line tools (ogr2ogr, ogrinfo, gdal_translate,
## gdalinfo) built with the Parquet driver, and base R. Run it from the
## package source root, or anywhere with ccamlrcat installed.

args <- commandArgs(trailingOnly = TRUE)
check_only <- "--check" %in% args
args <- setdiff(args, "--check")
out_dir <- if (length(args)) args[[1L]] else "snapshot"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

## From the package source root use its R/ code; otherwise the installed package.
if (file.exists(file.path("R", "catalog.R"))) {
  source(file.path("R", "catalog.R"))
} else {
  library(ccamlrcat)
  catalog_path <- utils::getFromNamespace("catalog_path", "ccamlrcat")
}

cat_all <- utils::read.csv(catalog_path(), stringsAsFactors = FALSE)
todo <- cat_all[cat_all$harvest & cat_all$advertised &
                cat_all$source %in% c("ccamlr-wfs", "ccamlr-wcs"), , drop = FALSE]

run <- function(cmd, args) {
  res <- suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE))
  status <- attr(res, "status")
  list(ok = is.null(status) || status == 0L, out = paste(res, collapse = "\n"))
}

feature_count <- function(file_or_dsn) {
  r <- run("ogrinfo", c("-so", "-al", "-ro", shQuote(file_or_dsn)))
  m <- regmatches(r$out, regexpr("Feature Count: [0-9]+", r$out))
  if (length(m)) as.integer(sub("Feature Count: ", "", m)) else NA_integer_
}

harvest_one <- function(row) {
  dsn <- cc_dsn(row$id)
  file <- file.path(out_dir, paste0(row$id, if (row$kind == "vector") ".parquet" else ".tif"))
  if (check_only) {
    r <- if (row$kind == "vector") run("ogrinfo", c("-so", "-al", "-ro", shQuote(dsn)))
         else run("gdalinfo", shQuote(dsn))
    return(list(ok = r$ok, file = NA_character_, msg = if (r$ok) "" else r$out,
                n = if (row$kind == "vector" && r$ok) feature_count(dsn) else NA_integer_))
  }
  r <- if (row$kind == "vector") {
    run("ogr2ogr", c("-f", "Parquet", "-overwrite", "-nln", row$id,
                     "-lco", "COMPRESSION=ZSTD", shQuote(file), shQuote(dsn)))
  } else {
    run("gdal_translate", c("-of", "COG", "-co", "COMPRESS=DEFLATE",
                            "-co", "OVERVIEWS=AUTO", shQuote(dsn), shQuote(file)))
  }
  list(ok = r$ok && file.exists(file), file = file, msg = if (r$ok) "" else r$out,
       n = if (row$kind == "vector" && r$ok) feature_count(file) else NA_integer_)
}

rows <- lapply(seq_len(nrow(todo)), function(i) {
  row <- as.list(todo[i, ])
  t0 <- Sys.time()
  res <- tryCatch(harvest_one(row), error = function(e)
    list(ok = FALSE, file = NA_character_, msg = conditionMessage(e), n = NA_integer_))
  have <- !is.na(res$file) && file.exists(res$file)
  message(sprintf("%-28s %s", row$id, if (res$ok) "ok" else "FAILED"))
  data.frame(
    id = row$id, kind = row$kind, layer = row$layer,
    status = if (res$ok) "ok" else "failed",
    file = if (have) basename(res$file) else NA_character_,
    bytes = if (have) file.size(res$file) else NA_real_,
    md5 = if (have) unname(tools::md5sum(res$file)) else NA_character_,
    n_features = res$n,
    seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1),
    retrieved_utc = format(t0, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    message = substr(gsub("[\r\n]+", " ", res$msg), 1L, 300L),
    stringsAsFactors = FALSE
  )
})
manifest <- do.call(rbind, rows)
utils::write.csv(manifest, file.path(out_dir, "manifest.csv"), row.names = FALSE)
message(sum(manifest$status == "ok"), " of ", nrow(manifest), " ok; manifest in ",
        file.path(out_dir, "manifest.csv"))
