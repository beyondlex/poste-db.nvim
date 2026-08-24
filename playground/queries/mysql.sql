-- @connection my-blog
-- @database blog

-- ============================================================
-- Blog: basic queries
-- ============================================================
SELECT * FROM authors LIMIT 5;
SELECT * FROM posts ORDER BY created_at DESC LIMIT 10;
SELECT * FROM comments WHERE approved = TRUE ORDER BY created_at DESC LIMIT 10;

-- JOIN aggregations
SELECT p.title, a.username AS author, c.name AS category, p.status, p.published_at
FROM posts p
JOIN authors a ON a.id = p.author_id
JOIN categories c ON c.id = p.category_id
ORDER BY p.created_at DESC LIMIT 20;

SELECT p.title, GROUP_CONCAT(t.name SEPARATOR ', ') AS tags
FROM posts p
JOIN post_tags pt ON pt.post_id = p.id
JOIN tags t ON t.id = pt.tag_id
GROUP BY p.id, p.title ORDER BY p.id LIMIT 20;

SELECT p.title, COUNT(c.id) AS total_comments, SUM(c.approved) AS approved
FROM posts p LEFT JOIN comments c ON c.post_id = p.id
GROUP BY p.id, p.title HAVING total_comments > 0 ORDER BY total_comments DESC LIMIT 10;

-- Subqueries
SELECT * FROM posts WHERE author_id IN (SELECT id FROM authors WHERE id > 10) LIMIT 10;
SELECT title, (SELECT COUNT(*) FROM comments WHERE post_id = posts.id) AS comment_count
FROM posts ORDER BY comment_count DESC LIMIT 10;

-- UNION
SELECT 'active' AS status, COUNT(*) FROM authors WHERE id <= 3
UNION ALL
SELECT 'generated', COUNT(*) FROM authors WHERE id > 3;

-- Window functions (MySQL 8.0+)
SELECT title, author_id, created_at,
  ROW_NUMBER() OVER (PARTITION BY author_id ORDER BY created_at) AS rn,
  RANK() OVER (PARTITION BY author_id ORDER BY created_at) AS rk
FROM posts LIMIT 20;

-- ENUM
SELECT DISTINCT status FROM posts;
SELECT status, COUNT(*) FROM posts GROUP BY status;

-- String functions
SELECT CONCAT('Hello, ', username) AS greeting, LENGTH(bio) AS bio_len FROM authors LIMIT 5;
SELECT UPPER(title), LOWER(slug) FROM posts LIMIT 5;
SELECT SUBSTRING(email, 1, 5) AS email_prefix FROM authors LIMIT 5;

-- Date functions
SELECT title, published_at, DATE_FORMAT(published_at, '%Y-%m-%d') AS fmt_date
FROM posts WHERE published_at IS NOT NULL LIMIT 10;

SELECT DATEDIFF(NOW(), published_at) AS days_ago FROM posts WHERE published_at IS NOT NULL LIMIT 10;
SELECT DATE_ADD(NOW(), INTERVAL 7 DAY) AS next_week, NOW(), CURDATE(), CURTIME();

-- Conditional functions
SELECT title, status,
  CASE status
    WHEN 'published' THEN 'published'
    WHEN 'draft' THEN 'draft'
    ELSE 'other'
  END AS status_label
FROM posts LIMIT 10;

-- Metadataj
SHOW TABLES;
DESC posts;
SHOW CREATE TABLE posts;
SHOW TABLE STATUS LIKE 'posts';

-- System functions
SELECT VERSION(), DATABASE(), USER(), CONNECTION_ID();
SELECT CHARSET('hello'), COLLATION('hello');

-- WITH RECURSIVE
INSERT INTO authors (username, email, bio)
WITH RECURSIVE seq (i) AS (
  SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 3
)
SELECT CONCAT('demo_', i), CONCAT('demo_', i, '@test.com'), 'demo bio' FROM seq;
DELETE FROM authors WHERE username LIKE 'demo_%';

-- Wide table (web_vitals: 54 cols)
SELECT * FROM web_vitals LIMIT 5;
SELECT url, COUNT(*), AVG(metric_01) AS avg_load, MAX(metric_05) AS max_ttfb
FROM web_vitals WHERE url != '/' GROUP BY url ORDER BY avg_load DESC LIMIT 10;

