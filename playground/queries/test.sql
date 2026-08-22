-- @connection my-inventory
-- @database inventory

-- Quick data verification
SELECT 'items' AS tbl, COUNT(*) FROM items
UNION SELECT 'warehouses', COUNT(*) FROM warehouses
UNION SELECT 'suppliers', COUNT(*) FROM suppliers
UNION SELECT 'stock', COUNT(*) FROM stock
UNION SELECT 'shipments', COUNT(*) FROM shipments;

-- Random sampling
SELECT * FROM items ORDER BY RAND() LIMIT 5;
SELECT * FROM stock WHERE quantity < 50 ORDER BY quantity ASC;