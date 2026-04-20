#!/bin/bash
set -e

projectId="$1"
projectNum="$2"
region="$3"

org_name="kgacdevops"
identity_pool_name="gh-identity-pool"      
tfstate_bucket_name="arc_tfstate_bucket"  

svc_account_name_tf="tf-svc-account"
svc_account_name_compute="kube-svc-account"
full_svc_account_id_tf="${svc_account_name_tf}@${projectId}.iam.gserviceaccount.com"
full_svc_account_id_compute="${svc_account_name_compute}@${projectId}.iam.gserviceaccount.com"

#### Below steps are expected to be performed prior to this script ####
# Create workload identity pool 
# gcloud iam workload-identity-pools create "$identity_pool_name" \
#     --location="global" \
#     --description="Pool for GitHub Actions" \
#     --display-name="Pool for GitHub Actions"

# # Add provider
# gcloud iam workload-identity-pools providers create-oidc "gh-provider" \
#     --location="global" \
#     --workload-identity-pool="$identity_pool_name" \
#     --issuer-uri="https://token.actions.githubusercontent.com" \
#     --attribute-mapping="google.subject=assertion.sub,attribute.repository_owner=assertion.repository_owner" \
#     --attribute-condition="assertion.repository_owner == '$org_name'"

# Add binding to the devops-svc-account for the identity pool to impersonate access (use a diff account to execute below cmd)
#gcloud iam service-accounts add-iam-policy-binding <devops_svc_account> --member="principalSet://iam.googleapis.com/projects/<gcp_project_num>/locations/global/workloadIdentityPools/github-pool/attribute.repository/<org_name>/<repo_name>" --role="roles/iam.serviceAccountTokenCreator"

# Add binding to the svc-account to allow granting of project-level binding
# gcloud projects add-iam-policy-binding <project_id> --member="serviceAccount:<devops_svc_account>@<project_id>.iam.gserviceaccount.com" --role="roles/resourcemanager.projectIamAdmin" --condition=None
## ----------------------------------------------------------------- ##

# Create Bucket for state file
echo "Creating TF State Bucket.."
gcloud storage buckets describe "gs://${tfstate_bucket_name}" || gcloud storage buckets create "gs://${tfstate_bucket_name}" \
    --location="${region^^}" \
    --uniform-bucket-level-access

# Create service account for Terraform
echo "Creating Service Account for Terraform"
gcloud iam service-accounts describe "$full_svc_account_id_tf" || gcloud iam service-accounts create "$svc_account_name_tf" --display-name="Service Account for Terraform"

# Create service account for Compute (Nodes)
echo "Creating Service Account for Kubernetes Nodes.."
gcloud iam service-accounts describe "$full_svc_account_id_compute" || gcloud iam service-accounts create "$svc_account_name_compute" --display-name="Service Account for Kube Cluster/Compute resources"

# Add policy to bucket
gcloud storage buckets add-iam-policy-binding "gs://${tfstate_bucket_name}" \
    --member="serviceAccount:${full_svc_account_id_tf}" \
    --role="roles/storage.admin"

# Allow GitHub OIDC identities to act as svc account        
gcloud iam service-accounts add-iam-policy-binding "$full_svc_account_id_tf" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${projectNum}/locations/global/workloadIdentityPools/${identity_pool_name}/attribute.repository_owner/${org_name}"

# Allow Terraform to request access tokens (needed by provider)
gcloud iam service-accounts add-iam-policy-binding "$full_svc_account_id_tf" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --member="principalSet://iam.googleapis.com/projects/${projectNum}/locations/global/workloadIdentityPools/${identity_pool_name}/attribute.repository_owner/${org_name}"

# Add bindings - TF Svc Account
gcloud projects add-iam-policy-binding "$projectId" \
  --member="serviceAccount:${full_svc_account_id_tf}" \
  --role="roles/container.admin" \
  --condition="expression=true,title=always_allow,description=No restrictions"

gcloud iam service-accounts add-iam-policy-binding "$full_svc_account_id_tf" \
  --member="serviceAccount:${full_svc_account_id_tf}" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding "$projectId" \
  --member="serviceAccount:${full_svc_account_id_tf}" \
  --role="roles/compute.viewer"

# Add bindings - Nodes Svc Account
gcloud projects add-iam-policy-binding "$projectId" \
    --member="serviceAccount:${full_svc_account_id_compute}" \
    --role="roles/container.defaultNodeServiceAccount"