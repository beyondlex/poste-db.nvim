-- @connection sqlite-dev
-- @database main

-- SQLite Features

-- PRAGMA
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -8000;
PRAGMA foreign_keys = ON;

-- table structure
PRAGMA table_info(users);
PRAGMA index_list(users);
PRAGMA foreign_key_list(orders);

-- CREATE TABLE 选项
CREATE TABLE posts (
  id    INTEGER PRIMARY KEY ,
  title TEXT NOT NULL,
  body  TEXT,
  created_at TEXT DEFAULT (datetime('now'))
) WITHOUT ROWID;

-- INSERT OR 冲突处理 (SQLite 特有冲突子句)
INSERT OR IGNORE INTO users (email) VALUES ('dupe@test.com');
INSERT OR REPLACE INTO users (id, name) VALUES (1, 'overwritten');
INSERT OR ROLLBACK INTO products (id, name) VALUES (99, 'fail');
INSERT OR ABORT INTO products (id, name) VALUES (100, 'abort');
INSERT OR FAIL INTO products (id, name) VALUES (101, 'fail');

-- REPLACE INTO (MySQL 兼容, SQLite 也支持)
REPLACE INTO users (id, email) VALUES (1, 'new@test.com');

-- 日期/时间函数
SELECT date('now') AS today;
SELECT time('now') AS now;
SELECT datetime('now') AS now_iso;
SELECT strftime('%Y-%m-%d %H:%M:%S', 'now') AS formatted;
SELECT julianday('now') - julianday('2024-01-01') AS days_since;

-- JSON 函数 (SQLite 内置, 无需扩展)
SELECT json_extract('{"a":1}', '$.a') AS val;
SELECT * from json_each('["a","b","c"]');
SELECT json_set('{"a":1}', '$.b', 2) AS updated;
SELECT json_type('{"a":1}', '$.a') AS typ;

-- 聚合函数 (SQLite 特有)
SELECT COUNT(*) AS total, TOTAL(amount) AS sum_float, AVG(amount) AS avg
FROM orders;

-- 字符串函数
SELECT instr('hello world', 'world') AS pos;
SELECT substr('hello', 2, 3) AS part;
SELECT printf('Hello %s, you are %d', name, age) AS greeting
FROM users;

-- 类型函数
SELECT typeof(42) AS t1, typeof('hello') AS t2, typeof(1.5) AS t3;

-- GLOB (类似 LIKE 但用通配符, SQLite 特有)
SELECT * FROM users WHERE email GLOB '*@gmail.com';

-- CREATE VIRTUAL TABLE (FTS5 全文搜索)
-- CREATE VIRTUAL TABLE posts_fts USING fts5(title, body, content=posts);
-- SELECT * FROM posts_fts WHERE posts_fts MATCH 'search term';

-- SAVEPOINT (嵌套事务)
BEGIN;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp2;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
RELEASE SAVEPOINT sp2;
RELEASE SAVEPOINT sp1;
COMMIT;

-- EXPLAIN (SQLite 有 EXPLAIN, 没有 ANALYZE)
EXPLAIN SELECT * FROM users WHERE id = 1;
EXPLAIN QUERY PLAN SELECT * FROM users WHERE id = 1;

-- LIMIT 和 OFFSET (SQLite 语法)
SELECT * FROM products ORDER BY id LIMIT 10 OFFSET 20;

-- NATURAL JOIN
SELECT * FROM orders NATURAL JOIN order_items;

-- 子查询作为表达式
SELECT id, name, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- 查看系统信息
SELECT sql AS ddl FROM sqlite_master WHERE type = 'table';
SELECT * FROM sqlite_master WHERE type = 'index';
