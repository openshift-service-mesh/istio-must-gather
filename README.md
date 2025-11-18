# istio-must-gather
A client tool for gathering Service Mesh information in a OpenShift cluster 

# Issues for this repository are disabled

Issues for this repository are tracked in Red Hat Jira. Please head to <https://issues.redhat.com/browse/OSSM> in order to browse or open an issue.

Istio must-gather
=================

`Istio must-gather` is a tool built on top of [OpenShift must-gather](https://github.com/openshift/must-gather) that expands its capabilities to gather Service Mesh information.

### Usage
```sh
oc adm must-gather --image=quay.io/sail-dev/istio-must-gather:3.1
```

The command above will create a local directory with a dump of the OpenShift Service Mesh state. Note that this command will only get data related to the Service Mesh part of the OpenShift cluster.

You will get a dump of:
- The Sail Operator namespace (and its children objects)
- All Control Plane namespaces (and their children objects)
- All namespaces (and their children objects) that belong to any service mesh
- All Istio CRD definitions
- All Istio CRD objects (VirtualServices in a given namespace, etc)
- All Istio Webhooks
- All Sail operator CRD definitions
- All Sail operator CRD objects (Istio CNI, Istio, Istio Revision, etc.)
- All Kiali CRD definitions
- All Kiali CRD objects (Kiali, ossmconsole)
- All gateway.networking.k8s.io group CRD definitions
- All gateway.networking.k8s.io group instances
- All inference.networking.x-k8s.io group CRD definitions
- All inference.networking.x-k8s.io group instances

In order to get data about other parts of the cluster (not specific to service mesh) you should run just `oc adm must-gather` (without passing a custom image). Run `oc adm must-gather -h` to see more options.

<!-- 
Current full version: 3.2.1
-->
