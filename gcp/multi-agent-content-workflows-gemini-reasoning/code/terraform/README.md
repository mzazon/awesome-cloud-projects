# Multi-Agent Content Workflows with Gemini 2.5 Reasoning - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete multi-agent content processing pipeline using Google Cloud Platform services, Gemini 2.5's advanced reasoning capabilities, and Cloud Workflows orchestration.

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage**: Content ingestion and results storage
- **Cloud Workflows**: Multi-agent orchestration engine
- **Cloud Functions**: Event-driven triggers for content processing
- **Vertex AI**: Gemini 2.5 Pro for advanced reasoning and content analysis
- **Vision API**: Image analysis capabilities
- **Speech-to-Text API**: Audio/video transcript extraction
- **IAM**: Secure service account and permissions management
- **Monitoring**: Alerts and observability for the processing pipeline

## Prerequisites

### Required Tools

- [Terraform](https://terraform.io/downloads.html) >= 1.5.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (gcloud)
- [Git](https://git-scm.com/) for version control

### Required Permissions

Your Google Cloud account needs the following IAM roles:

- `roles/owner` OR the following specific roles:
  - `roles/compute.admin`
  - `roles/storage.admin`
  - `roles/iam.serviceAccountAdmin`
  - `roles/workflows.admin`
  - `roles/cloudfunctions.admin`
  - `roles/aiplatform.admin`
  - `roles/serviceusage.serviceUsageAdmin`

### API Prerequisites

The following APIs will be automatically enabled during deployment:

- AI Platform API (`aiplatform.googleapis.com`)
- Cloud Workflows API (`workflows.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Eventarc API (`eventarc.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Speech-to-Text API (`speech.googleapis.com`)
- Vision API (`vision.googleapis.com`)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/multi-agent-content-workflows-gemini-reasoning/code/terraform/
```

### 2. Configure Authentication

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project (replace with your actual project ID)
gcloud config set project your-project-id
```

### 3. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your specific values
# At minimum, set your project_id
nano terraform.tfvars
```

Required variables to set in `terraform.tfvars`:

```hcl
project_id = "your-actual-project-id"
region     = "us-central1"  # or your preferred region
```

### 4. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Test the Deployment

```bash
# Upload sample content to trigger processing
gsutil cp your-test-file.txt gs://$(terraform output -raw content_bucket_name)/input/

# Monitor workflow executions
gcloud workflows executions list \
    --workflow=$(terraform output -raw workflow_name) \
    --location=$(terraform output -raw region)

# Check for results
gsutil ls gs://$(terraform output -raw content_bucket_name)/results/
```

## Configuration Guide

### Basic Configuration

The most common variables to customize:

```hcl
# terraform.tfvars
project_id = "your-project-id"
region     = "us-central1"

# Resource labels for organization
labels = {
  environment = "production"
  team       = "ai-ml"
  purpose    = "content-analysis"
}

# Function performance settings
function_config = {
  memory        = "1Gi"      # Increase for faster processing
  timeout       = 540        # Max execution time
  max_instances = 20         # Scale based on load
  min_instances = 1          # Keep warm instances
}
```

### Advanced Configuration

For production deployments:

```hcl
# Enhanced security
security_config = {
  enable_audit_logs        = true
  enable_vpc_flow_logs     = true
  allowed_ip_ranges        = ["10.0.0.0/8"]  # Restrict access
  enable_cmek             = true              # Customer-managed encryption
}

# Create dedicated network
create_dedicated_network = true

# Enable data loss prevention
enable_dlp = true

# Cost management
cost_management = {
  budget_amount_usd       = 5000
  budget_alert_thresholds = [0.5, 0.8, 1.0]
}
```

### Content Processing Tuning

Optimize for your content types:

```hcl
# Content processing limits
content_processing_config = {
  max_file_size_mb = 500                    # Larger files for high-res content
  supported_text_formats = ["txt", "pdf"]  # Limit to needed formats
  enable_ocr = true                         # OCR for image text extraction
}

# AI agent tuning
agent_configurations = {
  text_agent = {
    temperature = 0.1          # Lower for consistent analysis
    confidence_threshold = 0.9 # Higher for production quality
  }
}
```

## Usage Examples

### Upload Content for Processing

```bash
# Get bucket name from Terraform output
BUCKET_NAME=$(terraform output -raw content_bucket_name)

# Upload different content types
gsutil cp document.pdf gs://$BUCKET_NAME/input/
gsutil cp image.jpg gs://$BUCKET_NAME/input/
gsutil cp video.mp4 gs://$BUCKET_NAME/input/
```

### Monitor Processing

```bash
# List recent workflow executions
gcloud workflows executions list \
    --workflow=$(terraform output -raw workflow_name) \
    --location=$(terraform output -raw region) \
    --limit=10

# Get detailed execution info
gcloud workflows executions describe EXECUTION_ID \
    --workflow=$(terraform output -raw workflow_name) \
    --location=$(terraform output -raw region)

# View function logs
gcloud functions logs read $(terraform output -raw function_name) \
    --region=$(terraform output -raw region) \
    --limit=50
```

### Retrieve Results

```bash
# List all results
gsutil ls gs://$(terraform output -raw content_bucket_name)/results/

# Download specific analysis
gsutil cp gs://$(terraform output -raw content_bucket_name)/results/document.pdf_analysis.json ./

# View analysis results
cat document.pdf_analysis.json | jq .
```

## Monitoring and Troubleshooting

### Health Checks

```bash
# Check function health
curl -X GET "$(terraform output -raw function_url)/health"

# Check workflow status
gcloud workflows describe $(terraform output -raw workflow_name) \
    --location=$(terraform output -raw region)

# Check storage bucket
gsutil ls -L gs://$(terraform output -raw content_bucket_name)
```

### Common Issues

#### 1. Workflow Execution Failures

```bash
# Check execution logs
gcloud workflows executions describe EXECUTION_ID \
    --workflow=$(terraform output -raw workflow_name) \
    --location=$(terraform output -raw region)

# Common causes:
# - API quotas exceeded
# - Invalid content format
# - Network connectivity issues
# - Insufficient permissions
```

#### 2. Function Trigger Issues

```bash
# Check function logs
gcloud functions logs read $(terraform output -raw function_name) \
    --region=$(terraform output -raw region)

# Common causes:
# - File size too large
# - Unsupported content type
# - Storage event configuration
```

#### 3. Permission Errors

```bash
# Verify service account permissions
gcloud projects get-iam-policy $(terraform output -raw project_id) \
    --flatten="bindings[].members" \
    --filter="bindings.members:$(terraform output -raw service_account_email)"
```

### Performance Optimization

#### Monitor Resource Usage

```bash
# Function performance metrics
gcloud functions describe $(terraform output -raw function_name) \
    --region=$(terraform output -raw region)

# Workflow execution times
gcloud workflows executions list \
    --workflow=$(terraform output -raw workflow_name) \
    --location=$(terraform output -raw region) \
    --format="table(name,createTime,endTime,duration)"
```

#### Scaling Recommendations

- **High Volume**: Increase `max_instances` and `max_concurrent_executions`
- **Large Files**: Increase function `memory` and `timeout`
- **Complex Analysis**: Adjust agent `max_tokens` and `confidence_threshold`
- **Cost Optimization**: Use `min_instances = 0` and lifecycle policies

## Security Considerations

### Production Security

1. **Network Security**:
   ```hcl
   create_dedicated_network = true
   security_config = {
     allowed_ip_ranges = ["10.0.0.0/8"]  # Internal networks only
   }
   ```

2. **Data Protection**:
   ```hcl
   enable_dlp = true
   security_config = {
     enable_cmek = true  # Customer-managed encryption
   }
   ```

3. **Access Control**:
   - Use least-privilege IAM roles
   - Regular service account key rotation
   - Enable audit logging

### Compliance Features

- **Audit Logs**: Complete activity tracking
- **Data Loss Prevention**: Sensitive content detection
- **Encryption**: At-rest and in-transit encryption
- **Access Logs**: Detailed access monitoring

## Cost Management

### Estimated Costs

| Usage Level | Monthly Estimate | Primary Cost Drivers |
|------------|------------------|---------------------|
| Light (100 files/month) | $50-100 | AI API calls, Storage |
| Medium (1K files/month) | $200-400 | AI API calls, Functions |
| Heavy (10K files/month) | $1K-2K | AI API calls, Compute |

### Cost Optimization

1. **Set Processing Limits**:
   ```hcl
   content_processing_config = {
     max_file_size_mb = 50  # Reduce API costs
   }
   processing_limits = {
     max_requests_per_minute = 30  # Rate limiting
   }
   ```

2. **Storage Lifecycle**:
   ```hcl
   storage_config = {
     lifecycle_age_nearline = 30   # Move to cheaper storage
     lifecycle_age_coldline = 90
   }
   ```

3. **Budget Alerts**:
   ```hcl
   cost_management = {
     budget_amount_usd = 1000
     budget_alert_thresholds = [0.5, 0.8, 1.0]
   }
   ```

## Maintenance

### Updates and Upgrades

```bash
# Update Terraform providers
terraform init -upgrade

# Plan and apply updates
terraform plan
terraform apply
```

### Backup and Recovery

```bash
# Export Terraform state
terraform show > infrastructure-state.txt

# Backup important configurations
gsutil cp gs://$(terraform output -raw content_bucket_name)/config/* ./backups/
```

## Cleanup

### Selective Cleanup

```bash
# Remove specific resources
terraform destroy -target=google_storage_bucket_object.sample_text_content
```

### Complete Cleanup

```bash
# Remove all infrastructure
terraform destroy

# Confirm cleanup
gcloud projects list --filter="projectId:$(terraform output -raw project_id)"
```

## Support and Troubleshooting

### Getting Help

1. **Check Logs**: Function and workflow logs provide detailed error information
2. **Review Documentation**: Google Cloud AI Platform and Workflows documentation
3. **Monitor Quotas**: Check API quotas and limits in Cloud Console
4. **Validate Configuration**: Use `terraform plan` to check configuration

### Useful Commands

```bash
# Complete system status
terraform output deployment_summary

# Cost estimation
terraform output estimated_monthly_costs

# Integration examples
terraform output integration_examples

# Cleanup commands
terraform output cleanup_commands
```

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new variables
3. Validate with `terraform plan` before applying
4. Follow security best practices
5. Update cost estimates for significant changes

## License

This infrastructure code is provided as part of the Multi-Agent Content Workflows recipe. See the main recipe documentation for complete licensing information.