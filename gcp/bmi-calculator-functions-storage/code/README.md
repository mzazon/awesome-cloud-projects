# Infrastructure as Code for BMI Calculator API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "BMI Calculator API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (Cloud Functions Admin)
  - Cloud Storage (Storage Admin)
  - IAM (Security Admin for service account management)
  - Project management (Project Editor or Owner)
- Python 3.11+ for local function development and testing
- Basic understanding of serverless architecture and HTTP APIs

> **Note**: This infrastructure creates billable Google Cloud resources. Review the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for cost estimates.

## Architecture Overview

The infrastructure deploys:
- **Cloud Function** (2nd generation): HTTP-triggered serverless function for BMI calculations
- **Cloud Storage Bucket**: Persistent storage for calculation history
- **IAM Service Account**: Dedicated service account with minimal required permissions
- **API Enablement**: Required Google Cloud APIs (Cloud Functions, Cloud Storage, Cloud Build)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code, providing native integration with Google Cloud services and built-in state management.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/bmi-calculator \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/bmi-calculator
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive community support with detailed state management and resource planning capabilities.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform (downloads providers and modules)
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure changes
terraform apply

# View outputs (function URL, bucket name, etc.)
terraform output
```

### Using Bash Scripts

Bash scripts provide direct Google Cloud CLI commands for straightforward deployment and are ideal for CI/CD pipelines or quick testing scenarios.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy all resources
./scripts/deploy.sh

# Test the deployed function
./scripts/test-function.sh

# View deployment status
./scripts/status.sh
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
# Required variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"  # or your preferred region

# Optional customization variables
export FUNCTION_NAME="bmi-calculator"
export BUCKET_NAME="bmi-history-$(date +%s)"
export MEMORY_SIZE="256MB"
export TIMEOUT="60s"
```

### Infrastructure Manager Variables

Edit `infrastructure-manager/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "bmi-calculator"
bucket_name = "bmi-history-unique-suffix"
memory_mb = 256
timeout_seconds = 60
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "bmi-calculator"
storage_bucket_name = "bmi-history-unique-suffix"
function_memory = "256MB"
function_timeout = 60
enable_cors = true
```

## Testing the Deployment

After successful deployment, test the BMI Calculator API:

```bash
# Get the function URL (from Terraform output or gcloud command)
FUNCTION_URL=$(terraform output -raw function_url)
# OR
FUNCTION_URL=$(gcloud functions describe bmi-calculator --gen2 --region=us-central1 --format="value(serviceConfig.uri)")

# Test with valid BMI calculation
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"height": 1.75, "weight": 70}' \
    | python3 -m json.tool

# Expected response:
# {
#   "timestamp": "2025-01-XX...",
#   "height": 1.75,
#   "weight": 70,
#   "bmi": 22.86,
#   "category": "Normal weight"
# }

# Test error handling
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"height": 0, "weight": 70}' \
    | python3 -m json.tool

# Verify data storage
gsutil ls gs://your-bucket-name/calculations/
```

## Monitoring and Observability

### View Function Logs

```bash
# Stream function logs in real-time
gcloud functions logs read bmi-calculator --gen2 --region=us-central1 --follow

# View specific log entries
gcloud functions logs read bmi-calculator --gen2 --region=us-central1 --limit=50
```

### Monitor Function Metrics

```bash
# View function invocation metrics
gcloud monitoring metrics list --filter="resource.type=cloud_function"

# Create custom dashboard (requires additional setup)
gcloud monitoring dashboards create --config-from-file=monitoring-dashboard.json
```

### Check Storage Usage

```bash
# View bucket contents and size
gsutil du -sh gs://your-bucket-name

# List recent calculations
gsutil ls -l gs://your-bucket-name/calculations/ | tail -10
```

## Cleanup

> **Warning**: Cleanup operations are irreversible and will permanently delete all resources and data.

### Using Infrastructure Manager

