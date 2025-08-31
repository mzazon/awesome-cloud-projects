# Terraform Infrastructure for Smart Content Classification

This directory contains Terraform Infrastructure as Code (IaC) for deploying an AI-powered content classification system on Google Cloud Platform using Gemini 2.5 and Cloud Storage.

## Architecture Overview

The infrastructure creates:
- **Cloud Storage Buckets**: One staging bucket for uploads and four classification buckets for organized content
- **Cloud Function**: Serverless function that processes file uploads and classifies content using Gemini 2.5
- **Service Account**: Dedicated service account with least-privilege permissions
- **Event Triggers**: Automatic triggering of classification when files are uploaded
- **Monitoring & Logging**: Optional logging and alerting for production monitoring

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud CLI** installed and authenticated
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Authenticate
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Terraform** installed (version 1.5 or later)
   ```bash
   # Install Terraform
   wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
   unzip terraform_1.6.6_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **GCP Project** with billing enabled and appropriate permissions:
   - Project Owner or Editor role
   - Cloud Functions API access
   - Vertex AI API access
   - Cloud Storage admin permissions

4. **Enabled APIs** (these will be automatically enabled by Terraform):
   - Vertex AI API
   - Cloud Functions API
   - Cloud Storage API
   - Cloud Logging API
   - Eventarc API

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment           = "dev"
resource_prefix      = "content-classifier"
gemini_model         = "gemini-2.5-pro"
function_memory      = 1024
function_timeout     = 540
max_file_size_mb     = 10
notification_email   = "your-email@example.com"

# Labels for resource organization
labels = {
  application = "content-classification"
  team        = "data-engineering"
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

After deployment, Terraform will output important information including bucket names and verification commands:

```bash
# Check the staging bucket
gsutil ls -la gs://$(terraform output -raw staging_bucket_name)/

# Upload a test file
echo "This is a sample contract document" | gsutil cp - gs://$(terraform output -raw staging_bucket_name)/test-contract.txt

# Check function logs
gcloud functions logs read $(terraform output -raw function_name) --region=$(terraform output -raw region) --limit=10

# Verify classification (wait 30-60 seconds after upload)
gsutil ls gs://$(terraform output -raw contracts_bucket_name)/
```

## Configuration Options

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID | - | Yes |
| `region` | GCP region | `us-central1` | No |
| `environment` | Environment name | `dev` | No |
| `resource_prefix` | Resource name prefix | `content-classifier` | No |

### AI Model Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `gemini_model` | Gemini model version | `gemini-2.5-pro` | `gemini-2.5-pro`, `gemini-2.5-flash` |
| `max_file_size_mb` | Max file size to process | `10` | 1-100 |

### Function Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `function_memory` | Memory allocation (MB) | `1024` | 128, 256, 512, 1024, 2048, 4096, 8192 |
| `function_timeout` | Timeout (seconds) | `540` | 60-540 |
| `function_max_instances` | Max concurrent instances | `10` | 1-1000 |

### Storage Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `storage_class` | Storage class for buckets | `STANDARD` | `STANDARD`, `NEARLINE`, `COLDLINE`, `ARCHIVE` |
| `enable_bucket_versioning` | Enable bucket versioning | `true` | `true`, `false` |
| `enable_uniform_bucket_access` | Enable uniform bucket access | `true` | `true`, `false` |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_logging` | Enable detailed logging | `true` |
| `log_retention_days` | Log retention period | `30` |
| `notification_email` | Email for alerts | `""` |

## Usage Examples

### Basic Development Setup

```hcl
# terraform.tfvars
project_id = "my-dev-project"
region     = "us-central1"
environment = "development"
gemini_model = "gemini-2.5-flash"  # Cost-effective for testing
```

### Production Setup

```hcl
# terraform.tfvars
project_id = "my-prod-project"
region     = "us-central1"
environment = "production"
resource_prefix = "prod-content-classifier"
gemini_model = "gemini-2.5-pro"  # Best accuracy
function_memory = 2048
function_max_instances = 50
notification_email = "alerts@company.com"
enable_logging = true
log_retention_days = 90

labels = {
  application = "content-classification"
  team        = "data-engineering"
  environment = "production"
  cost-center = "engineering"
}
```

### High-Volume Setup

```hcl
# terraform.tfvars
project_id = "my-project"
gemini_model = "gemini-2.5-flash"  # Faster, more cost-effective
function_memory = 1024
function_max_instances = 100
max_file_size_mb = 5  # Limit for faster processing
storage_class = "NEARLINE"  # Cost optimization

bucket_lifecycle_rules = [
  {
    action = {
      type = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition = {
      age = 7  # Move to coldline after 1 week
    }
  }
]
```

