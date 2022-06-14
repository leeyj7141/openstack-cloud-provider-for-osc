#!/bin/sh

read -p "Enter your server domain [www.example.com]: " DOMAIN
DOMAIN=${DOMAIN:-"www.example.com"}

if [[ ! -f ca.crt ]]; then
  echo "Create CA cert(self-signed) and key..."
  CA_SUBJECT="/C=NZ/ST=Wellington/L=Wellington/O=Catalyst/OU=Lingxian/CN=CA"
  openssl req -new -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ca.key -out ca.crt -subj $CA_SUBJECT >/dev/null 2>&1
fi

echo "Create server key..."
openssl genrsa -des3 -out $DOMAIN_encrypted.key 1024 >/dev/null 2>&1
echo "Remove password..."
openssl rsa -in $DOMAIN_encrypted.key -out $DOMAIN.key >/dev/null 2>&1

echo "Create server certificate signing request..."
SUBJECT="/C=NZ/ST=Wellington/L=Wellington/O=Catalyst/OU=Lingxian/CN=$DOMAIN"
openssl req -new -nodes -subj $SUBJECT -key $DOMAIN.key -out $DOMAIN.csr >/dev/null 2>&1

echo "Sign SSL certificate..."
openssl x509 -req -days 3650 -in $DOMAIN.csr -CA ca.crt -CAkey ca.key -set_serial 01 -out $DOMAIN.crt >/dev/null 2>&1

echo "Succeed!"