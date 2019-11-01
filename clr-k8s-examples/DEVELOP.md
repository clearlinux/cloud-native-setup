# Developer

This document describes the key concepts and technologies used in the project, and lists the ways to contribute to the 
project.

## Code Conventions

### Shell Scripts 

Shell scripts should adhere to the [Google Shell Style Guide](https://google.github.io/styleguide/shell.xml) as much as 
possible.

#### Formatting with `shfmt`

The [shfmt](https://github.com/mvdan/sh#shfmt) tool should be used to format shell scripts with 2 spaces and should use 
the following parameters:

```shell script
shfmt -i 2 -ci
``` 

#### Linting with shellcheck

The [shellcheck](https://github.com/koalaman/shellcheck) tool should be used to identify issues with the scripts 
themselves. The config file for shellcheck is typically found in `~/.shellcheckrc` and should include rules that 
are [ignored](https://github.com/koalaman/shellcheck/wiki/Ignore) project wide.

```shell script
# ~/.shellcheckrc
# disabled rules here 
```



## Kustomize Usage

[Kustomize](https://kustomize.io/) is used to offer multiple versions of components simultaneously and helps us be
explicit in patching. The main functionality of the tool is now built into `kubectl`. The following sections provide an 
overview of how we use Kustomize.

### Multiple Versions of Components

We maintain multiple versions of a component by creating a directory for each version (e.g. `v0.8.3` and `v1.0.3`) and 
using a `kustomization.yaml` file to specify the required files and patches. 

```bash
7-rook
├── overlays
│   ├── v0.8.3
│   │   ├── kustomization.yaml
│   │   └── operator_patch.yaml
│   └── v1.0.3
│       ├── kustomization.yaml
│       ├── patch_operator.yaml
│       └── rook

```

For each component to be installed, the `create_stack.sh` will clone the relevant repo to the specified version 
dir (e.g. `7-rook/overlays/v1.0.3/rook`) and switch the branch to the specified release. The `create_stack.sh` script will then 
install the specified version via `kubectl` (e.g. `kubectl apply -k 7-rook/overlays/v1.0.3`) which will apply the 
required files and patches.  

### Specific files

The `kustomization.yaml` allows us to specify which manifests to load under the `resources:` element and makes it easy 
to see any customizations via patch files. 

```yaml
# 7-rook/overlays/v1.0.3/kustomization.yaml
resources:
  - rook/cluster/examples/kubernetes/ceph/common.yaml
  - rook/cluster/examples/kubernetes/ceph/operator.yaml
  - rook/cluster/examples/kubernetes/ceph/cluster.yaml
  - rook/cluster/examples/kubernetes/ceph/storageclass.yaml

patchesStrategicMerge:
  - patch_operator.yaml
``` 

### Patches

There are two types of patches in Kustomize, `patchesStrategicMerge` for simple YAML fragments and 
`patchesJson6902` for more advanced use cases.

#### patchesStrategicMerge

The `patchesStrategicMerge` patch is just a fragment of YAML that will be merged into the final manifest. Note that the 
metadata is required so the tool can locate the target manifest.

```yaml
# 7-rook/overlays/v1.0.3/patch_operator.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rook-ceph-operator
spec:
  template:
    spec:
      containers:
        - name: rook-ceph-operator
          env:
          - name: FLEXVOLUME_DIR_PATH
            value: "/var/lib/kubelet/volume-plugins"
```
The above example adds the `FLEXVOLUME_DIR_PATH` environment variable and value to the `rook-ceph-operator` manifest. 

#### patchesJson6902

In the following example we demonstrate the more advanced JSON patching format.

```yaml
# 5-ingres-lb/overlays/nginx-0.25.0/kustomization.yaml
resources:
  - ingress-nginx/deploy/static/mandatory.yaml
  - ingress-nginx/deploy/static/provider/baremetal/service-nodeport.yaml

patchesJson6902:
  # adds "networking.k8s.io" to ClusterRole's apiGroups
  - target:
      group: rbac.authorization.k8s.io
      version: v1
      kind: ClusterRole
      name: nginx-ingress-clusterrole
    path: patch_clusterrole.yaml
```
```yaml
# 5-ingres-lb/overlays/nginx-0.25.0/patch_clusterrole.yaml

# adds "networking.k8s.io" to apiGroups for ingress rules which is missing in 0.25.0
- op: add
  path: /rules/3/apiGroups/-
  value: "networking.k8s.io"
```
In the above example, the metadata for the target manifest is specified in the `kustomization.yaml` and the patch file 
itself contains the operation to perform, target path and value. The `rules/3/apiGroups/-` path indicates to perform the 
operation (in this case "add") at the `apiGroups:` list found under the 4th list item of `rules:`. 

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nginx-ingress-clusterrole
  ...
rules:
  - apiGroups:
      ...
  - apiGroups:
      ...
  - apiGroups:
      ...
  - apiGroups:
      ...
  - apiGroups:
      - "extensions"
      - "networking.k8s.io" # <- The patch adds the value to the list here
```  

The `value:` property specifies the data being operated on (added) and in this case it is a simple string,  
"networking.k8s.io". The `value:` can also be more complex and specified as JSON or YAML. For more information, see 
[jsonpath.md](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/jsonpatch.md)
 
### Kustomize Resources

  * `kustomization.yaml` [fields](https://github.com/kubernetes-sigs/kustomize/blob/master/docs/fields.md)
  
  