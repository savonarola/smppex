#!/bin/bash

set -euo pipefail

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

server_ext() {
    local hostname="$1"
    local extfile="$2"

    cat > "$extfile" <<EOF
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:$hostname
EOF
}

openssl req \
    -x509 \
    -new \
    -nodes \
    -key ca.key \
    -subj "/C=LT/ST=Vilniaus/L=Vilnius/O=RubyBox/CN=rubybox.dev" \
    -sha256 \
    -days 10000 \
    -addext "basicConstraints = critical, CA:true" \
    -addext "keyUsage = critical, keyCertSign, cRLSign" \
    -addext "subjectKeyIdentifier = hash" \
    -out ca.crt

server_ext good.rubybox.dev "$tmpdir/good.rubybox.dev.ext"

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
    -extfile "$tmpdir/good.rubybox.dev.ext" \
    -out good.rubybox.dev.crt

server_ext bad.rubybox.dev "$tmpdir/bad.rubybox.dev.ext"

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
    -extfile "$tmpdir/bad.rubybox.dev.ext" \
    -out bad.rubybox.dev.crt

rm -f good.rubybox.dev.csr bad.rubybox.dev.csr ca.srl
