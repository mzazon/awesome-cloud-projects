# Infrastructure as Code for Resource Allocation with Cloud Quotas API and Cloud Run GPU

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Resource Allocation with Cloud Quotas API and Cloud Run GPU".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Quotas API
  - Cloud Run GPU
  - Cloud Functions
  - Cloud Monitoring
  - Firestore
  - Cloud Storage
  - Cloud Scheduler
- Docker (for container image building)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $20-50 for initial testing (includes GPU usage, function executions, and storage)

> **Note**: GPU quotas may have approval delays and regional limitations. Review [Google Cloud GPU availability](https://cloud.google.com/compute/docs/gpus/gpu-regions-zones) before proceeding.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Clone the repository and navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create quota-allocation-deployment \
    --location=${REGION} \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/quota-allocation-repo" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe quota-allocation-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys an intelligent GPU quota management system with the following components:

- **Cloud Run GPU Service**: AI inference platform with automatic scaling
- **Cloud Functions**: Intelligent quota analysis and decision engine
- **Cloud Quotas API**: Dynamic GPU quota management
- **Cloud Monitoring**: Resource utilization tracking and alerting
- **Firestore**: Usage history and analytics storage
- **Cloud Storage**: Quota policies and configuration management
- **Cloud Scheduler**: Automated quota analysis triggers

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

```yaml
variables:
  project_id:
    type: string
    description: "Google Cloud Project ID"
  region:
    type: string
    description: "Deployment region"
    default: "us-central1"
  gpu_type:
    type: string
    description: "GPU type for Cloud Run"
    default: "nvidia-l4"
  max_gpu_quota:
    type: number
    description: "Maximum GPU quota per region"
    default: 10
```

### Terraform Variables

Customize your deployment by creating a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# GPU Configuration
gpu_type = "nvidia-l4"
max_gpu_instances = 10
min_gpu_instances = 1

# Function Configuration
function_memory = "512MB"
function_timeout = "540s"

# Storage Configuration
bucket_location = "US"
bucket_storage_class = "STANDARD"

# Monitoring Configuration
alert_threshold = 0.85
analysis_schedule = "*/15 * * * *"

# Cost Optimization
enable_preemptible = true
max_cost_per_hour = 50.0

# Tags
labels = {
  environment = "production"
  team        = "platform"
  purpose     = "quota-management"
}
```

### Script Configuration

Edit variables at the top of `scripts/deploy.sh`:

```bash
# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_GPU_TYPE="nvidia-l4"
DEFAULT_MAX_QUOTA=10
DEFAULT_FUNCTION_MEMORY="512MB"
```

## Deployment Verification

After deployment, verify the system is working correctly:

### 1. Check Service Endpoints

```bash
# Get Cloud Run service URL
SERVICE_URL=$(gcloud run services describe ai-inference-* \
    --region=${REGION} \
    --format="value(status.url)")

# Test AI inference endpoint
curl -X POST ${SERVICE_URL}/infer \
    -H "Content-Type: application/json" \
    -d '{"model": "test", "complexity": "medium"}'

# Check service health
curl ${SERVICE_URL}/
```

### 2. Verify Quota Management Function

```bash
# List Cloud Functions
gcloud functions list --regions=${REGION}

# Test quota analysis function
FUNCTION_URL=$(gcloud functions describe quota-manager-* \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d "{\"project_id\":\"${PROJECT_ID}\",\"region\":\"${REGION}\"}"
```

### 3. Check Monitoring and Alerts

```bash
# View monitoring dashboards
echo "Monitoring Console: https://console.cloud.google.com/monitoring"

# Check alert policies
gcloud alpha monitoring policies list
```

### 4. Verify Scheduled Jobs

```bash
# List Cloud Scheduler jobs
gcloud scheduler jobs list --location=${REGION}

# Check job execution history
gcloud scheduler jobs describe quota-analysis-job \
    --location=${REGION}
```

## Cost Monitoring

Monitor costs associated with this deployment:

```bash
# Check current GPU usage costs
gcloud billing accounts list
gcloud billing projects link ${PROJECT_ID} --billing-account=YOUR_BILLING_ACCOUNT

# View cost breakdown by service
echo "Billing Console: https://console.cloud.google.com/billing"
```

## Troubleshooting

### Common Issues

1. **GPU Quota Approval Required**
   ```bash
   # Check current GPU quotas
   gcloud compute project-info describe --format="table(quotas.metric,quotas.limit)"
   
   # Request quota increase if needed
   echo "Request quota increase: https://console.cloud.google.com/quotas"
   ```

2. **Cloud Run GPU Not Available in Region**
   ```bash
   # Check GPU availability by region
   gcloud compute accelerator-types list
   ```

3. **Function Deployment Timeout**
   ```bash
   # Check function logs
   gcloud functions logs read quota-manager-* --region=${REGION}
   ```

4. **Storage Permission Issues**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify Cloud Run service status
gcloud run services list --region=${REGION}

# Check Firestore database
gcloud firestore databases list

# View function execution logs
gcloud functions logs read --region=${REGION} --limit=50
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete quota-allocation-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Clean up state files
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion
gcloud run services list --region=${REGION}
gcloud functions list --region=${REGION}
gcloud scheduler jobs list --location=${REGION}
```

### Manual Cleanup (if needed)

```bash
# Remove remaining resources manually
gcloud run services delete ai-inference-* --region=${REGION} --quiet
gcloud functions delete quota-manager-* --region=${REGION} --quiet
gcloud scheduler jobs delete quota-analysis-job --location=${REGION} --quiet
gsutil -m rm -r gs://${PROJECT_ID}-quota-policies-*

# Note: Firestore database requires manual deletion via console
echo "Manually delete Firestore database: https://console.cloud.google.com/firestore"
```

## Customization

### Extending the Solution

1. **Multi-Region Deployment**: Modify variables to deploy across multiple regions
2. **Additional GPU Types**: Update configuration to support different GPU families
3. **Enhanced Monitoring**: Add custom metrics and dashboards
4. **Cost Optimization**: Implement more sophisticated cost-aware allocation algorithms

### Integration Points

- **CI/CD Pipelines**: Integrate with Cloud Build for automated deployments
- **External Monitoring**: Connect to third-party monitoring solutions
- **Enterprise Security**: Integrate with organization security policies
- **Cost Management**: Connect to FinOps tools and processes

## Security Considerations

- All services use Google Cloud IAM for authentication and authorization
- Service accounts follow principle of least privilege
- Data is encrypted in transit and at rest
- Network access is restricted through VPC and firewall rules
- Audit logging is enabled for all quota management operations

## Performance Tuning

- Cloud Run instances auto-scale based on demand
- Function memory and timeout can be adjusted based on workload
- GPU quotas are dynamically managed based on utilization patterns
- Storage and database performance scales automatically with load

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation:
   - [Cloud Quotas API](https://cloud.google.com/docs/quotas)
   - [Cloud Run GPU](https://cloud.google.com/run/docs/configuring/services/gpu)
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and adapt according to your organization's requirements and security policies.