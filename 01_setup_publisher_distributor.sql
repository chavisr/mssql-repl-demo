/*
  Run against sql-publisher (localhost,14330), as 'sa'.
  Mimics: Azure SQL MI configured as Distributor + Publisher.

  The docker-compose.yml now creates /var/opt/mssql/ReplData automatically on
  container startup, so no manual mkdir/chown step is needed before this script.

  Example:
  sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 01_setup_publisher_distributor.sql
*/

USE master;
GO

-- 1) Install a local distributor.
--    @security_mode = 0 (SQL Server Authentication) throughout this whole exercise,
--    because Linux containers have no Windows/AD auth available without extra setup.
EXEC sp_adddistributor
    @distributor = @@SERVERNAME,
    @password    = N'DistPassword1!';
GO

EXEC sp_adddistributiondb
    @database      = N'distribution',
    @security_mode = 0,
    @login         = N'sa',
    @password      = N'P@ssw0rd_Pub1';
GO

-- Replication encrypts agent secrets (e.g. the subscriber password used in step 3)
-- using this key. Without it you get a warning now and likely a hard failure later.
USE distribution;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'DistrMasterKey1!';
GO

USE master;
GO

-- 2) Register this server as a publisher that uses the distributor above
EXEC sp_adddistpublisher
    @publisher         = @@SERVERNAME,
    @distribution_db   = N'distribution',
    @working_directory = N'/var/opt/mssql/ReplData',
    @security_mode     = 0,
    @login             = N'sa',
    @password          = N'P@ssw0rd_Pub1';
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

EXEC sp_addpublication_snapshot
    @publication = N'ReplDemoPub';
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
