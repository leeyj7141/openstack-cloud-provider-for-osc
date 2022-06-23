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

export FLOATING_IP_NET_ID=6b84c969-e0e1-4106-a5d0-a601f92f2903
export K8S_SUBNET_ID=b3861eec-d017-4277-969b-258c9a9debf8
export DNS_DOMAIN='devops.osc cicd.osc'
export DNS='192.168.88.254 192.168.88.250'
export DNS_ZONE_EMAIL='yjlee@linux.com'
export FLOATING_IP=192.168.88.224
export CLUSTER_ID=$(kubectl config current-context)
export OPENSTACK_CMD='/home/openstack-cli/bin/openstack'
export INGRESS_CONTROLLER_IPS="$(kubectl get nodes  -o jsonpath={.items[*].status.addresses[?\(@.type==\"InternalIP\"\)].address})"

function check_cluster_id {
echo -e ""
read -p "###### Current k8s context is $CLUSTER_ID  #######
###### Floating IP Netowrk ID = $FLOATING_IP_NET_ID
###### Floating IP = $FLOATING_IP 
###### K8S Subnet ID = $K8S_SUBNET_ID
###### DNS DOMAIN = $DNS_DOMAIN
###### DNS SERVER = $DNS
###### CLUSTER ID = $CLUSTER_ID
###### OPENSTACK CMD = $OPENSTACK_CMD 
###### Do you want to proceed? [y|n] ###### " answer
case $answer in 
  y) 
    echo ;;
  n) 
    exit ;;
  *) 
    help_page ; exit ;;
esac
}

function create_zone {
echo 
for Z in $DNS_DOMAIN
do
  echo "------ Check if zone $Z exists -----"
  if $OPENSTACK_CMD zone list -f value -c name  |grep -i "^${Z}.$" -q ; then
    echo "------ DNS zone $Z already exists. -----"
  else
    echo "------ Create zone $Z -----"
    $OPENSTACK_CMD zone create --email $DNS_ZONE_EMAIL ${Z}.
  fi
done
}

function create_lb {
echo
echo "------ Create Loadbalancer ${CLUSTER_ID}-LB ------"
if $OPENSTACK_CMD loadbalancer list -f value -c name | grep -qE \^${CLUSTER_ID}-LB\$ ; then 
  echo "------ Loadbalancer ${CLUSTER_ID}-LB already exists  ------"
else 
  $OPENSTACK_CMD loadbalancer create --name ${CLUSTER_ID}-LB --vip-subnet-id ${K8S_SUBNET_ID} --project admin  --wait 
  $OPENSTACK_CMD loadbalancer listener create --name  ${CLUSTER_ID}-listener --protocol HTTP --protocol-port 80 --enable  ${CLUSTER_ID}-LB --wait 
  $OPENSTACK_CMD loadbalancer pool create --protocol HTTP --lb-algorithm ROUND_ROBIN --name ${CLUSTER_ID}-http-pool --listener ${CLUSTER_ID}-listener  --wait
  for i in ${INGRESS_CONTROLLER_IPS}
  do
    $OPENSTACK_CMD loadbalancer member create ${CLUSTER_ID}-http-pool --name ${i}-http --address ${i} --protocol-port 80 --wait
  done
  
  $OPENSTACK_CMD loadbalancer listener create --name  ${CLUSTER_ID}-tls-listener --protocol TCP --protocol-port 443 --enable  ${CLUSTER_ID}-LB --wait
  $OPENSTACK_CMD loadbalancer pool create --protocol TCP --lb-algorithm ROUND_ROBIN --name ${CLUSTER_ID}-tls-pool --listener ${CLUSTER_ID}-tls-listener  --wait
  for i in ${INGRESS_CONTROLLER_IPS}
  do
    $OPENSTACK_CMD loadbalancer member create ${CLUSTER_ID}-tls-pool --name ${i}-tls --address ${i} --protocol-port 443 --wait
  done
  
fi
if  openstack floating ip list  -f value -c 'Floating IP Address'  |grep -iq "^${FLOATING_IP}$" ; then 
  echo "----- Floating ip ${FLOATING_IP} already exists. -----"
else
  echo "$OPENSTACK_CMD floating ip create --floating-ip-address ${FLOATING_IP} ${FLOATING_IP_NET_ID}" # debug 
  $OPENSTACK_CMD floating ip create --floating-ip-address ${FLOATING_IP} ${FLOATING_IP_NET_ID}
  LB_IP=$($OPENSTACK_CMD loadbalancer show ${CLUSTER_ID}-LB -f value  -c vip_address)
  LB_IP=$($OPENSTACK_CMD loadbalancer show ${CLUSTER_ID}-LB -f value  -c vip_address)
  LB_PORT_ID=$($OPENSTACK_CMD port list -f value | grep ${LB_IP} |awk '{print $1}')
  LB_PORT_ID=$($OPENSTACK_CMD port list -f value | grep ${LB_IP} |awk '{print $1}')
  echo "$OPENSTACK_CMD floating ip set --port ${LB_PORT_ID} ${FLOATING_IP}"
  $OPENSTACK_CMD floating ip set --port ${LB_PORT_ID} ${FLOATING_IP}
fi
}

