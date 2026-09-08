#!/bin/sh
# ES 8.14.2 has no *-*.otel-* index templates (those arrive with otel-data in
# 8.16+), so the elasticsearch exporter's data-stream writes fail with
# index_not_found_exception / "Can't find dynamic template". We install our own.
set -eu
ES="${ES_URL:-http://elasticsearch:9200}"
DIR="$(dirname "$0")/templates"

put() { # put <url-path> <file>
  code=$(curl -sS -o /tmp/out -w '%{http_code}' -XPUT "$ES$1" \
    -H 'content-type: application/json' --data-binary "@$2")
  echo "PUT $1 -> $code $(cat /tmp/out)"
  [ "$code" = "200" ]
}

put /_component_template/otel-common@mappings "$DIR/00-component-otel-common.json"
put /_index_template/otel-traces             "$DIR/10-otel-traces.json"
put /_index_template/otel-logs               "$DIR/10-otel-logs.json"
put /_index_template/otel-metrics            "$DIR/10-otel-metrics.json"
echo "templates installed"
