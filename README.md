# SQL Server replication demo

A local SQL Server 2022 transactional replication lab using Docker Compose. It publishes `dbo.Customers` from `ReplDemo` to `ReplDemo_Sub` through a continuous push subscription.

The project models an Azure SQL Managed Instance publisher/distributor and an AWS RDS SQL Server subscriber using local SQL Server Developer containers. It does not provision or validate either cloud service.

## Topology

| Container | Role | Host connection | Database |
| --- | --- | --- | --- |
| `sql-publisher` | Publisher and distributor | `localhost,14330` | `ReplDemo`, `distribution` |
| `sql-subscriber` | Push subscriber | `localhost,14331` | `ReplDemo_Sub` |

The containers communicate over `repl-net` using their container hostnames and port `1433`. The publication is named `ReplDemoPub`, with `Customers` as its article. The subscriber is not configured as a publisher or distributor.

Compose enables SQL Server Agent and creates `/var/opt/mssql/ReplData` on the publisher for snapshot files.

## Prerequisites

- Docker with Docker Compose support.
- `sqlcmd` installed on the host and available on `PATH`.
- Host ports `14330` and `14331` available.

Run the commands below from this repository. The supplied `sa` passwords are embedded in the Compose file and SQL scripts for this local lab. The `-C` option trusts the server certificate.

## Run the demo

### 1. Start SQL Server

```sh
docker compose up -d
docker compose logs -f
```

Wait until both servers report that they are ready for client connections. Press Ctrl+C to stop following the logs; the containers keep running.

### 2. Configure replication

Run these commands in order:

```sh
sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 01_setup_publisher_distributor.sql
sqlcmd -S localhost,14331 -U sa -P 'P@ssw0rd_Sub1' -C -i 02_setup_subscriber_db.sql
sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 03_create_subscription.sql
```

The first script creates the distributor, publication, and `Customers` table, seeded with Alice and Bao. The second creates the destination database. The third creates the push subscription and starts the initial snapshot.

Allow a minute or two for the snapshot to initialize the subscriber before continuing. Replication is asynchronous, so a completed setup command does not mean the data has arrived yet.

### 3. Check live replication

```sh
sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 04_validate_on_publisher.sql
```

This script checks the subscription, posts a tracer token, attempts to read latency information, and inserts Chloe as customer `3`.

The tracer check currently calls `sp_helptracertokenhistory` without passing the token ID captured earlier. It also queries immediately despite its comment suggesting a 10–30 second wait. If that check reports an error or incomplete latency data, inspect it separately; it is not proof that row replication failed. The commands here preserve the workflow in [step.md](step.md).

After a few seconds, query the subscriber:

```sh
sqlcmd -S localhost,14331 -U sa -P 'P@ssw0rd_Sub1' -C -i 05_check_subscriber.sql
```

Expected result: customers `1`, `2`, and `3` appear. If Chloe has not arrived, wait and rerun only the subscriber check. Rerunning script `04` attempts to insert the same primary key again.

### 4. Test replication edge cases

```sh
sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 06_test_edge_cases_on_publisher.sql
```

The script attempts to truncate the published table, adds a `Phone` column and updates Alice's phone number, then creates an unpublished `Orders` table.

An error for the `TRUNCATE` attempt is an expected test outcome. Keep the command as shown, without `-b`, so that this deliberate error does not stop the later batches.

Wait a few seconds, then run:

```sh
sqlcmd -S localhost,14331 -U sa -P 'P@ssw0rd_Sub1' -C -i 07_check_subscriber_after_tests.sql
```

The scripts are designed to check these outcomes:

| Test | Expected observation |
| --- | --- |
| Truncate a published table | The publisher rejects the operation and the customer rows remain. |
| Add and update `Phone` | The subscriber gains the column; customer `1` has `555-0100`. |
| Create unpublished `Orders` | The table does not appear on the subscriber. |

## Script reference

| Script | Run on | Purpose |
| --- | --- | --- |
| [01_setup_publisher_distributor.sql](01_setup_publisher_distributor.sql) | Publisher | Configure distribution, seed data, and publish `Customers`. |
| [02_setup_subscriber_db.sql](02_setup_subscriber_db.sql) | Subscriber | Create `ReplDemo_Sub`. |
| [03_create_subscription.sql](03_create_subscription.sql) | Publisher | Create the push subscription and start the snapshot. |
| [04_validate_on_publisher.sql](04_validate_on_publisher.sql) | Publisher | Inspect the subscription, attempt a latency check, and insert customer `3`. |
| [05_check_subscriber.sql](05_check_subscriber.sql) | Subscriber | Read replicated customers. |
| [06_test_edge_cases_on_publisher.sql](06_test_edge_cases_on_publisher.sql) | Publisher | Test truncation, schema replication, and an unpublished table. |
| [07_check_subscriber_after_tests.sql](07_check_subscriber_after_tests.sql) | Subscriber | Inspect edge-case results. |

## Stop or reset

To stop the lab while retaining the existing containers:

```sh
docker compose stop
```

Resume with `docker compose start`.

The setup and mutation scripts are intended for a fresh lab and are not safe to rerun unchanged against an initialized database. To remove the containers and network:

```sh
docker compose down
```

The Compose file defines no persistent data volumes. Removing the containers discards the lab databases and replication configuration. To start fresh, run `docker compose up -d` and repeat the setup sequence.
