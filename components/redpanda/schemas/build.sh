#!/bin/bash

# Compile all of the files
cd ./src

for file in *; do
    echo "building $file"
    if [ -f "$file" ]; then
        flatc --binary -o "../build" --schema "$file"
    fi
done

# Go to parent of the schemas dir
cd ../build

FROM_FILE_ARGS=""
for file in *; do
    if [ -f "$file" ]; then
        echo "Found file for secret: $file"
        FROM_FILE_ARGS+="--from-file=$file "
    fi
done

# Create the secret
kubectl create secret generic flatbuffer-schemas $FROM_FILE_ARGS -n redpanda --dry-run=client -o yaml > secrets.yml

mv secrets.yml ../../
cd ../..

# Seal the secret
kubectl config use-context prod
kubeseal <secrets.yml>sealedsecrets.yml --namespace redpanda --controller-name=sealed-secrets-production --controller-namespace=kube-system --format yaml