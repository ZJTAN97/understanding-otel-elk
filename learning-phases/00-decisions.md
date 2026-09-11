# Decision record

Everything decided so far, why, and what is still open. This file is the contract the
rest of the phases are built on. If a decision here changes, phases change with it.

---

## D1 — Greenfield build, not an in-place upgrade

**Decision:** build a new Elastic cluster alongside the existing one. Do not upgrade
8.14.2 in place.

**Why:**

- **Elasticsearch has no downgrade path.** Once a node writes 9.x metadata into its data
  path, that data path is 9.x forever. The only rollback from a failed major upgrade is
  restore-from-snapshot.
- **There are no snapshots.** `GET _snapshot` on the production cluster returns `{}` — no
  repository has ever been registered. So the only rollback mechanism does not exist.
- **Nothing is tracked in git.** The upgrade could not be rehearsed, because there is no
  declarative description of what would be rehearsed.
- **The environment is air-gapped.** When something breaks mid-upgrade you cannot pull a
  patched image or reach support quickly. Recovery is measured in change requests.
- **Capacity exists.** The constraint that normally forces in-place upgrades — no room to
  run two copies — does not apply here.

Irreversible + untracked + unrehearsable + air-gapped is three of the four things that
make a change dangerous. Blue/green is the standard practice for major upgrades of
stateful systems; in-place is the compromise you accept when you cannot afford two
copies. We can afford two copies.

**Consequence:** the old cluster keeps running untouched and becomes its own rollback.

## D2 — No data migration; parallel run and age-out

**Decision:** the new cluster takes new data only. The old cluster goes read-only, stays
queryable for historical questions, and is deleted after one retention window.

**Why:** retention is ~30 days. A 30-day parallel run costs nothing but capacity, which
we have, and it removes the entire snapshot-restore/reindex migration project — including
the risk that indices originally created under 7.x refuse to restore into a 9.x cluster.

**Revisit if:** anyone needs multi-year history queryable in the *new* cluster. Then we
fall back to snapshot-restore migration for the archives only.

## D3 — Target versions

The binding constraint is Kubernetes, not Elasticsearch.

| Layer | Pin | Rationale |
|---|---|---|
| Kubernetes | **1.28.15** *(existing)* | Fixed for now. Itself past upstream EOL |
| k3d lab image | **`rancher/k3s:v1.28.15-k3s1`** | Lab must match prod, or compatibility findings do not transfer |
| ECK operator | **latest 3.0.x** | Newest ECK supporting k8s 1.28 (3.0 = 1.28–1.32). Exact patch tag TBC |
| Elasticsearch | **8.19.21** | Latest 8.x, and the only 8.x line still supported |
| Kibana | **8.19.21** | Must match Elasticsearch exactly |

ECK version support ladder, for reference:

| ECK | Kubernetes |
|---|---|
| 3.4 (latest) | 1.31 – 1.36 |
| 3.2 | 1.30 – 1.34 |
| 3.1 | 1.29 – 1.33 |
| **3.0** | **1.28 – 1.32** ← us |
| 2.16 | 1.27 – 1.32 |

**Why 8 and not 9:** deliberate sequencing, not avoidance. 8.19 reaches end-of-life
**15 July 2027** — roughly ten months out. Staying on 8 defers the major upgrade onto a
cluster that will by then be in git, backed up, rehearsed, and running an operator that
already supports 9.x. That is a far better place to perform a major upgrade from than
where we are today.

**Two consequences that must not be forgotten:**

1. The 8→9 hop is planned, not avoided. Phase 06 rehearses it in the lab.
2. **The Kubernetes upgrade is on the critical path.** 1.28 is past upstream EOL and is
   what pins us to ECK 3.0. It does not block this build but it blocks everything after
   it. Open that conversation with the cluster owners early — it will move slowly.

## D4 — Ingest architecture: OpenTelemetry Collector

**Decision:** collect with the OpenTelemetry Collector in a two-tier agent/gateway
pattern. Do not rebuild Fleet. Do not deploy APM Server.

**Why not Fleet — the decisive argument:**

Fleet policies live in Kibana saved objects and the `.fleet-*` indices. They are clicked
into a UI. They cannot be meaningfully version-controlled, reviewed, or diffed. The
defining failure of the current platform is *"nothing was tracked."* Rebuilding on Fleet
structurally reintroduces that exact failure, by design.

In an air-gapped environment Fleet additionally drags along Fleet Server *and* a
self-hosted `elastic-package-registry` that must be kept version-matched to the stack —
two stateful components whose only job is distributing config that could have been a file
in git.

**Why OTel over standalone Elastic Agent** — both fix the git problem, so the tiebreakers
are:

| | Standalone Elastic Agent | OTel Collector |
|---|---|---|
| Config in git | yes | yes |
| Air-gap footprint | one image | one image |
| Vendor lock-in | Elastic-specific | portable |
| Prebuilt dashboards | ECS assets, manual install | you build them |
| Converges with the OTel learning track | no — two tracks forever | yes — one effort |

1. **We are rebuilding anyway.** This is the only moment where portability is free.
   Instrumentation outlives backends.
2. **It collapses two projects into one.** The learning track and the build track become
   the same work, instead of studying one architecture while operating another.

8.19 clears the version bar: `mapping.mode: otel` requires ES >= 8.12 and is solid from
8.16 onward.

**Accepted cost:** you build dashboards yourself rather than getting Elastic integration
assets for free. Phase 13 is where that bill comes due.

## D5 — Distribution (upstream vs EDOT): deferred to Phase 16

Start with upstream `opentelemetry-collector-contrib` in the lab — you learn every knob
yourself. Decide upstream vs **EDOT** (Elastic distribution of OpenTelemetry) at Phase 16,
based on how well Kibana out-of-the-box assets cover OTel-native documents on 8.19.

Safe to defer because it is the same configuration language either way, so switching is
cheap. This is not a fork you can get wrong.

## D6 — Part 2 runs on Compose, but against the real Elasticsearch

**Decision:** in Part 2, the Collector and sample apps run in Docker Compose while
Elasticsearch and Kibana stay in the k3d cluster built in Part 1.

**Why:** OTel pipeline mechanics, semantic conventions and Java agent behaviour are not
Kubernetes concepts. Learning them inside Kubernetes adds pod restarts, ConfigMap reload
semantics, image pulls and RBAC to every single edit — friction with no teaching value.
But standing up a *second, throwaway* Elasticsearch in Compose is equally wasteful: you
would be learning an Elasticsearch deployment you will never operate.

Splitting it this way gives a fast edit-restart loop for the parts that need one, while
every document you produce lands in the same ECK-managed cluster you are building toward.

---

## Superseded

- **`k3d-plan.md`** — the original ECK smoke test. Superseded by phases 01–07, which do
  the same thing as a production rehearsal rather than a demo.
- **`PLAN.md`** — still the best statement of *what* to learn about OpenTelemetry, and
  phases 08–16 draw heavily on it. But its sequencing is superseded: it assumed a
  throwaway Compose stack with Kubernetes deferred to the very end (P6), which would pile
  security, certificates and Kubernetes into one step and violate its own "at most one new
  concept" rule. Its version pins (ES 9.5.0) are superseded by D3.
- **`current-infra.md:6`** — *"elastic-system got no deployments, probably can delete."*
  **Wrong and dangerous.** The ECK operator runs as a **StatefulSet**, not a Deployment.
  `kubectl get deploy -n elastic-system` returning nothing is expected output. Deleting
  that namespace would strand every Elastic resource with no reconciliation, and the
  orphaned `ValidatingWebhookConfiguration` would begin rejecting or hanging Elastic API
  calls cluster-wide.

---

## Open questions

Tracked here until answered. Each names the phase it blocks.

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | **What is actually being collected today?** Container logs? Node metrics? Application APM? Specific integrations? The new pipeline must cover the same ground. "Ignore the old cluster" is not the same as "ignore what it monitors." | 14, 18 | **open** |
| Q2 | Daily ingest volume and affordable node count | 04, 18 | open |
| Q3 | Does an internal image registry exist in the air-gap, and what is it? | 17 | open |
| Q4 | Is there existing S3-compatible object storage, or do we deploy MinIO for snapshots? | 07, 18 | open |
| Q5 | Same Kubernetes cluster (new namespaces) or a new one? | 18 | open |
| Q6 | Exact latest ECK 3.0.x patch tag | 02 | trivial, confirm at build time |
| Q7 | Licence tier — Basic vs a paid tier. Affects alerting, SLO and ML availability | 13 | open |

## Facts established

Recorded so they never have to be rediscovered.

- Production Elasticsearch and Kibana: **8.14.2**, ECK operator **2.13.0**, both roughly
  two years stale. 8.14 is past end-of-support.
- Kubernetes: client 1.26.9, **server 1.28.15**. The client is one minor outside the
  supported +/-1 skew window — upgrade it; it silently mangles newer API fields.
- **Zero snapshot repositories registered.** No backups exist.
- **Zero active Fleet agents**, despite a running `elastic-agent` DaemonSet, an
  `apm-server`, a `fleet-server-agent` and an `elastic-package-registry`. A significant
  part of the current deployment is vestigial.
- **Data is flowing** — source not yet established. See Q1.
- Self-hosted `elastic-package-registry` strongly implies the environment is air-gapped
  (confirmed).
- Nothing is in git. No GitOps, no manifests of record. This is the root cause of the
  two-year version freeze, and it is the failure this whole plan exists to fix.

## Prior work: the P0 index template finding

A Docker Compose P0 was built against **Elasticsearch 8.14.2** before this plan existed.
Its findings are in [notes-per-phase.md](notes-per-phase.md) and one of them is a strong,
independent confirmation of D3:

**`mapping.mode: otel` expects the `otel-data` index templates that ship with
Elasticsearch 8.16+.** On 8.14.2 they do not exist, and the failure is misleading rather
than obvious:

1. `logs-*-*` and `metrics-*-*` have built-in templates so those data streams appear,
   while `traces-*` does not — a **partial success** that looks like a traces-specific bug
2. Once a traces template exists, metrics then fail with
   `Can't find dynamic template for dynamic template name [gauge_long]` — the exporter
   references dynamic templates **by name** (`counter_long`, `gauge_long`,
   `counter_double`, `gauge_double`, `histogram`, `summary_metrics`), and rejects every
   metric document if the index template does not define them

The workaround was hand-writing what 8.16 would have shipped: an `otel-common@mappings`
component template plus one index template per signal at `priority: 200`.

**On 8.19.21 (D3) this entire class of work disappears** — the templates ship natively,
including the TSDB metrics mapping the hand-rolled version deliberately skipped. That is a
concrete, already-paid-for reason the version choice in D3 is correct, discovered the hard
way rather than from documentation.

Other findings from that work worth carrying into Phase 08:

- OTel `@timestamp` arrives as epoch millis **with a fractional part**. Map it as
  `date_nanos`, not `date`, or you silently lose precision
- Span `duration` is **nanoseconds**
- Dynamic mapping turns attributes into `text` + `.keyword`, which breaks `terms`
  aggregations on `resource.attributes.service.name`. OTel attributes are dimensions and
  belong as `keyword`
- On export failure: `send_failed_*` climbing while `queue_size` sits at 0 means data was
  **already dropped**. `queue_size` climbing means back-pressure with data still in
  flight. The default in-memory sending queue is also lost on Collector restart
- The `debug` exporter still prints records that Elasticsearch later rejected. It proves
  the receiver and processors work and says **nothing** about whether anything was indexed
- `batch.timeout` plus the ES refresh interval means ~10s before a document is searchable.
  Several "nothing arrived" moments were impatience

## Sources

- [ECK supported versions (current)](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-supported.html)
- [ECK 3.0 supported versions](https://www.elastic.co/guide/en/cloud-on-k8s/3.0/k8s-supported.html)
- [ECK 2.16 supported versions](https://www.elastic.co/guide/en/cloud-on-k8s/2.16/k8s-supported.html)
- [Elasticsearch end-of-life dates](https://endoflife.date/elasticsearch)
- [cloud-on-k8s releases](https://github.com/elastic/cloud-on-k8s/releases)