function delete_lb {
echo
echo ----- Delete Loadbalancer ${CLUSTER_ID}-LB -----
$OPENSTACK_CMD loadbalancer delete ${CLUSTER_ID}-LB --cascade --wait 
echo ----- Loadbalancer ${CLUSTER_ID}-LB deleted -----
$OPENSTACK_CMD floating ip delete ${FLOATING_IP}
echo ----- Floating ip ${FLOATING_IP} deleted -----
}


function setup_cloud_conf {
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
}

function setup_octavia_config {
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
}

function setup_cinder_csi_config {
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
}

function setup_external_loadbalancer {
echo ---- create cloud provider loadbalancer yaml ---
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
}

function setup_external_dns {
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
}

function setup_coredns {
cat << EE > coredns/coredns-config.yaml 
apiVersion: v1
data:
  Corefile: |
EE
for D in $DNS_DOMAIN
do
  cat << EF >> coredns/coredns-config.yaml 
    ${D}:53 {
        errors
        cache 300
        forward . "${DNS}"
    }
EF
done
cat << ED >> coredns/coredns-config.yaml 
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
        forward . "/etc/resolv.conf"
        cache 300
        loop
        reload
        loadbalance
    } 
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
ED
}

function create_cinder_csi {
echo 
echo --- create cinder csi ---
kubectl apply -f cinder-csi/
}

function create_external_loadbalancer {
echo 
echo --- create external loadbalancer provider ---
kubectl apply -f loadbalancer/
}

function create_external_dns {
echo 
echo --- create external dns provider ---
kubectl apply -f dns/
}

function edit_coredns {
echo 
echo --- edit coredns nameservers ---
kubectl apply -f coredns/
kubectl delete pod -l k8s-app=kube-dns  -n kube-system 
}

function remove_taints {
echo 
echo --- unset cloudprovider taint ---
for i in $(kubectl get node -o jsonpath="{ .items[*].metadata.name }")
do
  kubectl taint nodes $i node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule-
done
}

function create_octavia_ingress_controller {
echo 
echo --- create octavia ingress controller  ---
kubectl apply -f ingress/
}

function delete_external_loadbalancer {
kubectl delete -f loadbalancer/
}

function delete_external_dns {
kubectl delete -f dns/
}

function delete_octavia_ingress_controller {
kubectl delete -f ingress
}

function delete_cinder_csi {
kubectl delete -f cinder-csi
}

function help_page {
echo "
Usage: $0 CLUSTER_ID SUBCOMMAND OPTION...

SUBCOMMAND 
    create
    delete
OPTION
    --csi | -c 
    --lb-provider | -l
    --ingress | -i 
    --coredns  | -n 
    --dns | -d
    --octavia-lb | -o 
EXAMPLE
   $0 create --csi -d -o -n 
   $0 delete --dns -c -l
"
}


case "$1" in 
  help)
    help_page ;;
  create)
    check_cluster_id ; 
    remove_taints ;
    create_zone ;
    until [ -z "$2" ]
    do
      case "$2" in     
        --lb-provider| -l)
          setup_external_loadbalancer ; create_external_loadbalancer  ;;
        --dns | -d)
          setup_external_dns  ; create_external_dns  ;;
        --ingress| -i)
          setup_octavia_config  ; create_octavia_ingress_controller  ;; 
        --coredns| -n)
          setup_coredns ; edit_coredns ;;
        --csi| -c )
          setup_cinder_csi_config ; create_cinder_csi ;;
        --octavia-lb| -o )
          create_lb ;;
        *)  
          help_page ;;
      esac
      shift
    done ;;
  delete)
    check_cluster_id ;
    until [ -z "$2" ]
    do
      case "$2" in     
        --lb-provider| -l)
          delete_external_loadbalancer ;;
        --dns | -d)
          delete_external_dns ;;
        --ingress| -i)
          delete_octavia_ingress_controller  ;;
        --csi| -c )
          delete_cinder_csi  ;;
        --octavia-lb| -o )
          delete_lb ;;
        *)  
          help_page ;;
      esac
      shift
    done ;;
  *)  
    help_page ;;
esac
