# Phase 18 — Production design

**Goal:** a written, reviewable design for the new production platform, backed by measured
numbers from the lab.

**Prerequisites:** Phases 01–17.

**Artifacts produced:** the production manifest set in git; this document filled in.

**Blocked on:** Q1 (current coverage), Q2 (volume, capacity), Q4 (object storage),
Q5 (same cluster or new).

---

## This phase is writing, not building

Everything before this was learning. Everything after is execution. This is the seam, and
it is the moment to write the design down so that it can be reviewed by someone other than
you — and so that in two years the next engineer inherits a document instead of a mystery.

That is the actual failure being corrected here. The current cluster is not bad because it
runs 8.14.2. It is bad because **nobody can tell why it is the way it is.**

## Design decisions to record

### 1. Placement (Q5)

Same Kubernetes cluster in new namespaces, or a new cluster?

| | Same cluster | New cluster |
|---|---|---|
| Effort | low | high |
| Isolation from old platform | namespace only | complete |
| k8s version constraint | stuck on 1.28 → ECK 3.0 | free to choose newer |
| Parallel run (D2) | shared node resources | fully independent |

Note the second-order effect: if a new cluster is viable, the k8s version constraint from
D3 disappears and you could run current ECK. That may be worth more than it first appears,
because it removes the platform-upgrade dependency from the critical path.

**Decision:** _______________

### 2. Namespaces

Keep the operator/workload split the current platform uses — it is sound.

```
elastic-system     ECK operator
elastic-stack      Elasticsearch, Kibana
observability      OTel gateway, OTel operator
```

Must not collide with the existing `eck` and `elastic-system` namespaces if sharing a
cluster (Q5). **If sharing, the existing `elastic-system` already holds ECK 2.13.0 — two
ECK operators in one cluster need careful namespace scoping (Phase 02) or they will fight
over the same CRDs.** This is the single largest risk in the same-cluster option and must
be resolved before anything is deployed.

**Decision:** _______________

### 3. Topology and sizing

From Phase 04 (roles) and Phase 13 (measured bytes/day). Extrapolate to Q2 volume.

| Tier | Count | CPU | Memory | Heap | Storage |
|---|---|---|---|---|---|
| master | 3 | | | | |
| data | | | | | |
| ingest | *justify or omit* | | | | |

Rules carried forward from the lab:

- 3 dedicated masters, never 2
- Heap = half of memory limit
- `node.store.allow_mmap: false` was a **lab-only** workaround — set
  `vm.max_map_count=262144` on production nodes instead
- At least 1 replica, or a node loss is data loss (Phase 06 exercise 5)

**Storage class matters.** If production uses node-local storage, a node loss means shard
rebuild rather than reschedule. Confirm what is available and design replicas accordingly.

**Decision:** _______________

### 4. Collection coverage (Q1)

The new pipeline must cover everything the old one does. Map it explicitly:

| Currently collected | New mechanism | Phase |
|---|---|---|
| *(fill from Q1)* | | |

Any row you cannot fill is visibility that disappears at cutover. Find them now.

**Decision:** _______________

### 5. Security

- TLS on by default, ECK-managed internally (Phase 03)
- Ingress certificates from wherever the organisation issues them — not self-signed
- Least-privilege users for every component (Phase 05 associations, Phase 12 monitoring users)
- Elasticsearch credentials only in the gateway tier (Phase 14)
- Secrets from Kubernetes Secrets, ideally with encryption at rest enabled
- Consider whether the `elastic` superuser should be usable at all day to day

**Decision:** _______________

### 6. Snapshots (Q4)

From Phase 07. Repository target, SLM schedule, retention, and **where restores are
tested**. A restore that has never been performed against production storage is not a
verified restore.

**Decision:** _______________

### 7. Retention and ILM

From Phase 13, per signal type. Traces are the volume; metrics are the long tail.

| Signal | Hot | Delete | Rationale |
|---|---|---|---|
| traces | | | |
| metrics | | | |
| logs | | | |

**Decision:** _______________

### 8. Capacity headroom

Size for the parallel run (D2): both platforms running simultaneously for one retention
window, roughly 30 days. Confirm the environment can carry both at once — this was the
premise the whole greenfield decision rested on, so verify it rather than assume it.

**Decision:** _______________

## Repository layout

The thing that was missing. Everything, in git, reviewable.

```
k8s/
├── eck-operator/          Helm values, pinned chart version
├── elasticsearch/         Elasticsearch resource, secure settings
├── kibana/                Kibana resource, ingress
├── otel-operator/         Helm values, Instrumentation CRD
├── otel-collector/        agent DaemonSet, gateway Deployment, ConfigMaps, RBAC
├── snapshots/             repository registration, SLM policy
├── ilm/                   policies and index templates
└── images.txt             the air-gap supply chain manifest
```

## Deliverable

**A design document that someone else could review.** For each decision: what was chosen,
what was rejected, and why. When this cluster is two years old and someone asks "why is it
like this?", this document is the answer.

That is the entire difference between this platform and the one it replaces.

## Done when

- Every `Decision:` above is filled in
- Sizing is backed by measured numbers, not guesses
- The Q1 coverage map has no empty rows
- Someone other than you has read it
- The manifest set exists in git and deploys cleanly in the lab

## Notes

- 

## Next

[Phase 19 — Build and cutover](19-build-and-cutover.md)
