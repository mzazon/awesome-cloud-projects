# Infrastructure as Code for Secure CI/CD Authentication with Workload Identity Federation and GitHub Actions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure CI/CD Authentication with Workload Identity Federation and GitHub Actions".

## Overview

This solution implements keyless authentication between GitHub Actions and Google Cloud using Workload Identity Federation (WIF), eliminating the need for service account keys while maintaining secure access to Google Cloud resources for CI/CD pipelines.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The infrastructure deploys the following components:

- **Workload Identity Pool**: Central identity namespace for external workloads
- **GitHub OIDC Provider**: Establishes trust relationship with GitHub's identity provider
- **Service Account**: Dedicated account with minimal required permissions for CI/CD operations
- **IAM Bindings**: Configures workload identity federation and service account permissions
- **Artifact Registry**: Container image repository for CI/CD artifacts
- **Sample Application**: Containerized demo application for testing the pipeline

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- GitHub repository with Actions enabled
- GitHub repository admin access for configuring secrets and workflows
- Appropriate Google Cloud permissions:
  - Project Owner or Editor role (for resource creation)
  - IAM Admin role (for configuring workload identity federation)
  - Security Admin role (for managing service accounts and policies)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution that supports Terraform configurations with Google Cloud native integration.

```bash
# Set your project and repository details
export PROJECT_ID="your-project-id"
export GITHUB_REPO_OWNER="your-github-username"
export GITHUB_REPO_NAME="your-repo-name"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create the Infrastructure Manager deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/wif-github-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars" \
    --labels="environment=production,team=devops"
```

### Using Terraform

Terraform provides cross-cloud compatibility and a mature ecosystem for infrastructure management.

```bash
# Set your project and repository details
export PROJECT_ID="your-project-id"
export GITHUB_REPO_OWNER="your-github-username"
export GITHUB_REPO_NAME="your-repo-name"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create a terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
region = "us-central1"
github_repo_owner = "${GITHUB_REPO_OWNER}"
github_repo_name = "${GITHUB_REPO_NAME}"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply -auto-approve
```

### Using Bash Scripts

The bash scripts provide a simple deployment option that follows the exact steps from the recipe.

```bash
# Set your project and repository details
export PROJECT_ID="your-project-id"
export GITHUB_REPO_OWNER="your-github-username"
export GITHUB_REPO_NAME="your-repo-name"

# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Run the deployment
./deploy.sh
```

## Configuration

### Environment Variables

All implementations support the following environment variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | None | Yes |
| `REGION` | Google Cloud region | `us-central1` | No |
| `GITHUB_REPO_OWNER` | GitHub repository owner/organization | None | Yes |
| `GITHUB_REPO_NAME` | GitHub repository name | None | Yes |
| `WIF_POOL_ID` | Workload Identity Pool ID | `github-pool-${random}` | No |
| `WIF_PROVIDER_ID` | OIDC Provider ID | `github-provider-${random}` | No |
| `SERVICE_ACCOUNT_ID` | Service Account ID | `github-actions-sa-${random}` | No |
| `ARTIFACT_REPO_NAME` | Artifact Registry repository name | `apps-${random}` | No |

### Terraform Variables

When using Terraform, customize the deployment by modifying `terraform.tfvars`:

```hcl
# Required variables
project_id = "your-project-id"
github_repo_owner = "your-github-username"
github_repo_name = "your-repo-name"

# Optional variables
region = "us-central1"
zone = "us-central1-a"
environment = "production"

# Resource naming (optional - will be auto-generated if not provided)
wif_pool_id = "github-pool-custom"
wif_provider_id = "github-provider-custom"
service_account_id = "github-actions-sa-custom"
artifact_repo_name = "apps-custom"
```

### Infrastructure Manager Configuration

Infrastructure Manager uses the same Terraform configuration but with Google Cloud native deployment management:

