#!/usr/bin/env bash
# Alternative to docker-compose.publisher.yaml for a fresh two-VM lab.
set -euo pipefail

: "${SUBSCRIBER_VM_IP:?Set SUBSCRIBER_VM_IP to the reachable subscriber VM IP address}"

# Do not remove an existing container: this demo has no persistent data volume.
docker run -d \
  --name sql-publisher \
  --hostname sql-publisher \
  --network host \
  --add-host sql-publisher:127.0.0.1 \
  --add-host SQL-PUBLISHER:127.0.0.1 \
  --add-host "sql-subscriber:${SUBSCRIBER_VM_IP}" \
  --user root \
  -e ACCEPT_EULA=Y \
  -e MSSQL_SA_PASSWORD='P@ssw0rd_Pub1' \
  -e MSSQL_PID=Developer \
  -e MSSQL_AGENT_ENABLED=true \
  mcr.microsoft.com/mssql/server:2022-latest \
  bash -c '
    mkdir -p /var/opt/mssql/ReplData &&
    chown -R mssql:mssql /var/opt/mssql/ReplData &&
    exec su mssql -c "/opt/mssql/bin/sqlservr"
  '
