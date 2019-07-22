# Metric testing for scaling on Kubernetes.

The usage is

```bash
cd metrics/scaling
./k8s-scale.sh
```

The default container runtime is not Kata containers, but Kata can be specified
setting the environment variable:

```bash
use_kata_runtime=yes
```

These tests currently only support single node deployments, but PRs to add
multi-node support will follow shortly.
