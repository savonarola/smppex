#!/bin/bash

openssl req \
    -x509 \
    -new \
    -nodes \
    -key ca.key \
    -subj "/C=LT/ST=Vilniaus/L=Vilnius/O=RubyBox/CN=rubybox.dev" \
    -sha256 \
    -days 10000 \
    -out ca.crt

openssl req \
    -batch \
    -new \
    -key cert.key \
    -subj '/CN=good.rubybox.dev/O=SMPPEX/C=LT/ST=Vilniaus/L=Vilnius' \
    -out good.rubybox.dev.csr

openssl x509 \
    -req \
    -in good.rubybox.dev.csr \
    -days 10000 \
    -CA ca.crt \
    -CAkey ca.key \
    -CAcreateserial \
    -out good.rubybox.dev.crt

openssl req \
    -batch \
    -new \
    -key cert.key \
    -subj '/CN=bad.rubybox.dev/O=SMPPEX/C=LT/ST=Vilniaus/L=Vilnius' \
    -out bad.rubybox.dev.csr

openssl x509 \
    -req \
    -in bad.rubybox.dev.csr \
    -days 10000 \
    -CA ca.crt \
    -CAkey ca.key \
    -CAcreateserial \
    -out bad.rubybox.dev.crt
