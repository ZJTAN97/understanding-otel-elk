# Phase 20 — Operating the platform

**Goal:** make sure this platform does not become the thing it replaced.

**Prerequisites:** Phase 19.

**Artifacts produced:** runbooks, an upgrade calendar, the 8→9 plan.

---

## The actual point of this entire document

The previous platform did not fail because of a bad architecture decision. It failed
because **nothing made its staleness visible to anyone.** No release record, no chart
version in git, no upgrade cadence, no owner, no backups, and a Fleet apparatus half of
which nobody used.

A brand-new 8.19 cluster with no lifecycle becomes an 8.19 cluster in 2029. This phase is
the difference.

## 1. Everything in git, and nothing outside it

The rule: **if it is not in git, it is not deployed.**

Enforce it by working that way — always change the file, never the cluster. When someone
patches a live resource to fix an incident, that patch is reconciled into the repo the same
day or it is lost.

Consider Argo CD or Flux if the environment permits. Automated reconciliation makes drift
impossible rather than merely discouraged. If not, at minimum a documented deploy procedure
that reads from a git tag.

**The config that tries to escape git:**

| Escapes | Mitigation |
|---|---|
| Kibana saved objects — dashboards, alerting rules | Export to `kibana/` on a schedule. Phase 13 |
| ILM policies, index templates | Declare as files, apply on deploy |
| Snapshot repository registration | Declare as a file |
| Elasticsearch cluster settings | Declare, and periodically diff live against declared |

Fleet is not on this list, because D4 removed it. That was much of the reason for D4.

## 2. Version ownership

The single mechanism that would have prevented the two-year freeze:

- **A named owner.** Not a team — a person, with a backup
- **A calendar entry, quarterly**, to check current versions against the compatibility
  matrix. Fifteen minutes. Put it in the calendar, not in your head
- **A version table in the repo README**, so drift is visible on every browse
- **The compatibility ladder recorded** (`00-decisions.md` D3), so the next person does not
  have to rediscover it

**Track these four together, because they constrain each other:**

| Layer | Current | Constrains |
|---|---|---|
| Kubernetes | | which ECK you can run |
| ECK operator | | which stack versions you can run |
| Elasticsearch / Kibana | | the whole platform |
| OTel Collector / Operator | | independent, moves fastest |

## 3. The 8→9 upgrade, already planned

8.19 reaches end-of-life **15 July 2027**. You knew this when you chose it (D3), and Phase
06 exercise 2 rehearsed it.

Schedule it now, backwards from the deadline:

| When | What |
|---|---|
| ~Q4 2026 | Kubernetes upgrade off 1.28, unblocking newer ECK |
| ~Q1 2027 | ECK operator upgrade. Operator before stack, always |
| ~Q2 2027 | Upgrade Assistant, resolve deprecations, rehearse in lab again |
| **before Jul 2027** | Elasticsearch → Kibana → Collector |

**The Kubernetes upgrade is the long pole**, because you do not control it. Start that
conversation in 2026, not 2027.

Order within the stack: **operator, then Elasticsearch, then Kibana, then collection.**

## 4. Runbooks

Write these from your lab notes. Every one of these questions was answered by an exercise
in Parts 1–3 — the runbook is just that answer, written where someone else can find it at
3am.

| Runbook | Answered in |
|---|---|
| No data in Kibana — the pipeline-order debug procedure | 08 |
| A rolling upgrade is stuck | 06 |
| A node is lost | 06 |
| The gateway is down — what is queued, what is lost | 14 |
| Cardinality explosion — detect and fix | 12 |
| Enrichment stopped working — check RBAC | 15 |
| Restore from snapshot | 07 |
| Add a new application to instrumentation | 16 |
| Add a new infrastructure component to scraping | 12, 15 |
| Mirror a new image into the air-gap | 17 |

**The pipeline-order debug procedure is the most valuable page you will write:**

```
generated?  -> agent debug/logging exporter
received?   -> Collector debug exporter
exported?   -> Collector logs + self-telemetry
indexed?    -> Discover
mapped?     -> semantic conventions, Kibana view expectations
```

In order, every time. Guessing at random costs hours; this costs minutes.

## 5. Monitor the monitoring

The self-health dashboard from Phase 13 is not optional. Alert on:

- Collector export failures and refused spans
- Elasticsearch cluster health not green
- Disk watermarks approaching
- **SLM snapshot failures** — a silently failing backup is worse than no backup, because
  you believe you are covered
- Data volume anomalies in either direction. A sudden drop means collection broke; a sudden
  spike means cardinality

## 6. Review the decision record

`00-decisions.md` is a living document, not an artifact. Revisit it when:

- A version support window changes
- The EDOT question is worth reopening (D5)
- Data volume outgrows the topology (D3, Phase 18)
- Someone asks "why is it like this?" — and if the answer is not in there, add it

## Done when

This is the phase with no end state. But you are on the right footing when:

- A version check happens on a schedule, owned by a named person
- Nothing is deployed that is not in git
- Runbooks exist and someone other than you has used one successfully
- Snapshots are verified, with restores tested and failures alerted
- The 8→9 upgrade has dates and an owner
- Someone new could read `docs/` and understand why the platform is the way it is

That last point is the one that matters. It is the only thing that was actually missing
before.

## Notes

- 

---

## Back to the start

[README](README.md) · [Decision record](00-decisions.md)
