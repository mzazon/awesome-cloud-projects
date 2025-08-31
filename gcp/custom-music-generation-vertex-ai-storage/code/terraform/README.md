# Infrastructure as Code for Custom Music Generation with Vertex AI and Storage

This directory contains Terraform Infrastructure as Code (IaC) implementation for the recipe "Custom Music Generation with Vertex AI and Storage" on Google Cloud Platform.

## Architecture Overview

This solution deploys a serverless music generation system that:

- Uses **Vertex AI Lyria 2** for high-fidelity music generation from text prompts
- Leverages **Cloud Storage** for secure file management with lifecycle policies
- Implements **Cloud Functions (2nd gen)** for API orchestration and processing
- Provides **REST API** for integration with content creation workflows
- Includes **IAM security** with least-privilege access patterns

## Infrastructure Components

### Core Resources
- **Cloud Storage Buckets**: Input prompts and generated music storage
- **Cloud Functions**: API endpoint and music generation processor
- **Service Account**: Secure service-to-service authentication
- **IAM Policies**: Fine-grained access control

### Supporting Resources
- **API Services**: Vertex AI, Cloud Functions, Cloud Storage APIs
- **Lifecycle Policies**: Automated cost optimization for storage
- **Logging Configuration**: Centralized logging and monitoring

## Prerequisites

1. **Google Cloud Account**: With billing enabled and appropriate permissions
2. **Terraform**: Version 1.6 or later installed locally
3. **Google Cloud CLI**: Installed and authenticated (`gcloud auth login`)
4. **Project Setup**: Google Cloud project with necessary APIs enabled
5. **IAM Permissions**: Ability to create resources and manage IAM policies

### Required Google Cloud APIs
The following APIs will be automatically enabled during deployment:
- AI Platform API (`aiplatform.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)

## Quick Start

### 1. Initialize Terraform

```bash
# Clone or navigate to the terraform directory
cd gcp/custom-music-generation-vertex-ai-storage/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"

# Optional customizations
region               = "us-central1"
environment          = "dev"
resource_suffix      = "demo"

# Storage configuration
storage_class           = "STANDARD"
enable_versioning      = true
lifecycle_age_nearline = 30
lifecycle_age_coldline = 90

# Function configuration
function_memory        = 512
api_function_memory   = 256
function_timeout      = 540
api_function_timeout  = 60
python_runtime        = "python311"

# Security configuration
enable_public_access = false
allowed_members = [
  "user:your-email@domain.com",
  "serviceAccount:your-app@project.iam.gserviceaccount.com"
]

# Monitoring
enable_cloud_logging = true
log_retention_days   = 7

# Resource labels
labels = {
  project     = "music-generation"
  solution    = "vertex-ai-lyria"
  managed-by  = "terraform"
  environment = "development"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check bucket creation
gsutil ls -p your-gcp-project-id

# Verify Cloud Functions
gcloud functions list --gen2 --region=us-central1

# Test the API endpoint (get URL from output)
curl -X POST "$(terraform output -raw music_api_endpoint)" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Peaceful ambient sounds for focus and productivity",
    "style": "ambient",
    "duration_seconds": 30,
    "tempo": "slow"
  }'
```

## Configuration Options

### Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `enable_public_access` | Allow public API access | `false` | No |
| `function_memory` | Memory for generator function (MB) | `512` | No |
| `storage_class` | Cloud Storage class | `STANDARD` | No |
| `enable_versioning` | Enable bucket versioning | `true` | No |

### Security Configuration

**Private API (Recommended)**:
```hcl
enable_public_access = false
allowed_members = [
  "user:developer@company.com",
  "serviceAccount:app@project.iam.gserviceaccount.com"
]
```

**Public API** (for development/testing):
```hcl
enable_public_access = true
```

### Cost Optimization

```hcl
# Storage lifecycle for cost optimization
lifecycle_age_nearline = 30  # Move to Nearline after 30 days
lifecycle_age_coldline = 90  # Move to Coldline after 90 days

# Function sizing for cost control
function_memory = 256        # Reduce for lower costs
api_function_memory = 128    # Minimum for API functions
```

## Usage Examples

### Testing the API

```bash
# Get the API endpoint
API_URL=$(terraform output -raw music_api_endpoint)

# Test with different music styles
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Uplifting piano melody for a sunrise scene",
    "style": "classical",
    "duration_seconds": 45,
    "tempo": "moderate"
  }'

# Check for generated files
gsutil ls gs://$(terraform output -raw output_bucket_name)/audio/
gsutil ls gs://$(terraform output -raw output_bucket_name)/metadata/
```

### Monitoring and Logs

```bash
# View function logs
GENERATOR_FUNCTION=$(terraform output -raw music_generator_function_name)
API_FUNCTION=$(terraform output -raw music_api_function_name)

gcloud functions logs read $GENERATOR_FUNCTION --gen2 --region=us-central1 --limit=10
gcloud functions logs read $API_FUNCTION --gen2 --region=us-central1 --limit=10

