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
FLOATING_IP=192.168.88.206
CLUSTER_ID=yjlee-test4
OPENSTACK_CMD='/home/openstack-cli/bin/openstack'
INGRESS_CONTROLLER_IPS=$(kubectl get nodes  -o jsonpath={.items[*].status.addresses[?\(@.type==\"InternalIP\"\)].address})

function create_lb {
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
  $OPENSTACK_CMD floating ip create --floating-ip-address ${FLOATING_IP} ${FLOATING_IP_NET_ID}
  LB_IP=$($OPENSTACK_CMD loadbalancer show ${CLUSTER_ID}-LB -f value  -c vip_address)
  LB_PORT_ID=$($OPENSTACK_CMD port list -f value | grep ${LB_IP} |awk '{print $1}')
  $OPENSTACK_CMD floating ip set --port ${LB_PORT_ID} ${FLOATING_IP}
}

function delete_lb {
$OPENSTACK_CMD loadbalancer delete ${CLUSTER_ID}-LB --cascade --wait 
echo ----- Loadbalancer ${CLUSTER_ID}-LB deleted -----
$OPENSTACK_CMD floating ip delete ${FLOATING_IP}
echo ----- Floating ip ${FLOATING_IP} deleted -----
}

if [[ $# -eq 0 ]] ; then 
  create_lb
fi

case "$1" in 
  create) 
    create_lb ;;
  delete) 
    delete_lb ;;
esac
