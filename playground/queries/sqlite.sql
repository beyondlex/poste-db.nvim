-- @connection sqlite-dev
-- @database main

-- ============================================================
-- Basic queries
-- ============================================================
SELECT * FROM users LIMIT 5;
SELECT * FROM products ORDER BY price DESC LIMIT 10;
SELECT * FROM orders ORDER BY created_at DESC LIMIT 10;

-- JOIN
SELECT u.name, o.status, o.total, oi.quantity, p.name AS product
FROM users u
JOIN orders o ON o.user_id = u.id
JOIN order_items oi ON oi.order_id = o.id
JOIN products p ON p.id = oi.product_id
LIMIT 20;

-- Aggregations
SELECT u.name, COUNT(o.id) AS order_count, SUM(o.total) AS total_spent
FROM users u LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.name ORDER BY total_spent DESC LIMIT 10;

-- Subqueries
SELECT id, name, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users ORDER BY order_count DESC LIMIT 10;

-- Window functions (SQLite 3.25+)
SELECT name, status, total,
  ROW_NUMBER() OVER (PARTITION BY status ORDER BY total DESC) AS rn,
  RANK() OVER (ORDER BY total DESC) AS rank
FROM (
  SELECT u.name, o.status, o.total FROM users u JOIN orders o ON o.user_id = u.id
) LIMIT 20;

-- ============================================================
-- SQLite-specific syntax
-- ============================================================

-- PRAGMA
PRAGMA journal_mode;
PRAGMA synchronous;
PRAGMA cache_size;
PRAGMA foreign_keys;
PRAGMA table_info(users);
PRAGMA index_list(users);
PRAGMA foreign_key_list(orders);

-- INSERT OR conflict handling
INSERT OR IGNORE INTO users (name, email) VALUES ('DupUser', 'dupe@test.com');
INSERT OR REPLACE INTO users (name, email) VALUES ('DupUser', 'replaced@test.com');
DELETE FROM users WHERE name = 'DupUser';

-- REPLACE INTO
REPLACE INTO users (id, name, email) VALUES (1, 'Alice', 'alice@new.com');
-- Restore original data
UPDATE users SET name = 'Alice', email = 'alice@gmail.com' WHERE id = 1;

-- Date/time functions
SELECT date('now') AS today;
SELECT time('now') AS now;
SELECT datetime('now') AS now_iso;
SELECT strftime('%Y-%m-%d %H:%M:%S', 'now') AS formatted;
SELECT julianday('now') - julianday('2024-01-01') AS days_since;
SELECT datetime('now', '-3 days', '+2 hours') AS computed;

-- JSON functions (built-in, no extension needed)
SELECT json_extract('{"a":1}', '$.a') AS val;
SELECT * FROM json_each('["a","b","c"]');
SELECT json_set('{"a":1}', '$.b', 2) AS updated;
SELECT json_type('{"a":1}', '$.a') AS typ;
SELECT json_object('name', 'Alice', 'age', 30) AS obj;

-- Aggregate functions
SELECT COUNT(*) AS total, TOTAL(amount) AS sum_float, AVG(amount) AS avg_amount
FROM orders;
SELECT status, COUNT(*), TOTAL(total), AVG(total) FROM orders GROUP BY status;

-- String functions
SELECT instr('hello world', 'world') AS pos;
SELECT substr('hello', 2, 3) AS part;
SELECT printf('Hello %s, you are %d', name, COALESCE(age, 0)) AS greeting
FROM users LIMIT 5;

-- Type functions
SELECT typeof(42) AS t1, typeof('hello') AS t2, typeof(1.5) AS t3, typeof(x'0102') AS t4;

-- GLOB (SQLite-specific, similar to LIKE with wildcards)
SELECT * FROM users WHERE email GLOB '*@gmail.com';
SELECT * FROM users WHERE email GLOB '*@???.com' LIMIT 5;

-- LIKE
SELECT * FROM users WHERE name LIKE '%a%' LIMIT 10;

-- NATURAL JOIN
SELECT * FROM orders NATURAL JOIN order_items LIMIT 10;

-- SAVEPOINT (nested transactions)
BEGIN;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp2;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
RELEASE SAVEPOINT sp2;
RELEASE SAVEPOINT sp1;
ROLLBACK;

-- EXPLAIN
EXPLAIN SELECT * FROM users WHERE id = 1;
EXPLAIN QUERY PLAN SELECT * FROM orders WHERE status = 'pending';

-- LIMIT and OFFSET
SELECT * FROM products ORDER BY id LIMIT 5 OFFSET 10;

-- WITH RECURSIVE
WITH RECURSIVE seq(n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 5
) SELECT * FROM seq;

-- VALUES clause
VALUES (1, 'a'), (2, 'b'), (3, 'c');

-- COALESCE / IFNULL / NULLIF
SELECT COALESCE(NULL, NULL, 'fallback') AS coalesced;
SELECT IFNULL(NULL, 'default') AS ifnull_val;
SELECT NULLIF(1, 1) AS nullif_eq, NULLIF(1, 2) AS nullif_neq;

-- UNION / INTERSECT / EXCEPT
SELECT name FROM users WHERE id <= 3
UNION ALL
SELECT name FROM users WHERE id <= 3 AND status = 'active';

-- System information
SELECT sql AS ddl FROM sqlite_master WHERE type = 'table' ORDER BY name;
SELECT name, type, tbl_name FROM sqlite_master WHERE type = 'index';

-- Wide table (events)
SELECT event_type, COUNT(*) AS cnt FROM events GROUP BY event_type ORDER BY cnt DESC;
SELECT * FROM events ORDER BY created_at DESC LIMIT 10;