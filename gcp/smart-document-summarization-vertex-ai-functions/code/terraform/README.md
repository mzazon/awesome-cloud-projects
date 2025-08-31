# Infrastructure as Code for Smart Document Summarization with Vertex AI and Functions

This directory contains Terraform Infrastructure as Code (IaC) for deploying a smart document summarization solution on Google Cloud Platform using Vertex AI and Cloud Functions.

## Solution Overview

This infrastructure creates a serverless document processing pipeline that:
- Automatically processes documents uploaded to Cloud Storage
- Uses Cloud Functions for event-driven processing orchestration
- Leverages Vertex AI's Gemini models for intelligent document summarization
- Provides monitoring and logging capabilities

## Architecture Components

- **Cloud Storage Bucket**: Document ingestion and summary storage
- **Cloud Functions (2nd Gen)**: Serverless document processing
- **Vertex AI**: AI-powered document summarization using Gemini models
- **Service Account**: Secure access with least privilege permissions
- **Cloud Monitoring**: Error alerts and performance monitoring
- **Cloud Logging**: Centralized log collection and analysis

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: Active project with billing enabled
2. **Terraform**: Version 1.0 or later installed
3. **Google Cloud CLI**: Latest version installed and authenticated
4. **Required Permissions**: 
   - Project Editor or Owner role
   - Service Account Admin role
   - Cloud Functions Admin role
   - Storage Admin role
   - Vertex AI User role

## Authentication Setup

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project ID
export GOOGLE_CLOUD_PROJECT="your-project-id"
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize as needed:

```bash
# Review variables.tf for all available options
terraform plan -var="project_id=your-project-id"
```

### 3. Deploy Infrastructure

```bash
# Plan the deployment
terraform plan -var="project_id=your-project-id" -out=tfplan

# Apply the plan
terraform apply tfplan
```

### 4. Verify Deployment

```bash
# Check outputs
terraform output

# Test document upload
echo "This is a test document for summarization." > test-doc.txt
gsutil cp test-doc.txt gs://$(terraform output -raw bucket_name)/

# Wait 1-2 minutes, then check for summary
gsutil ls gs://$(terraform output -raw bucket_name)/*_summary.txt
```

## Configuration Options

### Essential Variables

```hcl
# terraform.tfvars example
project_id = "your-gcp-project-id"
region     = "us-central1"
bucket_name = "doc-summarizer"
function_name = "summarize-document"
```

### Advanced Configuration

```hcl
# Additional customization options
function_memory = 2048          # Increase for large documents
function_timeout = 540          # Max processing time in seconds
max_instances = 20              # Scale up for high volume
storage_class = "STANDARD"      # Storage optimization
enable_versioning = true        # Document version protection

# Custom labels
labels = {
  environment = "production"
  team        = "ai-engineering"
  cost-center = "research"
}
```

## Supported Document Formats

The solution supports these document formats:
- **PDF files** (.pdf) - Extracted using PyPDF2
- **Word documents** (.docx) - Processed using python-docx
- **Text files** (.txt) - Direct text processing
- **Other formats** - Attempted as plain text

## Monitoring and Logging

### View Function Logs

```bash
# Real-time log streaming
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --gen2 --limit=50

# Or use the console URL from outputs
terraform output console_urls
```

### Monitor Function Performance

```bash
# Check function metrics
gcloud functions describe $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --gen2

# View monitoring dashboard
# Use console URL from terraform output console_urls
```

## Cost Management

### Estimated Costs

- **Cloud Storage**: ~$0.023/GB/month (STANDARD class)
- **Cloud Functions**: ~$0.0000004/invocation + compute time
- **Vertex AI**: Variable based on Gemini model token usage
- **Cloud Logging**: ~$0.50/GB ingested

### Cost Optimization

```hcl
# Use lifecycle rules for storage cost optimization
storage_class = "NEARLINE"      # For less frequent access
function_memory = 512           # Reduce for smaller documents
max_instances = 5               # Limit concurrent executions
```

### Monitor Costs

```bash
# View current billing
gcloud billing budgets list

# Check resource usage
gcloud logging metrics list
```

## Security Features

### Service Account Permissions

The solution follows the principle of least privilege:
- `roles/aiplatform.user` - Access to Vertex AI models
- `roles/storage.objectAdmin` - Read/write to storage bucket
- `roles/logging.logWriter` - Write to Cloud Logging
- `roles/monitoring.metricWriter` - Write monitoring metrics

### Network Security

- Cloud Function configured with `ALLOW_INTERNAL_ONLY` ingress
- Storage bucket uses uniform bucket-level access
- No public endpoints exposed

### Data Protection

- Storage bucket versioning enabled by default
- Lifecycle rules for automatic data archival
- Centralized logging for audit trails

## Troubleshooting

### Common Issues

1. **Function Timeout**: Increase `function_timeout` for large documents
2. **Memory Errors**: Increase `function_memory` to 2048MB or higher
3. **Permission Denied**: Verify service account has required roles
4. **API Not Enabled**: Check that all required APIs are enabled

### Debug Commands

```bash
# Check function status
terraform output function_url

# View recent logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) --gen2 --limit=10

# Test function manually
gcloud functions call $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) --gen2

# Check enabled APIs
gcloud services list --enabled
```

### Log Analysis

```bash
# Search for errors in logs
gcloud logging read "resource.type=cloud_function AND severity=ERROR" \
  --limit=10 --format=json

# Monitor function executions
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=$(terraform output -raw function_name)" \
  --limit=20
```

## Cleanup

### Remove All Resources

```bash
# Destroy infrastructure
terraform destroy -var="project_id=your-project-id"

# Confirm cleanup
gcloud functions list
gcloud storage buckets list
```

### Partial Cleanup

```bash
# Remove specific resources
terraform destroy -target=google_cloudfunctions2_function.document_processor

# Clean up storage manually if needed
gsutil rm -r gs://$(terraform output -raw bucket_name)
```

## Extension Ideas

1. **Multi-format Support**: Add support for PowerPoint, Excel, and image-based documents
2. **Custom Summarization**: Implement different summary styles based on document type
3. **Real-time Notifications**: Integrate with Pub/Sub for processing notifications
4. **Web Interface**: Build a frontend using Cloud Run for document upload and management
5. **Batch Processing**: Implement batch processing for high-volume scenarios

## Support and Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Generative AI Guide](https://cloud.google.com/vertex-ai/generative-ai/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

To contribute improvements to this infrastructure:

1. Test changes in a development project
2. Update documentation for any new variables or outputs
3. Ensure security best practices are maintained
4. Submit changes with clear descriptions

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements and security policies.