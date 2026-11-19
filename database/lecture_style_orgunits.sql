-- FacilityGeo — same method as the lecture (schools/roads), using Organisation units.
--
-- Lecture flow:
--   1. PostGIS-enabled database
--   2. QGIS → DB Manager → Import layer (attribute table + geometry)
--   3. Basic spatial SQL (SRID, ALTER, UPDATE, geometry measures)
--   4. Relational spatial analysis (buffer / overlay with ST_Contains + ST_Transform)
--   5. Load result tables back into QGIS (double-click in DB Manager)
--
-- Prerequisites:
--   - database/setup.sql already applied
--   - Organisation units GeoJSON imported from QGIS into public.organisation_units
--     (see qgis/IMPORT.md). Optional: main_roads + main_roads_buffer from the lecture.
--
-- Run:
--   psql -d facilitygeo -f database/lecture_style_orgunits.sql

-- ---------------------------------------------------------------------------
-- A. Confirm the QGIS import (attribute table + geometry column)
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS organisation_units,
       GeometryType(geom) AS geom_type,
       ST_SRID(geom) AS srid
FROM organisation_units
GROUP BY 2, 3;

-- CRS meaning (lecture used spatial_ref_sys for 32736; org units are 4326)
SELECT srid, auth_name, auth_srid, left(srtext, 100) AS srtext
FROM spatial_ref_sys
WHERE srid = (SELECT ST_SRID(geom) FROM organisation_units LIMIT 1);

-- ---------------------------------------------------------------------------
-- B. Basic analysis: add fields and assign values (like speed_limit / time)
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
-- D. Relational spatial analysis (lecture: schools inside road buffer)
--     Here: organisation units inside the multi-valued main-roads buffer
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

-- Point-in-polygon cross-check with districts (lecture overlay idea)
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
-- E. Quick report (compare with QGIS attribute table / canvas)
-- ---------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM organisation_units) AS imported_from_qgis,
    (SELECT COUNT(*) FROM orgunits_raw) AS orgunits_raw,
    (SELECT COUNT(*) FROM facilities) AS facilities,
    (SELECT COUNT(*) FROM orgunits_in_buffer) AS near_main_roads,
    (SELECT COUNT(*) FROM orgunits_by_district_spatial) AS inside_hdx_district;
