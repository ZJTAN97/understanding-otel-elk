# Phase 14 — The Collector on Kubernetes

**Goal:** the two-tier agent/gateway pattern running in k3d, replacing the Compose
Collector.

**Prerequisites:** Phase 13.

**Artifacts produced:** `k8s/otel/daemonset.yaml`, `k8s/otel/gateway.yaml`, ConfigMaps.

**Blocked on:** Q1 (what is actually collected today) — the DaemonSet must cover the same
ground the current platform does.

---

## What changes and what does not

The *concepts* do not change at all. Receivers, processors, exporters, pipelines,
semantic conventions — all identical to Part 2. **The deployment mechanics change
completely, and that is the entire lesson.**

Keep the Compose stack working. Being able to run both and diff them is the fastest way to
isolate whether a problem is an OTel problem or a Kubernetes problem.

## Concepts

**Why two tiers.** This is the central design idea, and it is worth being able to defend.

```
   node 1              node 2              node 3
  +--------+          +--------+          +--------+
  | agent  |          | agent  |          | agent  |     DaemonSet - one per node
  +---+----+          +---+----+          +---+----+
      |                   |                   |
      +---------+---------+---------+---------+
                          |
                   +------+-------+
                   |   gateway    |               Deployment - a few replicas
                   +------+-------+
                          |
                   Elasticsearch
```

| Tier | Handles | Why it must be there |
|---|---|---|
| **Agent** (DaemonSet) | Node-local concerns: container logs on that node's filesystem, kubelet metrics, receiving OTLP from pods on the same node | Only a process on the node can read that node's log files. Node-local OTLP also avoids a network hop |
| **Gateway** (Deployment) | Cluster-wide concerns: batching, tail sampling, enrichment, the single egress to Elasticsearch | Tail sampling needs *all* spans of a trace in one process — impossible on a DaemonSet. And you want one controlled egress point, not one connection per node |

**Tail sampling forces this design.** A DaemonSet sees only the spans from its own node. A
trace spanning three services on three nodes would be sampled inconsistently. The gateway
exists so complete traces land in one place.

**The gateway is also your blast radius control.** Credentials for Elasticsearch live in
one tier, not on every node. Retry and queue behaviour is configured once. Backpressure is
visible in one place.

**Config as ConfigMaps.** Collector config becomes a ConfigMap. Note that **Collectors do
not reload config on ConfigMap change** by default — you must roll the pods. This surprises
people and is worth knowing before an incident.

**RBAC.** The agent needs to read node-level resources; the `k8sattributes` processor
(Phase 15) needs to read pods. Both need ServiceAccounts with real permissions. This is
new relative to Compose and is a common source of confusing "it works locally" failures.

## Steps

### 1. Answer Q1 first

Before writing the DaemonSet config, establish what the current production platform
actually collects. The new pipeline has to cover the same ground, or the cutover in Phase
19 loses visibility that people depend on.

Deciding to ignore the old *cluster* (D1) is not the same as ignoring what it *monitors*.

### 2. Deploy the gateway

A Deployment with 2+ replicas and a Service in front. Config: OTLP receiver, batch, and the
`elasticsearch` exporter.

The exporter config carries over almost verbatim from Phase 08 — with two changes that are
both improvements:

- The endpoint becomes in-cluster DNS: `https://obs-es-http.elastic-stack.svc:9200`
- The CA comes from mounting the `obs-es-http-certs-public` Secret directly, rather than a
  file you copied by hand

That second point is worth pausing on: in Kubernetes, ECK certificate management becomes
*easier* than it was in Compose, because the Secret is right there.

### 3. Deploy the agent DaemonSet

Config: OTLP receiver (for pods on the node), `filelog` reading
`/var/log/pods/*/*/*.log`, `kubeletstats` for node and pod metrics. Exporter: OTLP to the
gateway Service.

Mount the host log directory read-only. Set `hostNetwork` only if you genuinely need it —
prefer not to.

### 4. Point the apps at the agent

Apps should send OTLP to the agent on **their own node**, not to a Service that
load-balances across nodes. Use the downward API:

```yaml
env:
  - name: NODE_IP
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://$(NODE_IP):4317"
```

This is the idiomatic pattern and worth understanding: it keeps the first hop local, which
matters for both latency and for the agent being able to correlate the sender with a pod on
its own node.

### 5. Verify end to end

Same data as Compose produced, now arriving via two tiers. Diff the documents between the
Compose path and the Kubernetes path — they should be nearly identical except for resource
attributes, which is exactly what Phase 15 is about.

## Deliberate exercise

Kill the gateway entirely:

```
kubectl scale deploy otel-gateway --replicas=0
```

Watch the agents. What happens to data during the outage? Does the agent queue it, drop it,
or block? For how long? Check the agent's own self-telemetry for refused and dropped counts.

Then scale back up and determine whether the queued data arrived or was lost.

**This tells you the real durability guarantee of your pipeline**, which is something you
must know *before* an incident rather than during one. Write the answer into
`20-operating-the-platform.md`.

## Done when

- Agent DaemonSet on every node, gateway Deployment with multiple replicas
- Container logs and kubelet metrics arriving via the agent tier
- Apps sending to their node-local agent via the downward API
- Elasticsearch credentials and CA exist only in the gateway tier
- You know exactly what happens when the gateway is unavailable
- The Compose stack still works, so you can diff the two

## Notes

- 

## Next

[Phase 15 — Kubernetes enrichment](15-kubernetes-enrichment.md)
