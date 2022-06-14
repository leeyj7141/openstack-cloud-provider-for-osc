#!/bin/bash 

kubectl create secret tls tls-secret --key foo.bar.com.devops.osc.key --cert foo.bar.com.devops.osc.crt
