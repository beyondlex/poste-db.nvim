-- @connection maria-dev
-- @database blog

-- ============================================================
-- MariaDB-specific syntax (differs from MySQL)
-- ============================================================

-- Basic queries (data validation)
SELECT * FROM users LIMIT 5;
SELECT * FROM authors LIMIT 5;
SELECT p.title, a.username, c.name AS category
FROM posts p
JOIN authors a ON a.id = p.author_id
JOIN categories c ON c.id = p.category_id
ORDER BY p.created_at DESC LIMIT 20;

-- ENUM type
SELECT DISTINCT status FROM posts;
SELECT status, COUNT(*) FROM posts GROUP BY status;

-- CTE (MariaDB 10.2+)
WITH RECURSIVE seq (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 5
)
SELECT * FROM seq;

-- ============================================================
-- MariaDB exclusive features
-- ============================================================

-- CREATE OR REPLACE TABLE
CREATE OR REPLACE TABLE test_mariadb (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100)
);

-- Sequences (MariaDB 10.3+, not in MySQL)
CREATE SEQUENCE IF NOT EXISTS seq_user_id START WITH 1000 INCREMENT BY 1;
SELECT NEXTVAL(seq_user_id), LASTVAL(seq_user_id), SETVAL(seq_user_id, 2000);

-- DELETE ... RETURNING (MariaDB 10.3+, not in MySQL)
INSERT INTO test_mariadb (name) VALUES ('demo');
DELETE FROM test_mariadb WHERE id = 1 RETURNING id, name;

-- INSERT ... RETURNING
INSERT INTO users (name, email) VALUES ('ReturningTest', 'rt@test.com') RETURNING id, created_at;
DELETE FROM users WHERE name = 'ReturningTest';

-- INVISIBLE columns (MariaDB 10.3+)
CREATE TABLE test_invisible (
  id INT PRIMARY KEY AUTO_INCREMENT,
  visible_col VARCHAR(50),
  hidden_col VARCHAR(50) INVISIBLE
);
SHOW COLUMNS FROM test_invisible;
DROP TABLE test_invisible;

-- Virtual columns (MariaDB 5.2+)
CREATE TABLE test_virtual (
  id INT PRIMARY KEY AUTO_INCREMENT,
  width INT DEFAULT 10,
  height INT DEFAULT 20,
  area INT GENERATED ALWAYS AS (width * height) VIRTUAL
);
INSERT INTO test_virtual (width, height) VALUES (5, 8);
SELECT *, area FROM test_virtual;
DROP TABLE test_virtual;

-- AES encryption / decryption
SELECT AES_ENCRYPT('plaintext', 'key') AS encrypted;
SELECT AES_DECRYPT(AES_ENCRYPT('plaintext', 'key'), 'key') AS decrypted;

-- Storage engines
SHOW ENGINES;
SELECT ENGINE, SUPPORT FROM information_schema.ENGINES WHERE ENGINE IN ('InnoDB', 'Aria', 'MyISAM');

-- Window functions (MariaDB 10.2+)
SELECT title, author_id, created_at,
  ROW_NUMBER() OVER (PARTITION BY author_id ORDER BY created_at) AS rn
FROM posts LIMIT 20;

-- ============================================================
-- JSON column (posts.metadata)
-- ============================================================

-- Raw JSON + path extraction
SELECT id, title, metadata,
  JSON_EXTRACT(metadata, '$.reading_time') AS reading_time,
  JSON_VALUE(metadata, '$.tags[0]') AS first_tag
FROM posts WHERE metadata IS NOT NULL LIMIT 10;

-- JSON key membership / type checks (MariaDB)
SELECT id, title,
  JSON_EXISTS(metadata, '$.views') AS has_views,
  JSON_TYPE(JSON_EXTRACT(metadata, '$.tags')) AS tags_type
FROM posts WHERE metadata IS NOT NULL LIMIT 10;

-- Sort by a numeric JSON member and filter on array containment
SELECT id, title, JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.tags[0]')) AS first_tag
FROM posts WHERE metadata IS NOT NULL AND JSON_SEARCH(metadata, 'one', 'rust') IS NOT NULL
LIMIT 10;

-- CTE for complex queries
WITH author_stats AS (
  SELECT a.id, a.username, COUNT(p.id) AS post_count
  FROM authors a LEFT JOIN posts p ON p.author_id = a.id
  GROUP BY a.id, a.username
)
SELECT * FROM author_stats WHERE post_count > 0 ORDER BY post_count DESC LIMIT 10;

-- GROUP_CONCAT with ORDER BY
SELECT p.title, GROUP_CONCAT(t.name ORDER BY t.name SEPARATOR ', ') AS tags
FROM posts p
JOIN post_tags pt ON pt.post_id = p.id
JOIN tags t ON t.id = pt.tag_id
GROUP BY p.id, p.title LIMIT 20;

-- Cleanup
DROP TABLE IF EXISTS test_mariadb;
DROP SEQUENCE IF EXISTS seq_user_id;
