# Phase 01 — Lab environment

**Goal:** a local Kubernetes cluster that is a faithful stand-in for production, plus the
tooling to work with it.

**Prerequisites:** none. This is the first phase.

**Artifacts produced:** `k3d/cluster.yaml`, a documented tool version list.

---

## Why this phase is not trivial

The single most important decision here is the Kubernetes version, and it is easy to get
wrong by accident.

Production runs **1.28.15**. If the lab runs whatever k3d installs by default (currently
much newer), then every compatibility finding you make in the lab is worthless — you would
discover that ECK 3.4 works beautifully, deploy it to production, and find it unsupported
on 1.28. The lab has to match, or it is a demo rather than a rehearsal.

## Concepts

- **k3d vs k3s vs kind.** k3s is a lightweight certified Kubernetes distribution. k3d runs
  k3s nodes as Docker containers on your machine. You pick the Kubernetes version by
  pinning the k3s image tag.
- **What k3d gives you for free:** Traefik as an ingress controller, `local-path` as a
  default StorageClass, and a `serverlb` load balancer container in front of the nodes.
  All three matter later — Traefik in Phase 05, `local-path` in Phase 04.
- **Version skew.** `kubectl` supports +/-1 minor from the API server. Your client is
  1.26.9 against a 1.28.15 server, which is outside the window. It mostly works, which is
  the problem — it fails by silently dropping or mangling fields on newer API objects.

## Steps

### 1. Fix the kubectl skew

Install a `kubectl` in the 1.27–1.29 range. Five minutes, and it removes a whole class of
confusing failures before they happen. Put it early on `PATH`, ahead of the one Docker
Desktop ships.

```
# Windows (PowerShell)
New-Item -ItemType Directory -Force "$env:USERPROFILE\bin" | Out-Null
curl.exe -Lo "$env:USERPROFILE\bin\kubectl.exe" `
  https://dl.k8s.io/release/v1.29.15/bin/windows/amd64/kubectl.exe
$env:PATH = "$env:USERPROFILE\bin;$env:PATH"
```

```
# macOS (zsh) — arm64 on Apple silicon, amd64 on Intel
mkdir -p ~/bin
ARCH=$([ "$(uname -m)" = "arm64" ] && echo arm64 || echo amd64)
curl -Lo ~/bin/kubectl "https://dl.k8s.io/release/v1.29.15/bin/darwin/$ARCH/kubectl"
chmod +x ~/bin/kubectl
export PATH="$HOME/bin:$PATH"          # and append the same line to ~/.zshrc
```

```
kubectl version
```

Confirm client and server are within one minor of each other. If the client version has
not changed, something earlier on `PATH` is winning — `Get-Command kubectl -All` on
Windows, `which -a kubectl` then `hash -r` on macOS.

### 2. Give Docker enough memory

Elasticsearch plus Kibana plus cluster overhead needs headroom. Allocate **at least 8 GB**
to Docker Desktop. Below this you will spend an evening debugging `OOMKilled` pods and
conclude, wrongly, that ECK is fragile.

### 3. Create the cluster, pinned

```
k3d cluster create elastic-lab \
  --image rancher/k3s:v1.28.15-k3s1 \
  --servers 1 \
  --agents 2
```

Two agents, not zero. A single-node cluster cannot demonstrate shard allocation across
nodes, pod anti-affinity, or what happens when a node goes away — and those are the things
Phase 04 and Phase 06 exist to teach.

Note what is **not** here: no `--port` mappings. The original `k3d-plan.md` mapped 5601
and 9200 at the load balancer, but ECK creates ClusterIP services by default, so nothing
binds those ports and the flags are dead config. Phase 05 sets up real Ingress instead,
which is what production uses.

Prefer this as a file, `k3d/cluster.yaml`, so it is in git rather than in your shell
history. That habit is the whole point.

### 4. Verify

```
kubectl get nodes -o wide
kubectl get storageclass
kubectl get pods -A
```

You should see three nodes on v1.28.15, `local-path` marked `(default)`, and Traefik
running in `kube-system`.

## Deliberate exercise

Run `kubectl get nodes` and confirm the version really is 1.28.15 and not what you
expected. Then look at what `k3d cluster create` did that you did not ask for — the
`serverlb` container, the Traefik deployment, the local-path provisioner. Every one of
these is something production either has an equivalent of or explicitly does not, and
knowing which is which stops you from writing lab-only manifests.

## Done when

- Three nodes, all `Ready`, all on v1.28.15
- `kubectl version` shows client and server within one minor
- The cluster definition lives in a file in git, not in your shell history

## Notes

Record here: what broke, exact error text, cause.

- 

## Next

[Phase 02 — ECK operator](02-eck-operator.md)
