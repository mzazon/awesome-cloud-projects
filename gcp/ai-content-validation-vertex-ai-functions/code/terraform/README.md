# AI Content Validation with Vertex AI and Cloud Functions - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete AI content validation system on Google Cloud Platform. The system uses Vertex AI's Gemini models for intelligent content safety analysis and Cloud Functions for serverless processing.

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage Buckets**: Separate buckets for content input and validation results
- **Cloud Function**: Serverless function triggered by storage events for content processing
- **Vertex AI Integration**: Gemini model integration for advanced content safety analysis
- **IAM Security**: Proper service accounts and least-privilege access controls
- **Monitoring & Alerting**: Cloud Monitoring alerts for error rates and latency
- **Logging**: Centralized logging for audit trails and debugging

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (gcloud)
- A Google Cloud Project with billing enabled

### Required Permissions

Your Google Cloud user or service account needs these IAM roles:

- `roles/compute.admin`
- `roles/storage.admin`
- `roles/cloudfunctions.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/monitoring.admin`
- `roles/logging.admin`

### API Enablement

The following APIs will be automatically enabled by Terraform:

- Cloud Functions API
- Cloud Storage API
- Vertex AI API
- Cloud Build API
- Eventarc API
- Cloud Logging API
- Cloud Monitoring API
- Secret Manager API

## Quick Start

### 1. Configure Google Cloud Authentication

```bash
# Authenticate with your Google Cloud account
gcloud auth login

# Set your default project (optional if you specify in variables)
gcloud config set project YOUR_PROJECT_ID

# Enable Application Default Credentials for Terraform
gcloud auth application-default login
```

### 2. Initialize Terraform

```bash
# Clone or navigate to this directory
cd path/to/terraform/

# Initialize Terraform (downloads providers)
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required Variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional Customizations
environment = "dev"
gemini_model_name = "gemini-1.5-flash"
safety_threshold = "BLOCK_MEDIUM_AND_ABOVE"

# Function Configuration
function_memory = "512Mi"
function_timeout = 60
function_max_instances = 10

# Storage Configuration
bucket_lifecycle_enabled = true
bucket_retention_days = 90

# Security Configuration
enable_uniform_bucket_level_access = true
enable_public_access_prevention = true

# Monitoring Configuration
enable_monitoring = true
enable_cloud_logging = true

# Custom Labels
labels = {
  team        = "ai-team"
  cost-center = "engineering"
  project     = "content-validation"
}
```

### 4. Plan and Apply

```bash
# Review the planned infrastructure changes
terraform plan

# Apply the infrastructure (will prompt for confirmation)
terraform apply

# Or apply without prompts
terraform apply -auto-approve
```

### 5. Test the Deployment

After deployment, use the output values to test the system:

```bash
# Create test content
echo "This is a safe test message for AI validation." > test_content.txt

# Upload to trigger validation (replace bucket name from output)
gsutil cp test_content.txt gs://CONTENT_BUCKET_NAME/

# Check for validation results (replace bucket name from output)
gsutil ls gs://RESULTS_BUCKET_NAME/validation_results/

# Download and view results
gsutil cp gs://RESULTS_BUCKET_NAME/validation_results/test_content_results_*.json ./
cat test_content_results_*.json
```

## Configuration Reference

### Core Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | GCP project ID | string | - | Yes |
| `region` | GCP region for resources | string | "us-central1" | No |
| `environment` | Environment name | string | "dev" | No |

### Storage Configuration

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `content_bucket_location` | Storage class for content bucket | string | "STANDARD" |
| `results_bucket_location` | Storage class for results bucket | string | "STANDARD" |
| `bucket_versioning_enabled` | Enable bucket versioning | bool | true |
| `bucket_lifecycle_enabled` | Enable lifecycle management | bool | true |
| `bucket_retention_days` | Retention period in days | number | 90 |

### Function Configuration

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `function_runtime` | Python runtime version | string | "python312" |
| `function_memory` | Memory allocation | string | "512Mi" |
| `function_timeout` | Timeout in seconds | number | 60 |
| `function_max_instances` | Maximum instances | number | 10 |

### AI Model Configuration

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `vertex_ai_location` | Vertex AI region | string | "us-central1" |
| `gemini_model_name` | Gemini model version | string | "gemini-1.5-flash" |
| `safety_threshold` | Content safety threshold | string | "BLOCK_MEDIUM_AND_ABOVE" |

### Security Configuration

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `enable_uniform_bucket_level_access` | Uniform bucket access | bool | true |
| `enable_public_access_prevention` | Prevent public access | bool | true |
| `allowed_principals` | Allowed function invokers | list(string) | [] |

## Advanced Configuration

### Custom Safety Thresholds

Configure content validation sensitivity:

```hcl
# Strictest setting - blocks low-risk content
safety_threshold = "BLOCK_LOW_AND_ABOVE"

# Balanced setting - blocks medium and high-risk content
safety_threshold = "BLOCK_MEDIUM_AND_ABOVE"

# Permissive setting - only blocks high-risk content
safety_threshold = "BLOCK_ONLY_HIGH"

# No blocking - returns analysis without blocking
safety_threshold = "BLOCK_NONE"
```

### VPC Connectivity

