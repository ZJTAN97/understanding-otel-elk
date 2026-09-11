# Phase 12 — Scraping the infrastructure

**Goal:** pull-based metrics and parsed logs from RabbitMQ, MongoDB and MinIO — and
cardinality discipline.

**Prerequisites:** Phase 11.

**Artifacts produced:** `otel/collector.yaml` grows substantially.

---

## Why this comes after the traces, not before

By now you have seen these systems from the *client* side. You know what a slow Mongo query
looks like in a trace and what a RabbitMQ publish costs.

That means when you see `rabbitmq_queue_messages_ready` climbing, you already understand
what it implies for the consumer spans you have been reading. Metrics-first would have
given you numbers with no meaning attached.

## Concepts

**The asymmetry that defines the Collector's job:**

```
applications  --PUSH-->  Collector  --> Elasticsearch
infrastructure <--PULL--  Collector
```

Applications push OTLP. Infrastructure is scraped. The Collector's entire purpose is to hide
that difference from the backend, so both arrive as uniform telemetry.

**Metric temporality.** Cumulative counters only ever increase and the backend computes
rates. Delta counters report the change since last report. Prometheus is cumulative; some
OTLP sources are delta. Mixing them without conversion produces charts that look plausible
and are wrong — which is worse than charts that look broken.

**Scrape interval, staleness, cardinality.** A 15-second interval on 500 series is 
2,880 data points per minute. Multiply by label combinations. This is how observability
platforms die.

**The processors that make infrastructure data usable:**

| Processor | Job |
|---|---|
| `resourcedetection` | Adds host, OS, cloud attributes automatically |
| `resource` | Sets or removes resource attributes |
| `attributes` | Modifies data point / span attributes |
| `transform` | OTTL — the general-purpose tool. Rename, drop, compute, conditionally edit |
| `filter` | Drop entire metrics or spans by rule |

`transform` with OTTL is the one to learn properly. It is the escape hatch for everything
the other processors cannot express.

**Log parsing is where quality is won or lost.** A log line that arrives as an unparsed
blob in a `body` field is nearly useless: you cannot filter by severity, aggregate by error
type, or correlate by trace ID. `filelog` operators (`regex_parser`, `json_parser`,
`severity_parser`, `time_parser`, `recombine`) turn text into structure.

Multiline handling deserves specific attention. A Java stack trace is one logical event
across forty physical lines. Without `recombine`, it becomes forty separate log records,
thirty-nine of which are meaningless, and your error rate metric is wrong by 40x.

## Steps

### 1. RabbitMQ, two ways — and diff them

Configure **both**:

- `prometheus` receiver scraping `:15692/metrics`
- `rabbitmq` receiver against the management API

Then compare the metric sets. They overlap but are not identical. The Prometheus plugin
exposes far more; the native receiver produces cleaner OTel semantic conventions.

Doing both once and diffing them teaches you more about how metric collection works than
either alone, and it is a decision you will have to make again for every component in
production.

### 2. MongoDB, with least privilege

The `mongodb` receiver needs a user. Create one with **only** `clusterMonitor`. Not root.

Monitoring credentials are credentials. They live in your Collector config, which lives in
git, which is read by more people than your database. Least privilege here is not
box-ticking — it is the difference between a leaked config being embarrassing and being an
incident.

### 3. MinIO, properly this time

You set `MINIO_PROMETHEUS_AUTH_TYPE=public` in Phase 11 to keep things moving. Now redo it
with a real bearer token, because production will require one and you need to know how the
`prometheus` receiver handles auth.

### 4. Logs via `filelog`

Two targets with different shapes:

- **Container stdout** — Docker JSON log files. Parse the JSON envelope, then the message
- **`mongod.log`** — already JSON, but with its own schema and timestamp format

For each: parse, map severity onto OTel severity numbers, parse the timestamp so events are
ordered by when they *happened* rather than when they were *read*, and handle multiline.

Route them to distinct data streams via `data_stream.dataset` so they get separate ILM
policies later.

## Deliberate exercise

**Add a high-cardinality attribute on purpose.** Put a request ID, or a full URL with query
parameters, onto a metric.

Then watch:

```
GET _cat/indices/metrics-*?v
GET metrics-*/_mapping
GET metrics-*/_field_caps?fields=*
```

Watch index size grow and the field count climb. Note how quickly it becomes alarming.

Then remove it with a `transform` statement and confirm the growth stops.

**Cardinality is the failure mode that kills real observability platforms.** Not disk, not
CPU — unbounded label values. Having caused it once, deliberately, in a lab, you will
recognise the early signs in production. This exercise is the most operationally valuable
thing in Part 2.

## Done when

- RabbitMQ, MongoDB and MinIO metrics are all arriving
- You have diffed the two RabbitMQ collection methods and chosen one, with reasons
- Container logs and `mongod.log` are parsed, with severity, timestamps and multiline handled
- Monitoring credentials are least-privilege
- You have caused and then fixed a cardinality explosion
- You can correlate a trace latency spike with a queue-depth metric at the same timestamp

## Notes

- 

## Next

[Phase 13 — Kibana and operational reality](13-kibana-observability.md)
