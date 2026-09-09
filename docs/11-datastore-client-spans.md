# Phase 11 — MongoDB and MinIO: client-side spans

**Goal:** full visibility into datastore behaviour with **zero instrumentation on the
datastores themselves**.

**Prerequisites:** Phase 10.

**Artifacts produced:** MongoDB and MinIO added to `compose/infra.yml`; apps use both.

---

## The conceptual payoff

MongoDB does not emit traces. MinIO does not emit traces. RabbitMQ does not emit traces.

You will still be able to see exactly how long every query took, which collection it hit,
which operation it was, and where it sat inside the request that caused it.

**This is not a workaround — it is the correct design.** The question you actually need
answered is "how long did *my request* wait for the database", and that is a property of
the client, not the server. Server-side timing would tell you how long the database spent
executing, which excludes connection acquisition, serialisation, and network time — the
parts that most often hurt.

Internalising this saves you from a long, fruitless search for "MongoDB OpenTelemetry
support".

| Component | Traces | Metrics | Logs |
|---|---|---|---|
| Spring Boot apps | yes — agent | yes — agent | yes — appender |
| RabbitMQ | **client-side only** | scrape (Phase 12) | stdout |
| MongoDB | **client-side only** | scrape (Phase 12) | `mongod.log` |
| MinIO | **client-side only** | scrape (Phase 12) | stdout |

## Concepts

**Driver-level instrumentation.** The MongoDB Java driver exposes a `CommandListener`
interface. The agent registers one, and it fires on command start, success and failure. The
span is created from those callbacks — the agent is not parsing wire protocol or patching
Mongo, it is using an extension point the driver already offers.

**Statement sanitisation.** `db.query.text` (or `db.statement` on older conventions) is
recorded with literals stripped:

```
{"find": "orders", "filter": {"customerId": "?"}}
```

The `?` replaces the real value. There are two reasons, and both matter:

- **Privacy** — query literals are user data. Unsanitised statements put PII into your
  observability platform, which typically has weaker access controls than your database
  and longer retention. This has caused real incidents.
- **Cardinality** — sanitised statements group. Unsanitised ones are unique per request,
  making aggregation by query shape impossible.

**AWS SDK against a non-AWS endpoint.** MinIO speaks the S3 API, so the AWS SDK
instrumentation works — but attributes may look odd, since they were designed assuming
real AWS. Expect surprises in region, endpoint and bucket attributes. `PLAN.md:315` calls
this a finding to document rather than a blocker, and that is the right posture.

## Steps

### 1. Add MongoDB and MinIO

Into `compose/infra.yml`. For MinIO set `MINIO_PROMETHEUS_AUTH_TYPE=public` for now —
Phase 12 redoes it with a real bearer token, because production will need that.

### 2. Wire the apps

- `order-api` persists orders to MongoDB
- `worker` writes an object to MinIO via the AWS S3 SDK

### 3. Read the resulting spans

Look for `db.system`, `db.namespace`, `db.operation.name`, `db.query.text`. Confirm
literals are stripped. Note the exact attribute names your agent version emits — they have
shifted across 2.x releases, and Kibana views depend on them.

### 4. The full trace

Trigger a request that exercises everything:

```
HTTP request
 └─ Mongo insert          (CLIENT)
 └─ AMQP publish          (PRODUCER)
     └─ AMQP consume      (CONSUMER)
         └─ S3 PutObject  (CLIENT)
```

One trace. Five systems. Instrumentation on two of them.

### 5. The dependency view

Open the APM dependency view. MongoDB and MinIO appear as downstream dependencies with
latency and throughput — derived entirely from client spans. Nothing was installed on
either.

## Deliberate exercise

Make the database slow. Insert a `sleep` in a Mongo aggregation, or throttle MinIO.

Then answer, using only the telemetry: **how much of the request latency was the database?**

Now do the harder version. Make MinIO return an error. Find:

- Which span failed and what its status is
- Whether the error propagated to the parent span
- Whether the trace is marked as failed in the APM UI
- Whether the exception appears in the correlated logs from Phase 09

Error propagation through span hierarchies is subtler than it looks, and it is what
determines whether your Phase 13 alerting actually fires.

## Done when

- A single trace shows HTTP → Mongo → publish → consume → S3
- The APM dependency view lists MongoDB and MinIO
- You have confirmed statement sanitisation and can explain both reasons for it
- You have documented how AWS SDK instrumentation attributes look against MinIO
- You can attribute a latency increase to a specific dependency from telemetry alone

## Notes

- 

## Next

[Phase 12 — Infrastructure scraping](12-infrastructure-scraping.md)
