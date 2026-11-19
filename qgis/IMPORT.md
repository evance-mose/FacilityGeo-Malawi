# Import organisation units from QGIS into PostGIS

1. Create a PostGIS database (pgAdmin / `CREATE EXTENSION postgis`)
2. Connect QGIS → PostgreSQL
3. **DB Manager → Import layer** (attribute table + geometry column)
4. Run spatial SQL (SRID, `ALTER`/`UPDATE`, buffer, `ST_Contains`)
5. Double-click result tables to show them again in QGIS

DHIS2 organisation units are the point layer. The web app reads the same PostGIS database.

## 1. Database + PostGIS

```bash
createdb facilitygeo
psql -d facilitygeo -c "CREATE EXTENSION IF NOT EXISTS postgis"
psql -d facilitygeo -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
psql -d facilitygeo -f database/setup.sql
```

Or use pgAdmin: create DB → Extensions → PostGIS.

## 2. Connect QGIS

**Browser → PostgreSQL → New Connection**

| Setting | Value |
|---|---|
| Name | e.g. `Postgres 17` or `facilitygeo` |
| Host | `localhost` |
| Database | `facilitygeo` |
| User / password | your role |

Test connection → OK. Open **Database → DB Manager**.

## 3. Import organisation units

1. **Layer → Add Vector Layer** → `Organisation units.geojson` (or `data/orgunits.geojson`).
2. Open the **attribute table** (`id`, `name`, `parentName`, `level`, …).
3. **DB Manager → Import layer/file** → choose that layer.
4. Target table: `organisation_units` (or `orgunits_raw` if you map fields).
5. CRS: leave source (EPSG:4326). Geometry column: `geom`.

QGIS writes every attribute field as a column, plus a **geometry** column (hidden in the QGIS attribute table, visible in pgAdmin / SQL).

Optional, for the facilities-near-roads check:

- Import `main_roads` shapefile → `main_roads`
- Merge and buffer those roads with `ST_Union` and `ST_Buffer`

## 4. Spatial SQL

```bash
psql -d facilitygeo -f database/organisation_units.sql
```

What it does:

| Step | Result |
|---|---|
| Check `ST_SRID` / `spatial_ref_sys` | Confirms `organisation_units` |
| `ALTER` + `UPDATE` | Adds **`district`** from `parentName` |
| Copy into app tables | `orgunits_raw` and `facilities` |
| Near main roads (`ST_Contains` + `ST_Transform`) | **`orgunits_in_buffer`** |
| Point in district (`ST_Contains`) | **`orgunits_by_district_spatial`** |
| Load tables back into QGIS | Double-click PostGIS tables in DB Manager |

Also copies into `orgunits_raw` / `facilities` so the **web app** uses the same imported data.

Then apply the rollout tracker (CSV can also be imported via QGIS as a table with no geometry):

```bash
psql -d facilitygeo -f database/match_tracker.sql
psql -d facilitygeo -f database/apply_tracker.sql
```

## 5. Show in QGIS + web app

- In DB Manager, double-click `organisation_units`, `orgunits_in_buffer`, `facilities`.
- Open `qgis/facilitygeo.qgz` for styled layers.
- Start the app: `uvicorn app.main:app --reload` → http://127.0.0.1:8000

## Field mapping (attribute table → PostGIS)

| QGIS field | Column |
|---|---|
| `id` | `id` (DHIS2 UID) |
| `name` | `name` |
| `parentName` | `parentName` / `parentname` |
| `level` | `level` |
| geometry (Point) | `geom` |
