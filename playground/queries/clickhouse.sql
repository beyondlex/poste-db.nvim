-- ClickHouse feature showcase.
--
-- Connection: add to connections.toml
--   [clickhouse]
--   dialect = "clickhouse"
--   host = "localhost"
--   port = 18123
--   database = "playground"
--   user = "default"
--   password = "poste_test"
--
-- Covered: MergeTree FINAL, TOTALS, ARRAY JOIN, arrays/maps/nested ops,
-- generateRandom, window functions, JSON functions, table functions
-- (numbers), ALTER UPDATE/DELETE (mutations), materialized view,
-- DateTime64/Decimal/UUID/Map types, groupArray/quantiles.
--
-- Note: ClickHouse has no transactions — ALTER UPDATE/DELETE are async
-- mutations; run this file with the default greedy mode.

-- @connection clickhouse
-- @database playground

-- TOP N 等价：LIMIT + ORDER BY
SELECT username, total FROM orders o
JOIN users u ON u.id = o.user_id
ORDER BY total DESC LIMIT 10;

-- TOTALS（小计行）+ 行数
SELECT status, count() AS n, sum(total) AS revenue
FROM orders GROUP BY status WITH TOTALS ORDER BY status;

-- 去重引擎 FINAL（ReplacingMergeTree 演示）
SELECT id, label, amount FROM type_showcase FINAL ORDER BY id;

-- ARRAY JOIN + 数组操作
SELECT id, tag, length(tags) AS tag_count
FROM type_showcase ARRAY JOIN tags AS tag ORDER BY id, tag;

-- ARRAY JOIN 多数组展开（sensors/readings 两个数组对齐展开）
SELECT id, sensor, reading
FROM type_showcase ARRAY JOIN sensors AS sensor, readings AS reading
ORDER BY id, sensor;

-- Map 操作
SELECT id, label, attrs['env'] AS env, mapKeys(attrs) AS keys
FROM type_showcase ORDER BY id;

-- window functions（ClickHouse 支持 OVER）
SELECT id, user_id, total,
       row_number() OVER (PARTITION BY user_id ORDER BY total DESC) AS rn,
       sum(total) OVER (PARTITION BY user_id ORDER BY id) AS running
FROM orders ORDER BY user_id, rn LIMIT 20;

-- generateRandom 表函数（纯演示，每次结果不同）
SELECT * FROM generateRandom('a UInt8, b String, c DateTime', 1, 2) LIMIT 3;

-- 表函数 numbers（批量生成）
SELECT count() AS n, sum(number) AS s FROM numbers(1, 100);

-- 聚合函数族：quantiles / groupArray / uniq
SELECT
  quantiles(0.5, 0.9)(total) AS p50_p90,
  groupArray(status) AS statuses,
  uniq(user_id) AS users
FROM orders;

-- 物化视图聚合（events_raw → events_daily_mv）
SELECT day, event, countMerge(cnt) AS n
FROM events_daily GROUP BY day, event ORDER BY day, event;

-- JSON 函数（ClickHouse 解析 JSON 字符串）
SELECT JSONExtractString('{"a": 1, "b": "x"}', 'b') AS b,
       JSONExtractInt('{"a": 1}', 'a') AS a;

-- 日期/类型函数
SELECT
  toDate(ordered_at) AS d,
  toStartOfHour(ordered_at) AS h,
  dateDiff('day', ordered_at, now()) AS days_ago,
  toTypeName(total) AS t
FROM orders ORDER BY id LIMIT 5;

-- ALTER UPDATE / DELETE（异步 mutation，返回后数据稍后生效）
ALTER TABLE type_showcase UPDATE amount = amount * 2 WHERE label = 'first';
SELECT id, label, amount FROM type_showcase WHERE label = 'first';
ALTER TABLE type_showcase DELETE WHERE label = 'second';
SELECT count() AS remaining FROM type_showcase;
