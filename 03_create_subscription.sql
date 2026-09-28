/*
  Run against sql-publisher (localhost,1433), as 'sa'.
  Creates a PUSH subscription targeting sql-subscriber — the only subscription
  type real RDS SQL Server supports, which is why we only ever use it here too.

  Example:
  sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Pub1' -C -i 03_create_subscription.sql

  Before running, verify the publisher container can connect to sql-publisher
  and SQL-PUBLISHER on TCP 1433, and to the remote sql-subscriber.
  See README.md: Verify publisher and subscriber connections.
*/

USE ReplDemo;
GO

EXEC sp_addsubscription
    @publication      = N'ReplDemoPub',
    @subscriber       = N'sql-subscriber',
    @destination_db   = N'ReplDemo_Sub',
    @subscription_type = N'push';
GO

EXEC sp_addpushsubscription_agent
    @publication            = N'ReplDemoPub',
    @subscriber             = N'sql-subscriber',
    @subscriber_db          = N'ReplDemo_Sub',
    @subscriber_security_mode = 0,           -- SQL Server auth — no Windows auth on Linux containers
    @subscriber_login       = N'sa',
    @subscriber_password    = N'P@ssw0rd_Sub1',
    @frequency_type         = 64;            -- continuous, not a batch schedule
GO

-- Kick off the initial snapshot immediately instead of waiting on its schedule
EXEC sp_startpublication_snapshot @publication = N'ReplDemoPub';
GO

PRINT 'Push subscription created; snapshot start requested. Wait for dbo.Customers on the Subscriber. Job startup does not confirm snapshot delivery; inspect agent history if the table stays missing.';
