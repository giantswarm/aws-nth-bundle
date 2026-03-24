[![CircleCI](https://circleci.com/gh/giantswarm/aws-nth-bundle.svg?style=shield)](https://circleci.com/gh/giantswarm/aws-nth-bundle)

# aws-node-termination-handler chart

Giant Swarm offers an `aws-nth-bundle` Managed App which can be installed in tenant clusters.
Here we define the `aws-nth-bundle` and `aws-node-termination-handler` charts with their templates and default configuration.

## Key terminology

| Term | Where it lives | What it does |
|------|---------------|--------------|
| **BUNDLE-ONLY** | Management cluster only | Never forwarded to workload chart. Examples: `clusterID`, `ociRepositoryUrl` |
| **UPSTREAM** | Workload cluster, under `upstream:` key | Routed to the unmodified upstream subchart. Controls the actual NTH application: image, replicas, service account, SQS settings, etc. |
| **EXTRAS** | Workload cluster, at top level (not under `upstream:`) | Consumed by GS extras templates: `networkPolicy`, `verticalPodAutoscaler`, `global.podSecurityStandards`, etc. |

## Architecture

```
Management Cluster                          Workload Cluster
+-----------------------------------------+ +-------------------------------------------+
| aws-nth-bundle                          | | aws-node-termination-handler              |
|                                         | |                                           |
| ConfigMap ─── values (workloadValues) ──┼─┼──► Flux HelmRelease                       |
| OCIRepository                           | |    ├── upstream: {} → upstream subchart    |
| Crossplane IAM Role                     | |    └── top-level   → GS extras            |
|   └── IRSA for NTH service account      | |        (NetworkPolicy, VPA, PSS)          |
+-----------------------------------------+ +-------------------------------------------+
```

### Charts

| Chart | Location | Deployed to | Purpose |
|-------|----------|-------------|---------|
| `aws-nth-bundle` | `helm/aws-nth-bundle/` | Management cluster | Orchestrator: IAM role (Crossplane), Flux resources, computed values ConfigMap |
| `aws-node-termination-handler` | `helm/aws-node-termination-handler/` | Workload cluster (via Flux) | Wraps unmodified upstream chart as dependency + GS extras |

### Value flow

1. **Bundle `values.yaml`** provides images in GS split format (`registry` + `name`), IRSA config, and extras
2. **`_helpers.tpl` (`giantswarm.workloadValues`)** transforms values:
   - Combines `registry` + `name` → single `repository` path for upstream
   - Computes IRSA role ARN from crossplane-config ConfigMap
   - Computes SQS queue URL from clusterID (`{clusterID}-nth`)
   - Routes upstream values under `upstream:` key
   - Routes extras (`networkPolicy`, `verticalPodAutoscaler`, `global`) at top level
3. **ConfigMap** stores the transformed values
4. **Flux HelmRelease** reads values from ConfigMap and deploys the workload chart

### Why this pattern

- **Unmodified upstream** — version bump = update dependency version + `helm dependency update`
- **Separation of concerns** — IAM and Flux on management cluster, app on workload cluster
- **Single App CR** — install the bundle once on the management cluster

## Installation

Create an App CR on the management cluster:

```yaml
apiVersion: application.giantswarm.io/v1alpha1
kind: App
metadata:
  name: aws-nth-bundle
  namespace: org-<org>
spec:
  catalog: giantswarm
  name: aws-nth-bundle
  namespace: org-<org>
  version: ""
```

## Upgrade from forked to upstream chart

This version replaces the forked upstream chart with the unmodified upstream chart used as a Helm dependency. The `nameOverride` is set to preserve `app.kubernetes.io/name` labels and selector compatibility. No manual migration steps are required.

## Testing

```bash
# Lint both charts
helm lint helm/aws-node-termination-handler/
helm lint helm/aws-nth-bundle/

# Update dependencies
cd helm/aws-node-termination-handler && helm dependency update

# Template workload chart
helm template test helm/aws-node-termination-handler/
```

## Credit

* https://github.com/aws/aws-node-termination-handler
* https://github.com/aws/eks-charts/tree/master/stable/aws-node-termination-handler
