# Phase 19 — Build, parallel run, cutover

**Goal:** the new platform live in the air-gap, the old one decommissioned, and no
visibility lost in between.

**Prerequisites:** Phase 18, reviewed.

**Artifacts produced:** a running production platform; a decommissioning record.

---

## The plan (D1, D2)

```
  build --> dual ingest --> validate --> cutover --> read-only --> delete
            |                                       |
            +--- both platforms receiving ----------+
                        ~30 days
```

No data migration. The old cluster receives nothing new, stays queryable for its retention
window, then goes away.

**The old cluster is the rollback.** For the whole parallel period, reverting means
repointing collection back at it. That is the property the entire greenfield decision was
built to obtain — do not compromise it by decommissioning early.

## Step 1 — Build

Deploy the Phase 18 manifest set. From git, via Helm, pinned, from the internal registry.

Verify against the lab checklist:

- Cluster health green, expected node roles
- Kibana reachable through Ingress with an organisation-issued certificate
- Snapshot repository registered and **verified** — `POST _snapshot/<repo>/_verify`
- SLM policy scheduled and manually triggered once, successfully
- ILM policies attached to templates
- Collector agent DaemonSet on every node, gateway with multiple replicas
- Self-telemetry dashboard populating (Phase 13)

**Take a snapshot before any real data arrives.** It costs nothing and it establishes that
the mechanism works on production storage rather than on MinIO in a lab.

## Step 2 — Dual ingest

Send telemetry to **both** platforms simultaneously.

The Collector makes this easy — one pipeline, two exporters:

```yaml
service:
  pipelines:
    traces:
      exporters: [elasticsearch/new, elasticsearch/old]
```

Whether the old platform can accept OTel data depends on Q1 — if it is ingesting via
Elastic Agent or APM Server, you may not be able to feed it from the Collector at all. In
that case dual ingest means **leaving the existing collection running untouched** while the
new pipeline runs alongside it. That is usually simpler and is the safer default: do not
modify the old platform during cutover. It is your rollback; changing it weakens it.

**Watch for double-counting.** If both platforms scrape the same infrastructure endpoints,
you now have two scrapers. Harmless for metrics correctness, but it doubles load on the
scraped component — check that RabbitMQ and MongoDB tolerate it.

## Step 3 — Validate

Do not shorten this. Run in parallel long enough to see:

- A full business cycle, including a weekend and a month-end if relevant
- A deployment of an instrumented application
- At least one real incident, or a deliberately induced one

**Compare the two platforms against the Q1 coverage map.** For every row, confirm the new
platform answers the same question the old one did. This is the actual acceptance test.

Then validate with the people who use it. A platform that satisfies your checklist and not
the on-call engineer's workflow has not been validated. Ask them to investigate something
using only the new platform, and watch where they get stuck.

## Step 4 — Cutover

Point the alerting and the dashboards people actually use at the new platform. Update
runbooks and links. Tell everyone, with a date.

**Stop new data into the old platform.** Do not delete anything.

## Step 5 — Read-only, then gone

The old cluster now holds up to 30 days of history and receives nothing.

- Keep it queryable, with its ingress intact
- Announce the deletion date up front — one retention window out
- Take one final snapshot before deletion **if** anyone might want the history later. This
  is the cheap insurance that makes the deletion irreversible-but-recoverable
- On the date, delete it

**Decommission in dependency order, and mind the trap from `00-decisions.md`:**

1. Elastic resources first — `Elasticsearch`, `Kibana`, `ApmServer`, `Agent`, `Beat` in the
   `eck` namespace
2. Then the PVCs, explicitly. They **survive** resource deletion (Phase 06 exercise 6) and
   will silently keep consuming storage
3. Then the ingresses and any remaining workloads
4. **Only then** the ECK 2.13.0 operator in `elastic-system` — and with it the
   `ValidatingWebhookConfiguration`

Reversing steps 1 and 4 is the mistake `current-infra.md:6` was about to make. Removing the
operator first strands every Elastic resource with no reconciliation, and the orphaned
webhook then rejects or hangs Elastic API calls **cluster-wide** — including calls to your
new platform if it shares the cluster (Q5).

If the two platforms share a cluster, verify before each deletion that you are acting on
the old namespace. `kubectl config set-context --namespace` and a slow, explicit
`--namespace` on every command.

Record what was deleted and when.

## Deliberate exercise

**Rehearse the rollback while you still can.** Midway through the parallel run, actually
repoint collection back to the old platform for an hour, then forward again.

An untested rollback is a plan, not a capability. This is the last moment where testing it
is free.

## Done when

- The new platform is the one people use
- The Q1 coverage map is fully satisfied
- Alerting fires from the new platform and has been seen to work
- The old platform is deleted, PVCs included, in the correct order
- The rollback was tested, not just documented
- Everything deployed came from git

## Notes

- 

## Next

[Phase 20 — Operating the platform](20-operating-the-platform.md)
