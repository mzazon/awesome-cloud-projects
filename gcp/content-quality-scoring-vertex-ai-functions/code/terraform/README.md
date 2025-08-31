# Content Quality Scoring with Vertex AI and Cloud Functions - Terraform Infrastructure

This directory contains Terraform infrastructure as code for deploying a complete content quality scoring system on Google Cloud Platform. The system uses Vertex AI's Gemini models to analyze text content across multiple quality dimensions and provides automated scoring with detailed feedback.

## Architecture Overview

The infrastructure includes:

- **Cloud Storage Buckets**: Separate buckets for content uploads and analysis results
- **Cloud Functions**: Serverless function triggered by storage events for content processing
- **Vertex AI Integration**: Uses Gemini models for sophisticated content analysis
- **IAM Configuration**: Secure service accounts with minimal required permissions
- **Monitoring & Alerting**: Optional Cloud Monitoring integration for system health

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: A GCP project with billing enabled
2. **Terraform**: Version 1.6.0 or later installed
3. **Google Cloud SDK**: gcloud CLI version 450.0.0+ installed and configured
4. **Authentication**: One of the following:
   - Application Default Credentials (ADC) configured
   - Service account key file
   - Cloud Shell environment
5. **Required APIs**: The following APIs will be automatically enabled:
   - Cloud Functions API
   - Cloud Storage API
   - Vertex AI API
   - Cloud Build API
   - Eventarc API

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the terraform directory
cd ./gcp/content-quality-scoring-vertex-ai-functions/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment = "dev"
content_bucket_prefix = "my-content-analysis"
results_bucket_prefix = "my-quality-results"

# Function configuration
function_memory = "512Mi"
function_timeout = 540
function_max_instances = 10

# Monitoring (optional)
enable_monitoring = true
alert_email = "your-email@example.com"

# Labels for resource organization
labels = {
  team        = "content-team"
  cost-center = "marketing"
  environment = "development"
}
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

After successful deployment, test the system:

```bash
# Create a test content file
echo "This is a sample article about effective communication in remote teams." > test-content.txt

# Upload to trigger analysis (use bucket name from terraform output)
gsutil cp test-content.txt gs://[CONTENT_BUCKET_NAME]/

# Check function logs
gcloud functions logs read analyze-content-quality --gen2 --region us-central1 --limit 10

# View results (use bucket name from terraform output)
gsutil ls gs://[RESULTS_BUCKET_NAME]/
```

## Configuration Options

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud Project ID | `"my-project-123456"` |

### Optional Variables

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `region` | GCP region for deployment | `"us-central1"` | Any Vertex AI supported region |
| `environment` | Environment name | `"dev"` | `"dev"`, `"staging"`, `"prod"` |
| `function_memory` | Cloud Function memory | `"512Mi"` | `"128Mi"` to `"32Gi"` |
| `function_timeout` | Function timeout (seconds) | `540` | `1` to `3600` |
| `storage_class` | Storage class for buckets | `"STANDARD"` | `"STANDARD"`, `"NEARLINE"`, etc. |
| `enable_monitoring` | Enable alerts | `false` | `true`, `false` |

### Vertex AI Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `vertex_ai_model` | Gemini model to use | `"gemini-1.5-flash"` | `"gemini-1.5-pro"`, `"gemini-1.0-pro"` |
| `vertex_ai_temperature` | Model temperature | `0.2` | `0.0` to `2.0` |
| `vertex_ai_max_tokens` | Max output tokens | `2048` | `1` to `8192` |

## Usage Instructions

### Uploading Content for Analysis

1. **Single File Upload**:
   ```bash
   gsutil cp your-content.txt gs://[CONTENT_BUCKET_NAME]/
   ```

2. **Batch Upload**:
   ```bash
   gsutil -m cp *.txt gs://[CONTENT_BUCKET_NAME]/
   ```

3. **Upload with Metadata**:
   ```bash
   gsutil -h "x-goog-meta-author:John Doe" cp content.txt gs://[CONTENT_BUCKET_NAME]/
   ```

### Retrieving Analysis Results

1. **List Results**:
   ```bash
   gsutil ls gs://[RESULTS_BUCKET_NAME]/
   ```

2. **Download Specific Result**:
   ```bash
   gsutil cp gs://[RESULTS_BUCKET_NAME]/analysis_content.txt_*.json ./result.json
   ```

3. **View Results with jq**:
   ```bash
   gsutil cat gs://[RESULTS_BUCKET_NAME]/analysis_*.json | jq '.analysis'
   ```

### Monitoring and Debugging

1. **Check Function Status**:
   ```bash
   gcloud functions describe analyze-content-quality --gen2 --region us-central1
   ```

2. **View Function Logs**:
   ```bash
   gcloud functions logs read analyze-content-quality --gen2 --region us-central1 --limit 50
   ```

3. **Monitor Error Logs**:
   ```bash
   gcloud functions logs read analyze-content-quality --gen2 --region us-central1 --filter="severity>=ERROR"
   ```

## Cost Optimization

### Expected Costs

The system incurs costs from:
- **Cloud Functions**: Per-invocation and compute time
- **Cloud Storage**: Storage and operations
- **Vertex AI**: API calls and token usage
- **Cloud Build**: Function deployments

### Cost Optimization Tips

1. **Function Configuration**:
   - Right-size memory allocation based on content size
   - Set appropriate timeout values
   - Use minimum instances = 0 for cost savings

