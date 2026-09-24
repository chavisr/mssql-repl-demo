/*
  Run against sql-subscriber (localhost,14331), as 'sa'.
  Mimics: AWS RDS SQL Server prepped as a push Subscriber ONLY.

  Note what's deliberately absent here: no sp_adddistributor, no sp_addpublisher.
  Real RDS can't do either — this container isn't going to either, on purpose.

  Example:
  sqlcmd -S localhost,14331 -U sa -P 'P@ssw0rd_Sub1' -C -i 02_setup_subscriber_db.sql
*/

CREATE DATABASE ReplDemo_Sub;
GO
