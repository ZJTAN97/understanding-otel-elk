Obs Elastic Search

- Version: 8.14.2

- 2 namespace worth mentioning (eck, elastic-system)
- elastic-system got no deployments, probably can delete
- within elastic-system namespace,
  - got eck-operator:2.13.0
- within eck namespace,
  - got 2 ingress (apm-ingress, kibana-ingress)
  - got 4 deployments 
    - apm-server:8.14.2
    - elastic-package-registry:8.14.2 
    - fleet-server-agent:8.14.2
    - kibana-kb:8.14.2
  - pvcs (elasticsearch-data-elasticsearch-es-default)
  - statefulsets
    - elasticsearch-es-default
    - elasticsearch-es-ingest
    - elasticsearch-es-master
  - for daemonsets, got elastic-agent-agent, from elastic.co/beats/elastic-agent:8.14.2


Seems like the deployment advocated for by the previous engineer was as such

"""
Install ECK using yaml manifests. This method is the quickest way to get started with ECK. the following components
will be installed or updated:
- CustomResourceDefinition: objects for all supported resource types (ElasticSearch, Kibana, APM Server, Enterprise Search, Beats, Elastic Agent, Elastic Maps.Server and LogStash)
- Namespace named `elastic-system` to hold all operator resources
- ServiceAccount, ClusterRole and ClusterRoleBinding to allow the operator to manage resources throughout the cluster
- ValidatingWebhookConfiguration to validate Elastic custom resources on admission
- StatefulSet, Configmap Secret and Service in elastic-system namespace to run the operator application
"""

I am honestly not very sure if this is even the right way, and somehow the version stayed 8.14.2 for the last 2 years already.