To test ECK locally using **k3d**, here is a lightweight, step-by-step walkthrough to get the operator, a single-node Elasticsearch cluster, and Kibana up and running.

---

### Step 1: Prepare the Host Memory Mapping

Elasticsearch uses memory mapping (`mmap`) by default. If running Linux or WSL2, make sure the host allows sufficient virtual memory:

```bash
sudo sysctl -w vm.max_map_count=262144
```

*(If you are on macOS Docker Desktop, Docker handles this automatically).*

---

### Step 2: Create a Local k3d Cluster

Create a simple cluster and map port `5601` (Kibana) and `9200` (Elasticsearch) to your host:

```bash
k3d cluster create elastic-test \
  --servers 1 \
  --port "5601:5601@loadbalancer" \
  --port "9200:9200@loadbalancer"
```

---

### Step 3: Install the ECK Operator via Helm

Add the Elastic repository and deploy the operator chart:

```bash
# 1. Add repository
helm repo add elastic https://helm.elastic.co
helm repo update

# 2. Install ECK Operator
helm install elastic-operator elastic/eck-operator \
  --namespace elastic-system \
  --create-namespace

# 3. Verify operator pod is running
kubectl get pods -n elastic-system
```

The operator manages the Custom Resource Definitions (CRDs) for `Elasticsearch`, `Kibana`, `Beat`, `Logstash`, etc.

---

### Step 4: Deploy a Minimal Elasticsearch Instance

Create a lightweight, single-node Elasticsearch cluster (`local-es.yaml`):

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: quickstart
  namespace: default
spec:
  version: 8.17.0
  nodeSets:
  - name: default
    count: 1
    config:
      node.store.allow_mmap: false # Disables mmap check if host limits aren't set
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

Apply it:
```bash
kubectl apply -f local-es.yaml
```

Check status until health becomes `green` or `yellow`:
```bash
kubectl get elasticsearch quickstart -w
```

---

### Step 5: Deploy Kibana

Create the Kibana definition (`local-kibana.yaml`):

```yaml
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: quickstart
  namespace: default
spec:
  version: 8.17.0
  count: 1
  elasticsearchRef:
    name: quickstart
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

Apply it:
```bash
kubectl apply -f local-kibana.yaml
```

---

### Step 6: Access Elasticsearch and Kibana

#### 1. Retrieve the default `elastic` superuser password:
The operator auto-generates credentials and stores them in a Secret:

```bash
PASSWORD=$(kubectl get secret quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
echo "Elastic Password: $PASSWORD"
```

#### 2. Test Elasticsearch connection (via port-forward):
```bash
kubectl port-forward service/quickstart-es-http 9200:9200
```
In another terminal:
```bash
curl -k -u "elastic:$PASSWORD" https://localhost:9200
```

#### 3. Access Kibana:
```bash
kubectl port-forward service/quickstart-kb-http 5601:5601
```
Open `https://localhost:5601` in your browser, log in with username `elastic` and the retrieved password.

---

### Step 7: Clean Up

When you are done testing, delete the local cluster:

```bash
k3d cluster delete elastic-test
```