# Tail logs in real-time
gcloud functions logs tail $GENERATOR_FUNCTION --gen2 --region=us-central1
```

### Managing Storage

```bash
# List all storage buckets
gsutil ls -p $(terraform output -raw project_id)

# View bucket contents
gsutil ls -la gs://$(terraform output -raw input_bucket_name)/
gsutil ls -la gs://$(terraform output -raw output_bucket_name)/

# Download generated music
gsutil cp gs://$(terraform output -raw output_bucket_name)/audio/*.wav ./downloads/
```

## Outputs

After successful deployment, Terraform provides these outputs:

### API Information
- `music_api_endpoint`: HTTP endpoint for music generation requests
- `api_test_command`: Sample curl command for testing

### Storage Information
- `input_bucket_name`: Bucket for prompt files
- `output_bucket_name`: Bucket for generated music
- `input_bucket_commands`: Useful gsutil commands
- `output_bucket_commands`: Storage management commands

### Function Information
- `music_generator_function_name`: Name of the generator function
- `music_api_function_name`: Name of the API function
- `function_logs_commands`: Log viewing commands

### Monitoring
- `estimated_costs`: Cost estimates for the deployment
- `next_steps`: Post-deployment instructions

## Customization

### Adding Custom Domains

To use a custom domain for the API:

1. Register a domain and configure Cloud DNS
2. Create an SSL certificate using Certificate Manager
3. Deploy a load balancer to route traffic to Cloud Functions

### Scaling Configuration

For high-volume production use:

```hcl
# Increase function limits
function_memory = 1024
api_function_memory = 512

# Configure for higher concurrency
# Add these to terraform.tfvars and extend the configuration
```

### Enhanced Security

```hcl
# Use VPC connector for private networking
# Add these resources to main.tf for VPC-native deployment

# Enable additional security features
enable_cloud_armor = true
enable_binary_authorization = true
```

## Troubleshooting

### Common Issues

**API Permission Errors**:
```bash
# Check IAM bindings
gcloud functions get-iam-policy $API_FUNCTION --region=us-central1

# Grant access manually if needed
gcloud functions add-iam-policy-binding $API_FUNCTION \
  --region=us-central1 \
  --member="user:your-email@domain.com" \
  --role="roles/cloudfunctions.invoker"
```

**Storage Access Issues**:
```bash
# Verify bucket permissions
gsutil iam get gs://$(terraform output -raw input_bucket_name)

# Check service account permissions
gcloud projects get-iam-policy $(terraform output -raw project_id) \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:*music-gen*"
```

**Function Deployment Failures**:
```bash
# Check build logs
gcloud builds list --limit=5

# View detailed function information
gcloud functions describe $GENERATOR_FUNCTION --gen2 --region=us-central1
```

### Validation Commands

```bash
# Validate Terraform configuration
terraform validate

# Check for security issues
terraform plan -out=plan.out
# Review the plan for any security concerns

# Test resource connectivity
gcloud compute networks connectivity-tests create test-connectivity \
  --source-project=$(terraform output -raw project_id) \
  --destination-project=$(terraform output -raw project_id)
```

## Cleanup

### Complete Cleanup

```bash
# Destroy all resources
terraform destroy

# Verify cleanup
gsutil ls -p $(terraform output -raw project_id)
gcloud functions list --gen2
```

### Selective Cleanup

```bash
# Remove only specific resources
terraform destroy -target=google_cloudfunctions2_function.music_api
terraform destroy -target=google_storage_bucket.output_bucket
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining storage objects
gsutil -m rm -r gs://music-prompts-*
gsutil -m rm -r gs://generated-music-*

# Check for any remaining functions
gcloud functions list --filter="name:music-*"
```

## Cost Management

### Cost Estimation

Approximate monthly costs for moderate usage:
- **Cloud Storage**: $1-5 (depends on data volume)
- **Cloud Functions**: $5-15 (depends on requests)
- **Vertex AI**: $10-50 (depends on generation frequency)
- **Total**: ~$16-70/month

### Cost Optimization Tips

1. **Enable lifecycle policies** for automatic storage class transitions
2. **Monitor function execution** to optimize memory allocation
3. **Use budget alerts** to track spending
4. **Clean up old generated content** regularly

```bash
# Set up budget alerts
gcloud billing budgets create \
  --billing-account=YOUR_BILLING_ACCOUNT \
  --display-name="Music Generation Budget" \
  --budget-amount=100USD \
  --threshold-rules-percent=50,90
```

## Support and Maintenance

### Monitoring

1. **Set up Cloud Monitoring** dashboards for functions and storage
2. **Configure alerting** for function errors and high costs
3. **Review logs regularly** for performance optimization

### Updates

1. **Keep Terraform up to date** for latest features and security
2. **Monitor Google Cloud** for new Vertex AI capabilities
3. **Update function dependencies** in requirements.txt files

### Backup and Recovery

1. **Enable versioning** on storage buckets (configured by default)
2. **Export Terraform state** to Cloud Storage for team access
3. **Document custom configurations** for disaster recovery

For additional support, refer to:
- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)