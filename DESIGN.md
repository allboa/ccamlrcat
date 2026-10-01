# ccamlrcat: design plan

Seeded 2026-10-01. Placeholder name. Status: prototype, breadth first.

## Why

A CCAMLR participant working in R should be able to see the Convention
Area's management geometry, bathymetry and sea ice next to their own data,
in an interactive polar view, in a few lines of R. Today that means finding
WFS endpoints by hand, or CCAMLRGIS for eight layers, and drawing static
plots. aobview (allboa) now gives a mapview-style `view(x)` that draws
lists of sf and terra objects in their own CRS, polar first. This project is
the data side of that experience: a catalogue of what exists, as recipes R
can open, and a snapshot of what needs keeping.

It is a consumer of allboa, not part of it. It adds nothing to aobcore or
aobview, and what it finds out about them goes back as issues there.

## The user experience

```r
library(ccamlrcat); library(aobview)
cc_catalog(priority = 1)                       # what is there
view(cc_layers(c("gebco_2026", "statistical_areas", "mpas", "coastline_v1")))
view(c(cc_layers(c("statistical_areas", "vme_risk_areas")), list(hauls = my_hauls)))
```

Four verbs, all thin: `cc_catalog()` lists, `cc_dsn()` gives the GDAL
string (the recipe), `cc_read()` opens it with sf or terra, and
`cc_layers()` builds the named list `view()` takes. The first projected
layer sets the view CRS, so CCAMLR layers in EPSG:6932 give a Lambert
azimuthal equal-area view on the pole, and the user's lon/lat data is
reprojected into it.

## What the CCAMLR GIS holds (2026-10-01)

- **Stack.** BAS-built OpenLayers front end with a login; GeoServer on
  PostGIS behind it. The OGC endpoints at `https://gis.ccamlr.org/geoserver/ows`
  are anonymous ("AccessConstraints: none").
- **WFS: 43 advertised feature types** in workspace `gis`, most as a pair
  (native "EPSG:102020", really ESRI:102020, and an `_6932` twin with the
  same projection under a real EPSG code). GeoJSON, GeoPackage-friendly
  outputs, CSV and SHAPE-ZIP are offered. Requesting `srsName=EPSG:6932`
  on a 102020-only layer returns clean GeoJSON in metres (checked on
  `vme_points`).
- **Three unadvertised but readable types:** `directed_fishing` (7),
  `penguins_locations` (2465), `USAMLRwaypoints`. Catalogued with
  `advertised = FALSE`, never harvested; ask the Secretariat.
- **WCS: 16 coverages.** GEBCO 2020 to 2025 at 500 m and 5 km in EPSG:6932,
  older GEBCO 08/14 products, a 600 to 1800 m depth band, hillshade,
  crabeater seal density, SSMIS, and a daily Bremen sea ice mirror back to
  2013-11.
- **Static files:** `geoserver/www/GEBCO2024_{500,1000,2500,5000}.tif`
  (used by CCAMLRGIS `load_Bathy()`). COG status unknown.
- **The areas schema** (`GAR_*`): `GAR_ID`, name and labels,
  `GAR_Start_Date`, `GAR_End_Date`, `GAR_Parent_ID`, `ATY_ID` (3 subarea,
  4 division), `GAR_Size`, created and modified stamps. The statistical
  areas layer holds the 19 leaf units; parents are referenced but not
  served; end dates are empty, so only current units are visible.
- **Elsewhere:** `ccamlr/data` on GitHub (CC0) holds a hand-maintained copy
  of the main layers; CCAMLRGIS reads 8 layers from the WFS.

Neighbouring cloud-ready sources already in the catalogue: GEBCO 2024 to
2026 as global COGs on source.coop (`ausantarctic/gebco`), and Bremen ASI
AMSR2 daily GeoTIFFs (6.25 km, Antarctic grid). IBCSO v2 is listed as a
candidate to host as a COG.

## Shape

Three tiers, cheapest first:

