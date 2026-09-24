/*
  Run against sql-publisher (localhost,14330), as 'sa'.
  Checks subscription status, measures latency with a tracer token, and inserts
  a live row. Run 05_check_subscriber.sql against sql-subscriber a few seconds
  after this one.

  Example:
  sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 04_validate_on_publisher.sql
*/

USE ReplDemo;
GO

-- Confirm the subscription exists and see its status
EXEC sp_helpsubscription;
GO

-- Post a tracer token to measure real Publisher -> Distributor -> Subscriber latency
DECLARE @tracer_id INT;
EXEC sp_posttracertoken @publication = N'ReplDemoPub', @tracer_token_id = @tracer_id OUTPUT;
GO

-- Wait ~10-30 seconds, then check the latency it measured
EXEC sp_helptracertokenhistory @publication = N'ReplDemoPub';
GO

-- Make a live change and watch it show up on the Subscriber
INSERT INTO dbo.Customers (CustomerId, Name, Email) VALUES (3, N'Chloe Pham', N'chloe@example.com');
GO