-- Performance analysis
SELECT url,
  ROUND(AVG(metric_01), 2) AS avg_load_time,
  ROUND(AVG(metric_05), 2) AS avg_ttfb,
  ROUND(AVG(metric_14), 4) AS avg_cls,
  ROUND(AVG(metric_08), 2) AS avg_lcp,
  ROUND(AVG(metric_13), 2) AS avg_fid
FROM web_vitals GROUP BY url ORDER BY avg_load_time DESC;

-- ============================================================
-- MySQL generic syntax (no table dependency)
-- ============================================================
SELECT JSON_OBJECT('key', 'value') AS obj;
SELECT JSON_ARRAY(1, 2, 3) AS arr;
SELECT JSON_EXTRACT('{"a":1,"b":2}', '$.a') AS val;
SELECT GROUP_CONCAT('a', 'b', 'c' SEPARATOR '-') AS concat_test;
SELECT ELT(1 + FLOOR(RAND() * 3), 'low', 'medium', 'high') AS priority;
SELECT FIELD('b', 'a', 'b', 'c') AS pos;
SELECT RAND(), ROUND(3.14159, 2), FLOOR(4.7), CEILING(4.3), ABS(-5), POWER(2, 3);
SELECT COALESCE(NULL, 'default') AS val, IFNULL(NULL, 'fallback') AS fb;
SELECT IF(1 > 0, 'true', 'false') AS bool_test;

-- JSON column (posts.metadata)
SELECT id, title, metadata FROM posts WHERE metadata IS NOT NULL LIMIT 10;

-- JSON path extraction (-> / ->>)
SELECT id, title,
  metadata->'$.reading_time' AS reading_time,
  JSON_UNQUOTE(metadata->'$.tags[0]') AS first_tag
FROM posts WHERE metadata IS NOT NULL ORDER BY id LIMIT 10;

-- JSON existence / containment
SELECT id, title FROM posts
WHERE metadata IS NOT NULL AND JSON_CONTAINS(metadata->'$.tags', '"rust"')
LIMIT 10;

SELECT id, title, JSON_EXTRACT(metadata, '$.views') AS views
FROM posts WHERE metadata IS NOT NULL ORDER BY JSON_EXTRACT(metadata, '$.views') DESC
LIMIT 10;

-- JSON aggregation over elements
SELECT JSON_ARRAYAGG(title) AS titles FROM posts WHERE metadata IS NOT NULL;

-- JSON key membership check (reading_time is a numeric member)
SELECT id, title, JSON_CONTAINS_PATH(metadata, 'one', '$.views', '$.tags') AS has_views_or_tags
FROM posts WHERE metadata IS NOT NULL LIMIT 10;

-- Full-text search (requires FULLTEXT index)
-- SELECT * FROM posts WHERE MATCH(title, body) AGAINST('Rust' IN BOOLEAN MODE) LIMIT 10;

-- @connection my-inventory
-- @database inventory

-- ============================================================
-- Inventory: stock queries
-- ============================================================
SELECT * FROM warehouses;
SELECT * FROM suppliers ORDER BY rating DESC;

SELECT w.name, w.city, COUNT(s.item_id) AS item_types, SUM(s.quantity) AS total_units
FROM warehouses w LEFT JOIN stock s ON s.warehouse_id = w.id
GROUP BY w.id, w.name, w.city ORDER BY total_units DESC;

SELECT i.sku, i.name, s.quantity, w.name AS warehouse
FROM stock s
JOIN items i ON i.id = s.item_id
JOIN warehouses w ON w.id = s.warehouse_id
WHERE s.quantity < 100 ORDER BY s.quantity ASC;

-- Shipment tracking
SELECT sh.id, wf.name AS `from`, wt.name AS `to`, sh.status,
       GROUP_CONCAT(CONCAT(i.name, ' x', si.quantity) SEPARATOR ', ') AS items
FROM shipments sh
JOIN warehouses wf ON wf.id = sh.from_warehouse
JOIN warehouses wt ON wt.id = sh.to_warehouse
LEFT JOIN shipment_items si ON si.shipment_id = sh.id
LEFT JOIN items i ON i.id = si.item_id
WHERE sh.status != 'delivered'
GROUP BY sh.id, wf.name, wt.name, sh.status;
