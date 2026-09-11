# Notes per phase

## P0 — pipeline skeleton, no apps

Built: `docker-compose.yml` (Elasticsearch 8.14.2, Kibana 8.14.2, Collector
0.145.0, plus a one-shot `es-init`), `otel/collector.yaml`, index templates in
`elasticsearch/templates/`.

Verified: `telemetrygen` traces, metrics and logs over both OTLP/gRPC `:4317`
and OTLP/HTTP `:4318` land in `traces|metrics|logs-generic.otel-default` with
zero index failures; attributes are aggregatable; time-range queries work.

### The 8.14.2 finding: you own the index templates

`mapping.mode: otel` writes into data streams and expects the OTel index
templates that ship with Elasticsearch **8.16+** (the `otel-data` plugin). On
8.14.2 they do not exist, and the failures are two-stage:

1. `index_not_found_exception` for `traces-generic.otel-default` — no template
   matches `traces-*`, so the data stream is never auto-created. (`logs-*-*` and
   `metrics-*-*` *do* have built-in templates, so those two data streams appear
   and only the traces one fails — a misleading partial success.)
2. Once a traces template exists, metrics fail with
   `document_parsing_exception: Can't find dynamic template for dynamic template
   name [gauge_long] of field [metrics.gen]`. The exporter puts
   `dynamic_templates` in each bulk action, referring to templates **by name**
   (`counter_long`, `gauge_long`, `counter_double`, `gauge_double`, `histogram`,
   `summary_metrics`). If the index template does not define those names, every
   metric document is rejected.

`elasticsearch/templates/` therefore defines what 8.16 would have shipped:

- `otel-common@mappings` — `@timestamp` as `date_nanos`, `subobjects: false` on
  `attributes` / `resource.attributes` / `scope.attributes`, and a
  `strings_as_keyword` dynamic template.
- one index template per signal, `priority: 200` so it beats the built-in
  `logs` / `metrics` templates (priority 100).

Two deliberate simplifications versus the real 8.16 templates:

- **No TSDB.** The shipped metrics template uses `index.mode: time_series` with
  `time_series_metric` / `time_series_dimension` field parameters. Here counters
  and gauges are plain `long` / `double`. Metrics are queryable but not
  dimension-deduplicated, and `_metric_names_hash` is just a keyword.
- `strings_as_keyword` was added after seeing dynamic mapping turn every
  attribute into `text` + `.keyword` — which made
  `terms` on `resource.attributes.service.name` fail outright. OTel attributes
  are dimensions; they should be `keyword`.

Mapping changes only affect **new** backing indices, so re-running `es-init`
after a template edit needs
`curl -XDELETE localhost:9200/_data_stream/'*-generic.otel-default'` (or a
rollover) before it shows up.

### Document shape actually observed

Span:

```json
{ "@timestamp": "1788871670597.180793",
  "data_stream": { "type": "traces", "dataset": "generic.otel", "namespace": "default" },
  "trace_id": "...", "span_id": "...", "parent_span_id": "...",
  "name": "okey-dokey-0", "kind": "Server", "duration": 123000,
  "attributes": { "network.peer.address": "1.2.3.4" },
  "links": [], "status": {},
  "resource": { "schema_url": "...", "attributes": { "service.name": "p0-smoke" } },
  "scope": { "name": "telemetrygen" } }
```

Points worth noticing:

- `@timestamp` arrives as epoch millis **with a fractional part** — a string.
  `date_nanos` parses it via `epoch_millis` and sorts on full nanosecond
  precision (`sort` key `1788871670597180793`). Mapping it as `date` would
  silently cost precision.
- `duration` is nanoseconds, not milliseconds.
- `kind` and `status.code` are the OTel enums, spelled out (`Server`), not the
  APM-Server-shaped `span.type` / `transaction.*` fields — which is exactly why
  some Kibana APM views will stay empty on this stack. Discover is the source of
  truth for P0.
- Log bodies land under `body.text`; a structured body would go to
  `body.structured.*`.

### Break-it-on-purpose result

Exporter pointed at `elasticsearch:9201`:

```
error internal/queue_sender.go:50  Exporting failed. Dropping data.
  {"otelcol.component.id": "elasticsearch", "otelcol.signal": "traces",
   "error": "failed to execute the request: dial tcp 172.19.0.2:9201: connect: connection refused",
   "dropped_items": 4}
```

and `otelcol_exporter_send_failed_spans_total{exporter="elasticsearch"} 4`,
while `otelcol_exporter_queue_size{data_type="traces"}` returns to 0 — the
retries are exhausted and the batch is *dropped*, not held. The distinction to
remember: `send_failed_*` climbing with `queue_size` at 0 means data loss
already happened; `queue_size` climbing means back-pressure but data still in
flight. With `sending_queue.enabled` in-memory (the default), a Collector
restart loses the queue too.

Also worth internalising: the `debug` exporter still printed every dropped
record. Records reaching the debug exporter proves the receiver and processors
work — it says nothing about whether Elasticsearch accepted anything.

### Batching latency

`batch.timeout: 5s` plus the ES refresh interval means a document can take
~10 seconds to appear in a search. Two of the "nothing arrived" moments during
P0 were just impatience; `_refresh` settles it.
