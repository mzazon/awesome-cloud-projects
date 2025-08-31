# Infrastructure as Code for Intelligent Document Classification with Cloud Functions and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Document Classification with Cloud Functions and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - `roles/cloudfunctions.admin`
  - `roles/storage.admin`
  - `roles/iam.serviceAccountAdmin`
  - `roles/aiplatform.admin`
  - `roles/serviceusage.serviceUsageAdmin`
- For Terraform: Terraform CLI installed (version 1.0 or later)
- For Infrastructure Manager: `gcloud` CLI with Infrastructure Manager API enabled

## Architecture Overview

This solution deploys:
- Cloud Storage buckets for document ingestion and classification
- Cloud Function for serverless document processing
- Service account with minimal required permissions
- Vertex AI integration for intelligent document classification
- Cloud Logging and Monitoring for observability

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/doc-classifier \
    --service-account "projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/doc-classifier
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud functions describe classify-documents --gen2 --region=us-central1
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `random_suffix`: Unique suffix for resource names
- `function_memory`: Cloud Function memory allocation (default: 512MiB)
- `function_timeout`: Cloud Function timeout (default: 540s)

### Terraform Variables

Create a `terraform.tfvars` file or set environment variables:

```bash
# terraform.tfvars
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
environment = "dev"
```

Available variables:
- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `environment`: Environment tag (default: dev)
- `function_memory`: Function memory in MB (default: 512)
- `function_timeout`: Function timeout in seconds (default: 540)

### Bash Script Configuration

Edit the script variables at the top of `scripts/deploy.sh`:

```bash
# Configuration variables
PROJECT_ID="your-project-id"
REGION="us-central1"
ZONE="us-central1-a"
FUNCTION_MEMORY="512MiB"
FUNCTION_TIMEOUT="540s"
```

## Testing the Deployment

After deployment, test the document classification system:

1. **Upload sample documents**:
   ```bash
   # Create test documents
   echo "This is a service agreement for software development..." > contract.txt
   echo "Invoice #12345 - Amount Due: $5,000..." > invoice.txt
   echo "Quarterly Business Report - Revenue increased by 15%..." > report.txt
   
   # Upload to inbox bucket
   gsutil cp contract.txt gs://doc-inbox-${RANDOM_SUFFIX}/
   gsutil cp invoice.txt gs://doc-inbox-${RANDOM_SUFFIX}/
   gsutil cp report.txt gs://doc-inbox-${RANDOM_SUFFIX}/
   ```

2. **Verify classification**:
   ```bash
   # Wait for processing (30-60 seconds)
   sleep 60
   
   # Check classified documents
   gsutil ls -r gs://doc-classified-${RANDOM_SUFFIX}/
   ```

3. **Monitor function logs**:
   ```bash
   gcloud functions logs read classify-documents \
       --gen2 \
       --region=${REGION} \
       --limit=20
   ```

## Monitoring and Troubleshooting

### Function Monitoring

```bash
# View function details
gcloud functions describe classify-documents --gen2 --region=${REGION}

# Check function logs
gcloud functions logs read classify-documents --gen2 --region=${REGION}

# Monitor function metrics
gcloud logging read 'resource.type="cloud_function" 
    resource.labels.function_name="classify-documents"' \
    --limit=50
```

### Storage Monitoring

```bash
# List bucket contents
gsutil ls -r gs://doc-inbox-${RANDOM_SUFFIX}/
gsutil ls -r gs://doc-classified-${RANDOM_SUFFIX}/

# Check bucket lifecycle policies
gsutil lifecycle get gs://doc-inbox-${RANDOM_SUFFIX}/
```

### Vertex AI Monitoring

```bash
# Check Vertex AI API usage
gcloud logging read 'protoPayload.serviceName="aiplatform.googleapis.com"' \
    --limit=20 \
    --format="table(timestamp,protoPayload.methodName,protoPayload.status.code)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/doc-classifier
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud functions list --filter="name:classify-documents"
gsutil ls | grep -E "(doc-inbox|doc-classified)"
gcloud iam service-accounts list --filter="email:doc-classifier-sa@*"
```

## Cost Optimization

### Estimated Costs

For testing/development usage:
- Cloud Functions: $0.40 per 1M invocations + $0.0000025 per 100ms of execution
- Cloud Storage: $0.020 per GB/month for Standard storage
- Vertex AI: $0.002-0.02 per 1K input tokens (varies by model)
- Cloud Logging: $0.50 per GB of logs ingested

### Cost Reduction Tips

1. **Function Configuration**:
   - Use minimum required memory allocation
   - Set appropriate timeout values
   - Consider using 1st gen functions for simpler workloads

2. **Storage Optimization**:
   - Implement lifecycle policies for old documents
   - Use Nearline/Coldline storage for archived documents
   - Enable compression for text documents

3. **Vertex AI Usage**:
   - Batch process documents when possible
   - Use efficient prompts to minimize token usage
   - Consider document content truncation for classification

## Security Considerations

### IAM and Access Control

- Service account follows principle of least privilege
- Cloud Function runs with dedicated service account
- Storage buckets have appropriate access controls
- Vertex AI access is restricted to classification tasks

### Data Protection

- Documents in transit are encrypted by default
- Storage buckets can be configured with customer-managed encryption
- Function logs don't expose document content
- Implement data retention policies for compliance

### Network Security

- Cloud Function operates in Google's secure environment
- Storage access uses secure HTTPS connections
- Vertex AI API calls use encrypted channels
- Consider VPC-native deployments for enhanced security

## Customization Examples

### Adding Document Types

Modify the Cloud Function code to support additional document categories:

```python
# In main.py, update the classification prompt
valid_categories = ['contracts', 'invoices', 'reports', 'proposals', 'agreements', 'other']
```

### Custom Storage Classes

Update storage bucket configuration for different access patterns:

```yaml
# In infrastructure-manager/main.yaml
storageClass: NEARLINE  # For infrequently accessed documents
storageClass: COLDLINE  # For archived documents
```

### Enhanced Monitoring

Add custom metrics and alerting:

```bash
# Create custom metric descriptor
gcloud logging metrics create document_classification_errors \
    --description="Count of document classification errors" \
    --log-filter='resource.type="cloud_function" severity>=ERROR'
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify all required APIs are enabled
   - Check service account permissions
   - Ensure source code is valid Python

2. **Documents not classified**:
   - Check function logs for errors
   - Verify Vertex AI API access
   - Confirm bucket triggers are configured

3. **Permission errors**:
   - Verify service account has required roles
   - Check IAM policy bindings
   - Ensure APIs are enabled in correct project

### Debug Commands

```bash
# Check enabled APIs
gcloud services list --enabled

# Verify service account roles
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:doc-classifier-sa@*"

# Test function directly
gcloud functions call classify-documents \
    --gen2 \
    --region=${REGION} \
    --data='{"bucket":"test","name":"test.txt"}'
```

## Support and Documentation

- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support resources.