```yaml
# Example Infrastructure Manager metadata
apiVersion: config.gcp.crossplane.io/v1beta1
kind: InfrastructureManagerDeployment
metadata:
  name: wif-github-deployment
spec:
  location: us-central1
  source:
    localSource: "."
  serviceAccount: "projects/PROJECT_ID/serviceAccounts/infra-manager@PROJECT_ID.iam.gserviceaccount.com"
  labels:
    environment: production
    team: devops
```

## GitHub Actions Integration

After deploying the infrastructure, configure your GitHub repository:

### 1. Update Repository Settings

The deployment outputs will provide the necessary values for GitHub Actions configuration:

```bash
# Get the required values from Terraform outputs
terraform output workload_identity_provider
terraform output service_account_email
terraform output project_id
terraform output artifact_registry_url
```

### 2. Create GitHub Actions Workflow

Create `.github/workflows/deploy.yml` in your repository:

```yaml
name: Build and Deploy to Cloud Run

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  PROJECT_ID: ${{ secrets.PROJECT_ID }}
  REGION: us-central1
  ARTIFACT_REPO: apps
  SERVICE_NAME: demo-app

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    permissions:
      contents: read
      id-token: write
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
        service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}
    
    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2
    
    - name: Configure Docker for Artifact Registry
      run: gcloud auth configure-docker ${REGION}-docker.pkg.dev
    
    - name: Build and push Docker image
      run: |
        IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/demo-app"
        IMAGE_TAG="${IMAGE_NAME}:${GITHUB_SHA}"
        
        docker build -t ${IMAGE_TAG} ./sample-app
        docker push ${IMAGE_TAG}
        
        echo "IMAGE_TAG=${IMAGE_TAG}" >> $GITHUB_ENV
    
    - name: Deploy to Cloud Run
      run: |
        gcloud run deploy ${SERVICE_NAME} \
          --image ${IMAGE_TAG} \
          --region ${REGION} \
          --platform managed \
          --allow-unauthenticated \
          --port 8080 \
          --memory 512Mi \
          --cpu 1 \
          --min-instances 0 \
          --max-instances 10 \
          --set-env-vars="APP_VERSION=${GITHUB_SHA:0:8},ENVIRONMENT=production"
    
    - name: Get service URL
      run: |
        SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
          --region=${REGION} \
          --format='value(status.url)')
        echo "Service deployed at: ${SERVICE_URL}"
```

### 3. Configure GitHub Secrets

Add the following secrets to your GitHub repository (Settings → Secrets and variables → Actions):

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `PROJECT_ID` | Google Cloud project ID | `my-project-123456` |
| `WIF_PROVIDER` | Workload Identity Provider resource name | `projects/123456789/locations/global/workloadIdentityPools/github-pool-abc123/providers/github-provider-abc123` |
| `WIF_SERVICE_ACCOUNT` | Service Account email | `github-actions-sa-abc123@my-project-123456.iam.gserviceaccount.com` |

## Validation

### Verify Infrastructure Deployment

1. **Check Workload Identity Pool**:
   ```bash
   gcloud iam workload-identity-pools describe ${WIF_POOL_ID} \
       --project=${PROJECT_ID} \
       --location="global"
   ```

2. **Verify OIDC Provider**:
   ```bash
   gcloud iam workload-identity-pools providers describe ${WIF_PROVIDER_ID} \
       --project=${PROJECT_ID} \
       --location="global" \
       --workload-identity-pool=${WIF_POOL_ID}
   ```

