# Infrastructure as Code for Content Syndication with Hierarchical Namespace Storage and Agent Development Kit

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete GCP-based content syndication platform featuring Hierarchical Namespace Storage, Agent Development Kit integration, and automated workflows.

## Architecture Overview

The platform automatically processes uploaded content through an intelligent pipeline:

1. **Hierarchical Namespace Storage** - High-performance storage with up to 8x faster operations
2. **Cloud Functions** - Content processing with AI-driven analysis and routing
3. **Vertex AI Agent Development Kit** - Intelligent content analysis and quality assessment
4. **Cloud Workflows** - Orchestration of the complete syndication pipeline
5. **Monitoring & Logging** - Comprehensive observability for the platform

## Prerequisites

- **Google Cloud Account** with billing enabled
- **Google Cloud CLI** (gcloud) installed and configured
- **Terraform** >= 1.5 installed
- **Required Permissions**:
  - Project Editor or custom role with:
    - Storage Admin
    - AI Platform Admin  
    - Workflows Admin
    - Cloud Functions Admin
    - Service Account Admin
    - Project IAM Admin

## Required APIs

The following APIs will be automatically enabled during deployment:

- Cloud Storage API
- Vertex AI API
- Cloud Workflows API
- Cloud Functions API
- Cloud Resource Manager API
- Identity and Access Management (IAM) API
- Cloud Logging API
- Cloud Monitoring API
- Eventarc API
- Cloud Run API

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the terraform directory
cd gcp/content-syndication-hierarchical-namespace-storage-agent-development-kit/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment           = "dev"
content_bucket_name   = "my-content-hns-bucket"
storage_location      = "US"
enable_vertex_ai      = true
enable_monitoring     = true
function_memory       = "1GB"
function_timeout      = 300

# Quality assessment settings
quality_thresholds = {
  minimum_score        = 0.75
  enable_auto_approval = true
  require_human_review = false
}

# Content lifecycle settings
enable_content_lifecycle = true
content_retention_days   = 30

# Tags for resource organization
tags = {
  project     = "content-syndication"
  environment = "dev"
  team        = "media-engineering"
  cost_center = "engineering"
}
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### 4. Verify Deployment

```bash
# Check bucket creation and hierarchical namespace
gcloud storage ls -L gs://$(terraform output -raw content_bucket_name)

# Verify function deployment
gcloud functions list --gen2 --region=$(terraform output -raw region)

# Check workflow deployment
gcloud workflows list --location=$(terraform output -raw region)

# View service accounts
gcloud iam service-accounts list --filter="email~content"
```

## Testing the Platform

### Upload Test Content

```bash
# Get bucket name from Terraform output
BUCKET_NAME=$(terraform output -raw content_bucket_name)

# Create test files
echo "Sample video content for testing" > test-video.mp4
echo "Sample image content for testing" > test-image.jpg
echo "Sample document content for testing" > test-document.pdf

# Upload to incoming folder (triggers processing)
gcloud storage cp test-video.mp4 gs://${BUCKET_NAME}/incoming/
gcloud storage cp test-image.jpg gs://${BUCKET_NAME}/incoming/
gcloud storage cp test-document.pdf gs://${BUCKET_NAME}/incoming/
```

### Monitor Processing

```bash
# Check function logs
gcloud functions logs read $(terraform output -raw content_processor_function_name) \
    --region=$(terraform output -raw region) \
    --limit=50

# View workflow executions
gcloud workflows executions list \
    --workflow=$(terraform output -raw workflow_name) \
    --location=$(terraform output -raw region)

# Check content organization
gcloud storage ls -r gs://${BUCKET_NAME}/
```

### Manual Workflow Trigger

```bash
# Trigger workflow manually
gcloud workflows run $(terraform output -raw workflow_name) \
    --location=$(terraform output -raw region) \
    --data='{"bucket":"'${BUCKET_NAME}'","object":"incoming/test-video.mp4"}'
```

## Configuration Options

### Storage Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `storage_location` | Storage bucket location | `"US"` | `"US"`, `"EU"`, `"ASIA"`, regional locations |
| `enable_content_lifecycle` | Enable automatic lifecycle management | `true` | `true`, `false` |
| `content_retention_days` | Days before moving to nearline | `30` | 1-365 |
| `enable_cors` | Enable CORS for web distribution | `true` | `true`, `false` |

### Function Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `function_memory` | Memory allocation | `"1GB"` | `"512MB"`, `"1GB"`, `"2GB"`, `"4GB"`, `"8GB"` |
| `function_timeout` | Function timeout | `300` | 1-540 seconds |
| `function_max_instances` | Max scaling instances | `100` | 1-3000 |

### AI and Quality Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_vertex_ai` | Enable Vertex AI components | `true` |
| `vertex_ai_location` | Vertex AI region | `"us-central1"` |
| `quality_thresholds.minimum_score` | Quality approval threshold | `0.75` |
| `quality_thresholds.enable_auto_approval` | Enable automatic approval | `true` |

