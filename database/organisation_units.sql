-- FacilityGeo — organisation units imported from QGIS into PostGIS.
--
-- Flow:
--   1. PostGIS-enabled database
--   2. QGIS → DB Manager → Import layer (attribute table + geometry)
--   3. Basic spatial SQL (SRID, ALTER, UPDATE)
--   4. Spatial analysis (buffer / overlay with ST_Contains + ST_Transform)
--   5. Load result tables back into QGIS (double-click in DB Manager)
--
-- Prerequisites:
--   - database/setup.sql already applied
--   - Organisation units GeoJSON imported from QGIS into public.organisation_units
--   - HDX districts imported from QGIS into public.districts_hdx
--     (see qgis/IMPORT.md). Optional: main_roads and main_roads_buffer.
--
-- Run:
--   psql -d facilitygeo -f database/organisation_units.sql

-- ---------------------------------------------------------------------------
-- A. Confirm the QGIS import (attribute table + geometry column)
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS organisation_units,
       GeometryType(geom) AS geom_type,
       ST_SRID(geom) AS srid
FROM organisation_units
GROUP BY 2, 3;

-- CRS check (organisation units are EPSG:4326)
SELECT srid, auth_name, auth_srid, left(srtext, 100) AS srtext
FROM spatial_ref_sys
WHERE srid = (SELECT ST_SRID(geom) FROM organisation_units LIMIT 1);

-- ---------------------------------------------------------------------------
-- B. Add the district name from parentName
-- ---------------------------------------------------------------------------
-- District name from DHIS2 parentName (Mangochi-DHO → Mangochi)
ALTER TABLE organisation_units
    ADD COLUMN IF NOT EXISTS district TEXT;

UPDATE organisation_units
SET district = btrim(replace(regexp_replace("parentName", '-DHO\s*$', ''), '-', ' '))
WHERE "parentName" IS NOT NULL;

-- ---------------------------------------------------------------------------
-- C. Feed the app tables from the QGIS-imported organisation units
-- ---------------------------------------------------------------------------
INSERT INTO orgunits_raw (id, name, parentname, level, geom)
SELECT id,
       btrim(name),
       "parentName",
       level,
       geom
FROM organisation_units
WHERE geom IS NOT NULL
  AND id IS NOT NULL
  AND name IS NOT NULL
ON CONFLICT (id) DO UPDATE
   SET name       = EXCLUDED.name,
       parentname = EXCLUDED.parentname,
       level      = EXCLUDED.level,
       geom       = EXCLUDED.geom;

INSERT INTO facilities (facility_code, name, district, geom)
SELECT o.id,
       btrim(o.name),
       btrim(replace(regexp_replace(o.parentname, '-DHO\s*$', ''), '-', ' ')),
       o.geom
FROM orgunits_raw o
WHERE o.geom IS NOT NULL
  AND o.parentname IS NOT NULL
ON CONFLICT (facility_code) DO UPDATE
   SET name     = EXCLUDED.name,
       district = EXCLUDED.district,
       geom     = EXCLUDED.geom;

-- ---------------------------------------------------------------------------
-- D. HDX districts imported from QGIS: clean names, regions, and geometry
-- ---------------------------------------------------------------------------
UPDATE districts_hdx
SET name = initcap(btrim(name))
WHERE name IS NOT NULL;

UPDATE districts_hdx
SET region = CASE
        WHEN upper(btrim(region)) IN ('SOUTH', 'SOUTHERN') THEN 'Southern'
        WHEN upper(btrim(region)) IN ('NORTH', 'NORTHERN') THEN 'Northern'
        WHEN upper(btrim(region)) IN ('CENTRE', 'CENTRAL') THEN 'Central'
        WHEN btrim(coalesce(region, '')) = '' AND name IN ('Chikwawa', 'Neno') THEN 'Southern'
        ELSE initcap(btrim(region))
    END;

UPDATE districts_hdx
SET geom = ST_Multi(ST_MakeValid(geom))
WHERE geom IS NOT NULL
  AND GeometryType(geom) NOT IN ('MULTIPOLYGON');

-- ---------------------------------------------------------------------------
-- E. Organisation units inside the main-roads buffer
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS orgunits_in_buffer;
CREATE TABLE orgunits_in_buffer AS
SELECT s.id,
       s.name,
       s."parentName",
       s.district,
       s.level,
       s.geom
FROM main_roads_buffer rb
JOIN organisation_units s
  ON ST_Contains(rb.geom, ST_Transform(s.geom, ST_SRID(rb.geom)));

-- Point-in-polygon: organisation units inside each HDX district
DROP TABLE IF EXISTS orgunits_by_district_spatial;
CREATE TABLE orgunits_by_district_spatial AS
SELECT d.name AS hdx_district,
       o.id,
       o.name,
       o.district AS dhis2_district,
       o.geom
FROM districts_hdx d
JOIN organisation_units o
  ON ST_Contains(d.geom, o.geom);

-- ---------------------------------------------------------------------------
-- F. Quick report (compare with QGIS attribute table / canvas)
-- ---------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM organisation_units) AS imported_from_qgis,
    (SELECT COUNT(*) FROM orgunits_raw) AS orgunits_raw,
    (SELECT COUNT(*) FROM facilities) AS facilities,
    (SELECT COUNT(*) FROM orgunits_in_buffer) AS near_main_roads,
    (SELECT COUNT(*) FROM orgunits_by_district_spatial) AS inside_hdx_district;
