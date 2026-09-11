# Learning path: ECK → OpenTelemetry → production

A sequenced, phase-by-phase path from "I have never run the ECK operator" to
"a new, git-tracked, OpenTelemetry-based observability platform is running in the
air-gapped environment and the old one has been decommissioned."

Every phase is a self-contained file. Each one ends with something visibly working,
introduces at most one new concept, and leaves behind an artifact you keep.

---

## Read this first

| | |
|---|---|
| [00-decisions.md](00-decisions.md) | Every decision made so far, why, and what is still open. **Start here.** |

## Part 1 — ECK foundations (k3d lab)

Goal: understand the operator well enough to design a production cluster, and produce
the manifests you will actually deploy.

| Phase | File | You learn |
|---|---|---|
| 01 | [01-lab-environment.md](01-lab-environment.md) | k3d pinned to the production Kubernetes minor; tooling |
| 02 | [02-eck-operator.md](02-eck-operator.md) | The operator: CRDs, webhook, RBAC, namespace scoping |
| 03 | [03-elasticsearch-basics.md](03-elasticsearch-basics.md) | The `Elasticsearch` CRD, generated secrets, TLS, services |
| 04 | [04-elasticsearch-topology.md](04-elasticsearch-topology.md) | nodeSets, node roles, master quorum, storage |
| 05 | [05-kibana-and-ingress.md](05-kibana-and-ingress.md) | Associations, Ingress, external TLS |
| 06 | [06-eck-operations.md](06-eck-operations.md) | Rolling upgrades, failure, scaling — **the payoff phase** |
| 07 | [07-snapshots-and-lifecycle.md](07-snapshots-and-lifecycle.md) | Snapshot repository, SLM, ILM, restore |

## Part 2 — OpenTelemetry fundamentals

Goal: understand the Collector and the Java agent deeply, with a fast feedback loop.
Collector and apps run in Docker Compose; **Elasticsearch stays in the k3d cluster from
Part 1**. You never build a throwaway Elasticsearch.

| Phase | File | You learn |
|---|---|---|
| 08 | [08-collector-skeleton.md](08-collector-skeleton.md) | Pipelines, OTLP, data streams, `mapping.mode: otel` |
| 09 | [09-first-app-three-signals.md](09-first-app-three-signals.md) | Java agent internals; traces, metrics, logs |
| 10 | [10-propagation-across-rabbitmq.md](10-propagation-across-rabbitmq.md) | W3C context propagation through a broker |
| 11 | [11-datastore-client-spans.md](11-datastore-client-spans.md) | Driver instrumentation for MongoDB and MinIO |
| 12 | [12-infrastructure-scraping.md](12-infrastructure-scraping.md) | Pull-based receivers, log parsing, cardinality |
| 13 | [13-kibana-observability.md](13-kibana-observability.md) | APM UI, dashboards, alerting, retention, sampling |

## Part 3 — Kubernetes-native collection

Goal: move everything you learned into the cluster, the way production will run it.

| Phase | File | You learn |
|---|---|---|
| 14 | [14-collector-on-kubernetes.md](14-collector-on-kubernetes.md) | The agent/gateway two-tier pattern |
| 15 | [15-kubernetes-enrichment.md](15-kubernetes-enrichment.md) | `k8sattributes`, cluster/kubelet receivers, discovery |
| 16 | [16-auto-instrumentation-operator.md](16-auto-instrumentation-operator.md) | OTel Operator, `Instrumentation` CRD, injection |

## Part 4 — Production

Goal: build it for real, cut over, and never let it rot again.

| Phase | File | You learn |
|---|---|---|
| 17 | [17-airgap-and-supply-chain.md](17-airgap-and-supply-chain.md) | Image mirroring, private registry, offline assets |
| 18 | [18-production-design.md](18-production-design.md) | Sizing, topology, namespaces, security, HA |
| 19 | [19-build-and-cutover.md](19-build-and-cutover.md) | Parallel run, dual ingest, cutover, decommission |
| 20 | [20-operating-the-platform.md](20-operating-the-platform.md) | GitOps, runbooks, upgrade cadence, the 8→9 path |

---

## How to use these

- **Do them in order.** Each assumes the previous one works.
- **Keep a running log.** Every phase has a *Notes* section — record what broke, the exact
  error text, and the cause. That log becomes your real reference, and it is the thing
  that was missing from the current production cluster.
- **Never mix a version bump with a config change** in the same step. When something
  breaks you want one suspect.
- **Debug in pipeline order**, always: was it generated? → did the Collector receive it?
  → did the export succeed? → is it indexed? → is it mapped for the UI? Guessing at
  random costs hours.

## Status

A Docker Compose P0 was already built against Elasticsearch 8.14.2 before this plan
existed — see [notes-per-phase.md](notes-per-phase.md) for its findings, which are still
valid and directly relevant to Phase 08. Its artifacts were removed from the working tree
during the repo reorganisation but remain in git history at commit `136c631`.

Everything else is plans. Update the checkbox as you go.

- [ ] Part 1 — ECK foundations
- [ ] Part 2 — OpenTelemetry fundamentals
- [ ] Part 3 — Kubernetes-native collection
- [ ] Part 4 — Production