### Content Categories

The platform automatically categorizes content into:

- **Video**: `.mp4`, `.avi`, `.mov`, `.mkv`
- **Image**: `.jpg`, `.png`, `.gif`, `.webp`
- **Audio**: `.mp3`, `.wav`, `.aac`, `.flac`
- **Document**: `.pdf`, `.doc`, `.txt`, `.md`

## Monitoring and Observability

### Built-in Monitoring

- **Cloud Monitoring Dashboard** - Real-time metrics and performance
- **Function Execution Logs** - Detailed processing information
- **Workflow Execution History** - Pipeline orchestration tracking
- **Storage Access Logs** - Content access patterns

### Key Metrics

- Content processing throughput
- Quality assessment scores
- Distribution success rates
- Storage utilization and costs
- Function execution duration and errors

### Alerting (Optional)

Configure alerting policies for:

```bash
# Example: Function error rate alert
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/function-error-alert.yaml
```

## Security Features

### Identity and Access Management

- **Dedicated Service Accounts** for each component
- **Least Privilege Access** - minimal required permissions
- **Function Isolation** - private ingress for internal communication
- **Workload Identity** for secure service-to-service communication

### Data Protection

- **Encryption at Rest** - automatic for Cloud Storage
- **Encryption in Transit** - HTTPS/TLS for all communications
- **Versioning Enabled** - content history and rollback capabilities
- **Uniform Bucket-Level Access** - consistent security model

### Network Security

- **Internal-Only Functions** - no external network access
- **VPC Service Controls** (optional) - enhanced security perimeter
- **CORS Configuration** - controlled web access

## Cost Optimization

### Storage Costs

- **Lifecycle Policies** - automatic migration to cheaper storage classes
- **Regional vs Multi-Regional** - choose based on access patterns
- **Versioning Cleanup** - automatic old version removal

### Compute Costs

- **Auto-Scaling Functions** - pay only for actual usage
- **Memory Optimization** - right-sized memory allocation
- **Timeout Configuration** - prevent runaway executions

### Expected Costs (USD/month)

For typical usage (1000 files/month, 500MB average):

- **Storage**: $5-15 (depending on retention)
- **Functions**: $10-30 (based on processing time)
- **Workflows**: $1-5 (execution-based)
- **Vertex AI**: $20-50 (model usage)
- **Total Estimated**: $35-100/month

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy $(terraform output -raw project_id)
   
   # Verify API enablement
   gcloud services list --enabled
   ```

2. **Workflow Execution Errors**
   ```bash
   # Check workflow logs
   gcloud workflows executions describe EXECUTION_ID \
       --workflow=$(terraform output -raw workflow_name) \
       --location=$(terraform output -raw region)
   ```

3. **Storage Access Issues**
   ```bash
   # Verify bucket permissions
   gcloud storage buckets describe gs://$(terraform output -raw content_bucket_name)
   
   # Check service account access
   gcloud storage buckets get-iam-policy gs://$(terraform output -raw content_bucket_name)
   ```

### Debug Mode

Enable debug logging by setting:

```hcl
workflow_call_log_level = "LOG_ALL_CALLS"
```

## Cleanup

### Remove All Resources

```bash
# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed

# Clean up local files
rm -f terraform.tfstate*
rm -f content-processor.zip
rm -f workflow_definition.yaml
rm -rf function_code/
```

### Selective Cleanup

```bash
# Remove only non-storage resources
terraform destroy -target=google_cloudfunctions2_function.content_processor
terraform destroy -target=google_workflows_workflow.content_syndication
```

## Advanced Configuration

### Custom Content Categories

Modify the content categorization by updating:

```hcl
content_categories = ["video", "image", "audio", "document", "3d-models", "datasets"]
```

### Custom Distribution Channels

Configure platform-specific routing:

```hcl
distribution_channels = {
  video    = ["youtube", "vimeo", "tiktok"]
  image    = ["instagram", "pinterest", "flickr"]
  audio    = ["spotify", "soundcloud", "podcast"]
  document = ["medium", "scribd", "issuu"]
}
```

### Multi-Environment Deployment

```bash
# Production environment
terraform workspace new prod
terraform apply -var-file="environments/prod.tfvars"

# Staging environment  
terraform workspace new staging
terraform apply -var-file="environments/staging.tfvars"
```

## Support and Documentation

- **Recipe Documentation**: [Content Syndication Recipe](../content-syndication-hierarchical-namespace-storage-agent-development-kit.md)
- **GCP Documentation**: [Cloud Storage](https://cloud.google.com/storage/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs), [Cloud Workflows](https://cloud.google.com/workflows/docs)
- **Terraform Provider**: [Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update variable descriptions and documentation
3. Verify all resources include appropriate labels
4. Test deployment and cleanup procedures
5. Update cost estimates if significant changes are made

## License

This infrastructure code is provided as-is under the same license as the parent recipe collection.