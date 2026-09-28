#!/usr/bin/env bash
# VM 2: start the push subscriber for a fresh two-VM lab.
set -euo pipefail

# Do not remove an existing container: this demo has no persistent data volume.
docker run --rm -d \
  --name sql-subscriber \
  --hostname sql-subscriber \
  --network host \
  -e ACCEPT_EULA=Y \
  -e MSSQL_SA_PASSWORD='P@ssw0rd_Sub1' \
  -e MSSQL_PID=Developer \
  -e MSSQL_AGENT_ENABLED=true \
  mcr.microsoft.com/mssql/server:2022-latest
