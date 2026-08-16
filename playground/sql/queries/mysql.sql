-- @connection my-blog
-- @database inventory

ALTER TABLE table_name ADD COLUMN column_name INTEGER NOT NULL DEFAULT 0 COMMENT '';

select * from poste_test_metrics ;
select * from poste_test_events;

show tables;

select 1;

set @a = 3;
SELECT * FROM items  where id = @a ;
set @a = 4;
SELECT * FROM items  where id = @a ;

SELECT * FROM items  ;

SELECT count(1) FROM items ;

SELECT * FROM blog.authors ;

select id, slug FROM blog.posts ;

-- SELECT p.slug, a. FROM posts p LEFT JOIN authors a on a.id = p.author_id;

-- SELECT p.slug, a.bio  FROM posts p LEFT JOIN authors a on a.id = p.author_id;

-- UPDATE posts SET bio = '' AFTERE id i


select * from poste_test_metrics;
select * from poste_test_events;;

select id, slug FROM blog.posts ;

-- drop table poste_test_events;
-- drop table poste_test_metrics;
-- drop table poste_test_users;
-- drop table shipments;

-- @database blog
SELECT id, page_id, url, measured_at, metric_01 from web_vitals  ;
SELECT * from web_vitals ;


SELECT p.slug, a.bio FROM posts p LEFT JOIN authors a on a.id = p.author_id;

SELECT * from comments;
SELECT * FROM posts;

-- ALTER TABLE authors
-- ADD COLUMN name   ;

SELECT * FROM categories;

SELECT * FROM authors a LEFT JOIN posts p on p.author_id = a.id;

use inventory;
select * from warehouses ;
SELECT * FROM shipments;
SELECT * FROM  items;
SELECT * FROM  suppliers;
SELECT * FROM  stock;


show tables;

use blog;

select * from posts;

use inventory;

SELECT w.name AS warehouse,
       w.city,
       COUNT(s.item_id) AS item_types,
       SUM(s.quantity) AS total_units
FROM warehouses w
LEFT JOIN stock s ON s.warehouse_id = w.id
GROUP BY w.id, w.name, w.city
ORDER BY total_units DESC;


SELECT s.*, p.title FROM authors s LEFT JOIN posts p on p.author_id = s.id;

update posts SET title = CONCAT(title, '.') WHERE id = 1;


SELECT s.*, p.title FROM authors s LEFT JOIN posts p on p.author_id = s.id;

USE blog;
-- show tables;

select * from posts;
desc posts;
select body from posts;

select s.*, c.* from posts s left join comments c on c.post_id = c.id;

select * from comments;

SELECT p.title,
       a.username AS author,
       c.name AS category,
       p.status,
       p.published_at
FROM posts p
JOIN authors a    ON a.id = p.author_id
JOIN categories c ON c.id = p.category_id
ORDER BY p.created_at DESC;

SELECT p.title,
       GROUP_CONCAT(t.name SEPARATOR ', ') AS tags
FROM posts p
JOIN post_tags pt ON pt.post_id = p.id
JOIN tags t       ON t.id = pt.tag_id
GROUP BY p.id, p.title;

SELECT p.title,
       COUNT(c.id) AS total_comments,
       SUM(c.approved) AS approved,
       COUNT(c.id) - SUM(c.approved) AS pending
FROM posts p
LEFT JOIN comments c ON c.post_id = p.id
GROUP BY p.id, p.title
HAVING total_comments > 0;

use inventory;

SELECT w.name AS warehouse,
       w.city,
       COUNT(s.item_id) AS item_types,
       SUM(s.quantity) AS total_units
FROM warehouses w
LEFT JOIN stock s ON s.warehouse_id = w.id
GROUP BY w.id, w.name, w.city
ORDER BY total_units DESC;

SELECT i.sku,
       i.name,
       s.quantity,
       w.name AS warehouse
FROM stock s
JOIN items i      ON i.id = s.item_id
JOIN warehouses w ON w.id = s.warehouse_id
WHERE s.quantity < 100
ORDER BY s.quantity ASC;

-- Active shipments
SELECT sh.id AS shipment_id,
       wf.name AS `from`,
       wt.name AS `to`,
       sh.status,
       GROUP_CONCAT(CONCAT(i.name, ' x', si.quantity) SEPARATOR ', ') AS items
FROM shipments sh
JOIN warehouses wf ON wf.id = sh.from_warehouse
JOIN warehouses wt ON wt.id = sh.to_warehouse
LEFT JOIN shipment_items si ON si.shipment_id = sh.id
LEFT JOIN items i ON i.id = si.item_id
WHERE sh.status != 'delivered'
GROUP BY sh.id, wf.name, wt.name, sh.status;



-- @connection pg-ecommerce
create table table_name (
  column_name INTEGER NOT NULL
);


