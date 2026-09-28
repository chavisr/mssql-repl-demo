/* Run on the Azure SQL Managed Instance publisher/distributor: bash ./run-sql.sh 06 */

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
