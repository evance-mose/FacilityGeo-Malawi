-- Run after GeoJSON / CSV layers were imported from QGIS into the staging tables.
--   psql -d facilitygeo -f database/after_qgis_import.sql
--
-- 1) Normalises district names/regions from an HDX export
-- 2) Builds/refreshes facilities from orgunits_raw (same as build_facilities.sql)

-- Districts: Title Case names; SOUTH -> Southern; fill missing Southern districts
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

-- If QGIS wrote Polygon instead of MultiPolygon, promote it
UPDATE districts_hdx
SET geom = ST_Multi(ST_MakeValid(geom))
WHERE geom IS NOT NULL
  AND GeometryType(geom) NOT IN ('MULTIPOLYGON');

-- Facilities from DHIS2 org units (identity + district + location only)
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

SELECT
    (SELECT COUNT(*) FROM orgunits_raw) AS orgunits_raw,
    (SELECT COUNT(*) FROM facilities) AS facilities,
    (SELECT COUNT(*) FROM districts_hdx) AS districts_hdx,
    (SELECT COUNT(*) FROM tracker_raw) AS tracker_raw;
