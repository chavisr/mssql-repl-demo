/* Run on the AWS RDS SQL Server subscriber: bash ./run-sql.sh 07 */

USE ReplDemo_Sub;
GO

-- TEST 1 result: did the rows survive (TRUNCATE blocked/not replicated)
-- or vanish (TRUNCATE actually replicated)?
SELECT * FROM dbo.Customers ORDER BY CustomerId;
GO

-- TEST 2 result: did the new Phone column make it across?
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Customers';
GO

-- TEST 3 result: does the never-published Orders table exist here at all?
SELECT CASE
    WHEN OBJECT_ID('dbo.Orders') IS NOT NULL THEN 'Orders table EXISTS on subscriber (unexpected)'
    ELSE 'Orders table does NOT exist on subscriber (expected)'
END AS Orders_Check;
GO
