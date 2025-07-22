# Infrastructure as Code for Secure Package Distribution Workflows with Artifact Registry and Secret Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Package Distribution Workflows with Artifact Registry and Secret Manager".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Artifact Registry Admin
  - Secret Manager Admin
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Cloud Tasks Admin
  - Service Account Admin
  - IAM Admin
  - Logging Admin
  - Monitoring Admin
- Docker installed locally for testing container workflows
- For Terraform: Terraform v1.5+ installed

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Set variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/secure-package-distribution \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/"

# Monitor deployment
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/secure-package-distribution
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud artifacts repositories list
gcloud secrets list
gcloud functions list
```

## Architecture Overview

This infrastructure creates a secure package distribution system with the following components:

- **Artifact Registry**: Multi-format repositories (Docker, NPM, Maven) for secure package storage
- **Secret Manager**: Encrypted credential storage with environment-specific secrets
- **Cloud Functions**: Serverless package distribution logic with IAM integration
- **Cloud Scheduler**: Automated job scheduling for regular distributions
- **Cloud Tasks**: Reliable task queuing with retry mechanisms
- **IAM Service Account**: Least-privilege access control
- **Cloud Monitoring**: Comprehensive logging and alerting

## Configuration

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
# Project and region settings
project_id: "your-project-id"
region: "us-central1"

# Repository configuration
repository_base_name: "secure-packages"
enable_vulnerability_scanning: true

# Function configuration
function_memory: "512MB"
function_timeout: "300s"

# Scheduler configuration
nightly_schedule: "0 2 * * *"
weekly_schedule: "0 6 * * 1"
timezone: "America/New_York"
```

### Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Repository settings
repository_base_name = "secure-packages"
enable_vulnerability_scanning = true

# Function settings
function_memory    = "512MB"
function_timeout   = "300s"
function_runtime   = "python311"

# Scheduler settings
nightly_schedule = "0 2 * * *"
weekly_schedule  = "0 6 * * 1"
timezone        = "America/New_York"

# Monitoring settings
enable_monitoring = true
alert_email      = "admin@example.com"

# Labels for resource organization
labels = {
  environment = "production"
  team        = "platform"
  purpose     = "package-distribution"
}
```

### Bash Script Environment Variables

Edit `scripts/deploy.sh` to customize:

```bash
# Project settings
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Repository settings
export REPO_BASE_NAME="secure-packages"
export ENABLE_VULNERABILITY_SCANNING="true"

# Function settings
export FUNCTION_MEMORY="512MB"
export FUNCTION_TIMEOUT="300s"

# Scheduler settings
export NIGHTLY_SCHEDULE="0 2 * * *"
export WEEKLY_SCHEDULE="0 6 * * 1"
export TIMEZONE="America/New_York"
```

## Testing and Validation

### Verify Artifact Registry

```bash
# List repositories
gcloud artifacts repositories list --location=${REGION}

# Check repository details
gcloud artifacts repositories describe ${REPO_NAME} --location=${REGION}

# Test repository access
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

### Test Secret Manager

```bash
# List secrets
gcloud secrets list --filter="labels.purpose=registry-auth"

# Test secret access
gcloud secrets versions access latest --secret="registry-credentials-dev"
```

### Test Cloud Function

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe package-distributor-function \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test function
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "package_name": "test-package",
      "package_version": "1.0.0",
      "environment": "development"
    }'
```

### Test Scheduler Jobs

```bash
# List scheduled jobs
gcloud scheduler jobs list --location=${REGION}

# Run job manually
gcloud scheduler jobs run package-distribution-nightly --location=${REGION}

# Check job execution history
gcloud scheduler jobs describe package-distribution-nightly --location=${REGION}
```

## Monitoring and Logging

### View Logs

```bash
# Function logs
gcloud functions logs read package-distributor-function --region=${REGION}

# Scheduler logs
gcloud logging read "resource.type=\"gce_instance\" AND logName=\"projects/${PROJECT_ID}/logs/cloudscheduler.googleapis.com%2Fexecutions\""

# Task queue logs
gcloud logging read "resource.type=\"cloud_tasks_queue\""
```

### Monitor Metrics

```bash
# Check distribution success metrics
gcloud logging metrics list --filter="name:package_distribution_success"

