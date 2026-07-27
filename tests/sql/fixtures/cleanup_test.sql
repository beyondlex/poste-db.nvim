-- Cleanup SQL file for poste exec-file test
-- Drops all temporary tables created by test_1000_lines.sql
-- Connection is provided via CLI --connection.

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS poste_test_events;
DROP TABLE IF EXISTS poste_test_metrics;
DROP TABLE IF EXISTS poste_test_orders;
DROP TABLE IF EXISTS poste_test_products;
DROP TABLE IF EXISTS poste_test_users;
SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Cleanup complete: all poste_test_* tables dropped' AS result;