/* Run on the Azure SQL Managed Instance publisher/distributor: bash ./run-sql.sh 01 */

USE master;
GO

-- Fresh dedicated lab MI only: do not overwrite an existing distributor.
IF CONVERT(int, SERVERPROPERTY('EngineEdition')) <> 8
    THROW 50001, 'This setup requires Azure SQL Managed Instance.', 1;
IF DB_ID(N'distribution') IS NOT NULL OR DB_ID(N'ReplDemo') IS NOT NULL
   OR EXISTS (SELECT 1 FROM sys.servers WHERE is_distributor = 1)
    THROW 50002, 'Use a fresh lab MI without distribution or ReplDemo already configured.', 1;
GO

-- 1) Configure the MI as its own distributor.
EXEC sp_adddistributor @distributor = @@SERVERNAME;
EXEC sp_adddistributiondb @database = N'distribution';
GO

USE distribution;
GO
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$(DISTRIBUTION_KEY_PASSWORD_SQL)';
GO

USE master;
GO

-- 2) Store snapshots in Azure Files, accessible from the MI on TCP 445.
EXEC sp_adddistpublisher
    @publisher = @@SERVERNAME,
    @distribution_db = N'distribution',
    @security_mode = 0,
    @login = N'$(MI_LOGIN_SQL)',
    @password = N'$(MI_PASSWORD_SQL)',
    @working_directory = N'$(SNAPSHOT_SHARE_SQL)',
    @storage_connection_string = N'$(STORAGE_CONNECTION_STRING_SQL)';
GO

-- 3) Sample database + table to replicate (needs a primary key to be eligible)
CREATE DATABASE ReplDemo;
GO

USE ReplDemo;
GO

CREATE TABLE dbo.Customers (
    CustomerId INT PRIMARY KEY,
    Name       NVARCHAR(100),
    Email      NVARCHAR(200),
    UpdatedAt  DATETIME2 DEFAULT SYSDATETIME()
);
GO

INSERT INTO dbo.Customers (CustomerId, Name, Email) VALUES
(1, N'Alice Nguyen', N'alice@example.com'),
(2, N'Bao Tran',     N'bao@example.com');
GO

-- 4) Enable the database for publication
EXEC sp_replicationdboption
    @dbname  = N'ReplDemo',
    @optname = N'publish',
    @value   = N'true';
GO

-- 5) Create the publication (continuous = the "always the same" behavior)
EXEC sp_addpublication
    @publication       = N'ReplDemoPub',
    @status             = N'active',
    @repl_freq          = N'continuous',
    @sync_method        = N'concurrent',
    @independent_agent  = N'true';
GO

-- Use explicit SQL credentials for MI replication agents.
EXEC sp_changelogreader_agent
    @publisher_security_mode = 0,
    @publisher_login = N'$(MI_LOGIN_SQL)',
    @publisher_password = N'$(MI_PASSWORD_SQL)',
    @job_login = N'$(MI_LOGIN_SQL)',
    @job_password = N'$(MI_PASSWORD_SQL)';
GO

EXEC sp_addpublication_snapshot
    @publication = N'ReplDemoPub',
    @frequency_type = 1,
    @publisher_security_mode = 0,
    @publisher_login = N'$(MI_LOGIN_SQL)',
    @publisher_password = N'$(MI_PASSWORD_SQL)',
    @job_login = N'$(MI_LOGIN_SQL)',
    @job_password = N'$(MI_PASSWORD_SQL)';
GO

-- 6) Add the table as an article
EXEC sp_addarticle
    @publication  = N'ReplDemoPub',
    @article      = N'Customers',
    @source_owner = N'dbo',
    @source_object = N'Customers',
    @type          = N'logbased';
GO

PRINT 'Publisher/Distributor setup complete.';