1. **Recipe (live).** A DSN string per entry. Vectors from the WFS as
   GeoJSON in EPSG:6932, rasters as `WCS:` or `/vsicurl/` strings. Nothing
   copied; always current; depends on gis.ccamlr.org being up.
2. **Snapshot (harvested).** `inst/harvest/harvest.R` writes every
   `harvest = TRUE` entry to GeoParquet (vectors, EPSG:6932) or COG
   (rasters) with a manifest (status, bytes, md5, feature count, time). A
   weekly GitHub Action commits it to a `snapshots` branch: each file's git
   history is the record of that layer's changes, which the WFS cannot give
   (research blocks and MPAs change through Conservation Measures).
   `cc_dsn(id, snapshot = TRUE)` points at it.
3. **External cloud.** Sources that already have a good home are recipes to
   that home, not copies: GEBCO on source.coop, sea ice from Bremen.

The catalogue is one CSV (`inst/extdata/catalog.csv`): id, group, kind,
source, layer, CRS, advertised, harvest, priority, title, notes. Breadth
over care: every advertised layer is in it, prioritised 1 to 3, with notes
where something is unclear.

## Decisions taken in the seed

- **EPSG:6932 everywhere for CCAMLR vectors.** It is CCAMLR's own working
  projection (CCAMLRGIS, geospatial_operations) and identical to ESRI:102020,
  which GDAL cannot resolve by that code.
- **GeoJSON over WFS for live reads**, the route CCAMLRGIS has proven, rather
  than GDAL's WFS driver.
- **Do not mirror what has a home.** No harvest of the GEBCO coverages or the
  sea ice mirror.
- **Base R only in Imports.** sf, terra and aobview are suggested.
- **ASCII only**, as in allboa.

## Not yet tested

This seed was written without network access to gis.ccamlr.org from the
build machine (only through a fetch tool), and without GDAL. Untested:

- `cc_read()` on real data; the harvest producing files (it was dry-run: it
  records every failure and still writes its manifest).
- The `WCS:` DSNs through GDAL's WCS driver.
- Page sizes: `coastline_v1` is full resolution and travels embedded in
  the page as GeoArrow; it may need simplifying or the older `coastline`.
- GEBCO 2026 (global lon/lat COG) drawn in a LAEA polar view: aobcore's
  tile planner should handle it (decision 0003), but this extent is new.
- CORS on data.source.coop and data.seaice.uni-bremen.de, for the browser
  fetching COG tiles by range (Bremen files are small plain GeoTIFFs, so
  aobview embeds them anyway).
- GeoServer's GeoJSON date format for `GAR_Start_Date` (may arrive as text
  with a trailing `Z`).

## Phases

0. **Seed (this).** Catalogue, four verbs, harvest script and Action, a
   first-look example, tests (17 pass).
1. **First run.** Run `first-look.R` end to end; run the harvest once;
   fix what breaks; record page sizes. Turn rough edges in aobview into
   allboa issues.
2. **A CCAMLR participant tries it.** Put the repo and snapshot somewhere
   they can install from; collect what they reach for that is missing.
3. **History and definition.** Decode `GAR_Parent_ID` and `ATY_ID` into a
   hierarchy table; dissolve parents (Areas 48, 58, 88); start the
   definitional form of boundaries that follow parallels and meridians
   (lon/lat corners plus an edge rule), densified per view by bigcurve.
4. **Hosting.** Move the snapshot from a git branch to object storage
   (source.coop `ausantarctic/ccamlr`, or Pawsey) with a STAC or JSON index,
   if the Secretariat agrees.

## Open questions for Michael

- Repo home and name: `mdsumner`, `hypertidy`, or an `allboa`-adjacent org?
- Is a public snapshot of CCAMLR layers fine, or should it wait for a word
  with the Secretariat (Gary Dewhurst, ISDS)? `ccamlr/data` is CC0, which
  suggests yes for the main layers.
- Which CCAMLR participant, and what would they want to see first: fishery
  geometry (SSRUs, research blocks), MPAs, or VMEs?
- Should the catalogue live in starc or sds instead of its own CSV, later?
