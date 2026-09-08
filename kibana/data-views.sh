#!/bin/sh
# Discover needs a data view per signal. P5 replaces this with exported saved objects.
set -eu
KB="${KIBANA_URL:-http://localhost:5601}"
for signal in traces logs metrics; do
  curl -sS -XPOST "$KB/api/data_views/data_view" \
    -H 'kbn-xsrf: true' -H 'content-type: application/json' \
    -d "{\"data_view\":{\"id\":\"otel-$signal\",\"name\":\"OTel $signal\",\"title\":\"$signal-*.otel-*\",\"timeFieldName\":\"@timestamp\"}}" \
    -o /dev/null -w "$signal data view -> %{http_code}\n"
done