3. **Test Service Account Permissions**:
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:serviceAccount:${SERVICE_ACCOUNT_EMAIL}"
   ```

### Test GitHub Actions Integration

1. **Trigger Workflow**: Push a commit to your main branch
2. **Monitor Execution**: Check GitHub Actions tab for workflow status
3. **Verify Deployment**: Confirm Cloud Run service is deployed successfully
4. **Test Application**: Access the deployed service URL

## Troubleshooting

### Common Issues

1. **Authentication Failure**:
   ```bash
   # Check workload identity pool configuration
   gcloud iam workload-identity-pools describe ${WIF_POOL_ID} \
       --project=${PROJECT_ID} \
       --location="global" \
       --format="yaml"
   ```

2. **Permission Denied**:
   ```bash
   # Verify service account has required roles
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
       --format="table(bindings.role)"
   ```

3. **Repository Access Issues**:
   ```bash
   # Check attribute condition in provider
   gcloud iam workload-identity-pools providers describe ${WIF_PROVIDER_ID} \
       --project=${PROJECT_ID} \
       --location="global" \
       --workload-identity-pool=${WIF_POOL_ID} \
       --format="value(attributeCondition)"
   ```

### Debug Commands

```bash
# Test token exchange (from GitHub Actions runner)
curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
     "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=//iam.googleapis.com/${WIF_PROVIDER_NAME}"

# Validate service account impersonation
gcloud auth print-access-token --impersonate-service-account=${SERVICE_ACCOUNT_EMAIL}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/wif-github-deployment \
    --async
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
cd scripts/
./destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Remove workload identity federation components
gcloud iam workload-identity-pools providers delete ${WIF_PROVIDER_ID} \
    --project=${PROJECT_ID} \
    --location="global" \
    --workload-identity-pool=${WIF_POOL_ID} \
    --quiet

gcloud iam workload-identity-pools delete ${WIF_POOL_ID} \
    --project=${PROJECT_ID} \
    --location="global" \
    --quiet

# Delete service account
gcloud iam service-accounts delete ${SERVICE_ACCOUNT_EMAIL} \
    --project=${PROJECT_ID} \
    --quiet

# Remove Artifact Registry repository
gcloud artifacts repositories delete ${ARTIFACT_REPO_NAME} \
    --location=${REGION} \
    --project=${PROJECT_ID} \
    --quiet

# Delete Cloud Run service (if deployed)
gcloud run services delete ${SERVICE_NAME} \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --quiet
```

## Security Considerations

### Best Practices Implemented

1. **Least Privilege**: Service account has minimal required permissions
2. **Repository Restriction**: Attribute conditions limit access to specific repository
3. **Short-lived Tokens**: GitHub OIDC tokens automatically expire
4. **No Long-lived Keys**: Eliminates service account key management
5. **Audit Trail**: All actions logged in Google Cloud audit logs

### Additional Security Measures

1. **Branch Protection**: Limit federation to protected branches only
2. **Environment Restrictions**: Use separate service accounts for different environments
3. **Token Scoping**: Configure audience restrictions for OIDC tokens
4. **Regular Reviews**: Periodically audit workload identity federation configurations

```yaml
# Example: Restrict to main branch only
attribute_condition = "assertion.ref=='refs/heads/main'"

# Example: Environment-specific service accounts
attribute_condition = "assertion.repository_owner=='your-org' && assertion.environment=='production'"
```

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../secure-cicd-authentication-workload-identity-federation-github-actions.md)
- [Google Cloud Workload Identity Federation documentation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub Actions OIDC documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Google Cloud IAM best practices](https://cloud.google.com/iam/docs/using-iam-securely)

## Cost Estimation

### Resource Costs

- **Workload Identity Federation**: No additional cost
- **Service Account**: No additional cost
- **Artifact Registry**: Storage and data transfer charges apply
- **Cloud Run**: Pay-per-use pricing for compute resources
- **IAM Operations**: Minimal cost for policy evaluations

### Cost Optimization Tips

1. **Artifact Registry**: Use lifecycle policies to clean up old images
2. **Cloud Run**: Configure appropriate min/max instances for your workload
3. **Regional Deployment**: Deploy in regions close to your users
4. **Resource Monitoring**: Use Google Cloud Monitoring to track usage

For detailed pricing information, visit the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator).