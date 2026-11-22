# GRIB2 fixtures

Real GRIB2 files from the NOAA NOMADS GRIB filter, used to test the GRIB2 reader against an independent
ecCodes reading. All are data representation template 5.0 (simple packing), no bitmap; HRRR is grid template 3.30
(Lambert conformal), GFS is 3.0 (regular lat/lon). Product templates 4.0 and 4.8.

- `record.sh [YYYYMMDD] [HRRR cycle] [GFS cycle]` re-records the files next to itself (defaults: today UTC, 12, 06).
  The files below were recorded with `record.sh 20261122 12 06`.
- `make-reference.py` writes `<name>.eccodes.json` for each fixture (needs the `eccodes` Python package; the
  committed JSON came from ecCodes 2.50). Test points: W = 36.5785, -118.2923 (Mount Whitney),
  S = 46.5586, 8.5610 (Swiss Alps). Grid lat/lon is stored once per file under `grid`.

## Licence and attribution

Source: NOAA / NCEP (HRRR and GFS model output, via nomads.ncep.noaa.gov). These are works of the United States
government and are in the public domain. Attribution: "Data: NOAA/NCEP". Do not imply NOAA or NCEP endorsement of
Iter or of anything derived from these files.

## Files

### `hrrr-W-20261122t12z-f01.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?dir=%2Fhrrr.20261122%2Fconus&file=hrrr.t12z.wrfsfcf01.grib2&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&var_MASSDEN=on&var_COLMD=on&var_AOTK=on&lev_8_m_above_ground=on&lev_entire_atmosphere_%28considered_as_a_single_layer%29=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=36.8&leftlon=-118.6&rightlon=-118.0&bottomlat=36.3`
- Fetched: 2026-11-22T13:43:10Z
- Size: 10618 bytes, 17 messages, 21 x 22 grid points
- Test point: W (36.5785, -118.2923)

### `hrrr-W-20261122t12z-f06.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?dir=%2Fhrrr.20261122%2Fconus&file=hrrr.t12z.wrfsfcf06.grib2&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&var_MASSDEN=on&var_COLMD=on&var_AOTK=on&lev_8_m_above_ground=on&lev_entire_atmosphere_%28considered_as_a_single_layer%29=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=36.8&leftlon=-118.6&rightlon=-118.0&bottomlat=36.3`
- Fetched: 2026-11-22T13:43:14Z
- Size: 10772 bytes, 18 messages, 21 x 22 grid points
- Test point: W (36.5785, -118.2923)

### `hrrr-W-20261122t12z-f12.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?dir=%2Fhrrr.20261122%2Fconus&file=hrrr.t12z.wrfsfcf12.grib2&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&var_MASSDEN=on&var_COLMD=on&var_AOTK=on&lev_8_m_above_ground=on&lev_entire_atmosphere_%28considered_as_a_single_layer%29=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=36.8&leftlon=-118.6&rightlon=-118.0&bottomlat=36.3`
- Fetched: 2026-11-22T13:43:18Z
- Size: 10425 bytes, 18 messages, 21 x 22 grid points
- Test point: W (36.5785, -118.2923)

### `gfs-S-20261122t06z-f003.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.20261122%2F06%2Fatmos&file=gfs.t06z.pgrb2.0p25.f003&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=47&leftlon=8&rightlon=9&bottomlat=46`
- Fetched: 2026-11-22T13:43:22Z
- Size: 4236 bytes, 20 messages, 5 x 5 grid points
- Test point: S (46.5586, 8.561)

### `gfs-W-20261122t06z-f003.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.20261122%2F06%2Fatmos&file=gfs.t06z.pgrb2.0p25.f003&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=37&leftlon=-119&rightlon=-118&bottomlat=36`
- Fetched: 2026-11-22T13:43:26Z
- Size: 4186 bytes, 20 messages, 5 x 5 grid points
- Test point: W (36.5785, -118.2923)

### `gfs-S-20261122t06z-f006.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.20261122%2F06%2Fatmos&file=gfs.t06z.pgrb2.0p25.f006&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=47&leftlon=8&rightlon=9&bottomlat=46`
- Fetched: 2026-11-22T13:43:30Z
- Size: 4282 bytes, 20 messages, 5 x 5 grid points
- Test point: S (46.5586, 8.561)

### `gfs-W-20261122t06z-f006.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.20261122%2F06%2Fatmos&file=gfs.t06z.pgrb2.0p25.f006&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=37&leftlon=-119&rightlon=-118&bottomlat=36`
- Fetched: 2026-11-22T13:43:34Z
- Size: 4212 bytes, 20 messages, 5 x 5 grid points
- Test point: W (36.5785, -118.2923)

### `gfs-S-20261122t06z-f012.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.20261122%2F06%2Fatmos&file=gfs.t06z.pgrb2.0p25.f012&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=47&leftlon=8&rightlon=9&bottomlat=46`
- Fetched: 2026-11-22T13:43:37Z
- Size: 4275 bytes, 20 messages, 5 x 5 grid points
- Test point: S (46.5586, 8.561)

### `gfs-W-20261122t06z-f012.grib2`
- URL: `https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?dir=%2Fgfs.20261122%2F06%2Fatmos&file=gfs.t06z.pgrb2.0p25.f012&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&var_TMP=on&var_DPT=on&var_RH=on&var_UGRD=on&var_VGRD=on&var_GUST=on&var_APCP=on&var_PRATE=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&subregion=&toplat=37&leftlon=-119&rightlon=-118&bottomlat=36`
- Fetched: 2026-11-22T13:43:41Z
- Size: 4090 bytes, 20 messages, 5 x 5 grid points
- Test point: W (36.5785, -118.2923)
