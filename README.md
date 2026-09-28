# SQL Server replication across two VMs

A SQL Server 2022 transactional replication lab that publishes `dbo.Customers` from `ReplDemo` to `ReplDemo_Sub` through a continuous push subscription.

This branch runs Docker containers on two Linux VMs. It models an Azure SQL Managed Instance publisher/distributor and an AWS RDS SQL Server subscriber; it does not provision either managed service. The single-machine demo is on [main](https://github.com/chavisr/mssql-repl-demo/tree/main).

## Topology

| VM | Container | Role | Databases | SQL port |
| --- | --- | --- | --- | --- |
| VM 1 | `sql-publisher` | Publisher + distributor | `ReplDemo`, `distribution` | `1433` |
| VM 2 | `sql-subscriber` | Push subscriber | `ReplDemo_Sub` | `1433` |

Both containers use host networking. The publisher maps its own server names to `127.0.0.1` and `sql-subscriber` to the subscriber VM's reachable IP. SQL Agent and snapshot-directory initialization are configured automatically. Snapshot files remain on the publisher; no shared filesystem is required.

## Prerequisites

- Two Linux VMs with Docker and Bash, each with TCP port `1433` available.
- Publisher-to-subscriber connectivity on TCP `1433`, allowed through the host and cloud firewalls.
- Host `sqlcmd` installed on both VMs.
- Branch `scenario/two-vm-replication` checked out on both VMs.

Run commands from this repository on the indicated VM. The supplied `sa` passwords are embedded lab credentials; `-C` trusts the server certificate. Restrict database access to the required hosts. Start with fresh containers; setup scripts are intended to run once per lab.

## Run the demo

### 1. Start each VM's container

On **VM 2 (subscriber)**, run [run-subscriber.sh](run-subscriber.sh):

```sh
bash ./run-subscriber.sh
docker logs -f sql-subscriber
```

On **VM 1 (publisher)**, replace the example IP with the subscriber VM's reachable IP and run [run-publisher.sh](run-publisher.sh):

```sh
export SUBSCRIBER_VM_IP='10.20.0.2'
bash ./run-publisher.sh
docker logs -f sql-publisher
```

Wait for each server to report that it is ready for client connections, then press Ctrl+C to stop following logs. Both scripts use `docker run --rm` with host networking. Containers are automatically removed when they exit. The publisher requires a nonempty `SUBSCRIBER_VM_IP` at container creation. The scripts leave existing containers untouched. Stopping these containers discards their unpersisted lab data.

### 2. Verify publisher and subscriber connections

On **VM 1**, verify the publisher and remote subscriber connections:

```sh
docker exec sql-publisher \
  /opt/mssql-tools18/bin/sqlcmd -S sql-publisher,1433 \
  -U sa -P 'P@ssw0rd_Pub1' -C -b \
  -Q 'SELECT @@SERVERNAME AS PublisherServerName;'

docker exec sql-publisher \
  /opt/mssql-tools18/bin/sqlcmd -S sql-subscriber,1433 \
  -U sa -P 'P@ssw0rd_Sub1' -C -b \
  -Q 'SELECT @@SERVERNAME AS SubscriberServerName;'
```

Expect `sql-publisher` and `sql-subscriber`, respectively.

### 3. Configure replication in order

Run the setup commands once, in the order below. Both VMs use port `1433`.

First, on **VM 1**:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Pub1' -C -b -i 01_setup_publisher_distributor.sql
```

Then, on **VM 2**:

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

Expect Alice and Bao (customers `1` and `2`). Customer `3` is added in the next step. Wait for these initial rows before continuing.

### 4. Validate live changes and edge cases

On **VM 1**, run the live-change script once:

```sh
sqlcmd -S localhost,1433 -U sa -P 'P@ssw0rd_Pub1' -C -i 04_validate_on_publisher.sql
```

Run script `04` without `-b` so its existing tracer-token check does not prevent the later insert of Chloe. After a few seconds, on **VM 2**:

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

### 5. Stop and reset

On **VM 1**:

```sh
docker stop sql-publisher
```

On **VM 2**:

```sh
docker stop sql-subscriber
```

With `--rm`, stopping a container automatically removes it. There are no persistent volumes, so its databases, replication configuration, and publisher snapshots are discarded. To run the lab again, repeat the startup and setup steps on both VMs.

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
