#!/bin/bash
# The mcr.microsoft.com/mssql/server image does not read
# /docker-entrypoint-initdb.d. Boot sqlservr, apply the mounted seed
# scripts via sqlcmd, then keep serving in the foreground.
set -u

/opt/mssql/bin/sqlservr &
SQLSERVR_PID=$!

# sqlcmd (tools18) needs -C to trust the container's self-signed cert
for _ in $(seq 1 120); do
  if /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" -C -b >/dev/null 2>&1; then
    echo "mssql-init: server is ready"
    break
  fi
  sleep 2
done

shopt -s nullglob
for f in /docker-entrypoint-initdb.d/*.sql; do
  echo "mssql-init: applying $(basename "$f")"
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -i "$f" \
    || echo "mssql-init: WARN seed failed: $f"
done

wait "$SQLSERVR_PID"
