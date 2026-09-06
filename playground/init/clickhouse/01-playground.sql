-- poste-db ClickHouse playground seed
-- Cross-engine core tables (users / orders / order_items) plus ClickHouse
-- feature tables (MergeTree family, Map/Nested columns, TTL, materialized
-- view source). Consumed by /docker-entrypoint-initdb.d (clickhouse-client).
-- File stays under 8KB.

CREATE DATABASE IF NOT EXISTS playground;
USE playground;

-- ── core tables (same shape as postgres/mysql/mariadb/mssql seeds) ────────
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS type_showcase;
DROP TABLE IF EXISTS events_raw;
DROP TABLE IF EXISTS events_daily;
DROP VIEW  IF EXISTS events_daily_mv;

CREATE TABLE users (
  id UInt64,
  username String,
  email String,
  is_active UInt8,
  created_at DateTime64(3) DEFAULT now64()
) ENGINE = MergeTree ORDER BY id;

CREATE TABLE orders (
  id UInt64,
  user_id UInt64,
  status String,
  total Decimal(10, 2),
  ordered_at DateTime64(3) DEFAULT now64()
) ENGINE = MergeTree ORDER BY id;

CREATE TABLE order_items (
  id UInt64,
  order_id UInt64,
  product String,
  qty UInt32,
  unit_price Decimal(8, 2)
) ENGINE = MergeTree ORDER BY id;

-- ~5 hand-crafted users (id 1..5) then bulk-generated orders/items
INSERT INTO users (id, username, email, is_active) VALUES
  (1, 'alice', 'alice@example.com', 1),
  (2, 'bob',   'bob@example.com',   1),
  (3, 'carol', 'carol@example.com', 0),
  (4, 'dave',  'dave@example.com',  1),
  (5, 'erin',  'erin@example.com',  1);

INSERT INTO orders (id, user_id, status, total, ordered_at)
SELECT
  number,
  (number % 5) + 1,
  arrayElement(['pending', 'paid', 'shipped', 'done'], (number % 4) + 1),
  toDecimal64(((number % 9000) + 100), 2) / 10,
  now64() - number
FROM numbers(1, 500);

INSERT INTO order_items (id, order_id, product, qty, unit_price)
SELECT
  number,
  (number % 500) + 1,
  concat('SKU-', toString((number % 40) + 1)),
  (number % 3) + 1,
  toDecimal64(((number % 4000) + 150), 2) / 100
FROM numbers(1, 1200);

-- ── ClickHouse-specific feature tables ─────────────────────────────────────
-- Map / Array / TTL columns on a ReplacingMergeTree with TTL
-- (plain Array columns — Nested VALUES insertion has parsing quirks with
-- empty arrays; ARRAY JOIN works the same on multiple arrays)
CREATE TABLE type_showcase (
  id UInt64,
  label String,
  attrs Map(String, String),
  tags Array(String),
  sensors Array(String),
  readings Array(Float64),
  amount Decimal(10, 4),
  seen_at DateTime64(3),
  ttl_days UInt8 TTL seen_at + INTERVAL 365 DAY
) ENGINE = ReplacingMergeTree ORDER BY id;

INSERT INTO type_showcase (id, label, attrs, tags, sensors, readings, amount, seen_at) VALUES
  (1, 'first',  map('env', 'prod', 'tier', '1'), ['a', 'b'],
     ['cpu', 'mem'], [0.42, 0.81], 12.3456, '2026-01-15 10:30:00'),
  (2, 'second', map('env', 'dev'), ['x'],
     [], [], 3.14159, '2025-12-31 23:59:59'),
  (3, 'third',  map('env', 'staging', 'owner', 'platform'), ['c'],
     ['cpu'], [0.10], -1.5, '2026-06-01 00:00:00');

-- AggregatingMergeTree + materialized view source (events_daily)
CREATE TABLE events_daily (
  day Date,
  event String,
  cnt AggregateFunction(count)
) ENGINE = AggregatingMergeTree ORDER BY (day, event);

-- plain source table + a materialized view feeding the aggregate table.
-- The MV must exist BEFORE the inserts: a TO-table MV only aggregates rows
-- inserted after its creation, so seeding first would leave events_daily
-- empty (countMerge queries would return 0 rows).
CREATE TABLE events_raw (
  event String,
  at DateTime DEFAULT now()
) ENGINE = MergeTree ORDER BY at;

CREATE MATERIALIZED VIEW events_daily_mv TO events_daily AS
SELECT toDate(at) AS day, event, countState() AS cnt
FROM events_raw GROUP BY day, event;

INSERT INTO events_raw (event) VALUES
  ('click'), ('click'), ('view'), ('click'), ('view'), ('view'), ('purchase'), ('click'), ('view'), ('purchase');
