#!/bin/bash
set -ex
# Copyright 2024 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BASE_COLLECTION_PATH="/tmp/must-gather"

# Get the namespaces of all control planes in the cluster
function getControlPlanes() {
  local result=()

  local namespaces
  #TODO: there should be never Istiorevision in a namespaces without Istio resource??
  namespaces=$(oc get Istio --all-namespaces -o jsonpath='{.items[*].spec.namespace}')
  for namespace in ${namespaces}; do
    result+=("${namespace}")
  done

  echo "${result[@]}"
}

# Get the CRD's that belong to Istio
function getCRDs() {
  local result=()
  local output
  output=$(oc get crds -o name | grep ".*\.istio\.io")
  for crd in ${output}; do
    result+=("${crd}")
  done

  echo "${result[@]}"
}

# getIstiodNames gets the names of the istiod pods in that namespace
function getIstiodNames() {
  local namespace="${1}"

  oc get pods -n "${namespace}" -l app=istiod -o jsonpath="{.items[*].metadata.name}"
}

# getSynchronization dumps the synchronization status for the specified control plane
# to a file in the control plane directory of the control plane namespace
# Arguments:
#   namespace of the control plane
# Returns:
#   nothing
function getSynchronization() {
  local namespace="${1}"

  local istiodNames
  istiodNames=$(getIstiodNames "${namespace}")

  local name
  for name in ${istiodNames}; do
    echo
    echo "Collecting /debug/syncz from ${name} in namespace ${cp}"

    local logPath=${BASE_COLLECTION_PATH}/namespaces/${namespace}/${name}
    mkdir -p "${logPath}"
    oc exec "${name}" -n "${namespace}" -c discovery -- /usr/local/bin/pilot-discovery request GET /debug/syncz > "${logPath}/debug-syncz.json" 2>&1
  done
}

# getEnvoyConfigForPodsInNamespace dumps the envoy config for the specified namespace and
# control plane to a file in the must-gather directory for each pod
# Arguments:
#   namespace of the control plane
#   namespace to dump
# Returns:
#   nothing
function getEnvoyConfigForPodsInNamespace() {
  local controlPlaneNamespace="${1}"
  
  # TODO: how to get proxy <> control plane mapping? Using istioctl proxy-status? Using just namespaces labels
  local pilotName
  pilotName=$(getPilotName "${controlPlaneNamespace}")
  local podNamespace="${2}"

  echo
  echo "Collecting Envoy config for pods in ${podNamespace}, control plane namespace ${controlPlaneNamespace}"

  local pods
  pods="$(oc get pods -n "${podNamespace}" -o jsonpath='{ .items[*].metadata.name }')"
  for podName in ${pods}; do
    if [ -z "$podName" ]; then
        continue
    fi

    if oc get pod -o yaml "${podName}" -n "${podNamespace}" | grep -q proxyv2; then
      echo "Collecting config_dump and stats for pod ${podName}.${podNamespace}"

      local logPath=${BASE_COLLECTION_PATH}/namespaces/${podNamespace}/pods/${podName}
      mkdir -p "${logPath}"

      oc exec "${pilotName}" -n "${controlPlaneNamespace}" -c discovery -- bash -c "/usr/local/bin/pilot-discovery request GET /debug/config_dump?proxyID=${podName}.${podNamespace}" > "${logPath}/config_dump_istiod.json" 2>&1
      oc exec -n "${podNamespace}" "${podName}" -c istio-proxy -- /usr/local/bin/pilot-agent request GET config_dump > "${logPath}/config_dump_proxy.json" 2>&1
      oc exec -n "${podNamespace}" "${podName}" -c istio-proxy -- /usr/local/bin/pilot-agent request GET stats > "${logPath}/proxy_stats" 2>&1
    fi
  done
}

function version() {
  if [[ -n $OSSM_MUST_GATHER_VERSION ]] ; then
    echo "${OSSM_MUST_GATHER_VERSION}"
  else
    echo "0.0.0-unknown"
  fi
}

function inspect() {
  local resource ns
  resource=$1
  ns=$2

  echo
  if [ -n "$ns" ]; then
    echo "Inspecting resource ${resource} in namespace ${ns}"
    oc adm inspect "--dest-dir=${BASE_COLLECTION_PATH}" "${resource}" -n "${ns}"
  else
    echo "Inspecting resource ${resource}"
    oc adm inspect "--dest-dir=${BASE_COLLECTION_PATH}" "${resource}"
  fi
}

function inspectNamespace() {
  local ns
  ns=$1

  inspect "ns/$ns"
  for crd in $crds; do
    inspect "$crd" "$ns"
  done
  inspect net-attach-def,roles,rolebindings "$ns"
}

function main() {
  #TODO: respect --since and --since-time: https://github.com/openshift/enhancements/blob/master/enhancements/oc/must-gather.md#must-gather-images
  local crds controlPlanes
  echo
  echo "Executing Istio gather script"
  echo

  versionFile="${BASE_COLLECTION_PATH}/version"
  echo "openshift-service-mesh/must-gather"> "$versionFile"
  version >> "$versionFile"

  # TODO: add new name label to servicemesh-operator3 pod and use that instead of the control-plane label
  operatorNamespace=$(oc get pods --all-namespaces -l control-plane=servicemesh-operator3 -o jsonpath="{.items[0].metadata.namespace}")

  inspect nodes

  # TODO: does this match everything we need?
  for r in $(oc get clusterroles,clusterrolebindings -l install.operator.istio.io/owning-resource -oname); do
    inspect "$r"
  done
  for r in $(oc get clusterroles,clusterrolebindings -l 'app in (istiod,istio-reader)' -oname); do
    inspect "$r"
  done


  crds="$(getCRDs)"
  for crd in ${crds}; do
    inspect "${crd}"
  done

  controlPlanes="$*"
  if [ -z "${controlPlanes}" ]; then
    controlPlanes="$(getControlPlanes)"
  fi

  inspect "ns/$operatorNamespace"
  inspect clusterserviceversion "${operatorNamespace}"

  # inspect all controlled mutatingwebhookconfiguration
  for mwc in $(oc get mutatingwebhookconfiguration -l app=sidecar-injector);do
    inspect ${mwc}
  done
  # inspect all controlled validatingwebhookconfiguration
  for vwc in $(oc get validatingwebhookconfiguration -l app=istiod);do
    inspect ${vwc}
  done

  for cp in ${controlPlanes}; do
      echo
      echo "Processing control plane namespace: ${cp}"

      crds="$crds" inspectNamespace "$cp"
      #getEnvoyConfigForPodsInNamespace "${cp}" "${cp}"
      getSynchronization "${cp}"

      #TODO: how to get proxy <> control plane mapping? Using istioctl proxy-status? Using just namespaces labels
      #members=$(getMembers "${cp}")
      #for member in ${members}; do
      #    if [ -z "$member" ]; then
      #        continue
      #    fi

       #   echo "Processing ${cp} member ${member}"
       #   crds="$crds" inspectNamespace "$member"
       #   getEnvoyConfigForPodsInNamespace "${cp}" "${member}"
       #done


       #TODO: istio-cni, remoteIstio
  done

  echo
  echo
  echo "Done"
  echo
}

main "$@"
