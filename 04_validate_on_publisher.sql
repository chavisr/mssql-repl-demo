/* Run on the Azure SQL Managed Instance publisher/distributor: bash ./run-sql.sh 04 */

USE ReplDemo;
GO

-- Confirm the subscription exists and see its status
EXEC sp_helpsubscription;
GO

-- Post a tracer token to measure real Publisher -> Distributor -> Subscriber latency
DECLARE @tracer_id INT;
EXEC sp_posttracertoken @publication = N'ReplDemoPub', @tracer_token_id = @tracer_id OUTPUT;

-- Keep the token in the same batch and allow asynchronous delivery.
WAITFOR DELAY '00:00:15';
EXEC sp_helptracertokenhistory
    @publication = N'ReplDemoPub',
    @tracer_id = @tracer_id;
GO

-- Make a live change and watch it show up on the Subscriber
INSERT INTO dbo.Customers (CustomerId, Name, Email) VALUES (3, N'Chloe Pham', N'chloe@example.com');
GO
