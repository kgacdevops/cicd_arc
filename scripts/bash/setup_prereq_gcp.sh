#!/bin/bash
set -e

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
# gcloud iam service-accounts add-iam-policy-binding <devops_svc_account> --member="principalSet://iam.googleapis.com/projects/<gcp_project_num>/locations/global/workloadIdentityPools/github-pool/attribute.repository/<org_name>/<repo_name>" --role="roles/iam.serviceAccountTokenCreator"

# Add binding to the svc-account to allow granting of project-level binding
# gcloud projects add-iam-policy-binding <project_id> --member="serviceAccount:<devops_svc_account>@<project_id>.iam.gserviceaccount.com" --role="roles/resourcemanager.projectIamAdmin" --condition=None
## ----------------------------------------------------------------- ##

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

echo "Create Bucket for state file.."
gcloud storage buckets describe "gs://${tfstate_bucket_name}" || gcloud storage buckets create "gs://${tfstate_bucket_name}" \
    --location="${region^^}" \
    --uniform-bucket-level-access

echo "Creating Service Accounts.."
serviceAccountsList="$svc_account_name_tf,$svc_account_name_compute"
IFS="," read -ra SVCACCOUNTS <<< "$serviceAccountsList"
for sa in "${SVCACCOUNTS[@]}"; do
  gcloud iam service-accounts describe "${sa}@${projectId}.iam.gserviceaccount.com" || gcloud iam service-accounts create "$sa" --display-name="Terrform managed SA"
done

echo "Updating policy on TF State Bucket.."
gcloud storage buckets add-iam-policy-binding "gs://${tfstate_bucket_name}" --member="serviceAccount:${full_svc_account_id_tf}" --role="roles/storage.admin"

echo "Allow usage of service accounts.."
gcloud iam service-accounts add-iam-policy-binding "${full_svc_account_id_tf}" --member="serviceAccount:${full_svc_account_id_tf}" --role="roles/iam.serviceAccountUser"
gcloud iam service-accounts add-iam-policy-binding "${full_svc_account_id_compute}" --member="serviceAccount:${full_svc_account_id_tf}" --role="roles/iam.serviceAccountUser"

echo "Adding IAM bindings on TF Svc Account and Identity Pool.."
identityPoolRoles="iam.workloadIdentityUser,iam.serviceAccountTokenCreator"
IFS="," read -ra POOLROLE <<< "$identityPoolRoles"
for idrole in "${POOLROLE[@]}"; do
  gcloud iam service-accounts add-iam-policy-binding "$full_svc_account_id_tf" --member="principalSet://iam.googleapis.com/projects/${projectNum}/locations/global/workloadIdentityPools/${identity_pool_name}/attribute.repository/${org_name}/github_arc" --role="roles/${idrole}"
done

echo "Adding Project-level bindings on TF Svc Account.."
projLevelRoles="artifactregistry.reader,compute.networkAdmin,compute.securityAdmin,compute.viewer,container.admin,iam.securityReviewer,iam.serviceAccountAdmin,storage.admin"
IFS="," read -ra PROJROLE <<< "$projLevelRoles"
for prole in "${PROJROLE[@]}"; do
  gcloud projects add-iam-policy-binding "$projectId" --member="serviceAccount:${full_svc_account_id_tf}" --role="roles/${prole}" --condition=None
done
echo "Adding project-level bindings on Kube Nodes Svc Account.."
gcloud projects add-iam-policy-binding "$projectId" --member="serviceAccount:${full_svc_account_id_compute}" --role="roles/container.defaultNodeServiceAccount" --condition=None