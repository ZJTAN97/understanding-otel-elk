# Phase 10 — Context propagation across a broker

**Goal:** one trace spanning two services through RabbitMQ, and a precise understanding of
what makes that possible.

**Prerequisites:** Phase 09.

**Artifacts produced:** `apps/worker/`, `compose/infra.yml`.

---

## Concepts

**W3C Trace Context is just a header being copied.** There is no shared state, no
coordinating service, no registry. A single header:

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             ^   ^                                ^                ^
          version  trace-id                    parent-span-id    flags
```

The producer injects it. The consumer extracts it. That is the entire mechanism, and
understanding that it is *this* small is the point of the phase.

**Over HTTP** it is an HTTP header. **Over AMQP** it is a message header, injected by the
RabbitMQ producer instrumentation and read by the consumer instrumentation. Same header,
different carrier.

**Span kinds change how traces are read:**

| Kind | Meaning |
|---|---|
| `SERVER` | Handling an inbound request |
| `CLIENT` | Making an outbound call, waiting for a response |
| `PRODUCER` | Sending a message, not waiting |
| `CONSUMER` | Receiving a message |

The producer/consumer distinction matters because messaging is **asynchronous**. An HTTP
trace is a neat nested tree — the parent is alive the whole time its children run. A
messaging trace is not: the producer span may have ended long before the consumer span
starts. Traces can appear to have gaps in time, and that is correct rather than broken.

**Span links.** Sometimes a consumer span links to a producer rather than being its child,
particularly when a batch of messages is consumed at once and there is no single parent.
Links express "related to" without implying "caused by, synchronously".

**Queue depth is a metric, not a trace.** No amount of tracing tells you a queue is backing
up. Traces tell you about requests that happened; they cannot tell you about work sitting
unprocessed. This is the clearest possible illustration of why you need more than one
signal type, and it sets up Phase 12.

## Steps

### 1. Add RabbitMQ

`compose/infra.yml` with the management plugin and `rabbitmq_prometheus` enabled. The
Prometheus plugin exposes `:15692/metrics` — not used until Phase 12, but enable it now so
the container definition stops changing.

### 2. Build the worker

`apps/worker` — a Spring Boot app consuming from a queue. Same agent, same environment
variable pattern, different `OTEL_SERVICE_NAME`.

### 3. Do the HTTP hop first

Have `order-api` call `worker` over plain HTTP. Confirm you get one trace with spans from
both services.

This is the control case. It establishes that propagation works at all, so that when the
AMQP hop misbehaves you know the problem is AMQP-specific.

### 4. Now the AMQP hop

`order-api` publishes; `worker` consumes. Confirm the trace still spans both services.

Then go and **look at the message headers themselves** in the RabbitMQ management UI. Find
`traceparent` sitting there as an ordinary message property. Seeing the actual header, in
the actual broker, is what converts this from documentation to knowledge.

### 5. Read the semantic conventions

On the messaging spans, find `messaging.system`, `messaging.destination.name`,
`messaging.operation`. These attribute names are what the Kibana APM UI keys off to draw
RabbitMQ as a node in the service map. **Semantic conventions are the contract** — when a
UI view is empty, suspect a missing or misnamed attribute long before you suspect a broken
pipeline.

## Deliberate exercise

Disable the RabbitMQ instrumentation module:

```
OTEL_INSTRUMENTATION_RABBITMQ_ENABLED=false
```

Restart and publish a message.

**Observe the trace split into two orphans.** The producer side ends at the publish. The
consumer side starts a brand new trace with a new `trace_id`. Nothing errors. Nothing warns.
You simply lose the connection between cause and effect, silently.

This is the single best demonstration of what propagation buys you, and it is also the exact
failure mode you will hit in production when a library has no instrumentation module, a
proxy strips headers, or a queue is consumed by something uninstrumented.

Re-enable it and watch the trace knit back together.

## Done when

- One trace in Kibana spans `order-api` → RabbitMQ → `worker`
- The service map draws the broker between the two services
- You have seen `traceparent` in the RabbitMQ management UI with your own eyes
- You have broken and repaired propagation deliberately
- You can explain why a messaging trace has time gaps and an HTTP trace does not

## Notes

- 

## Next

[Phase 11 — Datastore client spans](11-datastore-client-spans.md)