2. **Storage Management**:
   - Implement lifecycle policies for old content
   - Use appropriate storage classes
   - Clean up test data regularly

3. **Vertex AI Usage**:
   - Monitor token consumption
   - Implement content length limits
   - Use caching for similar content

4. **Monitoring**:
   ```bash
   # Check current costs
   gcloud billing budgets list
   
   # Monitor function invocations
   gcloud functions metrics list --region us-central1
   ```

## Security Considerations

### Authentication and Authorization

- **Service Account**: Dedicated service account with minimal permissions
- **IAM Roles**: Least privilege access to required resources
- **Bucket Security**: Uniform bucket-level access enabled
- **Function Security**: Internal-only ingress by default

### Data Protection

- **Encryption**: Google-managed encryption for all data at rest
- **Versioning**: Enabled on all storage buckets
- **Access Logging**: Optional access logging for audit trails
- **Network Security**: Private network access for function

### Security Best Practices

1. **Regular Updates**:
   ```bash
   # Update function dependencies
   terraform plan -var="google_cloud_storage_version=2.19.0"
   terraform apply
   ```

2. **Monitor Access**:
   ```bash
   # Check IAM policies
   gsutil iam get gs://[BUCKET_NAME]
   ```

3. **Review Logs**:
   ```bash
   # Security-related logs
   gcloud logging read 'resource.type="cloud_function" AND severity>=WARNING'
   ```

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**:
   ```bash
   # Check build logs
   gcloud builds list --limit=5
   gcloud builds log [BUILD_ID]
   ```

2. **Vertex AI Access Denied**:
   ```bash
   # Verify API is enabled
   gcloud services list --enabled | grep aiplatform
   
   # Check service account permissions
   gcloud projects get-iam-policy [PROJECT_ID]
   ```

3. **Storage Access Issues**:
   ```bash
   # Test storage access
   gsutil ls gs://[BUCKET_NAME]
   
   # Check bucket permissions
   gsutil iam get gs://[BUCKET_NAME]
   ```

4. **Function Not Triggering**:
   ```bash
   # Verify event trigger
   gcloud functions describe analyze-content-quality --gen2 --region us-central1
   
   # Check Eventarc triggers
   gcloud eventarc triggers list --location us-central1
   ```

### Debug Mode

Enable debug mode for detailed logging:

```hcl
# In terraform.tfvars
debug_mode = true
```

Then redeploy:
```bash
terraform apply
```

### Performance Issues

1. **Function Timeout**:
   - Increase timeout in variables
   - Optimize content processing logic
   - Implement streaming for large files

2. **Memory Issues**:
   - Increase function memory allocation
   - Implement content size limits
   - Use efficient data structures

3. **Rate Limiting**:
   - Implement exponential backoff
   - Monitor Vertex AI quotas
   - Use batch processing for multiple files

## Maintenance

### Regular Maintenance Tasks

1. **Update Dependencies**:
   ```bash
   # Review and update package versions
   terraform plan -var="functions_framework_version=3.9.0"
   ```

2. **Clean Up Old Data**:
   ```bash
   # Remove old analysis results (older than 90 days)
   gsutil -m rm gs://[RESULTS_BUCKET_NAME]/**/*$(date -d "90 days ago" +%Y%m%d)*
   ```

3. **Monitor Resource Usage**:
   ```bash
   # Check storage usage
   gsutil du -sh gs://[BUCKET_NAME]
   
   # Monitor function metrics
   gcloud functions metrics list --region us-central1
   ```

### Backup and Recovery

1. **Backup Configuration**:
   ```bash
   # Export Terraform state
   terraform show > infrastructure-backup.json
   ```

2. **Disaster Recovery**:
   - Terraform state is backed up automatically if using remote backend
   - Function source code is versioned in Cloud Build
   - Storage data has versioning enabled

## Advanced Configuration

### Custom Vertex AI Models

To use a custom or different model:

```hcl
# In terraform.tfvars
vertex_ai_model = "gemini-1.5-pro"
vertex_ai_temperature = 0.1
vertex_ai_max_tokens = 4096
```

### Multi-Region Deployment

For multi-region deployment, create separate Terraform configurations for each region:

```bash
# Region 1
terraform workspace new us-central1
terraform apply -var="region=us-central1"

# Region 2  
terraform workspace new europe-west1
terraform apply -var="region=europe-west1"
```

### Custom Analysis Logic

To modify the analysis logic, update the function template:

1. Edit `templates/function_main.py.tpl`
2. Customize the `ANALYSIS_PROMPT_TEMPLATE`
3. Redeploy with `terraform apply`

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify cleanup
gcloud functions list --regions=us-central1
gsutil ls gs://[PROJECT_ID]-*
```

**Note**: This will permanently delete all data. Ensure you have backups if needed.

## Support and Contributing

For issues, questions, or contributions:

1. Check the troubleshooting section above
2. Review Cloud Function logs for errors
3. Verify all prerequisites are met
4. Consult Google Cloud documentation for service-specific issues

## Version History

- **v1.0**: Initial release with basic content analysis
- **v1.1**: Added monitoring and alerting capabilities
- **v1.2**: Enhanced security and performance optimizations

## License

This infrastructure code is provided as-is for educational and development purposes. Review and adapt according to your organization's requirements and policies.