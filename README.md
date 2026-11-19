# FacilityGeo

Database-driven map app for a Malawi health-information-system rollout: where facilities stand, where gaps are, and which not-started sites cluster together.

**Stack:** PostgreSQL 17 + PostGIS 3.7 + `pg_trgm` · FastAPI · Leaflet + Tailwind (CDN) · QGIS

**Data:** real DHIS2 facility points (908), HDX districts (28), and a real rollout tracker (59 rows, 47 matched). No seed or simulated data. No officers, funder, internet, or power columns in the tracker used. Real files stay out of Git (`data/`).

## Spatial methods

| Question | Method |
|---|---|
| Facilities within N km | `ST_DWithin` on `geography` |
| Clusters of not-started facilities | `ST_ClusterDBSCAN` (EPSG:32736) + `ST_ConvexHull` |
| % live per district | `GROUP BY` DHIS2 district name (joined to HDX by name). QGIS cross-checks counts with `ST_Contains` |
| Tracker → facility match | DHIS2 code → exact name → core name → `pg_trgm` fuzzy → manual matches |

## Run locally

Needs PostgreSQL with PostGIS and Python 3.10+.

```bash
createdb facilitygeo
psql -d facilitygeo -c "CREATE ROLE geo LOGIN"
psql -d facilitygeo -c "\password geo"
psql -d facilitygeo -f database/setup.sql

cp .env.example .env   # set DB_PASSWORD

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
# load GeoJSON / tracker with scripts/ and database/*.sql (see scripts/ headers)

uvicorn app.main:app --reload   # http://127.0.0.1:8000  ·  /docs
pytest -q
```

QGIS: open `qgis/facilitygeo.qgz` and connect to the local database (no password stored in the project).

## Notes

- **% live** = live ÷ matched tracked facilities (not all 908). District tooltips show tracked counts.
- **12 tracker rows** are unmatched and listed in the app summary (not guessed onto the map).
- Officer / nearest-officer UI stays hidden until real officer locations are loaded.
- API is for localhost only (no auth).

## Layout

```
app/        FastAPI
database/   SQL setup, match, apply
scripts/    loaders
frontend/   map UI
qgis/       project + styles
tests/      API tests
```
