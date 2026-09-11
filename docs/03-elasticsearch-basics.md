# Phase 03 — First Elasticsearch

**Goal:** one working Elasticsearch node, and a complete understanding of everything the
operator generated to make it work.

**Prerequisites:** Phase 02.

**Artifacts produced:** `k8s/elasticsearch.yaml`.

---

## Concepts

**The `Elasticsearch` CRD is small; what it generates is not.** Twenty lines of YAML
produce a StatefulSet, three Services, several Secrets, a PodDisruptionBudget, and a
complete internal PKI. The value of this phase is enumerating all of it, once, so that
nothing in production is a mystery.

**TLS is on by default and cannot be casually disabled.** ECK generates a self-signed CA,
issues an HTTP certificate and per-node transport certificates, and rotates them. This is
a real difference from the Docker Compose learning setups you may have seen (and from
`PLAN.md:312`, which disabled security for phases P0–P5). Here, security is on from the
first minute — which is the right call, because it is on in production.

**Two separate certificate concerns:**

| | Purpose |
|---|---|
| **Transport** | Node-to-node traffic inside the cluster. Fully operator-managed, mTLS, you never touch it |
| **HTTP** | Client-facing. Self-signed by default; Phase 05 replaces it for external access |

**Generated secrets you should know by name:**

| Secret | Contains |
|---|---|
| `<name>-es-elastic-user` | The `elastic` superuser password |
| `<name>-es-http-certs-public` | The CA certificate clients need |
| `<name>-es-http-certs-internal` | Server cert and key |
| `<name>-es-transport-certs-public` | Transport CA |
| `<name>-es-internal-users` | Accounts the operator itself uses to talk to the cluster |

**Three services, not one:**

| Service | Use |
|---|---|
| `<name>-es-http` | What clients connect to |
| `<name>-es-transport` | Headless, for node discovery |
| `<name>-es-internal-http` | Operator-only |

## Steps

### 1. A minimal Elasticsearch

Create `k8s/elasticsearch.yaml`. Deliberately minimal — one nodeSet, one node.

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: obs
  namespace: elastic-stack
spec:
  version: 8.19.21
  nodeSets:
    - name: default
      count: 1
      config:
        node.store.allow_mmap: false
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            accessModes: [ReadWriteOnce]
            resources:
              requests:
                storage: 10Gi
            storageClassName: local-path
      podTemplate:
        spec:
          containers:
            - name: elasticsearch
              resources:
                requests:
                  memory: 2Gi
                  cpu: 1
                limits:
                  memory: 2Gi
              env:
                - name: ES_JAVA_OPTS
                  value: "-Xms1g -Xmx1g"
```

Three things worth understanding rather than copying:

- **`node.store.allow_mmap: false`** — Elasticsearch memory-maps index files and wants
  `vm.max_map_count=262144`. On a laptop that sysctl lives inside the Docker Desktop VM,
  not in the k3d containers, and does not persist across restarts either way:

  ```
  # Windows (PowerShell) — the docker-desktop WSL distro
  wsl -d docker-desktop sysctl -w vm.max_map_count=262144

  # macOS (zsh) — the LinuxKit VM, entered via a privileged container
  docker run --rm --privileged --pid=host alpine \
    nsenter -t 1 -m -u -n -i sysctl vm.max_map_count          # check first
  docker run --rm --privileged --pid=host alpine \
    nsenter -t 1 -m -u -n -i sysctl -w vm.max_map_count=262144
  ```

  Setting `allow_mmap: false` sidesteps the whole thing at some performance cost. Correct
  for a laptop, **wrong for production** — set the sysctl there instead. The original
  `k3d-plan.md` did both, which is redundant.
- **`volumeClaimTemplates` is explicit on purpose.** Omit it and ECK defaults to a 1Gi
  claim. Declaring it means you will notice when you need to change it — and Phase 06 has
  a lesson about what happens to these volumes.
- **Heap is half of the memory limit.** Standard Elasticsearch guidance. The container
  needs the other half for off-heap structures and the OS page cache.

### 2. Apply and watch

```
kubectl create namespace elastic-stack
kubectl apply -f k8s/elasticsearch.yaml
kubectl get elasticsearch -n elastic-stack -w
```

The `HEALTH` column moves `unknown` → `red` → `yellow` or `green`. `PHASE` shows
`ApplyingChanges` then `Ready`. Watch the operator log at the same time.

### 3. Enumerate what was generated

```
kubectl get all,secret,pdb -n elastic-stack
```

Go through it item by item against the tables above. Do not skip this — it is the phase.

### 4. Connect properly, with certificate validation

The lazy way works:

```
PW=$(kubectl get secret obs-es-elastic-user -n elastic-stack -o go-template='{{.data.elastic | base64decode}}')
kubectl port-forward -n elastic-stack service/obs-es-http 9200
curl -k -u "elastic:$PW" https://localhost:9200
```

But do it **once** the right way, so you know how the PKI fits together:

```
kubectl get secret obs-es-http-certs-public -n elastic-stack \
  -o go-template='{{index .data "ca.crt" | base64decode}}' > /tmp/es-ca.crt

curl --cacert /tmp/es-ca.crt -u "elastic:$PW" https://localhost:9200
```

No `-k`. If that succeeds, you understand ECK certificate management well enough to debug
it later — and this is the exact mechanism the OTel Collector will need in Phase 08.

## Deliberate exercise

Delete the Elasticsearch pod:

```
kubectl delete pod obs-es-default-0 -n elastic-stack
```

Watch the operator and the StatefulSet bring it back, and watch cluster health go red then
recover. Note *which* controller did what: the StatefulSet controller recreated the pod;
the ECK operator did not. Knowing where the boundary sits between Kubernetes primitives
and the operator is worth more than any amount of documentation reading.

## Done when

- Cluster health is green
- You can name every Secret, Service and workload the operator created and say what it is for
- You have connected with full certificate validation, no `-k`
- The manifest is in git

## Notes

- 

## Next

[Phase 04 — Topology](04-elasticsearch-topology.md)