```bash
# Delete the deployment and all associated resources
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/bmi-calculator

# Verify deletion
gcloud infra-manager deployments list --project=${PROJECT_ID} --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Preview resources to be destroyed
terraform plan -destroy

# Destroy all managed resources
terraform destroy

# Clean up state files (optional)
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script with confirmation
./scripts/destroy.sh

# Force cleanup without prompts (use with caution)
./scripts/destroy.sh --force
```

### Manual Cleanup Verification

```bash
# Verify function deletion
gcloud functions list --gen2 --regions=us-central1

# Verify bucket deletion
gsutil ls -p your-project-id

# Check for remaining IAM service accounts
gcloud iam service-accounts list --project=your-project-id
```

## Customization

### Function Configuration

Modify the Cloud Function settings by updating variables in your chosen IaC tool:

- **Memory**: Adjust based on expected workload (128MB - 8GB)
- **Timeout**: Set appropriate timeout for your use case (1s - 540s)
- **Concurrency**: Configure concurrent request handling (1-1000)
- **Environment Variables**: Add additional configuration as needed

### Storage Configuration

Customize Cloud Storage bucket settings:

- **Storage Class**: STANDARD, NEARLINE, COLDLINE, or ARCHIVE
- **Location**: Single region, dual-region, or multi-region
- **Lifecycle Policies**: Automatic data lifecycle management
- **Versioning**: Enable object versioning for data protection

### Security Enhancements

Implement additional security measures:

- **VPC Connector**: Connect function to private network
- **IAM Conditions**: Add conditional access controls
- **Cloud KMS**: Encrypt data with customer-managed keys
- **Cloud Armor**: Add DDoS protection and WAF rules

### Integration Options

Extend the solution with additional Google Cloud services:

- **Cloud Monitoring**: Custom metrics and alerting
- **Cloud Pub/Sub**: Event-driven architectures
- **BigQuery**: Analytics and data warehousing
- **Firebase**: Mobile and web app integration

## Troubleshooting

### Common Issues

**Function deployment fails:**
```bash
# Check API enablement
gcloud services list --enabled --project=your-project-id

# Verify IAM permissions
gcloud projects get-iam-policy your-project-id
```

**Storage access denied:**
```bash
# Check service account permissions
gcloud projects get-iam-policy your-project-id --flatten="bindings[].members" --filter="bindings.members:serviceAccount:*"

# Verify bucket IAM
gsutil iam get gs://your-bucket-name
```

**Function not responding:**
```bash
# Check function status
gcloud functions describe bmi-calculator --gen2 --region=us-central1

# View recent logs
gcloud functions logs read bmi-calculator --gen2 --region=us-central1 --limit=20
```

### Performance Optimization

- **Cold Start Reduction**: Use minimum instances setting for consistent performance
- **Memory Optimization**: Monitor memory usage and adjust allocation accordingly
- **Concurrency Tuning**: Configure concurrent execution limits based on downstream dependencies
- **Regional Deployment**: Deploy in regions closest to your users

## Cost Optimization

### Resource Sizing

- **Right-size Memory**: Use Cloud Monitoring to determine optimal memory allocation
- **Timeout Configuration**: Set appropriate timeouts to avoid unnecessary charges
- **Concurrency Limits**: Prevent runaway costs from unexpected traffic spikes

### Storage Optimization

- **Lifecycle Policies**: Automatically transition old data to cheaper storage classes
- **Data Retention**: Implement retention policies to automatically delete old calculations
- **Compression**: Enable gzip compression for stored JSON data

### Monitoring Costs

```bash
# View current month billing
gcloud billing budgets list --billing-account=your-billing-account-id

# Set up billing alerts
gcloud billing budgets create --billing-account=your-billing-account-id --budget-from-file=budget.yaml
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe documentation for solution context
2. **Google Cloud Documentation**: Check [Google Cloud Functions](https://cloud.google.com/functions/docs) and [Cloud Storage](https://cloud.google.com/storage/docs) documentation
3. **Community Support**: Visit [Google Cloud Community](https://cloud.google.com/community) for community assistance
4. **Error Troubleshooting**: Use `gcloud logs` and Cloud Monitoring for debugging

## Additional Resources

- [Google Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Cloud Storage Security and Access Control](https://cloud.google.com/storage/docs/access-control)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator)