-- @connection pg-ecommerce
-- @database ecommerce

SELECT 1;

use ecommerce;

show tables;
desc users;

SELECT * FROM users;

SELECT id, name, email, created_at
FROM users
WHERE status = 'active'
ORDER BY created_at DESC;

select * from products;

SELECT p.name AS product,
       SUM(oi.quantity * oi.unit_price) AS revenue,
       SUM(oi.quantity) AS units_sold
FROM order_items oi
JOIN products p ON p.id = oi.product_id
GROUP BY p.name
ORDER BY revenue DESC;

select quantity, unit_price from order_items;

SELECT o.id AS order_id,
       u.name AS customer,
       o.status,
       o.total,
       COUNT(oi.id) AS item_count
FROM orders o
JOIN users u ON u.id = o.user_id
LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id, u.name, o.status, o.total
ORDER BY o.created_at DESC;

-- === PostgreSQL-specific features ===

-- DISTINCT ON
SELECT DISTINCT ON (user_id) id, user_id, status, created_at
FROM orders
ORDER BY user_id, created_at DESC;

-- RETURNING 
INSERT INTO users (name, email) VALUES ('Lex', 'lex@test.com') RETURNING id, created_at;

UPDATE users SET status = 'inactive' WHERE id = 1 RETURNING id, status, updated_at;

DELETE FROM users WHERE id = 99 RETURNING *;

-- ON CONFLICT / UPSERT 
INSERT INTO users (id, name, email) VALUES (1, 'Lex', 'lex@test.com')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, created_at = now()
RETURNING *;

SELECT * FROM users WHERE name ILIKE 'lex%';

SELECT p.id, p.name, ARRAY_AGG(t.name) AS tags
FROM products p
LEFT JOIN product_tags t ON t.product_id = p.id
GROUP BY p.id, p.name;

-- STRING_AGG 
SELECT p.id, p.name, STRING_AGG(t.name, ', ') AS tags_csv
FROM products p
LEFT JOIN product_tags t ON t.product_id = p.id
GROUP BY p.id, p.name;

-- generate_series 
SELECT generate_series(1, 10) AS num;

SELECT d::date AS dt
FROM generate_series('2024-01-01'::date, '2024-01-10'::date, '1 day') d;

SELECT unnest(ARRAY['a', 'b', 'c']) AS letter;

SELECT id, payload->>'url' AS url, payload ? 'utm_source' AS has_utm
FROM events;

SELECT id, jsonb_array_elements(payload->'items') AS item
FROM events;

-- LATERAL join
SELECT u.id, u.name, recent.order_id, recent.total
FROM users u
LEFT JOIN LATERAL (
  SELECT id AS order_id, total
  FROM orders
  WHERE user_id = u.id
  ORDER BY created_at DESC
  LIMIT 3
) recent ON true;

-- WINDOW clause 
SELECT id, user_id, total,
  RANK() OVER w AS rank,
  LAG(total, 1) OVER w AS prev_total,
  LEAD(total, 1) OVER w AS next_total
FROM orders
WHERE status = 'completed'
WINDOW w AS (PARTITION BY user_id ORDER BY created_at);

-- GROUPING SETS / CUBE / ROLLUP 
SELECT user_id, status, COUNT(*) AS cnt
FROM orders
GROUP BY GROUPING SETS ((user_id), (status), ());

-- PERCENTILE_CONT 
SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY total) AS median_total
FROM orders;

-- SIMILAR TO
SELECT * FROM users WHERE email SIMILAR TO '%@(gmail|yahoo)\.com';

-- SPLIT_PART
SELECT split_part('a,b,c,d', ',', 2) AS part2;

-- FOR UPDATE SKIP LOCKED
BEGIN;
SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
COMMIT;

-- NOTIFY / LISTEN
NOTIFY order_shipped, 'order 42 shipped';

TABLE users;

-- EXPLAIN ANALYZE 
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'active';

-- pg_catalog 
SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = 'public';

-- lock
SELECT pid, locktype, mode, granted
FROM pg_catalog.pg_locks
WHERE NOT granted;

SELECT pid, query, state, query_start
FROM pg_catalog.pg_stat_activity
WHERE state = 'active';

USE analytics;

SELECT event_type, user_id, payload->>'url' AS url, created_at
FROM events
ORDER BY created_at DESC
LIMIT 20;

select * from events;

SELECT s.id,
       s.user_id,
       EXTRACT(EPOCH FROM (s.ended_at - s.started_at)) / 60 AS duration_min,
       COUNT(pv.id) AS pages_viewed
FROM sessions s
LEFT JOIN page_views pv ON pv.session_id = s.id
GROUP BY s.id, s.user_id, s.started_at, s.ended_at
ORDER BY duration_min DESC NULLS LAST;

SELECT
  COUNT(*) FILTER (WHERE event_type = 'page_view') AS views,
  COUNT(*) FILTER (WHERE event_type = 'add_cart')  AS add_to_cart,
  COUNT(*) FILTER (WHERE event_type = 'purchase')  AS purchases
FROM events;
