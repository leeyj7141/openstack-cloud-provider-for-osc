#!/bin/bash 

PROVIDERS='
cinder-csi
dns
loadbalancer'

for i in $PROVIDERS
do
kubectl delete -f $i 
done
