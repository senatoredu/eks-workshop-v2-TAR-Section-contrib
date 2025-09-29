#!/bin/bash

set -e

logmessage "Deleting OpenTelemetry collectors and instrumentation..."

delete-all-if-crd-exists opentelemetrycollectors.opentelemetry.io
delete-all-if-crd-exists instrumentations.opentelemetry.io

kubectl delete -n other pod load-generator --ignore-not-found

kubectl delete namespace opentelemetry-operator-system --ignore-not-found=true

kubectl delete namespace cert-manager --ignore-not-found=true

uninstall-helm-chart aws-load-balancer-controller kube-system
