-- sqlite3 test.db < 01-schema.sql

CREATE TABLE IF NOT EXISTS users (
  id    INTEGER PRIMARY KEY,
  name  TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  age   INTEGER,
  status TEXT DEFAULT 'active',
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT
);

CREATE TABLE IF NOT EXISTS products (
  id    INTEGER PRIMARY KEY,
  name  TEXT NOT NULL,
  price REAL NOT NULL DEFAULT 0,
  stock INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS orders (
  id         INTEGER PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id),
  status     TEXT DEFAULT 'pending',
  total      REAL NOT NULL DEFAULT 0,
  amount     REAL NOT NULL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS order_items (
  id         INTEGER PRIMARY KEY,
  order_id   INTEGER NOT NULL REFERENCES orders(id),
  product_id INTEGER NOT NULL REFERENCES products(id),
  quantity   INTEGER NOT NULL DEFAULT 1,
  unit_price REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
  id      INTEGER PRIMARY KEY,
  name    TEXT NOT NULL,
  balance REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS events (
  id         INTEGER PRIMARY KEY,
  event_type TEXT NOT NULL,
  user_id    INTEGER,
  payload    TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

-- 3 hand-crafted users
INSERT INTO users (name, email, age) VALUES
  ('Alice', 'alice@gmail.com', 30),
  ('Bob', 'bob@yahoo.com', 25),
  ('Charlie', 'charlie@outlook.com', 35);

-- 1000 generated users
WITH RECURSIVE seq(i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 1000
)
INSERT INTO users (name, email, age, status, created_at)
SELECT
  'User_' || i,
  'user' || i || '@example.com',
  abs(random()) % 50 + 18,
  CASE WHEN i % 7 = 0 THEN 'inactive' ELSE 'active' END,
  datetime('now', '-' || (abs(random()) % 365) || ' days')
FROM seq;

-- 3 hand-crafted products
INSERT INTO products (name, price, stock) VALUES
  ('Widget A', 9.99, 100),
  ('Widget B', 19.99, 50),
  ('Gadget X', 49.99, 20);

-- 100 generated products
WITH RECURSIVE seq(i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 100
)
INSERT INTO products (name, price, stock)
SELECT
  'Product_' || i,
  round(abs(random()) % 50000 / 100.0, 2),
  abs(random()) % 1000 + 10
FROM seq;

-- 500 generated orders
WITH RECURSIVE seq(i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 500
)
INSERT INTO orders (user_id, status, total, amount, created_at)
SELECT
  abs(random()) % 1003 + 1,
  CASE WHEN i % 5 = 0 THEN 'shipped' WHEN i % 7 = 0 THEN 'cancelled' ELSE 'pending' END,
  round(abs(random()) % 50000 / 100.0 + 10, 2),
  round(abs(random()) % 50000 / 100.0 + 10, 2),
  datetime('now', '-' || (abs(random()) % 180) || ' days')
FROM seq;

-- 2000 generated order_items
WITH RECURSIVE seq(i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 2000
)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
  abs(random()) % 500 + 1,
  abs(random()) % 103 + 1,
  abs(random()) % 8 + 1,
  round(abs(random()) % 40000 / 100.0 + 5, 2)
FROM seq;

-- 2 hand-crafted accounts
INSERT INTO accounts (name, balance) VALUES
  ('Checking', 1000.00),
  ('Savings', 5000.00);

-- 1000 generated events
WITH RECURSIVE seq(i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < 1000
)
INSERT INTO events (event_type, user_id, payload, created_at)
SELECT
  CASE WHEN i % 3 = 0 THEN 'click' WHEN i % 5 = 0 THEN 'purchase' ELSE 'page_view' END,
  abs(random()) % 1003 + 1,
  '{"page": "/page_' || (abs(random()) % 50) || '"}',
  datetime('now', '-' || (abs(random()) % 90) || ' days')
FROM seq;