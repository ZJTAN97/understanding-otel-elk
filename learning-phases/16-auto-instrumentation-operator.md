# Phase 16 — Auto-instrumentation, and the EDOT decision

**Goal:** instrument an application without modifying its image, and settle D5.

**Prerequisites:** Phase 15.

**Artifacts produced:** OTel Operator install, `Instrumentation` CRD, the D5 decision
written into `00-decisions.md`.

---

## Part A — Auto-instrumentation without touching images

### Why this matters for production

In Phase 09 you baked the agent jar into your Dockerfile. That works when you own the
image. It does not work when you want to instrument thirty applications owned by other
teams, or a vendor image you cannot rebuild.

The OpenTelemetry Operator solves this by injecting the agent at pod creation time. The
application team adds one annotation. Nothing else changes — not the Dockerfile, not the
build, not the code.

For a platform team serving other teams, this is the difference between instrumentation
being your project and instrumentation being a self-service capability.

### The mechanism

1. The OTel Operator runs a **mutating admission webhook**
2. A pod is created with an annotation like
   `instrumentation.opentelemetry.io/inject-java: "true"`
3. The webhook intercepts the pod spec before it is persisted
4. It adds an **init container** holding the agent jar
5. The init container copies the jar into an `emptyDir` volume shared with the app container
6. It sets `JAVA_TOOL_OPTIONS=-javaagent:/otel-auto-instrumentation/javaagent.jar`
7. It injects the `OTEL_*` environment variables from the `Instrumentation` CRD
8. The JVM starts, reads `JAVA_TOOL_OPTIONS`, loads the agent

**Step 8 is identical to Phase 09.** Same `premain`, same `ClassFileTransformer`, same Byte
Buddy. The bytecode mechanics have not changed at all — only the delivery. Recognising that
these are the same system in different clothing is the conceptual payoff of the phase.

Note the parallel with ECK: a validating webhook checks Elastic resources (Phase 02); a
mutating webhook modifies pods here. Admission webhooks are the extension mechanism behind
both operators.

### Steps

1. **Install the OTel Operator.** Helm, pinned version, values in git. It requires
   cert-manager or its own self-signed certificate setup — check the chart. Note the extra
   images for Phase 17's air-gap mirroring list.
2. **Create an `Instrumentation` resource** pointing at the node-local agent endpoint
   (Phase 14), with your sampler configuration and resource attributes.
3. **Annotate a deployment** and roll it.
4. **Inspect the mutated pod** — `kubectl get pod -o yaml`. Find the init container, the
   `emptyDir`, the `JAVA_TOOL_OPTIONS`, the injected environment. Everything the webhook did
   is visible here, and reading it once removes all the mystery.
5. **Confirm traces arrive** identical to the baked-in-agent version.

### Deliberate exercise

Annotate a pod, then **delete the `Instrumentation` resource** while the pod is running.

Nothing happens — the running pod is already mutated. Now restart the pod and watch the
injection fail, or fall back to defaults.

This teaches that admission webhooks act **only at creation time**. Changing the
`Instrumentation` CRD does not affect running pods; you must restart them. That is a
genuinely surprising operational property and one that causes real confusion when a sampler
change appears not to take effect.

---

## Part B — The EDOT decision (D5)

You deferred this in `00-decisions.md`. Decide it now, with evidence.

### The inputs

From Phase 13, you have a written list of which Kibana views work well on OTel-native
documents and which do not. That list is the whole basis for this decision.

### The comparison

| | Upstream contrib | EDOT |
|---|---|---|
| Config language | OTLP/OTel standard | **the same** |
| Vendor neutrality | full | Elastic-oriented |
| Elastic support | community | Elastic-supported |
| Kibana asset fit | whatever OTel-native mapping gives you | tuned for it |
| Air-gap footprint | one image | one image |
| Component set | everything in contrib | curated subset |

**Switching cost is low precisely because the configuration language is the same.** That is
why D5 was safe to defer, and it remains safe to change later if the answer turns out wrong.

### How to decide

Deploy EDOT alongside upstream, pointed at the same Elasticsearch but a different
`data_stream.namespace`. Send the same traffic through both. Compare in Kibana.

Ask specifically:

- Do the views that were broken in Phase 13 work under EDOT?
- Are the document shapes meaningfully different?
- Does EDOT include every component you rely on? Check the curated component list against
  your Phase 12 receivers — this is the most likely blocker
- Does the Elastic support story matter given your licence tier (Q7)?

### Recommendation, absent evidence to the contrary

**Stay on upstream** unless the Phase 13 gap list is genuinely painful. Vendor neutrality
was a stated reason for D4, and it is worth something real: instrumentation outlives
backends, and you are building a platform intended to last longer than the one it replaces.

But this is an evidence-based decision, not a principled one. If half the Kibana
observability UI is dark on upstream and lights up on EDOT, take the working UI. You are
building an observability platform for people to use, not a purity exercise.

**Write the decision and its reasoning into `00-decisions.md` as D5-resolved.**

## Done when

- An application is instrumented purely by annotation, with no image change
- You can explain the webhook → init container → shared volume → `JAVA_TOOL_OPTIONS` chain
- You can explain why it is the same mechanism as Phase 09
- You know that changing the `Instrumentation` CRD requires a pod restart
- **D5 is decided, in writing, with evidence**

## Notes

- 

## Next

Part 3 complete. Everything now moves to the air-gapped environment.

[Phase 17 — Air-gap and supply chain](17-airgap-and-supply-chain.md)
