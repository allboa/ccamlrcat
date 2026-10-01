## A first look for a CCAMLR R user: the Convention Area's management
## geometry, bathymetry and sea ice from the cloud, with your own data on
## top, in one interactive polar view.
##
## install.packages("remotes")
## remotes::install_github("allboa/aobview")      # the viewer
## remotes::install_github("<owner>/ccamlrcat")   # this catalogue

library(ccamlrcat)
library(aobview)

## What is there. Priority 1 is the short list most users reach for.
cc_catalog(priority = 1)[, c("id", "group", "kind", "title")]

## One layer. A recipe: the string GDAL opens, nothing copied.
cc_dsn("statistical_areas")
asd <- cc_read("statistical_areas")
view(asd, zcol = "GAR_Short_Label", popup = c("GAR_Name", "GAR_Start_Date"))

## The management stack, bottom first. The first projected layer (the ASDs,
## in EPSG:6932) sets the view: Lambert azimuthal equal area on the pole.
mgmt <- cc_layers(c("statistical_areas", "ssrus", "research_blocks", "mpas", "coastline_v1"))
view(mgmt)

## Bathymetry under it: GEBCO 2026 as a global COG on source.coop. aobview
## plans the tiles it needs for the view; the browser fetches them by range
## request.
view(c(list(gebco = cc_read("gebco_2026")), mgmt))

## Yesterday's sea ice from Bremen (a small GeoTIFF, embedded in the page).
ice <- cc_read("bremen_asi_amsr2", date = Sys.Date() - 1)
view(c(list(ice = ice), cc_layers(c("ssmus", "coastline_v1"))))

## Your own data on top: here, made-up haul positions in lon/lat. Anything
## sf or terra reads goes in the same list.
hauls <- sf::st_as_sf(
  data.frame(haul = 1:5, lon = c(-60.5, -58.2, -46.1, 170.3, 77.0),
             lat = c(-62.1, -61.0, -60.6, -72.4, -66.9),
             catch_kg = c(1200, 860, 400, 2300, 150)),
  coords = c("lon", "lat"), crs = "EPSG:4326")
view(c(cc_layers(c("statistical_areas", "vme_risk_areas", "coastline_v1")),
       list(hauls = hauls)))

## The same views from the harvested snapshot (GeoParquet), once a snapshot
## location exists, e.g. the `snapshots` branch of the repo:
## options(ccamlrcat.snapshot = "https://raw.githubusercontent.com/<owner>/ccamlrcat/snapshots")
## view(cc_layers(c("statistical_areas", "mpas"), snapshot = TRUE))
