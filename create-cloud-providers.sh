#!/bin/bash 

export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_PROJECT_ID=27d30691195a49a0a3b28f24bb881ed2
export OS_TENANT_NAME=admin
export OS_USERNAME=lb-admin
export OS_PASSWORD=root123
export OS_AUTH_URL=http://192.168.88.250:35357/v3
export OS_INTERFACE=internal
export OS_ENDPOINT_TYPE=internalURL
export OS_IDENTITY_API_VERSION=3
export OS_REGION_NAME=RegionOne
export OS_AUTH_PLUGIN=password

FLOATING_IP_NET_ID=6b84c969-e0e1-4106-a5d0-a601f92f2903
K8S_SUBNET_ID=b3861eec-d017-4277-969b-258c9a9debf8
DNS_DOMAIN=devops.osc
DNS=192.168.88.254
CLUSTER_ID=yjlee-test4


echo --- create cloud.conf  ---
echo "
[Global]
auth-url=${OS_AUTH_URL}
username=${OS_USERNAME}
password=${OS_PASSWORD}
region=${OS_REGION_NAME}
tenant-name=${OS_TENANT_NAME}
domain-name=${OS_PROJECT_DOMAIN_NAME}
user-domain-name=${OS_USER_DOMAIN_NAME}
tls-insecure=true

[LoadBalancer]
use-octavia=true
floating-network-id=${FLOATING_IP_NET_ID}
subnet-id=${K8S_SUBNET_ID} 
lb-provider=amphora 

[BlockStorage]
bs-version=v2

#[KeyManager]
#key-id = fdfe96cc-0408-4e2b-8d95-7531e4e0e647
" |tee  cloud.conf 

echo ---- octavia ingress controller configmap ---
cat << EE > ingress/config.yaml
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: octavia-ingress-controller-config
  namespace: kube-system
data:
  config: |
    cluster-name: ${CLUSTER_ID}
    openstack:
      auth-url: ${OS_AUTH_URL}
      domain-name: ${OS_PROJECT_DOMAIN_NAME}
      username: "${OS_USERNAME}"
      password: "${OS_PASSWORD}"
      project-name: ${OS_TENANT_NAME}
      region: ${OS_REGION_NAME}
    octavia:
      subnet-id: ${K8S_SUBNET_ID}
      floating-network-id: ${FLOATING_IP_NET_ID}
      manage-security-groups: true
      provider: amphora
EE

echo ---- create secret yaml ----
cat <<EE > cinder-csi/csi-secret-cinderplugin.yaml
---
kind: Secret
apiVersion: v1
metadata:
  name: cloud-config-csi
  namespace: kube-system
data:
  cloud.conf: `base64 -w 0 cloud.conf`
EE

cat <<EE > loadbalancer/cloud-config-secret-loadbalancer.yaml
---
kind: Secret
apiVersion: v1
metadata:
  name: cloud-config
  namespace: kube-system
data:
  cloud.conf: `base64 -w 0 cloud.conf`
EE

echo ---- create external dns deployment yaml ---
cat << EE > dns/externaldns-deployment.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: external-dns
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      tolerations:
        - effect: NoSchedule # Make sure the pod can be scheduled on master kubelet.
          operator: Exists
        - key: CriticalAddonsOnly # Mark the pod as a critical add-on for rescheduling.
          operator: Exists
        - effect: NoExecute
          operator: Exists
      containers:
      - name: external-dns
        image: k8s.gcr.io/external-dns/external-dns:v0.12.0
        args:
        #- --source=ingress
        - --source=service
        - --domain-filter=${DNS_DOMAIN}
        - --provider=designate
        - --registry=txt
        - --txt-owner-id=${CLUSTER_ID}
        env: 
        - name: OS_AUTH_URL
          value: ${OS_AUTH_URL}
        - name: OS_REGION_NAME
          value: ${OS_REGION_NAME}
        - name: OS_USERNAME
          value: ${OS_USERNAME}
        - name: OS_PASSWORD
          value: ${OS_PASSWORD}
        - name: OS_PROJECT_NAME
          value: ${OS_PROJECT_NAME}
        - name: OS_USER_DOMAIN_NAME
          value: ${OS_USER_DOMAIN_NAME}
EE

cat << EE > coredns/coredns-config.yaml 
apiVersion: v1
data:
  Corefile: |
    ${DNS_DOMAIN}:53 {
        errors
        cache 300
        forward . "${DNS}"
    }
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . "8.8.8.8"
        cache 300
        loop
        reload
        loadbalance
    } 
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
EE

echo 
echo --- create cinder csi ---
kubectl apply -f cinder-csi/

#echo 
#echo --- create external loadbalancer provider ---
#kubectl apply -f loadbalancer/

echo 
echo --- create external dns provider ---
kubectl apply -f dns/


echo 
echo --- unset cloudprovider taint ---
for i in $(kubectl get node -o jsonpath="{ .items[*].metadata.name }")
do
  kubectl taint nodes $i node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule-
done

#echo 
#echo --- create octavia ingress controller  ---
#kubectl apply -f ingress/

