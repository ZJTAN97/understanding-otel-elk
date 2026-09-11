# Phase 04 — Topology: nodeSets, roles and storage

**Goal:** understand node roles well enough to decide whether production actually needs the
three-tier layout it currently has, rather than inheriting it.

**Prerequisites:** Phase 03.

**Artifacts produced:** `k8s/elasticsearch.yaml` grows into a multi-nodeSet definition.

**Blocked on:** Q2 (daily ingest volume, affordable node count) for the *production* sizing
conclusion. The lab exercise runs regardless.

---

## Why this phase exists

Production runs three StatefulSets: `elasticsearch-es-master`, `-es-ingest`, `-es-default`.
That is a textbook layout. The question this phase answers is whether it is the *right*
layout at your data volume, or a pattern copied from documentation written for clusters an
order of magnitude larger.

The honest answer at small scale is often: dedicated masters yes, dedicated ingest nodes
usually not — especially with the OTel Collector doing enrichment before data ever reaches
Elasticsearch (D4). If the Collector is doing the transformation work, a dedicated ingest
tier may be solving a problem you no longer have.

Decide it deliberately. Do not inherit it.

## Concepts

**Node roles.** Every node advertises `node.roles`. The ones that matter here:

| Role | Job |
|---|---|
| `master` | Cluster state, index metadata, shard allocation decisions |
| `data` | Holds shards, serves queries |
| `ingest` | Runs ingest pipelines before indexing |
| `ml`, `transform`, `remote_cluster_client` | Off unless needed — each one costs memory |

**Master quorum.** Dedicated master-eligible nodes should number **3**. Not 1, not 2, not
4. Two gives you a split-brain risk with no availability gain; even numbers add a voting
member without improving fault tolerance. Three tolerates one failure.

**Why dedicate masters at all:** a master node under heap pressure from serving queries can
stall cluster-state updates, and a stalled master looks exactly like a total cluster
outage. Isolating them means query load cannot take down cluster coordination.

**nodeSets map 1:1 to StatefulSets.** Each nodeSet gets its own StatefulSet, its own PVCs,
and its own pod template. The nodeSet `name` is part of resource names, so **renaming a
nodeSet destroys and recreates it** — a genuinely dangerous edit in production.

**A nodeSet is also the unit of rolling change.** ECK upgrades nodes within a nodeSet in
order, respecting shard allocation. This is why Phase 06 is interesting.

## Steps

### 1. Split into roles

Extend the manifest to three nodeSets. Sketch:

```yaml
  nodeSets:
    - name: master
      count: 3
      config:
        node.roles: ["master"]
        node.store.allow_mmap: false
      # small disk, modest heap - masters hold cluster state, not shards

    - name: data
      count: 2
      config:
        node.roles: ["data", "ingest"]
        node.store.allow_mmap: false
      # the bulk of your storage and heap

    # - name: ingest
    #   Only add this if Q2 volume justifies it. With the OTel Collector doing
    #   enrichment upstream, a dedicated ingest tier is often unnecessary.
```

Fill in resources and volume claims per nodeSet. Masters want small disks and modest heap;
data nodes want the opposite.

On a laptop, 3 masters plus 2 data nodes is five Elasticsearch JVMs. Shrink the heaps
(512Mi masters, 1Gi data) or temporarily drop to 1 master if Docker cannot take it — but
understand you are then rehearsing something production will not do.

### 2. Apply and watch the transition

```
kubectl apply -f k8s/elasticsearch.yaml
kubectl get pods -n elastic-stack -w
```

Watch carefully. Going from one node to five is not a create — it is a migration. Shards
must move off the old node before it can be repurposed or removed. The operator will not
just delete a node holding the only copy of data.

```
kubectl get es obs -n elastic-stack -o jsonpath='{.status}' | jq
curl --cacert /tmp/es-ca.crt -u "elastic:$PW" https://localhost:9200/_cat/nodes?v
curl --cacert /tmp/es-ca.crt -u "elastic:$PW" https://localhost:9200/_cat/shards?v
```

`_cat/nodes` shows a `node.role` column. Confirm the roles landed as declared.

### 3. Understand replicas versus nodes

Create an index with one replica and look at where the shards go:

```
PUT /test-index
{ "settings": { "number_of_shards": 2, "number_of_replicas": 1 } }
```

Then `_cat/shards`. With two data nodes, primaries and replicas sit on different nodes and
health is green. Scale data nodes to one and health goes yellow — the replica cannot be
allocated, because a replica on the same node as its primary protects against nothing.

This is why a single-node lab teaches you nothing about resilience, and why Phase 01 asked
for multiple agents.

## Deliberate exercise

**Rename a nodeSet** — change `data` to `data-hot` and apply. Watch what happens.

ECK treats it as removing one nodeSet and adding another: new StatefulSet, new PVCs, data
migrated off the old set before it is torn down. In the lab this is instructive. In
production, on a cluster with real data, this is a multi-hour full data migration triggered
by what looks like a cosmetic edit.

Learn this here rather than there.

## Done when

- Five nodes with the roles you declared, health green
- You can explain why 3 masters and not 2
- You have watched a shard relocate and can read `_cat/shards`
- **You have written down a recommendation for the production topology**, with the
  reasoning, in `18-production-design.md` — even if Q2 is still open and the numbers are
  provisional

## Notes

- 

## Next

[Phase 05 — Kibana and Ingress](05-kibana-and-ingress.md)
