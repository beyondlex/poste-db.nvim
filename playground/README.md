# SQL Integration Test Environment

Docker Compose environment for testing SQL queries across PostgreSQL, MySQL, MariaDB, and SQLite.

## Quick Start

```bash
cd playground
docker compose up -d
```

Wait 10-20 seconds for initialization, then verify:

```bash
docker compose ps
```

## Reinitialize

```bash
docker compose down -v
docker compose up -d
```

## Databases

### PostgreSQL (port 15432)

| Database    | Tables                                    | Rows               |
|-------------|-------------------------------------------|--------------------|
| `ecommerce` | users, products, orders, order_items      | 500 / 100 / 500 / 2.3k |
| `analytics` | events, sessions, page_views              | 2k / 505 / 5k      |
| `analytics` | sensor_readings (52-col wide table)       | 10k                |

- User: `poste` / Password: `poste_test`

### MySQL (port 13306)

| Database    | Tables                                                         | Rows             |
|-------------|----------------------------------------------------------------|------------------|
| `blog`      | authors, categories, posts, tags, post_tags, comments          | 53 / 4 / 207 / 30 / 508 |
| `blog`      | web_vitals (54-col wide table)                                 | 10k              |
| `inventory` | warehouses, suppliers, items, stock, shipments, shipment_items | 24 / 34 / 110 / 523 / 105 |
| `cinema`    | 36 tables (works, work_titles, people, characters, seasons, episodes, episode_lines, reviews, box_office, tracks, game_achievements, ...) | ~26k (works 300, titles 1.5k, people 501, characters 450, episodes 12.6k, episode_lines 1.5k, reviews 710, ...) |
| `history`   | 34 tables (regions, civilizations, eras, historical_figures, dynasties, wars, battles, literary_works, relics, timelines, citations, ...) | ~7k (figures 504, events 640, timeline 2k, citations 918, ...) |

- `cinema` (04/05) and `history` (06/07) demonstrate type coverage beyond the
  basics: JSON, ENUM, SET, BIT, BINARY(16), POINT geometry, DECIMAL, DOUBLE,
  FLOAT, SMALLINT, YEAR, TIME, BLOB — plus multilingual rows (en/zh/ja/la/ru)
  and deep parent→child hierarchies (works→seasons→episodes→episode_lines)
  sized for tree pagination demos.
- User: `root` / Password: `poste_test`

### MariaDB (port 13307)

| Database    | Tables                                                         | Rows             |
|-------------|----------------------------------------------------------------|------------------|
| `blog`      | users, authors, categories, posts, tags, post_tags, comments   | 53 / 53 / 4 / 207 / 30 / 506 |

- User: `root` / Password: `poste_test`

### SQL Server (port 11433)

> No official arm64 image: on Apple Silicon it runs under Rosetta/QEMU and
> startup is slow — the healthcheck allows ~2 minutes (`start_period`).
>
> **Unlike the other services, mssql data resets on every restart**: the
> image ignores `docker-entrypoint-initdb.d`, so `init/mssql/entrypoint.sh`
> re-applies the seed on each boot (tables are dropped and recreated). Hand-written
> tables survive a restart on postgres/mysql/mariadb but not here.

### ClickHouse (port 18123 HTTP / 19000 native)

> arm64 image — runs natively on Apple Silicon. Seed applies once on first
> volume init (like postgres/mysql/mariadb).

| Database    | Tables                                                         | Rows             |
|-------------|----------------------------------------------------------------|------------------|
| `playground`| users, orders, order_items                                     | 5 / 500 / 1.2k   |
| `playground`| type_showcase (Map/Nested/TTL on ReplacingMergeTree)           | 3                |
| `playground`| events_raw, events_daily (+materialized view `events_daily_mv`)| 10 / aggregated  |

- User: `default` / Password: `poste_test` (recent images disable network access for default unless credentials are set)

| Database    | Tables                                                         | Rows             |
|-------------|----------------------------------------------------------------|------------------|
| `playground`| users, orders, order_items                                     | 5 / 500 / 1.2k   |
| `playground`| type_showcase (MONEY/XML/DATETIMEOFFSET/ROWVERSION types)      | 4                |

- User: `sa` / Password: `Poste_test_2022` (needs `ACCEPT_EULA`; the image
  ignores `docker-entrypoint-initdb.d`, so `init/mssql/entrypoint.sh` boots
  `sqlservr`, applies the seed via `sqlcmd`, then keeps serving)

## Sample Queries

The `queries/` directory contains dialect-specific query files covering each database's syntax:

| File              | Dialect      | Connection      | Features Covered |
|-------------------|-------------|-----------------|------------------|
| `postgres.sql`    | PostgreSQL  | pg-ecommerce    | JSONB, DISTINCT ON, RETURNING, LATERAL, window functions, FILTER, ARRAY_AGG, generate_series, INET, full-text search, GROUPING SETS |
| `mysql.sql`       | MySQL       | my-blog         | GROUP_CONCAT, ELT, JSON functions, window functions, WITH RECURSIVE, wide tables, date functions |
| `mysql.sql`       | MySQL       | my-cinema       | multilingual titles, works→seasons→episodes→episode_lines tree, BIT/TIME/BINARY/YEAR, JSON metadata, ratings/reviews aggregation |
| `mysql.sql`       | MySQL       | my-history      | POINT geometry (ST_AsText), SET membership (FIND_IN_SET), JSON honors, BINARY(16) hex, 2k-row timeline pagination, multilingual citations |
| `mariadb.sql`     | MariaDB     | maria-dev       | Sequences, RETURNING, INVISIBLE columns, virtual columns, AES encryption, CTE |
| `sqlite.sql`      | SQLite      | sqlite-dev      | PRAGMA, INSERT OR, GLOB, NATURAL JOIN, SAVEPOINT, JSON functions, WITHOUT ROWID |
| `mssql.sql`       | SQL Server  | mssql           | TOP, OFFSET/FETCH, MERGE (UPSERT), IDENTITY, CAST/CONVERT, DATEDIFF/DATEADD, TRY_*, STRING_AGG, FORMAT, derived tables, temp tables, FOR JSON, GENERATE_SERIES, window functions, rowversion |
| `clickhouse.sql`  | ClickHouse  | clickhouse      | FINAL, TOTALS, ARRAY JOIN, arrays/maps/nested, generateRandom, window functions, JSON functions, table functions, quantiles/groupArray, ALTER UPDATE/DELETE (mutations), materialized view |

## Data Generation Strategy

Hand-crafted demo data (3-40 rows per table) is kept for realistic samples; the
rest is generated via `generate_series()` / `WITH RECURSIVE` + `random()`. The
large cinema/history MySQL seeds intentionally exceed ~8KB so tree pagination
has real volume (episodes 12.6k, timeline 2k, citations 918). No external
dependencies, no other file bloat.

## Cleanup

```bash
docker compose down -v
```