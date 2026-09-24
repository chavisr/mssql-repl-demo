/*
  Run against sql-subscriber (localhost,14331), as 'sa'.
  Run this a few seconds after 04_validate_on_publisher.sql.

  Example:
  sqlcmd -S localhost,14331 -U sa -P 'P@ssw0rd_Sub1' -C -i 05_check_subscriber.sql
*/

USE ReplDemo_Sub;
GO

SELECT * FROM dbo.Customers ORDER BY CustomerId;
GO
-- Row 3 (Chloe) should appear here shortly after 04 runs, with no manual sync step.