# View alerting policies
gcloud alpha monitoring policies list
```

## Security Considerations

### IAM Best Practices

- Service account uses least-privilege permissions
- Secrets are accessed only by authorized services
- Function execution is restricted to authenticated requests
- Repository access is controlled through IAM policies

### Secret Management

- All credentials are encrypted at rest in Secret Manager
- Secrets are versioned and can be rotated
- Environment-specific secrets prevent cross-environment access
- Audit logs track all secret access

### Network Security

- Cloud Functions use VPC connectors for private network access
- Artifact Registry supports private repositories
- All communication uses TLS encryption
- IAM conditions can restrict access by IP or time

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check function logs
   gcloud functions logs read package-distributor-function --region=${REGION}
   
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Scheduler jobs not executing**:
   ```bash
   # Check scheduler status
   gcloud scheduler jobs describe package-distribution-nightly --location=${REGION}
   
   # Verify Cloud Tasks queue
   gcloud tasks queues describe package-distribution-queue --location=${REGION}
   ```

3. **Secret access denied**:
   ```bash
   # Check secret IAM policies
   gcloud secrets get-iam-policy registry-credentials-dev
   
   # Verify service account has secretmanager.secretAccessor role
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.role:roles/secretmanager.secretAccessor"
   ```

### Debug Commands

```bash
# Enable debug logging
export CLOUDSDK_CORE_VERBOSITY=debug

# Check API enablement
gcloud services list --enabled --filter="name:artifactregistry.googleapis.com OR name:secretmanager.googleapis.com"

# Verify resource creation
gcloud resource-manager liens list --project=${PROJECT_ID}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/secure-package-distribution

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud artifacts repositories list --location=${REGION}
gcloud secrets list
gcloud functions list --region=${REGION}
gcloud scheduler jobs list --location=${REGION}
gcloud tasks queues list --location=${REGION}
gcloud iam service-accounts list --filter="email:package-distributor-sa-*"
```

## Cost Optimization

### Cost Monitoring

```bash
# Set up billing budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Package Distribution Budget" \
    --budget-amount=50USD \
    --threshold-rule=percent=90

# Monitor resource usage
gcloud logging read "resource.type=\"cloud_function\" AND resource.labels.function_name=\"package-distributor-function\"" \
    --format="table(timestamp,resource.labels.function_name,jsonPayload.executionId)"
```

### Cost Optimization Tips

1. **Artifact Registry**: Use lifecycle policies to automatically delete old packages
2. **Cloud Functions**: Optimize memory allocation and timeout settings
3. **Secret Manager**: Use fewer secret versions and enable auto-deletion
4. **Cloud Scheduler**: Optimize job frequency based on business requirements
5. **Monitoring**: Set up alerting to avoid unexpected charges

## Advanced Configuration

### Multi-Region Deployment

```bash
# Deploy to multiple regions
export REGIONS=("us-central1" "us-east1" "europe-west1")

for region in "${REGIONS[@]}"; do
    export REGION=$region
    ./scripts/deploy.sh
done
```

### Integration with CI/CD

```yaml
# Example Cloud Build configuration
steps:
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        cd terraform/
        terraform init
        terraform apply -auto-approve
```

### Custom Package Types

```bash
# Add support for additional package formats
gcloud artifacts repositories create ${REPO_NAME}-python \
    --repository-format=python \
    --location=${REGION} \
    --description="Python packages repository"

gcloud artifacts repositories create ${REPO_NAME}-generic \
    --repository-format=generic \
    --location=${REGION} \
    --description="Generic packages repository"
```

## Support

For issues with this infrastructure code, refer to:

1. [Original recipe documentation](../secure-package-distribution-workflows-artifact-registry-secret-manager.md)
2. [Google Cloud Artifact Registry documentation](https://cloud.google.com/artifact-registry/docs)
3. [Google Cloud Secret Manager documentation](https://cloud.google.com/secret-manager/docs)
4. [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
5. [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest)

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation for any configuration changes
3. Ensure security best practices are maintained
4. Add appropriate resource labels for organization
5. Update cost estimates if resource usage changes

## License

This infrastructure code is provided as-is for educational and implementation purposes. Ensure compliance with your organization's security and governance policies before using in production environments.