For private network connectivity:

```hcl
enable_vpc_connector = true
vpc_connector_name = "projects/PROJECT_ID/locations/REGION/connectors/CONNECTOR_NAME"
```

### Monitoring and Alerting

Configure notification channels for alerts:

```hcl
monitoring_notification_channels = [
  "projects/PROJECT_ID/notificationChannels/CHANNEL_ID_1",
  "projects/PROJECT_ID/notificationChannels/CHANNEL_ID_2"
]
```

### Performance Optimization

For high-performance requirements:

```hcl
# Increase function resources
function_memory = "1Gi"
function_timeout = 120
function_max_instances = 50
enable_function_cpu_boost = true

# Keep minimum instances warm
function_min_instances = 2

# Higher concurrency per instance
function_concurrency = 10
```

## Outputs Reference

After deployment, Terraform provides these useful outputs:

### Storage Information
- `content_input_bucket_name`: Input bucket for content uploads
- `validation_results_bucket_name`: Results bucket for validation outputs
- `content_input_bucket_url`: Direct URL to input bucket
- `validation_results_bucket_url`: Direct URL to results bucket

### Function Information
- `function_name`: Name of the deployed Cloud Function
- `function_uri`: URI for direct function invocation
- `function_service_account_email`: Service account used by function

### Console URLs
- `console_urls`: Direct links to Google Cloud Console for each resource

### Test Commands
- `test_commands`: Ready-to-use commands for testing the system

## Monitoring and Observability

### Cloud Monitoring Dashboards

Access pre-configured monitoring through:

```bash
# Function metrics
gcloud functions describe FUNCTION_NAME --region=REGION

# View logs
gcloud functions logs read FUNCTION_NAME --region=REGION --limit=50

# Monitor error rates
gcloud logging read "resource.type=cloud_function AND severity>=ERROR" --limit=20
```

### Custom Metrics

The system creates these custom monitoring alerts:

1. **Error Rate Alert**: Triggers when function error rate exceeds 10%
2. **Latency Alert**: Triggers when 95th percentile latency exceeds 30 seconds

### Log Analysis

Function logs include structured information:

```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "severity": "INFO",
  "message": "Validation completed for file.txt",
  "file_name": "test_content.txt",
  "recommendation": "approved",
  "safety_analysis": {
    "overall_safe": true,
    "content_blocked": false
  }
}
```

## Cost Optimization

### Estimated Costs

For moderate usage (1000 validations/month):

- **Cloud Functions**: ~$5-10/month
- **Cloud Storage**: ~$1-3/month
- **Vertex AI API**: ~$5-15/month
- **Other services**: ~$1-2/month

**Total**: Approximately $12-30/month

### Cost Optimization Features

1. **Lifecycle Management**: Automatically moves old files to cheaper storage
2. **Retention Policies**: Automatically deletes old validation results
3. **Function Scaling**: Only pays for actual usage
4. **Efficient Storage Classes**: Uses appropriate storage tiers

### Cost Monitoring

```bash
# Check current costs
gcloud billing budgets list

# Analyze costs by service
gcloud billing projects list
```

## Security Considerations

### Data Protection

- All storage buckets use uniform bucket-level access
- Public access prevention is enforced
- Versioning enabled for audit trails
- Encryption at rest using Google-managed keys

### Access Control

- Function uses dedicated service account with minimal permissions
- IAM roles follow principle of least privilege
- Optional VPC connectivity for network isolation

### Audit Logging

- All function executions are logged
- Storage access is audited through Cloud Audit Logs
- Validation results include processing metadata

## Troubleshooting

### Common Issues

#### Function Deployment Fails

```bash
# Check enabled APIs
gcloud services list --enabled

# Verify service account permissions
gcloud projects get-iam-policy PROJECT_ID

# Check Cloud Build logs
gcloud builds list --limit=10
```

#### Vertex AI Access Issues

```bash
# Verify Vertex AI API is enabled
gcloud services list --filter="name:aiplatform.googleapis.com"

# Check service account has AI Platform User role
gcloud projects get-iam-policy PROJECT_ID --flatten="bindings[].members" --filter="bindings.role:roles/aiplatform.user"
```

#### Storage Access Issues

```bash
# Verify bucket permissions
gsutil iam get gs://BUCKET_NAME

# Check bucket lifecycle configuration
gsutil lifecycle get gs://BUCKET_NAME
```

### Debug Mode

Enable debug logging:

```hcl
log_level = "DEBUG"
```

## Cleanup

To remove all deployed resources:

```bash
# Destroy all resources (will prompt for confirmation)
terraform destroy

# Or destroy without prompts
terraform destroy -auto-approve
```

**Warning**: This will permanently delete all data in the storage buckets and cannot be undone.

## Support and Updates

### Version Updates

To update to newer versions:

```bash
# Update Terraform providers
terraform init -upgrade

# Update function dependencies
# Edit function_source/requirements.txt and re-apply
terraform apply
```

### Getting Help

1. Check the [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
2. Review [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
3. Consult [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
4. Check the original recipe documentation for implementation details

## License and Compliance

This infrastructure code follows Google Cloud security best practices and is suitable for production deployments with appropriate configuration. Ensure compliance with your organization's security policies before deployment.