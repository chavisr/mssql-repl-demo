/* Run on the Azure SQL Managed Instance publisher/distributor: bash ./run-sql.sh 03 */

USE ReplDemo;
GO

EXEC sp_addsubscription
    @publication      = N'ReplDemoPub',
    @subscriber       = N'$(RDS_SERVER_SQL)',
    @destination_db   = N'ReplDemo_Sub',
    @subscription_type = N'push',
    @sync_type = N'automatic',
    @article = N'all',
    @update_mode = N'read only',
    @subscriber_type = 0;
GO

EXEC sp_addpushsubscription_agent
    @publication            = N'ReplDemoPub',
    @subscriber             = N'$(RDS_SERVER_SQL)',
    @subscriber_db          = N'ReplDemo_Sub',
    @subscriber_security_mode = 0,           -- SQL authentication to RDS
    @subscriber_login       = N'$(RDS_LOGIN_SQL)',
    @subscriber_password    = N'$(RDS_PASSWORD_SQL)',
    @job_login              = N'$(MI_LOGIN_SQL)',
    @job_password           = N'$(MI_PASSWORD_SQL)',
    @frequency_type         = 64;            -- continuous, not a batch schedule
GO

-- Kick off the initial snapshot immediately instead of waiting on its schedule
EXEC sp_startpublication_snapshot @publication = N'ReplDemoPub';
GO

PRINT 'Push subscription created; snapshot start requested. Wait for dbo.Customers on the Subscriber. Job startup does not confirm snapshot delivery; inspect agent history if the table stays missing.';
