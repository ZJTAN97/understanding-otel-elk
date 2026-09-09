# Phase 15 — Kubernetes enrichment and discovery

**Goal:** every signal stamped with pod, namespace, deployment and node — and scraping that
finds targets by itself.

**Prerequisites:** Phase 14.

**Artifacts produced:** RBAC manifests, `k8sattributes` config, cluster-level receivers.

---

## Why this phase matters more than it sounds

Without enrichment you have a trace that says `service.name: order-api` and nothing else.
You cannot answer "which pod?", "which node?", "was this the canary?", or "did this start
when we rolled out?".

With enrichment, every log line, metric and span carries its Kubernetes identity — and
suddenly telemetry can be joined against deployments, nodes and namespaces. This is the
difference between observability that describes your application and observability that
describes your *system*.

## Concepts

**How `k8sattributes` works.** The processor:

1. Sees a signal arrive with a source IP or pod UID
2. Looks that up against the Kubernetes API
3. Stamps on `k8s.pod.name`, `k8s.namespace.name`, `k8s.deployment.name`, `k8s.node.name`,
   labels, annotations

It needs **RBAC to list and watch pods**. Missing permissions is the number one cause of
"the processor is configured but nothing is enriched" — and it fails quietly, which is
worse.

**Why the DaemonSet placement matters.** The processor identifies pods by source IP. On the
node-local agent, the sender is on the same node and the IP resolves cleanly. Behind a
Service that load-balances, the source IP may be the gateway rather than the workload —
enrichment then attributes everything to the gateway pod. This is exactly why Phase 14 sent
app telemetry to the node-local agent.

**Cluster-level receivers, and where each belongs:**

| Receiver | Provides | Runs on |
|---|---|---|
| `k8s_cluster` | Cluster state: deployment replicas, pod phases, node conditions | **Gateway** — exactly one instance, or you get duplicates |
| `kubeletstats` | Per-node CPU, memory, filesystem, network for pods and containers | **Agent** — reads the local kubelet |
| `k8sobjects` | Kubernetes events as logs | Gateway, one instance |

Getting the placement wrong produces either duplicate metrics (cluster receiver on a
DaemonSet) or missing data (kubelet receiver on a single deployment). Both are confusing
after the fact.

**Kubernetes events as logs** is underrated. `OOMKilled`, `FailedScheduling`,
`BackOff` — correlated on the same timeline as your traces and metrics. Many production
mysteries are solved instantly by having these alongside everything else.

**Service discovery replaces hardcoded hostnames.** In Compose you scraped
`rabbitmq:15692`. In Kubernetes, the Prometheus receiver discovers targets by annotation or
by service/pod role. Scale a StatefulSet and the new pod is scraped automatically. This is
the mechanism that makes infrastructure monitoring self-maintaining rather than a list
someone must remember to update.

## Steps

### 1. RBAC first

ServiceAccount, ClusterRole, ClusterRoleBinding for the agent and gateway. The agent needs
pods, nodes and nodes/stats. The gateway needs a broader read for `k8s_cluster`.

Do this before configuring the processor, so that when enrichment does not work you have
already eliminated the most likely cause.

### 2. Add `k8sattributes` to both tiers

Configure which attributes to extract. Be selective — extracting every label and annotation
is a cardinality trap (Phase 12 taught you what that costs). Pick the ones you will actually
query by.

### 3. Verify enrichment

Look at a document in Discover. It should now carry `k8s.pod.name`, `k8s.namespace.name`,
`k8s.deployment.name`, `k8s.node.name`.

If it does not: check RBAC, then check whether the signal reached a Collector that could
resolve the source IP.

### 4. Cluster and kubelet receivers

`k8s_cluster` on the gateway. `kubeletstats` on the agent. Confirm no duplicates by
checking that a given metric has one series per node, not three.

### 5. Kubernetes events

`k8sobjects` watching Events, routed to a dedicated data stream. Then, in Kibana, put pod
events on the same timeline as application errors.

### 6. Discovery-based scraping

Convert the RabbitMQ, MongoDB and MinIO scrapes from Phase 12 to use Kubernetes service
discovery. Then scale one of them and confirm the new pod is scraped with no config change.

## Deliberate exercise

Deliberately remove the pods permission from the agent ClusterRole and restart it.

Observe: telemetry keeps flowing, but unenriched. There is no loud failure. The processor
silently adds nothing.

This is the failure mode to recognise, because the symptom appears weeks later as "why can
I not filter by namespace?" and by then nobody connects it to an RBAC change. Check the
Collector logs — is there any warning at all? Note the answer.

## Done when

- Every signal carries pod, namespace, deployment and node attributes
- Cluster-level metrics arrive exactly once, not once per node
- Kubernetes events are queryable alongside application telemetry
- Scraping finds new pods without config changes
- You can filter a trace search by `k8s.namespace.name` and get sensible results
- You have seen what missing RBAC looks like, and how quiet it is

## Notes

- 

## Next

[Phase 16 — Auto-instrumentation](16-auto-instrumentation-operator.md)