## Testing the System

### 1. Upload Test Files

```bash
# Create test files
echo "CONFIDENTIALITY AGREEMENT - This agreement contains confidential information..." > contract.txt
echo "INVOICE #12345 - Amount Due: $1,000" > invoice.txt
echo "SPECIAL OFFER! 50% off this week only!" > marketing.txt

# Upload to staging bucket
STAGING_BUCKET=$(terraform output -raw staging_bucket_name)
gsutil cp contract.txt gs://$STAGING_BUCKET/
gsutil cp invoice.txt gs://$STAGING_BUCKET/
gsutil cp marketing.txt gs://$STAGING_BUCKET/
```

### 2. Monitor Classification

```bash
# Wait for processing (30-60 seconds)
sleep 60

# Check each classification bucket
echo "=== Contracts ==="
gsutil ls gs://$(terraform output -raw contracts_bucket_name)/

echo "=== Invoices ==="
gsutil ls gs://$(terraform output -raw invoices_bucket_name)/

echo "=== Marketing ==="
gsutil ls gs://$(terraform output -raw marketing_bucket_name)/

echo "=== Miscellaneous ==="
gsutil ls gs://$(terraform output -raw miscellaneous_bucket_name)/
```

### 3. View Function Logs

```bash
# View recent function execution logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --limit=20 \
  --format="value(timestamp,message)"
```

## Monitoring and Troubleshooting

### View Function Metrics

```bash
# Function invocations
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=$(terraform output -raw function_name)" --limit=10

# Error logs only
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=$(terraform output -raw function_name) AND severity>=ERROR" --limit=10
```

### Common Issues

1. **Function not triggering**: Check that the file was uploaded to the staging bucket
2. **Classification errors**: Check function logs for Vertex AI API errors
3. **Permission errors**: Verify service account has correct IAM roles
4. **File not moving**: Check file size limits and function timeout settings

### Performance Monitoring

```bash
# View function performance metrics in Cloud Console
echo "Function Metrics: https://console.cloud.google.com/functions/details/$(terraform output -raw region)/$(terraform output -raw function_name)?project=$(terraform output -raw project_id)"

# View storage usage
gsutil du -sh gs://$(terraform output -raw staging_bucket_name)
gsutil du -sh gs://$(terraform output -raw contracts_bucket_name)
gsutil du -sh gs://$(terraform output -raw invoices_bucket_name)
gsutil du -sh gs://$(terraform output -raw marketing_bucket_name)
gsutil du -sh gs://$(terraform output -raw miscellaneous_bucket_name)
```

## Cost Optimization

### Model Selection
- **gemini-2.5-pro**: Best accuracy, higher cost
- **gemini-2.5-flash**: Good accuracy, lower cost and latency

### Storage Optimization
- Use lifecycle rules to transition old files to cheaper storage
- Set appropriate storage classes based on access patterns
- Enable object versioning only if needed

### Function Optimization
- Right-size memory allocation based on actual usage
- Set appropriate timeout values
- Monitor and adjust max instances based on traffic

## Customization

### Adding New Content Categories

1. **Add new bucket**:
   ```hcl
   resource "google_storage_bucket" "reports" {
     name     = "${local.resource_prefix}-reports-${local.resource_suffix}"
     location = var.region
     # ... other configuration
   }
   ```

2. **Update function environment variables**:
   ```hcl
   environment_variables = {
     # ... existing variables
     REPORTS_BUCKET = google_storage_bucket.reports.name
   }
   ```

3. **Update classification logic** in `function_source/main.py`

### Custom Classification Rules

Modify the `classify_content_with_gemini` function in `function_source/main.py` to:
- Add industry-specific categories
- Include confidence scoring
- Implement multi-label classification
- Add content validation rules

## Security Considerations

- Service account uses least privilege principles
- Buckets use uniform bucket-level access
- All communication uses Google Cloud's encryption in transit
- Consider enabling Cloud KMS for additional encryption
- Review and audit IAM permissions regularly

## Cleanup

To remove all resources:

```bash
terraform destroy
```

This will delete all created resources and stop any ongoing charges.

## Support and Documentation

- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Vertex AI Gemini Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/models/gemini)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)

## License

This infrastructure code is provided as-is for educational and production use. Ensure compliance with your organization's policies and Google Cloud's terms of service.