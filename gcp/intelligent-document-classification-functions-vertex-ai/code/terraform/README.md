# Terraform Infrastructure for GCP Intelligent Document Classification

This Terraform configuration deploys a complete serverless document classification system on Google Cloud Platform using Cloud Functions, Vertex AI, and Cloud Storage.

## Architecture Overview

The infrastructure creates:
- **Cloud Storage buckets** for document ingestion and classified storage
- **Cloud Function** for document processing and classification
- **Vertex AI integration** for AI-powered document analysis using Gemini models
- **Service accounts** with appropriate IAM permissions
- **Monitoring and logging** for operational visibility
- **Pub/Sub topics** for event-driven architecture

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK** installed and configured
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Initialize and authenticate
   gcloud init
   gcloud auth application-default login
   ```

2. **Terraform** installed (version >= 1.8)
   ```bash
   # Install Terraform
   wget https://releases.hashicorp.com/terraform/1.8.0/terraform_1.8.0_linux_amd64.zip
   unzip terraform_1.8.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **Google Cloud Project** with billing enabled
   ```bash
   # Create a new project (optional)
   gcloud projects create your-project-id --name="Document Classification"
   
   # Set default project
   gcloud config set project your-project-id
   
   # Enable billing (required for API usage)
   # This must be done through the Cloud Console
   ```

4. **Required permissions** in your GCP project:
   - Project Owner or Editor role
   - Cloud Functions Admin
   - Storage Admin
   - AI Platform Admin
   - Service Account Admin

## Quick Start

### 1. Clone and Navigate
```bash
cd gcp/intelligent-document-classification-functions-vertex-ai/code/terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Configure Variables
Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment      = "dev"
resource_prefix  = "doc-classifier"
function_memory  = 512
function_timeout = 540

# Document categories
document_categories = ["contracts", "invoices", "reports", "other"]

# Storage configuration
storage_class            = "STANDARD"
enable_versioning        = false
enable_lifecycle         = true
lifecycle_age_days       = 30

# Monitoring and logging
enable_monitoring = true
enable_logging    = true
log_retention_days = 30

# Resource labels
labels = {
  purpose     = "document-classification"
  managed-by  = "terraform"
  component   = "ai-ml"
  owner       = "your-team"
}
```

### 4. Plan and Apply
```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Verify Deployment
```bash
# Check if resources were created
terraform output deployment_status

# Get bucket names for testing
terraform output inbox_bucket_name
terraform output classified_bucket_name
```

## Testing the Deployment

### 1. Upload Test Documents
```bash
# Get bucket name from Terraform output
INBOX_BUCKET=$(terraform output -raw inbox_bucket_name)

# Create test documents
echo "This is a service agreement between parties..." > test_contract.txt
echo "Invoice #12345 - Amount due: $1,000..." > test_invoice.txt
echo "Quarterly performance report for Q4..." > test_report.txt

# Upload documents for classification
gsutil cp test_contract.txt gs://$INBOX_BUCKET/
gsutil cp test_invoice.txt gs://$INBOX_BUCKET/
gsutil cp test_report.txt gs://$INBOX_BUCKET/
```

### 2. Verify Classification
```bash
# Get classified bucket name
CLASSIFIED_BUCKET=$(terraform output -raw classified_bucket_name)

# Wait for processing (30-60 seconds)
sleep 60

# Check classified documents
echo "=== Classified Documents ==="
gsutil ls -r gs://$CLASSIFIED_BUCKET/

# View logs
FUNCTION_NAME=$(terraform output -raw function_name)
gcloud functions logs read $FUNCTION_NAME --gen2 --region=us-central1 --limit=20
```

### 3. Monitor Performance
```bash
# View monitoring dashboard
terraform output monitoring_dashboard_url

