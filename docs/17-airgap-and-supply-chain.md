# Phase 17 — Air-gap and supply chain

**Goal:** every artifact the platform needs, available inside the air-gap, by a repeatable
process.

**Prerequisites:** Phase 16.

**Artifacts produced:** an image manifest, a mirroring script, `imagePullSecrets` config.

**Blocked on:** Q3 (does an internal registry exist, and what is it?).

---

## Why this gets its own phase

Air-gapped deployments do not fail on architecture. They fail on **artifacts** — an image
that was not mirrored, a Helm chart pulled from the internet by a subchart, a plugin
downloaded at container start.

Every one of those failures happens at deploy time, in a change window, with people
watching. Doing this phase properly in the lab is what prevents that.

The current production cluster already tells you this environment is air-gapped: nobody
self-hosts `elastic-package-registry` for fun.

## Concepts

**Three categories of artifact, and only one is obvious:**

| Category | Examples | Trap |
|---|---|---|
| **Container images** | Elasticsearch, Kibana, operators, Collector, init containers | The obvious one. Still easy to miss the init containers |
| **Helm charts** | eck-operator, opentelemetry-operator | Charts may reference images by digest, or pull subcharts |
| **Runtime downloads** | Agent jars, Kibana asset packages | The dangerous one — these happen at *pod start*, not deploy |

**The runtime downloads are what bite you.** A container that starts, tries to fetch
something from the internet, fails, and enters `CrashLoopBackOff` — with an error buried in
logs that says "connection timed out" and nothing about what it wanted. This is the single
most common air-gap failure mode.

**Simulate before you migrate.** k3d can create a local registry and you can run the cluster
with no internet access. Any artifact you forgot fails in the lab, where it costs an hour,
rather than in production, where it costs a change window.

**Digests over tags.** A tag can be repointed. A digest cannot. For a platform whose
defining failure was untracked versions, pinning by digest in production manifests is worth
the small extra friction.

## Steps

### 1. Enumerate every image

Walk every manifest and Helm chart and list what it pulls. Do not forget:

- Elasticsearch and Kibana (`docker.elastic.co`)
- ECK operator
- OpenTelemetry Collector — agent and gateway
- OpenTelemetry Operator **and its auto-instrumentation image** (the init container from
  Phase 16 — very easy to miss, and it fails only when someone annotates a pod)
- cert-manager, if the OTel Operator needs it
- MinIO, if you are deploying it for snapshots (Q4)

A reliable way to find what you missed:

```
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' | sort -u
```

Run this against the *working lab* cluster. It reports reality rather than intention.

### 2. Mirror

Pull, retag to the internal registry, push. Script it — this runs again at every version
bump, and a manual process will drift.

```
for img in $(cat images.txt); do
  docker pull "$img"
  docker tag  "$img" "$REGISTRY/${img#*/}"
  docker push "$REGISTRY/${img#*/}"
done
```

Adapt to the registry's path conventions (Q3). Keep `images.txt` in git — it is a manifest
of your supply chain and it belongs under review.

### 3. Repoint the manifests

ECK takes `spec.image` on Elasticsearch and Kibana, or a global operator setting for the
container registry — the operator-level setting is cleaner, since it covers everything ECK
creates. Helm charts take `image.repository` values. Add `imagePullSecrets` where the
registry requires authentication.

### 4. Handle offline Helm charts

```
helm pull elastic/eck-operator --version <3.0.x>
```

Store the chart tarball, or push it to an internal chart repository. Do not rely on
`helm repo update` reaching the internet at deploy time.

### 5. Rehearse with no internet

Create a fresh k3d cluster configured to use only the local registry, and deploy the entire
platform. Anything you missed fails here.

**Do not skip this.** It is the whole point of the phase, and it is the only step that
proves the previous four were done correctly.

### 6. Note what you are giving up

With no Fleet and no `elastic-package-registry` (D4), you have already avoided the worst
air-gap burden — keeping a package registry version-matched to the stack forever.

What remains: Kibana sample data and integration assets are unavailable, and you build
dashboards yourself (already accepted in D4, measured in Phase 13).

## Deliberate exercise

Deliberately omit **one** image from the mirror — the OTel auto-instrumentation init
container is the ideal choice, because everything appears fine until someone annotates a
pod.

Deploy, then annotate a pod, and watch the failure. Read the error. Note how far the message
is from the actual cause: the pod is `Init:ImagePullBackOff`, and nothing tells you that
somebody forgot a line in `images.txt` three weeks ago.

Now you will recognise it in ten seconds instead of an hour.

## Done when

- Every image is enumerated in a git-tracked manifest
- Mirroring is a script, not a procedure someone remembers
- The full platform deploys in a cluster with no internet access
- Helm charts are available offline
- Production manifests pin by digest
- You have experienced and diagnosed a missing-image failure

## Notes

- 

## Next

[Phase 18 — Production design](18-production-design.md)
