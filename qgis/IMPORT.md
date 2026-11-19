# Load data with QGIS → PostGIS

Official path: open GeoJSON (or CSV) in QGIS, use the **attribute table** fields, export into PostgreSQL. The web app then reads those tables.

Do this **after** `database/setup.sql` has created the empty tables.

## 1. Connect QGIS to the database

**Layer → Data Source Manager → PostgreSQL → New**

| Setting | Value |
|---|---|
| Name | `facilitygeo` (any label) |
| Host | `localhost` |
| Port | `5432` |
| Database | `facilitygeo` |
| User / password | your `geo` (or owner) role |

Do not store the password in the project file if you will share `facilitygeo.qgz`.

## 2. Facilities (DHIS2 org units GeoJSON)

1. **Layer → Add Layer → Add Vector Layer** → pick `Organisation units.geojson` (or your DHIS2 export).
2. Open the attribute table. You should see fields such as `id`, `name`, `parentName`, `level`.
3. **Database → DB Manager → PostgreSQL → your connection → Import Layer/File**  
   (or right‑click the layer → **Export → Save Features As… → PostgreSQL**).

| QGIS field (attribute table) | PostGIS column (`orgunits_raw`) |
|---|---|
| `id` (DHIS2 UID) | `id` |
| `name` | `name` |
| `parentName` | `parentname` |
| `level` | `level` |
| geometry (Point) | `geom` (EPSG:4326) |

Import options:

- Schema: `public`
- Table: `orgunits_raw`
- Primary key: `id`
- Geometry column: `geom`
- CRS: EPSG:4326
- Prefer **append** into the empty table from `setup.sql` (do not let QGIS invent a new table name)

Then build the clean `facilities` table (district from `parentname`):

```bash
psql -d facilitygeo -f database/build_facilities.sql
```

## 3. Districts (HDX GeoJSON)

1. Add `mw_districts.geojson` (or the HDX polygons) as a vector layer.
2. Attribute table should include a district name field (often `district`) and optionally `region`.
3. Import into `districts_hdx`:

| QGIS field | PostGIS column (`districts_hdx`) |
|---|---|
| `district` (rename to `name` on import if needed) | `name` |
| `region` | `region` |
| geometry (Polygon / MultiPolygon) | `geom` (EPSG:4326) |

If QGIS creates a temporary column name, rename it in the import dialog to match the table. After import, clean names/regions:

```bash
psql -d facilitygeo -f database/after_qgis_import.sql
```

## 4. Rollout tracker (CSV / spreadsheet → attribute table)

The tracker is not GeoJSON. In QGIS:

1. Convert the spreadsheet to CSV if needed.
2. **Layer → Add Layer → Add Delimited Text Layer** (no geometry, or “No geometry”).
3. Import into `tracker_raw`, mapping headers to:

| Typical spreadsheet header | PostGIS column (`tracker_raw`) |
|---|---|
| Facility / name | `facility_name` |
| District | `district` |
| Go-live / status | `status` |
| End-user training | `training` |
| DHIS2 code (if any) | `facility_code` |

Leave `facility_id` and `match_method` empty — matching SQL fills them.

Then:

```bash
psql -d facilitygeo -f database/match_tracker.sql
psql -d facilitygeo -f database/apply_tracker.sql
```

## 5. Check and open the project

```bash
psql -d facilitygeo -f database/checks.sql
```

Open `qgis/facilitygeo.qgz`, refresh the PostGIS layers, and start the web app (`uvicorn app.main:app --reload`).

## Optional: Python loaders

`scripts/load_orgunits.py`, `load_districts.py`, and `load_tracker.py` do the same inserts without QGIS. Prefer the QGIS path above for the course workflow.
