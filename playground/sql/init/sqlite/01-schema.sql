
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

-- Seed data
INSERT INTO users (name, email, age) VALUES
  ('Alice', 'alice@gmail.com', 30),
  ('Bob', 'bob@yahoo.com', 25),
  ('Charlie', 'charlie@outlook.com', 35);

INSERT INTO products (name, price, stock) VALUES
  ('Widget A', 9.99, 100),
  ('Widget B', 19.99, 50),
  ('Gadget X', 49.99, 20);

INSERT INTO accounts (name, balance) VALUES
  ('Checking', 1000.00),
  ('Savings', 5000.00);
