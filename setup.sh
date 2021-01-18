#!/bin/sh

# Bootstrap

flux bootstrap github \
  --owner=ketterma \
  --repository=mobius \
  --branch=main \
  --path=./base \
  --personal

flux create source git mobius \
  --secret-ref flux-system \
  --url=ssh://git@github.com/ketterma/mobius \
  --branch main

# Monitoring

flux create source git monitoring \
  --interval=30m \
  --url=https://github.com/fluxcd/flux2 \
  --branch=main

flux create kustomization monitoring \
  --interval=1h \
  --prune=true \
  --source=monitoring \
  --path="./manifests/monitoring" \
  --health-check="Deployment/prometheus.flux-system" \
  --health-check="Deployment/grafana.flux-system"
