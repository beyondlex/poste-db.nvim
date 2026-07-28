-- @connection maria-dev
-- @database blog

-- MariaDB 特有语法 (与 MySQL 的区别)

-- 基础查询
SELECT * FROM users;

-- CREATE OR REPLACE TABLE 
CREATE OR REPLACE TABLE test_mariadb (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100)
);

-- INVISIBLE 列 
CREATE TABLE test_invisible (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100),
  secret VARCHAR(100) INVISIBLE
);

-- 序列 (MariaDB 10.3+, MySQL 用 AUTO_INCREMENT)
CREATE SEQUENCE seq_user_id START WITH 1000 INCREMENT BY 1;
SELECT NEXTVAL(seq_user_id);
SELECT LASTVAL(seq_user_id);
SELECT SETVAL(seq_user_id, 2000);

-- DELETE ... RETURNING (MariaDB 10.3+, MySQL 没有)
DELETE FROM test_mariadb WHERE id = 1 RETURNING id, name;

-- INSERT ... RETURNING 
INSERT INTO users (name, email) VALUES ('Maria', 'maria3@test.com') RETURNING id, created_at;

-- CTE 
WITH RECURSIVE cte (n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM cte WHERE n < 10
)
SELECT * FROM cte;

-- AES 
SELECT AES_ENCRYPT('plaintext', 'key') AS encrypted;
SELECT AES_DECRYPT(AES_ENCRYPT('plaintext', 'key'), 'key') AS decrypted;

SHOW ENGINES;
SELECT * FROM information_schema.ENGINES WHERE ENGINE = 'Aria';

CREATE TABLE test_virtual (
  id INT PRIMARY KEY AUTO_INCREMENT,
  width INT,
  height INT,
  area INT GENERATED ALWAYS AS (width * height) VIRTUAL
);

DROP TABLE IF EXISTS test_mariadb;
DROP TABLE IF EXISTS test_invisible;
DROP TABLE IF EXISTS test_virtual;
DROP SEQUENCE IF EXISTS seq_user_id;
