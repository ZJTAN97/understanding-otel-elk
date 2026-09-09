# Phase 09 — One Spring Boot app, all three signals

**Goal:** a real application producing traces, metrics and logs, and an understanding of how
the Java agent does it without touching your source.

**Prerequisites:** Phase 08.

**Artifacts produced:** `apps/order-api/`, `compose/apps.yml`.

---

## Concepts

**How the Java agent actually works.** This is worth understanding properly, because it
explains every subsequent behaviour:

1. `-javaagent:opentelemetry-javaagent.jar` makes the JVM call the agent's `premain` method
   **before your application's `main`**
2. The agent registers a `ClassFileTransformer` with the `Instrumentation` API
3. As classes load, the transformer inspects them
4. **Byte Buddy** splices advice into method entry and exit for classes matching known
   instrumentation modules
5. Your source is unchanged. Your jar on disk is unchanged. Only the in-memory bytecode
   differs

This is why instrumentation is "automatic", why it only covers libraries someone wrote a
module for, and why load order matters. Phase 16 does the identical thing in Kubernetes
with completely different delivery mechanics — recognising that they are the same mechanism
is the payoff.

**Configuration is entirely environment variables.** `OTEL_*`. No code, no config file.

**`service.name` is the most important attribute in the system.** Nearly every Kibana view
groups by it. Get it wrong and the UI looks broken.

**Three attribute scopes, constantly confused:**

| Scope | Set on | Example |
|---|---|---|
| **Resource** | The emitting process | `service.name`, `host.name`, `k8s.pod.name` |
| **Span** | One operation | `http.route`, `db.statement` |
| **Metric (data point)** | One measurement | `http.response.status_code` |

Resource attributes are attached once and repeated on everything. This is where cardinality
discipline starts.

**Sampling.** `OTEL_TRACES_SAMPLER=parentbased_traceidratio` with
`OTEL_TRACES_SAMPLER_ARG=0.1`. The **parentbased** part is what matters: if the parent span
was sampled, children are sampled too. Without it, each service decides independently and
you get traces with holes — the worst possible outcome, because they look complete but are
not.

## Steps

### 1. Build a minimal app

`apps/order-api` — Spring Boot 3.5, JDK 21. A couple of REST endpoints, one of which does
something slow enough to be visible. Logback for logging. Nothing clever.

### 2. Dockerfile with the agent

Download a **pinned** agent version — not `latest`. Java agent 2.x semantic conventions are
still evolving, and an unpinned agent means your attribute names can change under you
between builds. That failure is maddening to diagnose because nothing in your code changed.

### 3. Traces only, first

```
OTEL_SERVICE_NAME=order-api
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none
```

**Do not skip this ordering.** One signal at a time means one thing to debug at a time.

Hit an endpoint. Watch the `debug` exporter. Find the trace in Discover, then in the Kibana
APM UI.

### 4. See what the agent instrumented

```
OTEL_JAVAAGENT_DEBUG=true
```

Restart and read the startup log. It lists which instrumentation modules matched. This is
the definitive answer to "why is my library not producing spans" — either a module exists
and matched, or it does not.

### 5. Add metrics

```
OTEL_METRICS_EXPORTER=otlp
```

You get JVM metrics (heap, GC, threads) and HTTP server duration histograms for free.
Find them in Discover, then chart one.

### 6. Add logs, and correlate

```
OTEL_LOGS_EXPORTER=otlp
OTEL_INSTRUMENTATION_LOGBACK_APPENDER_ENABLED=true
```

Two mechanisms worth comparing directly:

| | What it does |
|---|---|
| **Logback appender bridge** | Ships structured log records over OTLP with trace context attached |
| **MDC injection** | Injects `trace_id` / `span_id` into your log pattern, so plain stdout carries them |

Do both. The appender is the better mechanism; MDC is what saves you when something is
reading stdout instead. In Kubernetes you will often need both, for the same reason.

Verify correlation: find a span, take its `trace_id`, and search logs for it. You should get
that request's log lines and nothing else.

## Deliberate exercise

Add **one manual span** and **one custom counter** using the OpenTelemetry API directly in
your code.

Watch the agent adopt them: your manual span appears as a child of the automatic HTTP span,
in the same trace, with no wiring from you. Your counter appears alongside the JVM metrics.

This is the moment automatic and manual instrumentation stop feeling like two systems. They
share one SDK, one context, one exporter. The agent is just a very thorough way of calling
the same API you just called by hand.

## Done when

- One HTTP request appears as a complete trace in the APM UI
- JVM metrics are on a chart
- You can pivot from a span to that request's log lines via `trace_id`
- You can explain `premain` → `Instrumentation` → `ClassFileTransformer` → Byte Buddy
- You can list which instrumentation modules loaded, and why one you expected did not
- A manual span sits inside an automatic trace

## Notes

- 

## Next

[Phase 10 — Propagation across RabbitMQ](10-propagation-across-rabbitmq.md)
