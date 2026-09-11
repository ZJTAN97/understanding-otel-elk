# Phase 13 — Kibana, and the operational reality

**Goal:** answer "is the system healthy?" in under thirty seconds, and know what a day of
telemetry costs in disk.

**Prerequisites:** Phase 12.

**Artifacts produced:** `kibana/` saved objects, alerting rules, ILM policies.

**Blocked on:** Q7 (licence tier) — SLOs and some alerting features are not on Basic.

---

## The bill for D4 comes due here

Decision D4 chose OpenTelemetry over Elastic Agent, and named the cost: **you build your
own dashboards.** Elastic integration packages ship prebuilt dashboards, but they assume
ECS-shaped documents produced by Elastic Agent. Your documents are OTel-shaped.

This phase is where you find out how large that cost actually is. Be honest in your notes,
because the answer feeds directly into the Phase 16 decision about whether to switch to
EDOT — whose entire value proposition is bridging exactly this gap.

## Concepts

**The APM UI is not magic — it is semantic conventions.** Each view depends on specific
attributes being present and correctly named:

| View | Depends on |
|---|---|
| Service list | `service.name` |
| Service map | span kinds plus `peer.service` / `db.system` / `messaging.system` |
| Transactions | `SERVER` spans with `http.route` |
| Dependencies | `CLIENT` / `PRODUCER` spans with the target identified |
| Errors | span status and recorded exception events |

**When a view is empty, it is almost always a missing or misnamed attribute — not a broken
pipeline.** Check the document in Discover first. This one habit will save you days across
the life of the platform.

**Dashboards that answer a question.** The instinct is to display everything available. A
dashboard showing forty charts answers nothing, because the reader has no idea which chart
matters. Start from the question — "are we serving requests successfully and quickly?" —
and add only charts that help answer it.

**ILM and the cost of observability.** Traces are usually the largest signal by volume and
the least useful after a few days. Metrics are small and useful for a long time. Logs sit
in between. A single retention policy across all three is always wrong in one direction:
either you are paying to keep traces nobody will read, or discarding metrics you needed for
capacity planning.

**Sampling — a real tradeoff, not a free win:**

| | Where | Tradeoff |
|---|---|---|
| **Head-based** | SDK, at trace start | Cheap, decided before you know anything. You will discard errors |
| **Tail-based** | Collector, after the trace completes | Keeps all errors and slow traces. Requires buffering complete traces in the gateway — memory, and all spans of a trace must reach the same instance |

That last constraint is why Phase 14 has a gateway tier. Tail sampling is a major reason the
two-tier pattern exists.

**Alert on symptoms, not causes.** Alert on "error rate above 2%" and "p99 latency above
2s" — things users experience. Do not alert on "heap above 80%", which may be entirely
normal. Cause-based alerts train people to ignore alerts.

## Steps

### 1. Work the APM UI systematically

Service list, service map, transactions, dependencies, errors. For each one, find the
attribute it depends on in a raw document. Where a view is empty, diagnose why.

**Record the gaps.** This list is the input to the Phase 16 EDOT decision.

### 2. Discover and ES|QL

Query OTel-mapped documents directly. ES|QL is worth learning here — it makes ad-hoc
questions answerable without building a visualisation, which is most of what you actually
do during an incident.

### 3. Build three dashboards

- **Service health** — request rate, error rate, latency percentiles per service
- **Infrastructure** — queue depth, Mongo connections, MinIO throughput
- **Platform self-health** — Collector queue depth, refused spans, export failures,
  Elasticsearch indexing rate

The third one is the one people forget and then regret. When telemetry goes missing, you
need telemetry about your telemetry.

Export everything to `kibana/` as saved objects. Dashboards clicked into a UI and never
exported are the same untracked-config failure as Fleet policies (D4).

### 4. Alerting

Start with two rules: error rate and latency. Resist adding more until these have proven
themselves useful.

If the licence permits (Q7), define one SLO. If not, note the limitation and move on.

### 5. Measure the actual cost

```
GET _cat/indices/*?v&h=index,docs.count,store.size&s=store.size:desc
GET _cat/shards?v
```

Work out bytes per day per signal type. Extrapolate to production volume (Q2).

**This number determines your production sizing**, and it is far more trustworthy than any
estimate, because it is measured from your own data with your own attributes.

### 6. ILM per signal

Now write real policies, informed by step 5. Different retention for traces, metrics and
logs. Attach via index templates matching the data streams.

## Deliberate exercise

Turn on head-based sampling at 10%, generate load including some errors, and try to
investigate one of the errors.

Note how often the trace you actually want was discarded. Then implement `tail_sampling` in
the Collector — keep everything that errored or exceeded a latency threshold, sample the
rest — and repeat.

You have just made the tradeoff concrete instead of theoretical, and you now know why the
gateway tier in Phase 14 needs to exist.

## Done when

- You can answer "is the system healthy?" in under thirty seconds from one dashboard
- Alerting rules fire on real symptoms and you have seen them fire
- ILM policies differ per signal type and you can justify each
- You know your bytes-per-day, measured
- Every saved object is exported into `kibana/` and in git
- **You have a written list of which Kibana views work well on OTel-native documents and
  which do not** — the Phase 16 input

## Notes

- 

## Next

Part 2 complete. Everything moves into Kubernetes now.

[Phase 14 — Collector on Kubernetes](14-collector-on-kubernetes.md)
