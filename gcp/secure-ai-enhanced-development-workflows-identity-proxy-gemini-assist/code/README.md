# Infrastructure as Code for Secure AI-Enhanced Development Workflows with Cloud Identity-Aware Proxy and Gemini Code Assist

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure AI-Enhanced Development Workflows with Cloud Identity-Aware Proxy and Gemini Code Assist".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI v450.0.0 or later installed and configured
- Google Cloud account with billing enabled and Organization Admin permissions
- VS Code or JetBrains IDE with Gemini Code Assist extension installed
- Basic understanding of Google Cloud IAM, zero-trust security principles, and containerized applications
- Appropriate permissions for resource creation:
  - Organization Admin (for Cloud IAP configuration)
  - Project Creator
  - Billing Account Administrator
  - Cloud KMS Admin
  - Secret Manager Admin
  - Cloud Build Editor
  - Cloud Run Admin
  - Workstations Admin
  - Service Account Admin

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended native IaC solution that provides GitOps-style deployment with built-in state management.

```bash
# Set up environment variables
export PROJECT_ID="secure-dev-$(date +%s)"
export REGION="us-central1"
export ORG_ID=$(gcloud organizations list --format="value(name)" --limit=1)

# Create and configure project
gcloud projects create ${PROJECT_ID} --organization=${ORG_ID}
gcloud config set project ${PROJECT_ID}

# Link billing account
BILLING_ACCOUNT=$(gcloud billing accounts list --format="value(name)" --limit=1)
gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT}

# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/secure-dev-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/secure-dev-deployment
```

### Using Terraform

Terraform provides a mature, multi-cloud infrastructure as code solution with extensive Google Cloud provider support.

```bash
# Set up environment variables
export PROJECT_ID="secure-dev-$(date +%s)"
export REGION="us-central1"
export ORG_ID=$(gcloud organizations list --format="value(name)" --limit=1)

# Create and configure project
gcloud projects create ${PROJECT_ID} --organization=${ORG_ID}
gcloud config set project ${PROJECT_ID}

# Link billing account
BILLING_ACCOUNT=$(gcloud billing accounts list --format="value(name)" --limit=1)
gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT}

# Initialize and deploy with Terraform
cd terraform/

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a step-by-step deployment that follows the original recipe instructions.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete infrastructure
./scripts/deploy.sh

# Follow the interactive prompts for configuration
# The script will create all necessary resources and provide status updates
```

## Architecture Overview

This infrastructure deploys:

- **Zero Trust Security Layer**: Cloud Identity-Aware Proxy with OAuth 2.0 authentication
- **Development Environment**: Cloud Workstations with Gemini Code Assist integration
- **Secret Management**: Cloud Secrets Manager with Cloud KMS encryption
- **CI/CD Pipeline**: Cloud Build with Artifact Registry and Cloud Source Repositories
- **Application Platform**: Cloud Run services with secure secret access
- **Monitoring & Logging**: Cloud Monitoring and Cloud Logging integration

## Configuration Options

### Infrastructure Manager Configuration

The Infrastructure Manager deployment uses the following key configuration files:

- `main.yaml`: Primary infrastructure configuration
- `inputs.yaml`: Customizable input parameters
- `outputs.yaml`: Infrastructure outputs and endpoints

Key customizable parameters:
- `project_id`: Target Google Cloud project
- `region`: Deployment region
- `org_id`: Organization ID for IAP configuration
- `app_name`: Application name prefix
- `enable_gemini`: Enable Gemini Code Assist integration

### Terraform Configuration

The Terraform implementation provides extensive customization through variables:

```hcl
# Example terraform.tfvars
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
org_id = "your-org-id"

# Application configuration
app_name = "secure-dev-app"
container_image = "gcr.io/cloudrun/hello"

# Workstation configuration
workstation_machine_type = "e2-standard-4"
workstation_disk_size = 100

# Security configuration
enable_iap = true
enable_gemini_code_assist = true
```

### Bash Script Configuration

The bash scripts use environment variables for configuration:

```bash
# Core configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ORG_ID="your-org-id"

# Optional customization
export WORKSTATION_MACHINE_TYPE="e2-standard-4"
export CONTAINER_IMAGE="gcr.io/cloudrun/hello"
export ENABLE_MONITORING="true"
```

## Post-Deployment Setup

After successful deployment, complete these additional steps:

1. **Configure OAuth Consent Screen**:
   ```bash
   # Navigate to Google Cloud Console > APIs & Services > OAuth consent screen
   # Configure application details and authorized domains
   ```

