# SQL Integration Test Environment

Docker Compose environment for testing SQL queries across PostgreSQL, MySQL, MariaDB, and SQLite.

## Quick Start

```bash
cd playground/sql
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

- User: `root` / Password: `poste_test`

### MariaDB (port 13307)

| Database    | Tables                                                         | Rows             |
|-------------|----------------------------------------------------------------|------------------|
| `blog`      | users, authors, categories, posts, tags, post_tags, comments   | 53 / 53 / 4 / 207 / 30 / 506 |

- User: `root` / Password: `poste_test`

## Sample Queries

The `queries/` directory contains dialect-specific query files covering each database's syntax:

| File              | Dialect      | Connection      | Features Covered |
|-------------------|-------------|-----------------|------------------|
| `postgres.sql`    | PostgreSQL  | pg-ecommerce    | JSONB, DISTINCT ON, RETURNING, LATERAL, window functions, FILTER, ARRAY_AGG, generate_series, INET, full-text search, GROUPING SETS |
| `mysql.sql`       | MySQL       | my-blog         | GROUP_CONCAT, ELT, JSON functions, window functions, WITH RECURSIVE, wide tables, date functions |
| `mariadb.sql`     | MariaDB     | maria-dev       | Sequences, RETURNING, INVISIBLE columns, virtual columns, AES encryption, CTE |
| `sqlite.sql`      | SQLite      | sqlite-dev      | PRAGMA, INSERT OR, GLOB, NATURAL JOIN, SAVEPOINT, JSON functions, WITHOUT ROWID |

## Data Generation Strategy

All SQL files stay under 8KB. Hand-crafted demo data (3-7 rows) is kept for realistic samples; the rest is generated via `generate_series()` / `WITH RECURSIVE` + `random()`. No external dependencies, no file bloat.

## Cleanup

```bash
docker compose down -v
```