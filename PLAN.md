# Elastic Observability with OpenTelemetry — Learning Plan

> Status: **P0 built and verified** (see README.md and docs/notes-per-phase.md). P1 next.
> Goal: understand the inner workings of OTel → Elastic for Spring Boot apps and for
> RabbitMQ / MongoDB / MinIO, first on Docker Compose, then on Kubernetes via k3d.

---

## 0. Decisions already made

| Decision     | Choice                                                                                                 | Why                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Ingest path  | **Collector → `elasticsearch` exporter → Elasticsearch**                                               | Fewest moving parts; every document is inspectable in Discover. No APM Server.                              |
| Distribution | **Vanilla upstream** (`otel/opentelemetry-collector-contrib` + upstream `opentelemetry-javaagent.jar`) | You configure every knob yourself; knowledge transfers to any backend. EDOT comes later as a diff exercise. |
| Sample apps  | **Two minimal apps, Spring Boot 3.5**                                                                  | Purpose-built to fire exactly the instrumentation modules we want to study.                                 |
| Mapping mode | `mapping.mode: otel` on the exporter                                                                   | OTel-native document shape; requires ES >= 8.12, works best on >= 8.16.                                     |

### Version pinning

Tags verified to exist in the registries (probed, not guessed):

| Component           | Candidate pin       | Note                                                           |
| ------------------- | ------------------- | -------------------------------------------------------------- |
| Elasticsearch       | `8.14.2`            | `docker.elastic.co/elasticsearch/elasticsearch`                |
| Kibana              | `8.14.2`            | must match Elasticsearch exactly                               |
| Collector (contrib) | `0.145.0`           | `otel/opentelemetry-collector-contrib`                         |
| OTel Java agent     | latest `2.x`        | resolve exact version from the GitHub release when we reach P1 |
| Java / Spring Boot  | JDK 21 / Boot 3.5.x | Boot 3.5 needs JDK 17+; 21 is the sane default                 |

All pinned in a single `.env` so upgrades are one-line changes. I had not finished
confirming the newest patch releases when we stopped — worth a final check before P0 is
built, but any of the tags above works today.

---

## 1. Architecture we are building toward

```
                       +---------------- generation -----------------+
  order-api (Boot 3.5) |  -javaagent -> OTLP push                    |
  worker    (Boot 3.5) |  -javaagent -> OTLP push                    |
                       |                                             |
  RabbitMQ             |  :15692/metrics (prometheus plugin)  <- pull |
  MongoDB              |  serverStatus / dbStats              <- pull |
  MinIO                |  /minio/v2/metrics/*                 <- pull |
  container stdout     |  docker json log files               <- tail |
                       +----------------------+----------------------+
                                              |
                                  OpenTelemetry Collector
                          receivers -> processors -> exporters
                                              |  elasticsearch exporter
                                              v     (mapping.mode: otel)
                                       Elasticsearch  ->  Kibana
```

**The asymmetry to internalise:** applications *push* OTLP; infrastructure is *pulled*
by the Collector. The Collector's entire job is to hide that difference from Elastic.

**Signal availability per component** — this is the table that saves you a week:

| Component        | Traces                                                             | Metrics                       | Logs                          |
| ---------------- | ------------------------------------------------------------------ | ----------------------------- | ----------------------------- |
| Spring Boot apps | yes — Java agent (auto)                                            | yes — Java agent (JVM + HTTP) | yes — Logback appender bridge |
| RabbitMQ         | none — you get *client-side* producer/consumer spans from the apps | scrape                        | stdout                        |
| MongoDB          | none — you get *client-side* driver spans from the apps            | scrape                        | `mongod.log` (JSON)           |
| MinIO            | none — you get *client-side* S3 SDK spans from the apps            | scrape                        | stdout + audit webhook        |

Understanding *why* client-side spans are sufficient for datastores and brokers is a core
insight, not a workaround.

---

## 2. Target repository layout

