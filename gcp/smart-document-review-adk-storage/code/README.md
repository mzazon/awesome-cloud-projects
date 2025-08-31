# Infrastructure as Code for Smart Document Review Workflow with ADK and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Document Review Workflow with ADK and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Storage Admin
  - Cloud Functions Admin
  - Vertex AI User
  - Project IAM Admin
- Python 3.10+ for local development (Agent Development Kit)
- Estimated cost: $5-15 for deployment and testing

## Quick Start

### Using Infrastructure Manager

```bash
# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/document-review-workflow \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --local-source="infrastructure-manager/" \
    --input-values="project_id=PROJECT_ID,region=REGION"

# Check deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/document-review-workflow
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create Storage buckets
# 3. Deploy Cloud Function
# 4. Configure IAM permissions
# 5. Set up Agent Development Kit environment
```

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage Buckets**: Input and results buckets with versioning enabled
- **Cloud Functions**: Serverless document processing with ADK integration
- **IAM Roles**: Service accounts with least privilege permissions
- **API Services**: Vertex AI, Cloud Functions, Cloud Build, and Storage APIs
- **Agent Development Kit**: Multi-agent system for document review

## Configuration Variables

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `bucket_prefix`: Prefix for storage bucket names
- `function_memory`: Cloud Function memory allocation (default: 512MB)
- `function_timeout`: Cloud Function timeout (default: 300s)

### Terraform Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `bucket_prefix`: Storage bucket name prefix
- `function_memory`: Memory allocation for Cloud Function
- `function_timeout`: Timeout for Cloud Function execution
- `enable_versioning`: Enable bucket versioning (default: true)

### Bash Script Environment Variables

- `PROJECT_ID`: Google Cloud project ID (required)
- `REGION`: Deployment region (default: us-central1)
- `ZONE`: Deployment zone (default: us-central1-a)

## Testing the Deployment

After successful deployment, test the document review workflow:

1. **Upload a test document**:
   ```bash
   # Create sample document
   echo "This is a test document with grammar errors and content that needs review." > test_document.txt
   
   # Upload to input bucket
   gsutil cp test_document.txt gs://BUCKET_NAME-input/
   ```

2. **Monitor processing**:
   ```bash
   # Check Cloud Function logs
   gcloud functions logs read FUNCTION_NAME --limit 50
   
   # Check for results
   gsutil ls gs://BUCKET_NAME-results/
   ```

3. **Download results**:
   ```bash
   # Download review results
   gsutil cp gs://BUCKET_NAME-results/review_test_document.txt.json ./
   
   # View results
   cat review_test_document.txt.json | jq '.'
   ```

## Advanced Configuration

### Custom Agent Configuration

Modify agent behavior by updating the function source code:

1. **Grammar Agent Settings**:
   - Temperature: 0.2 (low creativity for consistency)
   - Max tokens: 1000
   - Model: gemini-2.0-flash

2. **Accuracy Agent Settings**:
   - Temperature: 0.1 (very low for factual accuracy)
   - Max tokens: 1000
   - Verification threshold: Configurable

3. **Style Agent Settings**:
   - Temperature: 0.3 (moderate creativity for style suggestions)
   - Readability analysis: Enabled
   - Tone consistency checks: Enabled

### Monitoring and Alerting

Set up monitoring for the document review workflow:

```bash
# Create monitoring policy for function errors
gcloud alpha monitoring policies create --policy-from-file=monitoring-policy.yaml

# Set up log-based metrics
gcloud logging metrics create document_processing_errors \
    --description="Document processing errors" \
    --log-filter='resource.type="cloud_function" AND severity="ERROR"'
```

### Security Hardening

The infrastructure implements security best practices:

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Bucket Security**: Private buckets with controlled access
- **Function Security**: Isolated execution environment
- **API Security**: Restricted API access through service accounts
- **Data Encryption**: Encryption at rest and in transit

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/document-review-workflow
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Function
# 2. Remove Storage buckets and contents
# 3. Clean up IAM bindings
# 4. Disable APIs (optional)
# 5. Remove local development files
```

### Manual Cleanup Verification

Verify all resources are removed:

```bash
# Check remaining functions
gcloud functions list --filter="name:document-processor"

# Check remaining buckets
gsutil ls -p PROJECT_ID | grep document-review

# Check IAM policies
gcloud projects get-iam-policy PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:*document*"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable storage.googleapis.com
   ```

2. **Permission Errors**:
   ```bash
   # Check current permissions
   gcloud auth list
   gcloud config get-value project
   
   # Re-authenticate if needed
   gcloud auth login
   gcloud auth application-default login
   ```

3. **Function Deployment Failures**:
   ```bash
   # Check function logs
   gcloud functions logs read FUNCTION_NAME --limit 100
   
   # Verify source code and dependencies
   gcloud functions describe FUNCTION_NAME
   ```

4. **ADK Installation Issues**:
   ```bash
   # Verify Python environment
   python --version
   pip --version
   
   # Reinstall ADK
   pip install --upgrade google-adk
   ```

### Performance Optimization

- **Function Memory**: Increase memory allocation for large documents
- **Timeout Settings**: Adjust timeout for complex document processing
- **Parallel Processing**: Configure agent coordination for optimal performance
- **Caching**: Implement result caching for frequently processed documents

### Cost Optimization

- **Function Scaling**: Configure minimum instances to reduce cold starts
- **Storage Classes**: Use appropriate storage classes for different data types
- **API Quotas**: Monitor and optimize API usage
- **Resource Lifecycle**: Implement automatic cleanup for temporary resources

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Review Cloud Function logs for runtime errors
4. Validate IAM permissions and API enablement
5. Consult Agent Development Kit documentation for agent-specific issues

## Additional Resources

- [Google Agent Development Kit Documentation](https://google.github.io/adk-docs/)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Cloud Storage Security Guide](https://cloud.google.com/storage/docs/best-practices)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Infrastructure Manager Guide](https://cloud.google.com/infrastructure-manager/docs)