#!/bin/sh
# Sample a proxy-gateway's connection-level JSON API N times with a delay.
# Works with any core exposing GET /connections with bearer auth.
#
# Usage (credentials via environment, never hardcoded):
#   CONNS_API='http://192.168.1.2:9090/connections' CONNS_SECRET='xxx' \
#   sh conns-api-snapshot.sh > snapshots.txt
#
# Snapshots are separated by a '---SNAP---' marker for conns-parse.ps1.
: "${CONNS_API:?set CONNS_API to the /connections endpoint}"
: "${CONNS_SECRET:?set CONNS_SECRET}"
SNAPS="${SNAPS:-4}"
DELAY="${DELAY:-8}"

i=0
while [ "$i" -lt "$SNAPS" ]; do
    i=$((i + 1))
    curl -s -m 4 -H "Authorization: Bearer $CONNS_SECRET" "$CONNS_API"
    echo '---SNAP---'
    [ "$i" -lt "$SNAPS" ] && sleep "$DELAY"
done
