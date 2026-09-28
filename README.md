# SQL Server replication demo

A local SQL Server 2022 transactional replication lab using Docker Compose. It publishes `dbo.Customers` from `ReplDemo` to `ReplDemo_Sub` through a continuous push subscription.

The project models an Azure SQL Managed Instance publisher/distributor and an AWS RDS SQL Server subscriber using local SQL Server Developer containers. It does not provision or validate either cloud service.

For containers on separate cloud VMs, follow [Two-VM deployment](#two-vm-deployment). The commands in the initial sections below run the original single-host demo.

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

The tracer check currently calls `sp_helptracertokenhistory` without passing the token ID captured earlier. It also queries immediately despite its comment suggesting a 10–30 second wait. If that check reports an error or incomplete latency data, inspect it separately; it is not proof that row replication failed.

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

## Two-VM deployment

This scenario runs the same push replication lab across two reachable Linux VMs. Check out branch `scenario/two-vm-replication` on both VMs. Install Docker with Compose and host `sqlcmd` on each VM, and run the commands from this repository.

| VM | Compose file | Role | Host SQL port |
| --- | --- | --- | --- |
| VM 1 | `docker-compose.publisher.yaml` | Publisher + distributor | `1433` |
| VM 2 | `docker-compose.subscriber.yaml` | Push subscriber | `1433` |

Both Compose files use `network_mode: host` on Linux: SQL Server shares its VM’s network stack and listens directly on TCP `1433`. Port mappings are omitted because [Docker host networking](https://docs.docker.com/engine/network/drivers/host/) does not use them. TCP `1433` must be free on each VM. The publisher resolves `sql-subscriber` to the subscriber VM's reachable IP using `extra_hosts`; the existing SQL scripts retain the subscriber identity `sql-subscriber`. Snapshot files stay on the publisher, where the push agents run. No shared filesystem or cross-host Docker network is needed.

Use fresh containers for this scenario. Run only the appropriate Compose file on each VM; the original demo uses the same container names. These files retain the embedded lab passwords and disposable storage. With host networking, SQL Server listens on the VM network interfaces; restrict access with the host and cloud firewalls. Restrict subscriber TCP `1433` in the cloud and host firewall to the publisher VM's source address (as seen by the subscriber). Run administrative commands locally on each VM; they do not require allowing inbound publisher TCP `1433` across clouds.

The publisher also maps `sql-publisher` and `SQL-PUBLISHER` to `127.0.0.1` inside its container. Replication agents use these names to connect to the local publisher/distributor. Setting `hostname` alone did not provide working resolution in the tested host-network deployment; without these mappings, all three agents failed to connect and the subscriber's `dbo.Customers` table was never created.

If you already ran the bridge-network version, changing network mode recreates the containers and discards this lab’s unpersisted data. For a disposable lab, reset both VMs using step 5, pull this branch on both VMs, and repeat setup. Back up first if you need the existing data.

### 1. Start each VM's service

On **VM 2 (subscriber)**:

```sh
docker compose -f docker-compose.subscriber.yaml up -d
docker compose -f docker-compose.subscriber.yaml logs -f
```

On **VM 1 (publisher)**, replace the example IP with the subscriber VM address reachable from the publisher container:

```sh
export SUBSCRIBER_VM_IP='10.20.0.2'
docker compose -f docker-compose.publisher.yaml up -d
docker compose -f docker-compose.publisher.yaml logs -f
```

Wait for each server to report that it is ready for client connections, then press Ctrl+C to stop following logs. Keep `SUBSCRIBER_VM_IP` exported for every publisher Compose command; export it again in a new shell. An unset or empty value causes Compose to fail with a configuration error.

#### Publisher without Compose

For a fresh publisher container, use the equivalent [run-publisher.sh](run-publisher.sh) script instead of the publisher Compose startup command:

```sh
export SUBSCRIBER_VM_IP='10.20.0.2'
bash ./run-publisher.sh
docker logs -f sql-publisher
```

It includes host networking, both publisher loopback aliases, the remote subscriber mapping, SQL Agent, and snapshot-directory initialization. It refuses an unset/empty subscriber IP and does not remove an existing container. Manage a script-created container with `docker stop sql-publisher` and `docker start sql-publisher`; `docker rm sql-publisher` after stopping it discards its data. Do not use Compose to manage a container created by this script.

### 2. Verify publisher and subscriber connections

On **VM 1**, first verify the agent's local publisher/distributor connections. These checks work with either startup method:

```sh
docker exec sql-publisher bash -c '
set -e
for server in tcp:127.0.0.1,1433 tcp:sql-publisher,1433 tcp:SQL-PUBLISHER,1433; do
  echo "Testing $server"
  /opt/mssql-tools18/bin/sqlcmd \
    -S "$server" -U sa -P "P@ssw0rd_Pub1" -C -b -l 5 \
    -Q "SELECT @@SERVERNAME AS PublisherServerName;"
done
'
```

All three must return `sql-publisher`. If loopback succeeds but the hostname connections fail, follow the hostname troubleshooting steps below before running setup.

On **VM 1**, connect from inside the publisher container, using the same hostname and port the replication agent will use:

```sh
docker exec sql-publisher \
  /opt/mssql-tools18/bin/sqlcmd -S sql-subscriber,1433 \
  -U sa -P 'P@ssw0rd_Sub1' -C -b \
  -Q 'SELECT @@SERVERNAME AS SubscriberServerName;'
```

Expect `sql-subscriber`. If the connection fails, check the configured VM IP, subscriber readiness, TCP `1433` availability, and firewall rules before configuring replication. Host-to-host reachability alone does not verify the container's connection. If the returned server name differs, correct the subscriber deployment before proceeding.

### 3. Configure replication in order

Use the commands below with port `1433` on both VMs; SQL file comments still show the original single-host demo ports.

First, on **VM 1**:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Pub1' -C -b -i 01_setup_publisher_distributor.sql
```

Then, on **VM 2** (use port `1433`, overriding the local-demo port shown in SQL file comments):

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Sub1' -C -b -i 02_setup_subscriber_db.sql
```

Finally, on **VM 1**:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Pub1' -C -b -i 03_create_subscription.sql
```

Allow a minute or two for initialization. On **VM 2**, verify customers `1` and `2` arrive:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Sub1' -C -b -i 05_check_subscriber.sql
```

Customer `3` is added in the next step. If the table or initial rows have not arrived yet, wait and rerun this read-only check; do not rerun the setup scripts against the initialized lab.

#### Troubleshooting a missing subscriber table

A successful job-start message only confirms that the agent launched. If script `03` says the snapshot job is already running, let the existing run continue instead of rerunning setup. If script `05` keeps reporting `Invalid object name 'dbo.Customers'`, inspect agent history on **VM 1**:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Pub1' -C -y 0 -Q "
SELECT TOP (15)
    j.name AS job_name, h.step_id, h.run_status,
    h.run_date, h.run_time, h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name LIKE '%ReplDemo%'
ORDER BY h.instance_id DESC;

SELECT TOP (10) [time], error_code, error_text
FROM distribution.dbo.MSrepl_errors
ORDER BY [time] DESC, id DESC;
"
```

For `could not connect to Distributor 'sql-publisher'` or publisher connection timeouts, run the three local connection checks above. If loopback succeeds but hostname connections fail, inspect resolution:

```sh
docker exec sql-publisher getent hosts sql-publisher SQL-PUBLISHER
```

For an existing host-network container missing the publisher mapping, apply this temporary repair without recreating it:

```sh
docker exec -u root sql-publisher sh -c \
  'printf "\n127.0.0.1 sql-publisher SQL-PUBLISHER\n" >> /etc/hosts'
```

Repeat the local connection checks, let retrying agents reconnect, and rerun script `05` on VM 2. If the table remains missing, inspect the latest history again. Do not manually create the subscriber table or rerun scripts `01`–`03` against the initialized lab.

The live `/etc/hosts` repair is temporary. The updated publisher Compose file and `run-publisher.sh` include the aliases for future container creation. Applying a changed Compose configuration can recreate the container and discard this lab's unpersisted data; keep the working container and back up needed data before recreation.

### 4. Validate live changes and edge cases

On **VM 1**, run the live-change script once:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Pub1' -C -i 04_validate_on_publisher.sql
```

The existing tracer-token limitation described in [Check live replication](#3-check-live-replication) still applies; leave `-b` off this command so later batches can insert Chloe. After a few seconds, on **VM 2**:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Sub1' -C -b -i 05_check_subscriber.sql
```

Expect customers `1`, `2`, and `3`. Next, on **VM 1**:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Pub1' -C -i 06_test_edge_cases_on_publisher.sql
```

The truncation error is expected; leave `-b` off so the remaining batches run. After a few seconds, on **VM 2**:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Sub1' -C -b -i 07_check_subscriber_after_tests.sql
```

Expect the customer rows to remain, Alice's replicated `Phone` to be `555-0100`, and no subscriber `Orders` table.

### 5. Stop, resume, or reset

On **VM 1**:

```sh
docker compose -f docker-compose.publisher.yaml stop
docker compose -f docker-compose.publisher.yaml start
```

On **VM 2**:

```sh
docker compose -f docker-compose.subscriber.yaml stop
docker compose -f docker-compose.subscriber.yaml start
```

To reset the entire lab, remove both containers on their respective VMs:

```sh
# VM 1 (publisher)
docker compose -f docker-compose.publisher.yaml down
```

```sh
# VM 2 (subscriber)
docker compose -f docker-compose.subscriber.yaml down
```

There are no persistent volumes: `down` discards databases, replication configuration, and publisher snapshots. To start fresh, repeat the startup and setup steps on both VMs.