```
.
├── PLAN.md                       <- this file
├── README.md                     <- how to run + what to look at, per phase
├── .env                          <- all image/version pins
├── docker-compose.yml            <- base: elasticsearch, kibana, otel-collector
├── compose/
│   ├── apps.yml                  <- order-api, worker              (P1, P2)
│   └── infra.yml                 <- rabbitmq, mongodb, minio       (P2, P3)
├── otel/
│   ├── collector.yaml            <- grows one phase at a time
│   └── javaagent/                <- downloaded agent jar (gitignored)
├── apps/
│   ├── order-api/                <- Spring Boot 3.5, HTTP entrypoint
│   └── worker/                   <- Spring Boot 3.5, AMQP consumer
├── kibana/                       <- exported dashboards / saved objects (P5)
├── k8s/                          <- k3d manifests, OTel Operator values (P6)
└── docs/
    └── notes-per-phase.md        <- what we learned, what broke, why
```

Compose overlays (`-f docker-compose.yml -f compose/apps.yml`) mean each phase adds files
rather than editing earlier ones. You can always go back and run P1 alone.

---

## 3. Phases

Each phase ends with **something visibly working in Kibana** and introduces **at most one
new concept**. Never two unknowns at once.

### P0 — Pipeline skeleton, no apps

**Build:** `docker-compose.yml` with Elasticsearch (single node, security disabled for
local learning), Kibana, and the Collector. Collector config: `otlp` receiver → `batch`
processor → `debug` + `elasticsearch` exporters.

**Prove it works:** push synthetic spans with `telemetrygen`, and turn on the Collector's
own self-telemetry so it monitors itself.

**Learning objectives**
- OTLP gRPC `:4317` vs HTTP `:4318` — when each matters
- Receiver → processor → exporter as a *pipeline*, declared per signal type
- The `debug` exporter as your first and best diagnostic tool
- Where documents actually land: data stream naming (`traces-*`, `logs-*`, `metrics-*`
  with dataset/namespace suffixes) and how the `data_stream.dataset` /
  `data_stream.namespace` attributes redirect them
- Reading a raw OTel-mapped document in Discover, field by field

**Deliberate exercise:** break it on purpose. Point the exporter at the wrong port and
read the retry/queue errors, so you recognise them later.

**Done when:** synthetic traces are queryable in Discover and you can name every field in
a span document.

---

### P1 — One Spring Boot app, all three signals

**Build:** `apps/order-api` — a small Boot 3.5 service, a couple of REST endpoints,
Logback. Dockerfile downloads the agent jar and sets `-javaagent`. Configuration entirely
through `OTEL_*` environment variables.

**Rollout order within the phase — do not skip the ordering:**
1. Traces only (`OTEL_METRICS_EXPORTER=none`, `OTEL_LOGS_EXPORTER=none`)
2. Add metrics (JVM heap/GC/threads, HTTP server duration histograms)
3. Add logs via the Logback appender bridge, with `trace_id` correlation

**Learning objectives**
- The `premain` → `Instrumentation` → `ClassFileTransformer` → Byte Buddy chain: how
  advice is spliced into method entry/exit without touching your source or your jar
- Which instrumentation modules matched, read from `OTEL_JAVAAGENT_DEBUG=true`
- `OTEL_SERVICE_NAME` / `OTEL_RESOURCE_ATTRIBUTES`, and why `service.name` is the single
  most important attribute in the system
- Resource vs span vs metric attributes — three different scopes, commonly confused
- Sampling: `OTEL_TRACES_SAMPLER=parentbased_traceidratio`, and why the *parent* part is
  what keeps traces whole
- Trace/log correlation: appender bridge (structured OTLP logs) vs MDC injection
  (`trace_id` in plain stdout) — we do both and compare
- The Kibana APM UI lighting up from nothing but semantic conventions

**Deliberate exercise:** add one manual span and one custom counter with the OTel API, and
watch the agent adopt them into the same trace. This is the moment auto- and manual
instrumentation stop feeling like separate systems.

**Done when:** a request appears as a trace in APM, its JVM metrics are on a chart, and
you can jump from a span to that request's log lines.

---

### P2 — Second app + RabbitMQ: context propagation across a broker

