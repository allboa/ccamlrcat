# ccamlrcat

A catalogue of CCAMLR spatial data as cloud-ready recipes, for R users
viewing with [aobview](https://github.com/allboa/aobview). Early prototype;
the name is a placeholder. The plan is in [DESIGN.md](DESIGN.md).

```r
# install.packages("remotes")
remotes::install_github("allboa/aobview")
remotes::install_github("<owner>/ccamlrcat")

library(ccamlrcat)
library(aobview)

cc_catalog(priority = 1)[, c("id", "kind", "title")]
cc_dsn("statistical_areas")                  # the GDAL string: a recipe, not a copy
view(cc_layers(c("gebco_2026", "statistical_areas", "mpas", "coastline_v1")))
```

`cc_layers()` returns a named list, so your own sf and terra objects go in
the same `view()`:

```r
view(c(cc_layers(c("statistical_areas", "vme_risk_areas")), list(hauls = my_hauls)))
```

A longer walk-through is `inst/examples/first-look.R`.

## What is in the catalogue

51 entries: every layer the CCAMLR GIS advertises (management areas, MPAs,
VMEs, protected sites, coastline, fronts, place-names, bathymetry, sea
ice), three it serves but does not advertise (hidden unless asked for), and
neighbouring cloud sources (GEBCO COGs on source.coop, Bremen AMSR2 sea
ice, IBCSO v2). Priority 1 is the short list.

## Snapshots

`inst/harvest/harvest.R` writes the harvestable layers to GeoParquet and
COG with a manifest; `--check` only probes the sources. The weekly
`.github/workflows/harvest.yml` commits the result to a `snapshots` branch,
so a layer's history shows when it changed. Read from it with
`options(ccamlrcat.snapshot = "<base url>")` and `snapshot = TRUE`.