2. **Add Development Team Members**:
   ```bash
   # Grant IAP access to team members
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:developer@company.com" \
       --role="roles/iap.httpsResourceAccessor"
   ```

3. **Configure IDE Extensions**:
   - Install Gemini Code Assist extension in VS Code or JetBrains IDE
   - Configure authentication using `gcloud auth application-default login`
   - Enable Gemini Code Assist in your IDE settings

4. **Access Cloud Workstation**:
   ```bash
   # Get workstation access URL
   gcloud workstations get-iam-policy ${WORKSTATION_NAME} \
       --cluster=secure-dev-cluster \
       --config=secure-dev-config \
       --region=${REGION}
   
   # Access at: https://workstations.googleusercontent.com/
   ```

## Verification Steps

1. **Test IAP Protection**:
   ```bash
   SERVICE_URL=$(gcloud run services describe ${APP_NAME} \
       --region=${REGION} \
       --format="value(status.url)")
   
   # Unauthenticated access should return 403
   curl -s -o /dev/null -w "%{http_code}" ${SERVICE_URL}/health
   ```

2. **Verify Secret Access**:
   ```bash
   # Test secret retrieval
   gcloud secrets versions access latest --secret=${SECRET_NAME}-db
   ```

3. **Test Authenticated Application Access**:
   ```bash
   # Generate IAP token and test authenticated access
   IAP_TOKEN=$(gcloud auth print-identity-token)
   curl -H "Authorization: Bearer ${IAP_TOKEN}" ${SERVICE_URL}/api/config
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/secure-dev-deployment

# Delete the project (optional, removes all resources)
gcloud projects delete ${PROJECT_ID}
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy

# Confirm with 'yes' when prompted

# Delete the project (optional)
gcloud projects delete ${PROJECT_ID}
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow interactive prompts for confirmation
# The script will remove resources in proper order
```

## Troubleshooting

### Common Issues

1. **IAP Configuration Errors**:
   - Ensure you have Organization Admin permissions
   - Verify OAuth consent screen is properly configured
   - Check that the OAuth brand exists for your organization

2. **Workstation Access Issues**:
   - Confirm workstation is in RUNNING state
   - Verify IAM permissions for workstation access
   - Check network connectivity and firewall rules

3. **Secret Manager Access Denied**:
   - Verify service account has `secretmanager.secretAccessor` role
   - Confirm secrets exist in the correct project
   - Check Cloud KMS permissions for encryption keys

4. **Cloud Build Failures**:
   - Verify Cloud Build service account permissions
   - Check Artifact Registry repository exists
   - Confirm source code is properly structured

### Support Resources

- [Google Cloud IAP Documentation](https://cloud.google.com/iap/docs)
- [Gemini Code Assist Documentation](https://cloud.google.com/gemini/docs/code-assist)
- [Cloud Workstations Documentation](https://cloud.google.com/workstations/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Security Considerations

- All resources are deployed with least-privilege IAM policies
- Secrets are encrypted using Cloud KMS with automatic key rotation
- Network access is controlled through Cloud IAP zero-trust policies
- Application containers run as non-root users
- All communication uses TLS encryption
- Audit logging is enabled for all administrative actions

## Cost Optimization

- Cloud Workstations automatically shut down after inactivity
- Cloud Run scales to zero when not in use
- Secrets Manager charges only for active secret versions
- Artifact Registry provides efficient container image storage
- Cloud Build offers generous free tier limits

## Customization

To customize this deployment for your environment:

1. **Modify Resource Sizing**:
   - Adjust workstation machine types and disk sizes
   - Configure Cloud Run memory and CPU limits
   - Customize Cloud Build machine types

2. **Add Additional Services**:
   - Integrate with Cloud SQL for application databases
   - Add Cloud Storage buckets for artifact storage
   - Configure Cloud Monitoring dashboards

3. **Enhance Security**:
   - Implement VPC Service Controls
   - Add Binary Authorization for container security
   - Configure Security Command Center monitoring

4. **Scale for Teams**:
   - Create multiple workstation configurations
   - Implement project-level IAM groups
   - Add Cloud Asset Inventory for governance

## Support

For issues with this infrastructure code, refer to:
- The original recipe documentation
- Google Cloud provider documentation  
- Community support forums
- Google Cloud Support (for enterprise customers)

## License

This infrastructure code is provided under the same license as the parent repository.