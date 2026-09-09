# Phase 06 — Operations: upgrades, failure, scaling

**Goal:** know exactly what ECK automates, what it refuses to do, and what it will happily
let you destroy.

**Prerequisites:** Phase 05.

**Artifacts produced:** operational notes; the beginnings of `20-operating-the-platform.md`.

---

## Why this is the most valuable phase in Part 1

Everything before this was setup. This is the phase that rehearses the thing you are
actually signing up for: **operating an Elastic cluster through version changes for years.**

The current production cluster sat on 8.14.2 for two years partly because nobody knew what
an upgrade would do. After this phase, you will.

Do these exercises deliberately, in order, and write down what you observe. This section is
the raw material for your production runbooks.

## Exercise 1 — A patch upgrade

Change `spec.version` from `8.19.21` to a slightly newer patch (or start the lab a patch
behind so you have somewhere to go), apply, and watch.

```
kubectl apply -f k8s/elasticsearch.yaml
kubectl get pods -n elastic-stack -w
```

**What to observe and write down:**

- Which nodeSet upgrades first? (masters or data — and can you reason about why?)
- How many pods are down at once
- What ECK does with shard allocation before taking a data node down. Look for it
  disabling allocation, or using the shutdown API
- How long one node takes, and therefore how long a full production upgrade would take
- Does cluster health ever go red, or only yellow?

That last question matters enormously: yellow means degraded but serving; red means data
unavailable. A well-executed rolling upgrade should never go red.

## Exercise 2 — A minor upgrade, and then the 8→9 hop

Repeat with a minor version change. Then — and this is the point — **rehearse the 8.19 to
9.x upgrade in the lab.**

Per D3 you are deliberately deploying 8.19 to production, which reaches end-of-life in
July 2027. That upgrade is coming. Doing it here, on disposable data, tells you:

- Whether ECK 3.0 handles it cleanly (it supports both 8.x and 9.x, so it should)
- What the Upgrade Assistant flags
- Whether any index compatibility issues appear
- Roughly how long it takes

Write the findings into `20-operating-the-platform.md`. When the real upgrade is scheduled,
you will already have done it once.

## Exercise 3 — Try to downgrade

Set `spec.version` back to a lower version and apply.

Watch it be rejected, and note *which* component rejected it — this is the validating
webhook from Phase 02 doing its job. Elasticsearch does not support downgrade, and ECK
enforces that rather than letting you destroy a cluster.

**This is the single fact that drove decision D1.** Seeing the refusal yourself makes the
greenfield decision concrete rather than theoretical.

## Exercise 4 — Resource changes

Change the memory limit and `ES_JAVA_OPTS` heap on a nodeSet. Apply.

Observe that this is also a rolling restart — a change that looks like editing a number is
a full cluster roll. Note the implication for production change windows: *any* podTemplate
edit costs you a rolling restart.

## Exercise 5 — Node failure

```
kubectl delete pod obs-es-data-0 -n elastic-stack --force
docker stop k3d-elastic-lab-agent-0
```

Two different failures. The first is a pod dying; the second is a whole node vanishing,
taking its `local-path` volume with it.

**Observe the difference.** A pod restarting reattaches to its PVC and rejoins with its
data intact. A node disappearing with `local-path` storage means the PVC is stranded — the
pod cannot be rescheduled elsewhere because its volume is node-local.

This is the moment to understand your production StorageClass. If production also uses
node-local storage, a node loss means shard rebuild from replicas, not a quick reschedule.
That is survivable with replicas and fatal without them.

Bring the node back with `docker start` and watch recovery.

## Exercise 6 — Scaling down, and the PVC trap

Reduce a data nodeSet from 2 to 1 and apply.

ECK migrates shards off the departing node before removing it. Watch it happen. Note that
it takes real time proportional to data size — scaling down is not instant, and cannot be.

Then the important part:

```
kubectl delete -f k8s/elasticsearch.yaml
kubectl get pvc -n elastic-stack
```

**The PVCs survive.** Deleting the Elasticsearch resource does not delete your data
volumes. This is deliberate and it protects you — but it also means:

- Reapplying the manifest reuses the existing data
- The volumes cost storage until explicitly deleted
- A "clean" reinstall that does not delete PVCs is not clean, and will behave confusingly

Confirm the current default retention policy for your ECK version, then delete the PVCs
explicitly and reapply, and note the difference.

## Deliberate exercise

Break a rolling upgrade on purpose. Set a resource limit far too low for Elasticsearch to
start, apply, and watch the roll get stuck.

Then answer: **how do you get out?** Does ECK roll back on its own? (It does not — it keeps
trying to reach the declared state.) Does reverting the manifest recover cleanly? How long
does the cluster stay degraded?

Knowing the recovery path for a stuck upgrade is worth more than knowing the happy path,
because the happy path does not need you.

## Done when

You can answer all of these from your own observation, not from documentation:

- What does ECK do before taking a data node down?
- Does a rolling upgrade take the cluster red?
- What happens if you try to downgrade?
- What happens to PVCs when you delete an Elasticsearch resource?
- How do you recover from a stuck rolling upgrade?
- Roughly how long would upgrading production take, extrapolating from lab timings?

## Notes

- 

## Next

[Phase 07 — Snapshots and lifecycle](07-snapshots-and-lifecycle.md)