**Build:** `apps/worker` consuming AMQP; `compose/infra.yml` adds RabbitMQ with the
management and `rabbitmq_prometheus` plugins enabled. `order-api` publishes.

Two hops to compare: `order-api → worker` over **HTTP**, then `order-api → queue →
worker` over **AMQP**.

**Learning objectives**
- W3C `traceparent`: injected into HTTP headers, and into AMQP message headers by the
  RabbitMQ producer instrumentation; extracted again on the consumer side
- Why a trace survives a broker with no shared state — just a header being copied along
- `PRODUCER` / `CONSUMER` span kinds, span links, and why messaging traces look different
  from HTTP traces
- Messaging semantic conventions (`messaging.system`, `messaging.destination.name`)
- Queue depth as a *metric* signal that traces cannot give you

**Deliberate exercise:** disable the AMQP instrumentation module
(`OTEL_INSTRUMENTATION_RABBITMQ_ENABLED=false`) and observe the trace split into two
orphans. Then re-enable. The best possible demonstration of what propagation buys you.

**Done when:** one Kibana trace spans both services through the queue, and the service map
draws the broker.

---

### P3 — MongoDB + MinIO as dependencies of the apps

**Build:** add MongoDB and MinIO to `compose/infra.yml`. `order-api` persists orders to
Mongo; `worker` writes objects to MinIO via the AWS S3 SDK.

**Learning objectives**
- Driver-level instrumentation: Mongo `CommandListener` hooks producing client spans that
  carry `db.system`, `db.namespace`, and the sanitised `db.query.text`
- Statement sanitisation — why literals are stripped, and the privacy reason it matters
- S3/AWS-SDK instrumentation pointed at a non-AWS endpoint (MinIO), and what breaks
- Reading dependency latency purely from client spans, with no server-side
  instrumentation at all — the key conceptual payoff of this phase

**Done when:** a single trace shows HTTP → Mongo query → publish → consume → S3 put, and
the APM dependency view lists Mongo and MinIO as downstreams.

---

### P4 — Scrape the infrastructure

Now, and only now, do we add infra receivers — because by this point you already know what
these metrics *mean* from having seen the traces.

**Build:** extend `otel/collector.yaml`:
- `prometheus` receiver → RabbitMQ `:15692`, MinIO `/minio/v2/metrics/cluster` (locally
  with `MINIO_PROMETHEUS_AUTH_TYPE=public`; then redo it with a real bearer token, because
  production needs that)
- `rabbitmq` receiver against the management API — build it alongside the Prometheus scrape
  and *diff the metric sets*
- `mongodb` receiver with a dedicated user holding only `clusterMonitor`
- `filelog` receiver for container stdout and `mongod.log`, with operators to parse and map
  onto semantic conventions

**Learning objectives**
- Pull-based collection: scrape intervals, staleness, cardinality
- Metric temporality (cumulative vs delta) and why the backend cares
- The processors that make infra data usable: `resourcedetection`, `resource`,
  `attributes`, `transform` (OTTL), `filter`
- Log parsing done properly: `regex_parser` / `json_parser`, severity mapping, multiline
  handling, timestamp parsing — and what a badly parsed log costs you
- Least-privilege monitoring credentials
- **Cardinality discipline** — the failure mode that kills real observability platforms

**Deliberate exercise:** add a high-cardinality attribute on purpose, watch index and field
growth, then remove it with a `transform` statement.

**Done when:** infra dashboards exist and you can correlate a latency spike in a trace with
a queue-depth or Mongo metric at the same timestamp.

---

### P5 — Kibana, and the operational reality

**Build:** dashboards for each component, exported as saved objects into `kibana/`.
Alerting rules and an SLO. ILM policies and retention.

**Learning objectives**
- APM UI: service map, transactions, dependencies, errors — and which semantic convention
  each view depends on
- Discover + ES|QL over OTel-mapped documents
- Building a dashboard that answers a question rather than one that displays everything
- ILM / data stream lifecycle: hot-warm-cold, retention, and the storage cost of
  observability
- Sampling strategy: head-based in the SDK vs `tail_sampling` in the Collector, and the
  tradeoff you are actually making
