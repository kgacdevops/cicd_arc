#!/bin/bash
set -e

# Variables
arc_namespace="arc"
cert_mgr_namespace="cert-manager"
cert_mgr_ver="v1.12.0"
secret_name="arc-secret"
git_owner_name="kgacandole"
git_repo_name="github_arc"
cloud_provider="$1"
runner_label="kg-runner-${cloud_provider}"

# Add Helm Repos
helm version || curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install Full Cert-Manager (Includes CRDs + Controllers)
echo "Installing Cert-Manager..."
kubectl create namespace "$cert_mgr_namespace" || echo "Namespace exists"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${cert_mgr_ver}/cert-manager.crds.yaml 
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${cert_mgr_ver}/cert-manager.yaml 
sleep 30s

# Wait for Cert-Manager pods to be ready
echo "Waiting for Cert-Manager to be ready (this can take 2-3 minutes)..."
kubectl wait --for=condition=Available deployment --all -n "$cert_mgr_namespace" --timeout=300s

# Create ARC Namespace
kubectl create namespace "$arc_namespace" || echo "Namespace exists"

# Create Secret
kubectl create secret generic "$secret_name" -n "$arc_namespace" --from-literal=github_app_id="$GH_APP_ID" --from-literal=github_app_installation_id="$GH_INSTALLATION_ID" --from-file=github_app_private_key=github_app_key.pem || echo "Secrets already exist"

# Install ARC
helm install arc -n "${arc_namespace}-systems" --create-namespace oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

# Install Runners
helm install "$runner_label" -n "$arc_namespace" --create-namespace --set githubConfigUrl="https://github.com/${git_owner_name}/${git_repo_name}" --set githubConfigSecret="$secret_name" oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --set minRunners=3 --set maxRunners=5