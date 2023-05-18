#!/usr/bin/env bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

waitforpodlabeled() {
  local ns=${1?namespace is required}; shift
  local podlabel=${1?pod label is required}; shift

  echo "Waiting for pod -l $podlabel to be created"
  until oc get pod -n "$ns" -l $podlabel -o=jsonpath='{.items[0].metadata.name}' >/dev/null 2>&1; do
    sleep 1
  done
}

waitpodready() {
  local ns=${1?namespace is required}; shift
  local podlabel=${1?pod label is required}; shift

  waitforpodlabeled "$ns" "$podlabel"
  echo "Waiting for pod -l $podlabel to become ready"
  kubectl wait --for=condition=ready --timeout=180s pod -n $ns -l $podlabel
}


# Deploy Distributed tracing operator (Jaeger)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-distributed-tracing
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-distributed-tracing
  namespace: openshift-distributed-tracing
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: jaeger-product
  namespace: openshift-distributed-tracing
spec:
  channel: stable
  installPlanApproval: Automatic
  name: jaeger-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

waitpodready "openshift-distributed-tracing" "name=jaeger-operator"

# Deploy Kiali operator
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kiali-ossm
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kiali-ossm
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

waitpodready "openshift-operators" "app=kiali-operator"

# Deploy OSSM operator
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

waitpodready "openshift-operators" "name=istio-operator"

# Install OSSM
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
---
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
  namespace: istio-system
spec:
  version: v2.3
  tracing:
    type: Jaeger
    sampling: 10000
# Uncomment if on ROSA
#  security:
#    identity:
#      type: ThirdParty
  addons:
    jaeger:
      name: jaeger
      install:
        storage:
          type: Memory
    kiali:
      enabled: true
      name: kiali
    grafana:
      enabled: true
EOF

# Waiting for OSSM minimum start
waitpodready "istio-system" "app=istiod"

echo -e "\n  OSSM has partially started and should be fully ready soon."