- Alerting on symptoms (latency, error rate) rather than on causes

**Done when:** you can answer "is the system healthy?" in under 30 seconds, and you know
roughly what a day of telemetry costs in disk.

---

### P6 — Port to Kubernetes with k3d

The *concepts* do not change here; the *deployment mechanics* change completely. That is
exactly the lesson.

**Build:** `k8s/` — k3d cluster config, Elasticsearch + Kibana (ECK operator or plain
manifests), the OpenTelemetry Operator, and the two-tier collection pattern.

**Learning objectives**
- **Agent/gateway pattern:** a Collector `DaemonSet` per node (node-local concerns: logs,
  host metrics, receiving app OTLP) feeding a Collector `Deployment` gateway (cluster-wide
  concerns: batching, tail sampling, the single egress to Elastic). Why the two tiers exist.
- **Auto-instrumentation without touching images:** the OTel Operator's `Instrumentation`
  CRD plus a pod annotation, which triggers a mutating admission webhook to inject an init
  container that copies the agent jar into a shared volume and sets `JAVA_TOOL_OPTIONS`.
  Identical bytecode mechanics to P1, entirely different delivery.
- `k8sattributes` processor: stamping pod / namespace / deployment onto every signal
- `k8s_cluster` and `kubeletstats` receivers for cluster-level metrics
- Service discovery for scraping, instead of hardcoded Compose hostnames
- What is genuinely harder in Kubernetes: certs, secrets, DNS, resource limits, restarts

**Done when:** the same traces, metrics and logs appear in Kibana from a k3d cluster,
enriched with Kubernetes resource attributes — and the Compose stack still works, so you
can run both and diff them.

---

## 4. Cross-cutting practices from day one

- **Every phase gets notes** in `docs/notes-per-phase.md`: what broke, the exact error
  text, the cause. This becomes your real reference.
- **The `debug` exporter stays configured permanently.** It is the difference between "no
  data in Kibana" being a five-minute problem or a five-hour one.
- **Debug in pipeline order**, always: was it generated? (agent `logging` exporter) → did
  the Collector receive it? (`debug` exporter) → did the export succeed? (Collector logs
  and self-metrics) → is it indexed? (Discover) → is it mapped for the UI? (semantic
  conventions). Guessing at random costs hours.
- **Never mix a version bump with a config change** in the same step.
- **Semantic conventions are the contract.** When a Kibana view is empty, suspect a missing
  or misnamed attribute long before you suspect a broken pipeline.

---

## 5. Known risks and open questions

| Item                                   | Risk                                                                    | How we handle it                                                                                                               |
| -------------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Elasticsearch memory in Compose        | ES will refuse to start or will thrash on default Docker Desktop memory | Set explicit JVM heap, disable ML, document the Docker Desktop memory floor                                                    |
| `mapping.mode: otel` on 8.14.2         | 8.14 clears the >= 8.12 floor but predates the >= 8.16 maturity point, so APM UI gaps are likely, not hypothetical | Verify each Kibana view as we build it; expect to enable the *optional* APM Server Compose profile for views that need APM-Server-shaped documents, and record which ones |
| Security disabled locally              | Not representative of production                                        | Deliberate for P0–P5 to cut moving parts; re-enable TLS + API keys in P6                                                       |
| Exact patch versions                   | Newest patch releases not fully confirmed yet                           | Confirm and pin in `.env` before P0 is built; any probed tag above works today                                                 |
| Agent version drift                    | Java agent 2.x semantic conventions are still evolving                  | Pin the agent version explicitly; never use `latest`                                                                           |
| MinIO S3 SDK instrumentation           | AWS SDK instrumentation against a non-AWS endpoint may attribute oddly  | Treat as a finding to document in P3, not as a blocker                                                                         |

---

## 6. Immediate next step

Build **P0 only**: `.env`, `docker-compose.yml`, `otel/collector.yaml`, and a `README.md`
section covering how to start it, how to push synthetic data, and exactly what to look at
in Kibana. Nothing else until synthetic traces are visible and understood.
