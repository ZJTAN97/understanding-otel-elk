# Phase 02 — The ECK operator

**Goal:** install the operator the way production should have installed it, and understand
what it actually is.

**Prerequisites:** Phase 01.

**Artifacts produced:** `helm/eck-operator/values.yaml`, a pinned chart version.

---

## Why this phase is the most important one in Part 1

This is where the current production cluster went wrong, and the mistake was not technical.

The previous engineer installed ECK via raw manifests:

```
kubectl apply -f https://download.elastic.co/downloads/eck/2.13.0/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/2.13.0/operator.yaml
```

That is an officially supported install method. It is not wrong. But it leaves behind **no
release record, no chart version, and nothing in git** — so "we are on 2.13.0 and 3.x
exists" was never visible to anyone. Two years passed. The install method was fine; the
absence of a lifecycle was not.

Everything in this phase is Helm, pinned, with values in a file. Not because Helm is
better, but because it makes the version a tracked fact instead of tribal knowledge.

## Concepts

**What the operator is.** A `StatefulSet` in its own namespace running a reconciliation
loop. It watches for Elastic custom resources and drives the real cluster toward the
declared spec. Note: **StatefulSet, not Deployment** — this is exactly the confusion that
produced the "elastic-system has no deployments, probably can delete" note in
`current-infra.md:6`.

**What gets installed:**

| Object | Purpose |
|---|---|
| CustomResourceDefinitions | `Elasticsearch`, `Kibana`, `ApmServer`, `Beat`, `Agent`, `Logstash`, `EnterpriseSearch`, `ElasticMapsServer` |
| Namespace `elastic-system` | Holds operator resources only |
| ServiceAccount + ClusterRole + ClusterRoleBinding | Lets the operator manage resources across namespaces |
| **ValidatingWebhookConfiguration** | Validates Elastic resources on admission |
| StatefulSet, ConfigMap, Secret, Service | The operator itself |

**The webhook is the sharp edge.** It sits in the admission path for every Elastic custom
resource. If the operator is gone but the webhook configuration remains, `kubectl apply` on
an `Elasticsearch` will hang or be rejected — the failure mode that makes deleting
`elastic-system` so much worse than it looks.

**Namespace scoping.** By default the operator watches all namespaces. It can be restricted
to a list. This is what produces the `elastic-system` (operator) plus `eck` (workloads)
split that production already has — a sound pattern worth keeping.

## Steps

### 1. Confirm the exact chart version

Open question Q6. ECK 3.0.x is the newest line supporting Kubernetes 1.28.

```
helm repo add elastic https://helm.elastic.co
helm repo update
helm search repo elastic/eck-operator --versions | head -30
```

Pick the highest `3.0.x`. Write it down in `00-decisions.md`.

### 2. Install, pinned, with a values file

```
helm install elastic-operator elastic/eck-operator \
  --namespace elastic-system --create-namespace \
  --version <3.0.x> \
  -f helm/eck-operator/values.yaml
```

**`--version` is not optional.** Omitting it is the exact mistake that froze production.
An unpinned chart means the next person to run `helm upgrade` gets an arbitrary version.

In `values.yaml`, set at minimum the namespaces the operator manages, so the scoping is
declared rather than defaulted:

```yaml
# managedNamespaces: [elastic-stack]
# installCRDs: true
```

Check the chart README for the exact key names in 3.0.x before committing this.

### 3. Look at what you just created

```
kubectl get all -n elastic-system
kubectl get crd | grep elastic
kubectl get validatingwebhookconfiguration | grep elastic
kubectl get clusterrole,clusterrolebinding | grep elastic
```

Confirm with your own eyes that the operator is a StatefulSet.

### 4. Watch it think

```
kubectl logs -n elastic-system sts/elastic-operator -f
```

Leave this running in a second terminal for the rest of Part 1. Watching reconciliation
happen in real time as you apply manifests is the single fastest way to build a mental
model of what the operator does.

## Deliberate exercise

Apply an intentionally invalid `Elasticsearch` resource — a bogus version string, say —
and read the rejection. That message came from the **validating webhook**, not from the
API server and not from Elasticsearch. You have now seen the component that would break
cluster-wide if the operator were deleted while its webhook config remained.

## Done when

- The operator pod is `Running` and its logs show a healthy reconcile loop
- You can list the CRDs it installed and explain what the webhook is for
- The chart version is pinned in a values file in git
- You can state why `kubectl get deploy -n elastic-system` returns nothing

## Notes

- 

## Next

[Phase 03 — Elasticsearch basics](03-elasticsearch-basics.md)
