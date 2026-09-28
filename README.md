# Azure SQL Managed Instance → AWS RDS SQL Server

A transactional replication lab that publishes `dbo.Customers` from `ReplDemo` on Azure SQL Managed Instance to `ReplDemo_Sub` on Amazon RDS for SQL Server through a continuous push subscription.

Use branch `scenario/azure-mi-to-rds`. The container lab is on [scenario/two-vm-replication](https://github.com/chavisr/mssql-repl-demo/tree/scenario/two-vm-replication). This branch configures existing managed services; it does not provision cloud resources.

## Topology and prerequisites

| Resource | Role |
| --- | --- |
| Azure SQL Managed Instance | Publisher, distributor, and all replication agent jobs |
| Azure Files share | Snapshot working directory |
| Amazon RDS for SQL Server | Push subscriber only |
| Administration machine | Bash, Microsoft ODBC `sqlcmd`, and network access to both databases |

Prepare these resources before running setup:

- A dedicated lab MI with no existing distributor or `ReplDemo` database. This requires **SQL Managed Instance**, not Azure SQL Database.
- An RDS for SQL Server instance with no existing `ReplDemo_Sub` database. Check supported replication versions for the chosen MI update policy and RDS engine version.
- An MI SQL administrator login able to configure replication, and the RDS master login for this lab. The agents use these credentials; supply the actual configured usernames, not the Docker lab's `sa` login.
- A reachable RDS DNS endpoint and SQL port from the MI subnet, with routing, DNS, Azure NSG rules, and the RDS security group configured. Use private connectivity between the Azure VNet and AWS VPC, such as a site-to-site VPN. Access from your administration machine alone does not establish MI-to-RDS connectivity.
- An Azure storage account with an SMB file share, its UNC path, and its storage connection string. Allow MI outbound TCP `445` to the share and access through the storage firewall. Use a share dedicated to this lab.
- Trusted TLS certificates on the administration machine, including the applicable RDS CA certificate. The runner requests encryption and does not bypass certificate validation.

MI snapshot storage and agent configuration follow [Microsoft's replication setup guide](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/replication-between-two-instances-configure-tutorial?view=azuresql). RDS subscription configuration uses the endpoint directly, as described in [AWS's transactional replication guide](https://aws.amazon.com/blogs/database/migrating-to-amazon-rds-for-sql-server-using-transactional-replication-part-2/). Keep the DNS endpoint instead of pinning an IP or requiring the RDS internal server name to match it.

## Configure the lab

From this repository on your administration machine:

```bash
cp cloud.env.example cloud.env
chmod 600 cloud.env
```

Edit `cloud.env` with your endpoints, credentials, Azure Files share, storage connection string, and a strong distribution database master-key password. The file is ignored by Git. Use Bash quoting for all values; for an apostrophe inside a single-quoted value, close the quote, insert `\'`, and reopen it. The runner escapes SQL string literals separately.

| Setting | Example or meaning |
| --- | --- |
| `MI_SERVER` | MI connection endpoint and port, e.g. `my-mi.zone.database.windows.net,1433` |
| `MI_LOGIN`, `MI_PASSWORD` | MI SQL login used for administration and replication agents |
| `RDS_SERVER` | RDS DNS endpoint and port, e.g. `my-rds.id.region.rds.amazonaws.com,1433` |
| `RDS_LOGIN`, `RDS_PASSWORD` | RDS SQL login used to create and populate the subscriber database |
| `SNAPSHOT_SHARE` | UNC path such as `\\storageaccount.file.core.windows.net\replshare` |
| `STORAGE_CONNECTION_STRING` | Storage account connection string containing its account key |
| `DISTRIBUTION_KEY_PASSWORD` | Password protecting the distribution database master key |

The MI endpoint/port must be reachable from your administration machine; use the appropriate connection endpoint for your network. The RDS endpoint/port is also used by the MI's Distribution Agent.

Load your configuration and verify administrative access:

```bash
source ./cloud.env
SQLCMDPASSWORD="$MI_PASSWORD" sqlcmd -S "$MI_SERVER" -U "$MI_LOGIN" -N -b \
  -Q "SELECT @@SERVERNAME AS ServerName, SERVERPROPERTY('EngineEdition') AS EngineEdition;"
SQLCMDPASSWORD="$RDS_PASSWORD" sqlcmd -S "$RDS_SERVER" -U "$RDS_LOGIN" -N -b \
  -Q 'SELECT @@SERVERNAME AS ServerName;'
```

Expect engine edition `8` on MI. RDS may return an internal server name different from its DNS endpoint; continue using the endpoint. Passwords are passed to `sqlcmd` through its environment, not command-line arguments. Do not run with shell tracing enabled.

## Run setup

The runner chooses the correct service for each numbered script. Run setup once against the fresh lab:

```bash
bash ./run-sql.sh 01
bash ./run-sql.sh 02
bash ./run-sql.sh 03
```

| Step | Service | Action |
| --- | --- | --- |
| `01` | MI | Configure distribution and Azure Files, seed Alice and Bao, publish `Customers`, and configure Log Reader and Snapshot agents |
| `02` | RDS | Create the empty `ReplDemo_Sub` database |
| `03` | MI | Create the continuous push subscription using the RDS endpoint and request the initial snapshot |

The scripts contain SQLCMD variables; use the runner after loading `cloud.env`. Setup is not idempotent. If the snapshot is already running when step `03` requests it, allow that run to finish rather than rerunning setup.

Allow a minute or two for initialization, then check the subscriber:

```bash
bash ./run-sql.sh 05
```

Expect Alice and Bao, IDs `1` and `2`. Wait for these rows before continuing; starting an agent job does not confirm snapshot delivery.

## Test replication

Insert Chloe and record tracer-token latency on MI, then check RDS:

```bash
bash ./run-sql.sh 04
bash ./run-sql.sh 05
```

Step `04` waits 15 seconds before reading its tracer token; incomplete latency values mean the token has not finished travelling. Expect customers `1`, `2`, and `3` on RDS after delivery. Run the publisher mutation once; repeat only the subscriber query while waiting.

Run the edge-case checks:

```bash
bash ./run-sql.sh 06
bash ./run-sql.sh 07
```

Step `06` deliberately attempts a prohibited `TRUNCATE`, so the runner lets subsequent batches continue. Inspect its output for the expected rejection and repeat step `07` after delivery if needed.

| Test | Expected result |
| --- | --- |
| Truncate published `Customers` | Rejected; rows remain |
| Add and update `Phone` | Column arrives on RDS; Alice's value is `555-0100` |
| Create unpublished `Orders` | Table does not appear on RDS |

## Lab lifecycle

These managed databases and agent jobs persist after your terminal closes. There is no container stop/reset operation. Reuse read-only checks `05` and `07`; run setup and mutation scripts only once per fresh lab. Cleanup is manual: remove the lab subscription/publication and its replication configuration before removing lab databases. Remove Azure Files snapshots when no longer needed, and delete dedicated cloud resources when finished to stop their charges. Do not drop an existing shared distributor.
