-- MSSQL (SQL Server 2022 / T-SQL) feature showcase.
--
-- Connection: add to connections.toml
--   [mssql]
--   dialect = "mssql"
--   host = "localhost"
--   port = 11433
--   database = "playground"
--   user = "sa"
--   password = "Poste_test_2022"
--
-- Covered: TOP, OFFSET/FETCH, MERGE (UPSERT), IDENTITY, CAST/CONVERT,
-- DATEDIFF/DATEADD, TRY_*, STRING_AGG, FORMAT, derived tables, temp tables,
-- FOR JSON, GENERATE_SERIES, window functions, IIF/CHOOSE, sys metadata.
-- Note: temp tables (#tmp) persist across statements because one TDS session
-- runs the whole file.

-- @connection mssql
-- @database playground

-- TOP + ORDER BY
SELECT TOP (10) o.id, u.username, o.status, o.total
FROM dbo.orders o
JOIN dbo.users u ON u.id = o.user_id
ORDER BY o.total DESC;

-- OFFSET / FETCH pagination (page 2 of 10-row pages)
SELECT o.id, o.status, o.total
FROM dbo.orders o
ORDER BY o.id
OFFSET 10 ROWS FETCH NEXT 10 ROWS ONLY;

-- MERGE as UPSERT into a temp table
CREATE TABLE #user_stats (user_id INT PRIMARY KEY, order_count INT, spend DECIMAL(12,2));
INSERT INTO #user_stats (user_id, order_count, spend)
SELECT user_id, COUNT(*), SUM(total) FROM dbo.orders GROUP BY user_id;

MERGE INTO #user_stats AS tgt
USING (SELECT user_id, COUNT(*) AS c, SUM(total) AS s FROM dbo.orders GROUP BY user_id) AS src
  ON tgt.user_id = src.user_id
WHEN MATCHED THEN UPDATE SET order_count = src.c, spend = src.s
WHEN NOT MATCHED THEN INSERT (user_id, order_count, spend) VALUES (src.user_id, src.c, src.s);
SELECT * FROM #user_stats ORDER BY spend DESC;

-- STRING_AGG with WITHIN GROUP + FORMAT
SELECT u.username,
       COUNT(o.id) AS orders,
       FORMAT(SUM(o.total), 'N2') AS total_fmt,
       STRING_AGG(o.status, ', ') WITHIN GROUP (ORDER BY o.status) AS statuses
FROM dbo.users u
JOIN dbo.orders o ON o.user_id = u.id
GROUP BY u.username
ORDER BY orders DESC;

-- Window functions: rank + running total
SELECT TOP (10) id, user_id, total,
       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY total DESC) AS rn,
       SUM(total) OVER (PARTITION BY user_id ORDER BY id) AS running_total
FROM dbo.orders
ORDER BY user_id, rn;

-- Date functions: DATEDIFF / DATEADD / FORMAT / DATETRUNC
SELECT TOP (5) id, ordered_at,
       DATEDIFF(DAY, ordered_at, SYSDATETIME()) AS days_ago,
       DATEADD(MONTH, 1, ordered_at) AS next_month,
       FORMAT(ordered_at, 'yyyy-MM-dd (ddd)') AS pretty,
       DATETRUNC(MONTH, ordered_at) AS month_start
FROM dbo.orders
ORDER BY id;

-- CAST / CONVERT / TRY_* (and error-safe conversion)
SELECT
  CAST(total AS INT) AS total_int,
  CONVERT(VARCHAR(19), ordered_at, 121) AS iso,
  TRY_CAST('not-a-number' AS INT) AS bad_cast,
  TRY_CONVERT(DECIMAL(5,2), '42.1234') AS ok_convert,
  IIF(total > 500, 'big', 'small') AS size_class,
  CHOOSE(status_ord, 'A', 'B', 'C', 'D') AS bucket
FROM (
  SELECT id, total, ordered_at,
         CASE status WHEN 'pending' THEN 1 WHEN 'paid' THEN 2 WHEN 'shipped' THEN 3 ELSE 4 END AS status_ord
  FROM dbo.orders
) AS derived_orders;  -- derived table

-- FOR JSON
SELECT TOP (3) u.username, o.total, o.status
FROM dbo.orders o
JOIN dbo.users u ON u.id = o.user_id
ORDER BY o.id
FOR JSON PATH, INCLUDE_NULL_VALUES;

-- IDENTITY + type showcase (uniqueidentifier, money, xml, datetimeoffset)
INSERT INTO dbo.type_showcase (label, big_text, amount, ratio, seen_at_offset, flags, doc)
VALUES ('from-queries', N'inserted via playground', 42.42, 0.666, SYSDATETIMEOFFSET(), 1, N'<q>ok</q>');
SELECT id, label, amount, ratio, seen_at_offset, flags, CAST(doc AS NVARCHAR(100)) AS doc_head
FROM dbo.type_showcase WHERE label = 'from-queries';

-- Temp table from a previous statement is still visible in this session
SELECT COUNT(*) AS temp_rows FROM #user_stats;

-- GENERATE_SERIES + sys metadata (2022 features)
SELECT TOP (5) s.value AS n, REPLICATE('*', s.value % 5 + 1) AS bar FROM GENERATE_SERIES(1, 5) AS s;
SELECT s.name AS schema_name, COUNT(*) AS objects
FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
GROUP BY s.name;

-- rowversion changes automatically on update
SELECT id, label, rowver FROM dbo.type_showcase WHERE label = 'first';
UPDATE dbo.type_showcase SET amount = amount * 2 WHERE label = 'first';
SELECT id, label, rowver FROM dbo.type_showcase WHERE label = 'first';
