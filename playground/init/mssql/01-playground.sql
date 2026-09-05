-- poste-db MSSQL playground seed (SQL Server 2022)
-- Cross-engine core tables (users / orders / order_items) plus MSSQL
-- feature showcase. Consumed by entrypoint.sh via sqlcmd, so GO batch
-- separators ARE allowed here (CREATE DATABASE must lead its batch).
-- Hand-crafted rows stay 3-7 per table; the rest is generated with
-- GENERATE_SERIES (SQL Server 2022+). File stays under 8KB.

IF DB_ID('playground') IS NULL CREATE DATABASE playground;
GO
USE playground;
GO

-- ── core tables (same shape as postgres/mysql/mariadb seeds) ────────────
IF OBJECT_ID('dbo.order_items', 'U') IS NOT NULL DROP TABLE dbo.order_items;
IF OBJECT_ID('dbo.orders', 'U') IS NOT NULL DROP TABLE dbo.orders;
IF OBJECT_ID('dbo.users', 'U') IS NOT NULL DROP TABLE dbo.users;
IF OBJECT_ID('dbo.type_showcase', 'U') IS NOT NULL DROP TABLE dbo.type_showcase;
GO

CREATE TABLE dbo.users (
  id INT IDENTITY(1,1) PRIMARY KEY,
  username NVARCHAR(64) NOT NULL,
  email NVARCHAR(255) NOT NULL,
  is_active BIT NOT NULL DEFAULT 1,
  guid UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
  created_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE dbo.orders (
  id INT IDENTITY(1,1) PRIMARY KEY,
  user_id INT NOT NULL REFERENCES dbo.users(id),
  status NVARCHAR(20) NOT NULL,
  total DECIMAL(10,2) NOT NULL,
  ordered_at DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE dbo.order_items (
  id INT IDENTITY(1,1) PRIMARY KEY,
  order_id INT NOT NULL REFERENCES dbo.orders(id),
  product NVARCHAR(100) NOT NULL,
  qty INT NOT NULL,
  unit_price DECIMAL(8,2) NOT NULL,
  rowver ROWVERSION
);
GO

CREATE INDEX idx_orders_user ON dbo.orders(user_id);
CREATE INDEX idx_items_order ON dbo.order_items(order_id);
GO

INSERT INTO dbo.users (username, email, is_active) VALUES
  ('alice',   'alice@example.com',   1),
  ('bob',     'bob@example.com',     1),
  ('carol',   'carol@example.com',   0),
  ('dave',    'dave@example.com',    1),
  ('erin',    'erin@example.com',    1);
GO

-- ~500 orders cycled across the 5 users with varied status/amounts
-- (the series column is `value`; the `AS s(n)` column-alias form is not
-- accepted for GENERATE_SERIES on this engine)
INSERT INTO dbo.orders (user_id, status, total, ordered_at)
SELECT
  (s.value % 5) + 1,
  CASE s.value % 4 WHEN 0 THEN 'pending' WHEN 1 THEN 'paid' WHEN 2 THEN 'shipped' ELSE 'done' END,
  CAST((s.value % 9000) + 100 AS DECIMAL(10,2)) / 10.0,
  DATEADD(DAY, -s.value, SYSDATETIME())
FROM GENERATE_SERIES(1, 500) AS s;
GO

-- ~1200 items, 1-3 per order, cycled across the 500 orders
INSERT INTO dbo.order_items (order_id, product, qty, unit_price)
SELECT
  (s.value % 500) + 1,
  'SKU-' + RIGHT('000' + CAST((s.value % 40) AS VARCHAR(4)), 4),
  (s.value % 3) + 1,
  CAST((s.value % 4000) + 150 AS DECIMAL(8,2)) / 100.0
FROM GENERATE_SERIES(1, 1200) AS s;
GO

-- ── MSSQL-specific type showcase ────────────────────────────────────────
CREATE TABLE dbo.type_showcase (
  id INT IDENTITY(1,1) PRIMARY KEY,
  label NVARCHAR(50) NOT NULL,
  big_text NVARCHAR(MAX),
  payload VARBINARY(256),
  amount MONEY,
  ratio DECIMAL(6,3),
  seen_at DATETIME2(7),
  seen_at_offset DATETIMEOFFSET,
  flags BIT,
  doc XML,
  rowver ROWVERSION
);
GO

INSERT INTO dbo.type_showcase (label, big_text, payload, amount, ratio, seen_at, seen_at_offset, flags, doc) VALUES
  ('first', REPLICATE('x', 200), 0xDEADBEEF, 12.3456, 0.125, '2026-01-15T10:30:00', '2026-01-15T10:30:00+08:00', 1, N'<root><a>1</a></root>'),
  ('second', NULL, NULL, -0.0001, 3.14159, '2025-12-31T23:59:59.997', '2025-12-31T23:59:59.997-05:00', 0, N'<root/>'),
  ('third', N'ünïcödé text', 0x00FF, 9999999.9999, -1.5, '2026-06-01T00:00:00', '2026-06-01T00:00:00Z', 1, N'<root><b>2</b></root>');
GO