# Check function metrics
gcloud functions describe $FUNCTION_NAME --gen2 --region=us-central1
```

## Configuration Options

### Environment Variables

The following environment variables are set in the Cloud Function:

| Variable | Description | Default |
|----------|-------------|---------|
| `CLASSIFIED_BUCKET` | Bucket for classified documents | Set by Terraform |
| `INBOX_BUCKET` | Bucket for document uploads | Set by Terraform |
| `VERTEX_LOCATION` | Vertex AI location | us-central1 |
| `DOCUMENT_CATEGORIES` | JSON array of categories | ["contracts", "invoices", "reports", "other"] |

### Scaling Configuration

| Parameter | Description | Default | Range |
|-----------|-------------|---------|-------|
| `function_memory` | Function memory allocation | 512 MiB | 128-8192 MiB |
| `function_timeout` | Function timeout | 540s | 1-540s |
| `max_instances` | Maximum function instances | 10 | 1-1000 |
| `min_instances` | Minimum function instances | 0 | 0-1000 |

### Storage Configuration

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `storage_class` | Storage class for buckets | STANDARD | STANDARD, NEARLINE, COLDLINE, ARCHIVE |
| `enable_versioning` | Enable object versioning | false | true, false |
| `enable_lifecycle` | Enable lifecycle management | true | true, false |
| `lifecycle_age_days` | Days before object deletion | 30 | 1-365 |

## Security Features

### IAM and Service Accounts
- Dedicated service account with minimal required permissions
- No public access to buckets by default
- Uniform bucket-level access enabled

### Audit and Monitoring
- Cloud Audit Logs enabled for storage operations
- Cloud Logging integration for function execution
- Cloud Monitoring alerts for error rates
- Pub/Sub events for classification tracking

### Data Protection
- Optional object versioning for data recovery
- Lifecycle policies for automatic cleanup
- Encryption at rest (Google-managed keys)
- Encryption in transit (HTTPS/TLS)

## Cost Optimization

### Estimated Monthly Costs
Based on moderate usage (1000 documents/month):

| Service | Estimated Cost |
|---------|----------------|
| Cloud Functions (invocations) | $0.40 |
| Cloud Functions (compute) | $2.50 |
| Vertex AI (Gemini requests) | $0.50 |
| Cloud Storage | $0.50 |
| Cloud Logging | $0.25 |
| **Total** | **~$4.15/month** |

### Cost Optimization Tips
1. **Adjust function memory** based on actual usage
2. **Enable lifecycle policies** to automatically delete old documents
3. **Use appropriate storage classes** for different data access patterns
4. **Monitor Vertex AI usage** and implement request throttling if needed
5. **Set up budget alerts** to track spending

## Customization

### Adding Custom Document Categories

1. Update the `document_categories` variable:
```hcl
document_categories = ["contracts", "invoices", "reports", "legal", "hr", "other"]
```

2. The function will automatically create folders for new categories

### Integrating with External Systems

#### Webhook Integration
```bash
# Get function URL
FUNCTION_URL=$(terraform output -raw function_url)

# Send HTTP requests to function
curl -X POST $FUNCTION_URL -H "Content-Type: application/json" -d '{"test": true}'
```

#### Pub/Sub Integration
```bash
# Get Pub/Sub topic
TOPIC_NAME=$(terraform output -raw pubsub_topic_name)

# Subscribe to classification events
gcloud pubsub subscriptions pull $TOPIC_NAME-sub --auto-ack
```

### Custom Classification Logic

To modify the classification logic:

1. Edit `templates/main.py.tpl`
2. Update the `classify_with_gemini` function
3. Apply Terraform changes: `terraform apply`

## Troubleshooting

### Common Issues

#### 1. Function Deployment Fails
```bash
# Check Cloud Build logs
gcloud builds list --limit=5

# Verify APIs are enabled
gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com"
```

#### 2. Classification Not Working
```bash
# Check function logs
gcloud functions logs read $FUNCTION_NAME --gen2 --limit=50

# Test Vertex AI connectivity
gcloud ai models list --region=us-central1
```

#### 3. Storage Trigger Not Firing
```bash
# Verify trigger configuration
gcloud functions describe $FUNCTION_NAME --gen2 --region=us-central1

# Check bucket notifications
gsutil notification list gs://$INBOX_BUCKET
```

#### 4. Permission Errors
```bash
# Check service account permissions
gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:*function-sa*"

# Test storage access
gsutil ls gs://$INBOX_BUCKET
```

### Debug Mode
Enable detailed logging by setting:
```hcl
labels = {
  debug_mode = "true"
}
```

## Maintenance

### Updates and Upgrades

#### Terraform Updates
```bash
# Update providers
terraform init -upgrade

# Plan changes
terraform plan

# Apply updates
terraform apply
```

#### Function Code Updates
```bash
# Function code is automatically redeployed when templates change
terraform apply

# Force function redeployment
terraform taint google_cloudfunctions2_function.document_classifier
terraform apply
```

### Backup and Recovery

#### Configuration Backup
```bash
# Export Terraform state
terraform show -json > backup-$(date +%Y%m%d).json

# Backup tfvars
cp terraform.tfvars terraform.tfvars.backup
```

#### Data Backup
```bash
# Backup bucket contents
gsutil -m cp -r gs://$CLASSIFIED_BUCKET gs://backup-bucket/$(date +%Y%m%d)/
```

## Cleanup

### Destroy All Resources
```bash
# Destroy infrastructure
terraform destroy

# Confirm deletion
# Type 'yes' when prompted
```

### Selective Cleanup
```bash
# Remove specific resources
terraform destroy -target=google_storage_bucket.inbox_bucket

# Clean up local files
rm -rf function_source/
rm -f function_source.zip
```

### Manual Cleanup (if needed)
```bash
# Delete remaining storage objects
gsutil -m rm -r gs://$INBOX_BUCKET/**
gsutil -m rm -r gs://$CLASSIFIED_BUCKET/**

# Delete service accounts
gcloud iam service-accounts delete doc-classifier-sa@$PROJECT_ID.iam.gserviceaccount.com
```

## Support and Documentation

### Google Cloud Documentation
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)

### Terraform Documentation
- [Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

### Recipe Documentation
- Original recipe: `../../../intelligent-document-classification-functions-vertex-ai.md`
- Architecture details and business context in the recipe file

## Contributing

To contribute improvements to this Terraform configuration:

1. Test changes in a development environment
2. Update documentation for any new variables or outputs
3. Ensure security best practices are maintained
4. Validate with `terraform plan` before submitting changes

## License

This Terraform configuration is part of the cloud recipes collection and follows the same licensing terms as the parent repository.