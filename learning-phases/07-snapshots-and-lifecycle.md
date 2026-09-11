# Phase 07 — Snapshots and data lifecycle

**Goal:** working automated snapshots, a verified restore, and an ILM policy — the three
things production has never had.

**Prerequisites:** Phase 06.

**Artifacts produced:** `k8s/minio.yaml` (or equivalent), `k8s/snapshot-repository.yaml`,
SLM and ILM policy definitions.

**Blocked on:** Q4 (does S3-compatible storage already exist in the air-gap?) for the
production form. The lab exercise uses MinIO regardless.

---

## Why this phase is not optional

`GET _snapshot` on the production cluster returns `{}`. Two years of observability data,
protected by nothing but the PVCs it sits on. Phase 06 exercise 5 showed you exactly what a
node loss does to node-local storage.

Snapshots are not an upgrade prerequisite here — decision D1 removed that dependency by
keeping the old cluster as its own rollback. They are a **day-one design element of the new
cluster**, so that the new platform never inherits the old one's single point of failure.

A backup you have never restored is not a backup. This phase ends with a verified restore.

## Concepts

**Snapshots are incremental at the segment level.** The first is full; subsequent ones copy
only new segments. So a daily snapshot of a 30-day-retention cluster is far cheaper than
30x the data — but it is not free, and old snapshots pin the segments they reference.

**Repository options in an air-gapped environment:**

| Type | Fit here |
|---|---|
| **S3-compatible** (MinIO) | Best fit. `repository-s3` is bundled in 8.x, no plugin install |
| **Shared filesystem** | Needs `path.repo` in the ES config plus a ReadWriteMany volume mounted at the same path on every data node. Awkward but viable |
| Azure / GCS / HDFS | Not applicable in an air-gap |

MinIO is also already in the plan for Phase 11 as an instrumentation target, so it earns
its keep twice.

**SLM (Snapshot Lifecycle Management)** schedules snapshots and expires old ones. Without
it you have a manual process that will be forgotten, which is functionally the same as
having nothing.

**ILM is a different thing and solves a different problem.** Snapshots protect against
loss. ILM manages cost and performance as data ages: hot → warm → cold → delete. With 30-day
retention and OTel data, your ILM policy is the thing that decides how much disk the
platform consumes.

**Data streams.** OTel data lands in data streams (`traces-*`, `logs-*`, `metrics-*`),
which are append-only and backed by rolling hidden indices. They are managed by ILM or by
data stream lifecycle. Understanding this now makes Phase 08 much less mysterious, because
you will already know why documents appear in an index named something like
`.ds-logs-generic-default-2026.09.09-000001`.

## Steps

### 1. Deploy MinIO in the lab

A single-node MinIO Deployment plus a Service and a PVC. Create a bucket for snapshots.
Keep it simple — this is a means to an end.

### 2. Give Elasticsearch the S3 credentials

Credentials go in the **Elasticsearch keystore**, not in a config file. ECK supports this
via `spec.secureSettings` referencing a Kubernetes Secret. The keys you need are
`s3.client.default.access_key` and `s3.client.default.secret_key`.

This is a genuinely useful ECK feature to learn: it is how any sensitive Elasticsearch
setting gets managed declaratively.

### 3. Register the repository

```
PUT _snapshot/minio
{
  "type": "s3",
  "settings": {
    "bucket": "es-snapshots",
    "endpoint": "minio.elastic-stack.svc:9000",
    "protocol": "http",
    "path_style_access": true
  }
}
```

`path_style_access: true` is usually required for MinIO. Then verify:

```
POST _snapshot/minio/_verify
```

This is the command whose production equivalent currently returns nothing at all.

### 4. Take a snapshot

```
PUT _snapshot/minio/manual-1?wait_for_completion=true
GET _snapshot/minio/_all
```

### 5. Automate with SLM

```
PUT _slm/policy/daily
{
  "schedule": "0 30 1 * * ?",
  "name": "<daily-{now/d}>",
  "repository": "minio",
  "config": { "indices": ["*"], "include_global_state": true },
  "retention": { "expire_after": "60d", "min_count": 10, "max_count": 100 }
}
```

Note `include_global_state: true` — that captures cluster settings, ILM policies, and
templates, not just data. A restore without it rebuilds your data into a cluster that has
forgotten how to manage it.

Trigger it manually to confirm rather than waiting for the schedule:

```
POST _slm/policy/daily/_execute
```

### 6. Restore — the step people skip

Delete an index, restore it, verify the document count matches.

Better, if you have capacity: create a **second** k3d cluster, point it at the same MinIO
bucket, and restore into it. That rehearses the actual disaster scenario — the original
cluster is gone — rather than the easy one.

### 7. An ILM policy for OTel data

Sketch a policy matching your 30-day retention: hot for recent data, delete at 30 days.
Attach it via an index template covering the OTel data streams.

Revisit this in Phase 13 once you know what the data volume and query patterns actually
look like. Setting it now means you never accidentally run without one.

## Deliberate exercise

Restore a snapshot **into a cluster that does not have the index templates**, by using
`include_global_state: false`. Look at the resulting mappings.

You will get your data back with dynamically-guessed field types instead of the intended
ones — which means aggregations break, dashboards break, and the data is technically
present but functionally useless. This is why global state matters, and it is a mistake
best made in a lab.

## Done when

- SLM runs on a schedule and you can list successful snapshots
- **You have performed a restore and verified document counts**
- An ILM policy is attached to a data stream and you can explain each phase
- Credentials are in the keystore via `secureSettings`, not in plaintext
- All of it is in git

## Notes

- 

## Next

Part 1 complete. You now understand ECK well enough to design the production cluster.

[Phase 08 — Collector skeleton](08-collector-skeleton.md)
