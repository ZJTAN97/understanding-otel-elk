# Elastic Observability with OpenTelemetry

Learning repo.


## To start

```md

k3d cluster create --config phase-1/k3d/cluster.yaml

docker run --rm --privileged --pid=host alpine \
  nsenter -t 1 -m -u -n -i sysctl vm.max_map_count   # check

docker run --rm --privileged --pid=host alpine \
  nsenter -t 1 -m -u -n -i sysctl -w vm.max_map_count=262144

helm repo add elastic https://helm.elastic.co
helm repo update elastic

kubectl create namespace eck

kubectl apply -f phase-3/k8s/elasticsearch.yaml

```
