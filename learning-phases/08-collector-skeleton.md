# Phase 08 — Collector skeleton

**Goal:** synthetic telemetry flowing from a Collector into the ECK cluster from Part 1,
and the ability to name every field in the resulting document.

**Prerequisites:** Phase 07. Elasticsearch and Kibana running in k3d.

**Artifacts produced:** `docker-compose.yml`, `otel/collector.yaml`, `.env`.

---

## Setup shape (D6)

```
   Docker Compose                      k3d cluster (Part 1)
   +-------------------+               +----------------------+
   | otel-collector    | --- OTLP ---> |                      |
   | sample apps       |               |  Elasticsearch (ECK) |
   +-------------------+   exporter -> |  Kibana              |
                                       +----------------------+
```

Collector and apps in Compose for a fast edit-restart loop; Elasticsearch stays in
Kubernetes because you are never going to operate an Elasticsearch that is not in
Kubernetes.

**The connection detail that will cost you twenty minutes if you skip it:** the Collector
runs in a Docker container and must reach Elasticsearch inside k3d. Port-forward
`obs-es-http` to the host, then have the Collector target `host.docker.internal:9200`.
And because ECK enables TLS with a self-signed CA, you must give the exporter the CA
certificate you extracted in Phase 03 — mount it into the container and point
`tls.ca_file` at it. This is not optional and not a lab-only wart: production will have the
same requirement, just with in-cluster DNS instead of a port-forward.

## Concepts

**A pipeline is per-signal.** You declare `traces`, `metrics` and `logs` pipelines
separately, each with its own receivers, processors and exporters. They share component
*definitions* but not *instances* of flow.

```
receivers -> processors -> exporters
```

**OTLP has two transports.** gRPC on `:4317`, HTTP on `:4318`. gRPC is more efficient and
the default for the Java agent. HTTP is easier to debug (you can curl it) and survives
proxies that mangle gRPC. Know which you are using.

**The `debug` exporter is the most important component you will configure.** It prints
telemetry to the Collector log. It answers "did the Collector receive anything at all",
which cleanly separates generation problems from export problems. Configure it now and
never remove it.

**Data streams and where documents land.** The `elasticsearch` exporter routes to data
streams named `<type>-<dataset>-<namespace>`:

- `traces-generic-default`
- `logs-generic-default`
- `metrics-generic-default`

The `data_stream.dataset` and `data_stream.namespace` attributes override the middle and
last parts. This is how you separate application logs from infrastructure logs into
different data streams — and therefore different ILM policies and different retention.

**`mapping.mode: otel`** makes the exporter write OTel-native document shapes rather than
ECS. This is what D4 chose. It requires ES >= 8.12 and is solid from 8.16 — your 8.19.21
is comfortably clear.

## Steps

### 1. Pin versions in `.env`

Collector `otel/opentelemetry-collector-contrib` at a specific tag. Never `latest`. The
Collector moves fast and configuration syntax does change between versions.

### 2. Minimal collector config

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch: {}

exporters:
  debug:
    verbosity: detailed
  elasticsearch:
    endpoints: ["https://host.docker.internal:9200"]
    user: elastic
    password: ${ES_PASSWORD}
    mapping:
      mode: otel
    tls:
      ca_file: /etc/otel/certs/es-ca.crt

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, elasticsearch]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, elasticsearch]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug, elasticsearch]
```

Verify exporter option names against the Collector version you pinned — this area has
changed shape across releases.

### 3. Turn on the Collector self-telemetry

The Collector emits its own metrics. Configure them and send them to Elasticsearch. You now
have a Collector monitoring itself, and — critically — visibility into queue depth, retries
and dropped spans. When data goes missing later, these are the metrics that tell you
whether the Collector dropped it or never received it.

### 4. Push synthetic data

Use `telemetrygen`:

```
telemetrygen traces --otlp-insecure --otlp-endpoint localhost:4317 --traces 10
telemetrygen metrics --otlp-insecure --otlp-endpoint localhost:4317
telemetrygen logs --otlp-insecure --otlp-endpoint localhost:4317
```

Watch the `debug` exporter output first, then look in Elasticsearch.

### 5. Find and read the documents

```
GET _cat/indices/*generic*?v
GET traces-generic-default/_search
```

Then open Discover in Kibana and create a data view.

**Now do the actual work of this phase:** take one span document and go through it field by
field. `trace_id`, `span_id`, `parent_span_id`, `name`, `kind`, `duration`, the `resource`
block, the `attributes` block, `scope`. Understand what each one is and where it came from.

Everything in Parts 2 and 3 is variations on this document. An hour spent here saves days
later.

## Deliberate exercise

**Break the exporter on purpose.** Point it at the wrong port, restart, and push data.

Read the errors: connection refused, retries backing off, the sending queue filling. Then
check the self-telemetry and find the metric showing dropped data.

Now you can recognise this failure in production, where the symptom is "data is missing in
Kibana" and the cause is three layers away.

Restore the config and confirm recovery. Note whether the queued data was delivered or
lost — that tells you what the Collector's durability guarantees really are.

## Done when

- `telemetrygen` traces, metrics and logs all appear in Discover
- You can name every field in a span document
- The Collector exports its own self-telemetry
- You have broken the exporter, recognised the errors, and recovered
- You can explain how `data_stream.dataset` changes where a document lands

## Notes

- 

## Next

[Phase 09 — First app, three signals](09-first-app-three-signals.md)
