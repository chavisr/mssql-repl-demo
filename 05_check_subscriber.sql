/* Run on the AWS RDS SQL Server subscriber: bash ./run-sql.sh 05 */

USE ReplDemo_Sub;
GO

SELECT * FROM dbo.Customers ORDER BY CustomerId;
GO
-- Row 3 (Chloe) should appear here shortly after 04 runs, with no manual sync step.
