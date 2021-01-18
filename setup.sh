#!/bin/sh

# Bootstrap
kubectl apply -k infra/argocd
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2

