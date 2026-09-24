/*
  Run against sql-publisher (localhost,14330), as 'sa'.
  Tests three things that don't behave like a plain INSERT/UPDATE/DELETE:
  TRUNCATE, a schema change (DDL), and a brand-new unpublished table.
  Run 07_check_subscriber_after_tests.sql against sql-subscriber a few
  seconds afterward to see what actually made it across.

  Example:
  sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 06_test_edge_cases_on_publisher.sql
*/

USE ReplDemo;
GO

-- TEST 1: TRUNCATE on a published table.
-- SQL Server often rejects this outright (Msg 4712, "Cannot truncate table
-- because it is published for replication") rather than letting it run and
-- silently not replicating. This line tells you which one actually happens.
TRUNCATE TABLE dbo.Customers;
GO

-- TEST 2: schema change (DDL) — add a column.
-- Simple ALTER TABLE ADD COLUMN is one of the DDL changes transactional
-- replication propagates by default.
ALTER TABLE dbo.Customers ADD Phone NVARCHAR(20) NULL;
GO

UPDATE dbo.Customers SET Phone = '555-0100' WHERE CustomerId = 1;
GO

-- TEST 3: a brand-new table, deliberately NOT added as an article.
-- Expectation: this should never appear on the Subscriber at all.
CREATE TABLE dbo.Orders (
    OrderId    INT PRIMARY KEY,
    CustomerId INT,
    Amount     DECIMAL(10,2)
);
GO

INSERT INTO dbo.Orders (OrderId, CustomerId, Amount) VALUES (1, 1, 49.99);
GO

SELECT * FROM dbo.Customers ORDER BY CustomerId;
GO
