test_that("the catalogue is well formed", {
  x <- cc_catalog(unadvertised = TRUE)
  expect_true(all(c("id", "group", "kind", "source", "layer", "crs", "advertised",
                    "harvest", "priority", "title", "notes") %in% names(x)))
  expect_false(anyDuplicated(x$id) > 0)
  expect_true(all(x$kind %in% c("vector", "raster")))
  expect_true(all(x$priority %in% 1:3))
  expect_false(any(x$harvest & !x$advertised))
})

test_that("unadvertised layers are hidden by default", {
  expect_false("directed_fishing" %in% cc_catalog()$id)
  expect_true("directed_fishing" %in% cc_catalog(unadvertised = TRUE)$id)
})

test_that("every non-download source has a DSN", {
  x <- cc_catalog(unadvertised = TRUE)
  x <- x[x$source != "pangaea", ]
  dsn <- vapply(x$id, cc_dsn, "", date = "2026-09-30")
  expect_true(all(nzchar(dsn)))
})

test_that("DSNs have the expected shape", {
  expect_match(cc_dsn("statistical_areas"),
               "typeName=gis:statistical_areas_6932&outputFormat=application/json&srsName=EPSG:6932$")
  expect_match(cc_dsn("gebco2025_5000"), "^WCS:https://gis.ccamlr.org/.*coverage=gis__GEBCO2025_5000$")
  expect_equal(cc_dsn("gebco_2026"),
               "/vsicurl/https://data.source.coop/ausantarctic/gebco/GEBCO_2026.tif")
  expect_equal(cc_dsn("bremen_asi_amsr2", date = "2026-09-30"),
               paste0("/vsicurl/https://data.seaice.uni-bremen.de/amsr2/asi_daygrid_swath/",
                      "s6250/2026/sep/Antarctic/asi-AMSR2-s6250-20260930-v5.4.tif"))
  expect_error(cc_dsn("ibcso_v2"), "no GDAL source name")
  expect_error(cc_dsn("nope"), "not in the catalogue")
})

test_that("snapshot DSNs need a location and a harvested layer", {
  withr_opt <- options(ccamlrcat.snapshot = NULL)
  on.exit(options(withr_opt))
  expect_error(cc_dsn("statistical_areas", snapshot = TRUE), "No snapshot location")
  options(ccamlrcat.snapshot = "https://example.org/snap/")
  expect_equal(cc_dsn("statistical_areas", snapshot = TRUE),
               "/vsicurl/https://example.org/snap/statistical_areas.parquet")
  expect_error(cc_dsn("gebco_2026", snapshot = TRUE), "not harvested")
})
