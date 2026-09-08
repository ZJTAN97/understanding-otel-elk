# Elastic Observability with OpenTelemetry

Learning repo. Plan and phases: [PLAN.md](PLAN.md). Per-phase findings:
[docs/notes-per-phase.md](docs/notes-per-phase.md).

Current phase: **P0 — pipeline skeleton, no apps.**

## P0: run it

Requires Docker Desktop with at least 4 GiB allocated.

```sh
docker compose up -d          # elasticsearch -> es-init (templates) -> kibana + collector
./kibana/data-views.sh        # one-off: Discover data views for traces/logs/metrics
```

- Elasticsearch: http://localhost:9200
- Kibana: http://localhost:5601
- Collector OTLP: `localhost:4317` (gRPC), `localhost:4318` (HTTP)
- Collector self-telemetry: http://localhost:8888/metrics

Everything is pinned in [`.env`](.env).

### Push synthetic telemetry

```sh
TG=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest
NET=understanding-otel-elk_default

docker run --rm --network $NET $TG traces  --otlp-endpoint otel-collector:4317 --otlp-insecure --traces 5  --service p0-smoke
docker run --rm --network $NET $TG metrics --otlp-endpoint otel-collector:4317 --otlp-insecure --metrics 5 --service p0-smoke
docker run --rm --network $NET $TG logs    --otlp-endpoint otel-collector:4317 --otlp-insecure --logs 5    --service p0-smoke

# same thing over OTLP/HTTP
docker run --rm --network $NET $TG traces --otlp-endpoint otel-collector:4318 --otlp-http --otlp-insecure --traces 5 --service p0-http
```

### What to look at

```sh
docker logs -f otel-collector                                   # debug exporter: every record, as the pipeline sees it
curl -s localhost:9200/_cat/indices/'.ds-*otel*?v&h=index,docs.count'
curl -s localhost:9200/traces-'*'.otel-'*'/_search?size=1 | jq .  # one raw OTel-mapped span document
curl -s localhost:8888/metrics | grep otelcol_exporter            # queue depth, sent, send_failed
```

In Kibana → Discover, pick the **OTel traces** data view. Documents land in data
streams named `<signal>-<data_stream.dataset>-<data_stream.namespace>`, so
`traces-generic.otel-default` by default; setting `data_stream.dataset` /
`data_stream.namespace` on the telemetry redirects them.

### Break it on purpose

Point the exporter at a port nothing listens on and watch it fail:

```sh
sed -i '' 's|elasticsearch:9200|elasticsearch:9201|' otel/collector.yaml
docker compose restart otel-collector
# push traces, then:
docker logs otel-collector | grep "Exporting failed"
curl -s localhost:8888/metrics | grep send_failed_spans
sed -i '' 's|elasticsearch:9201|elasticsearch:9200|' otel/collector.yaml
docker compose restart otel-collector
```

Observed signature is recorded in [docs/notes-per-phase.md](docs/notes-per-phase.md).

### Reset

```sh
docker compose down -v        # -v also drops the Elasticsearch volume
```
