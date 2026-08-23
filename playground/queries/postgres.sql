-- @connection pg-ecommerce
-- @database ecommerce

-- ============================================================
-- Ecommerce: basic queries
-- ============================================================
SELECT * FROM users LIMIT 5;
SELECT id, name, email, created_at FROM users WHERE status = 'active' ORDER BY created_at DESC LIMIT 10;
SELECT COUNT(*) AS total, status, COUNT(*) AS cnt FROM users GROUP BY status ORDER BY cnt DESC;
SELECT DISTINCT category FROM products ORDER BY category;

-- JOIN aggregations
SELECT p.name, SUM(oi.quantity * oi.unit_price) AS revenue, SUM(oi.quantity) AS units_sold
FROM order_items oi JOIN products p ON p.id = oi.product_id
GROUP BY p.name ORDER BY revenue DESC LIMIT 10;

SELECT o.id, u.name AS customer, o.status, o.total, COUNT(oi.id) AS item_count
FROM orders o JOIN users u ON u.id = o.user_id LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id, u.name, o.status, o.total ORDER BY o.id DESC LIMIT 10;

-- Subqueries
SELECT * FROM products WHERE id IN (SELECT product_id FROM order_items GROUP BY product_id HAVING COUNT(*) > 10);
SELECT id, name, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count FROM users ORDER BY order_count DESC LIMIT 10;

-- Window functions
SELECT id, user_id, total, created_at,
  RANK() OVER (PARTITION BY user_id ORDER BY created_at) AS rank,
  LAG(total) OVER (PARTITION BY user_id ORDER BY created_at) AS prev_total,
  LEAD(total) OVER (PARTITION BY user_id ORDER BY created_at) AS next_total
FROM orders WHERE status = 'completed' ORDER BY user_id, created_at LIMIT 20;

-- PG-specific: GROUPING SETS / PERCENTILE / generate_series
SELECT user_id, status, COUNT(*) FROM orders
GROUP BY GROUPING SETS ((user_id), (status), ()) ORDER BY user_id, status LIMIT 15;

SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY total) AS median_total FROM orders;
SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY total) AS median_disc FROM orders;

SELECT generate_series(1, 5) AS num;
SELECT d::date FROM generate_series('2024-01-01'::date, '2024-01-05'::date, '1 day') AS d;
SELECT unnest(ARRAY['a', 'b', 'c']) AS letter;

-- Time functions
SELECT id, user_id, created_at,
  EXTRACT(YEAR FROM created_at) AS yr,
  EXTRACT(MONTH FROM created_at) AS mon,
  date_trunc('hour', created_at) AS hour_bucket
FROM orders LIMIT 10;

-- ILIKE / SIMILAR TO / SPLIT_PART
SELECT * FROM users WHERE name ILIKE 'alice%' OR email ILIKE '%@example.com';
SELECT * FROM users WHERE email SIMILAR TO '%@(example|gmail)\.com' LIMIT 10;
SELECT name, split_part(email, '@', 1) AS local_part FROM users LIMIT 10;

-- LATERAL
SELECT u.id, recent.order_id, recent.total
FROM users u
LEFT JOIN LATERAL (
  SELECT id AS order_id, total FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 3
) recent ON true
WHERE u.id <= 5 ORDER BY u.id;

-- WITH RECURSIVE
WITH RECURSIVE t(n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM t WHERE n < 5
) SELECT * FROM t;

-- DML with RETURNING
BEGIN;
INSERT INTO users (name, email) VALUES ('Test User', 'test@test.com') RETURNING id, created_at;
ROLLBACK;

BEGIN;
UPDATE users SET status = 'active' WHERE id = 1 RETURNING id, status;
ROLLBACK;

BEGIN;
DELETE FROM users WHERE id = 999 RETURNING *;
ROLLBACK;

-- ON CONFLICT (UPSERT)
INSERT INTO users (id, name, email) VALUES (1, 'Updated Alice', 'alice@new.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, created_at = now()
RETURNING *;

-- FOR UPDATE SKIP LOCKED
BEGIN;
SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
ROLLBACK;

-- @connection pg-analytics
-- @database analytics

-- ============================================================
-- Analytics: event analysis
-- ============================================================
SELECT * FROM events LIMIT 10;
SELECT event_type, COUNT(*) FROM events GROUP BY event_type ORDER BY COUNT(*) DESC;

-- JSONB
SELECT id, event_type, payload->>'url' AS url, payload ? 'product_id' AS has_product
FROM events ORDER BY created_at DESC LIMIT 20;

SELECT id, payload->'order_id' AS order_id FROM events WHERE payload ? 'order_id' LIMIT 10;

-- DISTINCT ON
SELECT DISTINCT ON (user_id) id, user_id, event_type, created_at
FROM events ORDER BY user_id, created_at DESC LIMIT 10;

-- FILTER aggregation
SELECT
  COUNT(*) FILTER (WHERE event_type = 'page_view') AS page_views,
  COUNT(*) FILTER (WHERE event_type = 'add_cart') AS add_carts,
  COUNT(*) FILTER (WHERE event_type = 'purchase') AS purchases,
  COUNT(*) FILTER (WHERE event_type = 'login') AS logins
FROM events;

-- ARRAY_AGG
SELECT event_type, ARRAY_AGG(DISTINCT user_id ORDER BY user_id) AS user_ids
FROM events GROUP BY event_type;

-- Sessions analysis
SELECT id, user_id, ip, started_at, ended_at FROM sessions LIMIT 10;

-- INET type
SELECT * FROM sessions WHERE ip << '192.168.0.0/16'::inet LIMIT 10;

-- Time intervals
SELECT id, user_id,
  EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at)) / 60 AS duration_min
FROM sessions ORDER BY duration_min DESC NULLS LAST LIMIT 10;

-- Wide table (sensor_readings: 52 cols)
SELECT * FROM sensor_readings LIMIT 5;
SELECT device_id, COUNT(*), AVG(temp_01) AS avg_temp, MAX(vibration_01) AS max_vib
FROM sensor_readings GROUP BY device_id ORDER BY avg_temp DESC LIMIT 10;

-- System queries
SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = 'public' ORDER BY tablename;
SELECT pid, query, state FROM pg_catalog.pg_stat_activity WHERE state = 'active';
-- EXPLAIN ANALYZE
EXPLAIN ANALYZE SELECT * FROM events WHERE event_type = 'page_view';
