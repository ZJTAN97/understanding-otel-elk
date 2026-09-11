# Phase 05 — Kibana, associations and Ingress

**Goal:** Kibana reachable through an Ingress, and an understanding of how ECK wires
resources to each other without you supplying credentials.

**Prerequisites:** Phase 04.

**Artifacts produced:** `k8s/kibana.yaml`, `k8s/ingress.yaml`.

---

## Concepts

**Associations are the interesting part.** You write:

```yaml
  elasticsearchRef:
    name: obs
```

...and Kibana can talk to Elasticsearch. No username, no password, no CA path. The operator
noticed the reference and, behind the scenes:

1. Created a dedicated service account user in Elasticsearch with only the roles Kibana needs
2. Generated a Secret holding those credentials
3. Mounted the Elasticsearch CA into the Kibana pod
4. Injected the connection settings into `kibana.yml`
5. Set up rotation for all of it

This is the single strongest argument for the operator over hand-rolled manifests. It is
also the mechanism to check first when two Elastic resources will not talk to each other —
look for the association status:

```
kubectl get kibana obs -n elastic-stack -o jsonpath='{.status.associationStatus}'
```

**Associations are namespace-aware.** Cross-namespace references need the operator
configured to allow them. Relevant if production keeps the `elastic-system` / workload
namespace split.

**Kibana requires an encryption key for saved objects.** ECK generates and manages one. If
it were ever lost, encrypted saved objects (alerting rules, connectors) would become
unreadable. Worth knowing before Phase 13 creates any.

**Two layers of TLS, and this is where people get confused:**

| Layer | Managed by | Certificate |
|---|---|---|
| Browser → Ingress | Your ingress controller | Needs a cert your browser trusts |
| Ingress → Kibana pod | ECK | Self-signed, ECK-managed |

The Ingress must be told to speak **HTTPS** to the backend, because ECK enables TLS on
Kibana by default. Forgetting this produces a 502 with a confusing "plain HTTP request sent
to HTTPS port" error in the Kibana logs. The alternative is disabling Kibana self-signed
TLS and terminating only at the ingress — simpler, but it means unencrypted traffic inside
the cluster. Production already has `kibana-ingress` and `apm-ingress`, so this is a
rehearsal of a real configuration.

## Steps

### 1. Deploy Kibana

```yaml
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: obs
  namespace: elastic-stack
spec:
  version: 8.19.21          # must match Elasticsearch exactly
  count: 1
  elasticsearchRef:
    name: obs
  podTemplate:
    spec:
      containers:
        - name: kibana
          resources:
            requests:
              memory: 1Gi
              cpu: 500m
            limits:
              memory: 1Gi
```

Version skew between Kibana and Elasticsearch is not tolerated. Kibana will refuse to
start, with a clear message — read it once so you recognise it.

### 2. Inspect what the association created

```
kubectl get secret -n elastic-stack | grep kibana
kubectl get kibana obs -n elastic-stack -o yaml | grep -A5 associationStatus
```

Find the generated user. Then look it up in Elasticsearch and see what roles it holds:

```
GET _security/user
```

Note that it is not `elastic`. Least privilege, applied automatically.

### 3. Reach it, the quick way first

```
kubectl port-forward -n elastic-stack service/obs-kb-http 5601
```

Open `https://localhost:5601`, log in as `elastic` with the password from Phase 03.

### 4. Then do it properly, with Ingress

k3d ships Traefik. Create an Ingress that mirrors production. The critical part is telling
Traefik to use HTTPS to the backend — with Traefik that is a `ServersTransport` plus a
service annotation; with nginx it is `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`.

Add a hosts-file entry for a local name like `kibana.lab.local` pointing at 127.0.0.1, so
you are exercising name-based virtual hosting the way production does rather than raw
port-forwarding.

## Deliberate exercise

Configure the Ingress **without** the HTTPS-backend setting first. Observe the 502, then
read the Kibana container log and find the message about receiving a plain HTTP request on
an HTTPS port. Then fix it.

This is a five-minute lesson that prevents a two-hour outage later, because the symptom
(502 at the ingress) points away from the actual cause (TLS mismatch at the backend).

## Done when

- Kibana loads through the Ingress at a hostname, not a port-forward
- You can explain what `elasticsearchRef` caused the operator to do, in five steps
- You have seen the association status field and know where to look when it fails
- Both manifests are in git

## Notes

- 

## Next

[Phase 06 — Operations](06-eck-operations.md)
