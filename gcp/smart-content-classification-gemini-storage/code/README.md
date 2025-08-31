# Infrastructure as Code for Smart Content Classification with Gemini and Cloud Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Content Classification with Gemini and Cloud Storage".

## Solution Overview

This infrastructure deploys an intelligent content classification system that leverages Gemini 2.5's multimodal capabilities to automatically analyze uploaded files in Cloud Storage, extracting content meaning, sentiment, and business context to categorize documents into organized folder structures. The event-driven architecture uses Cloud Functions to trigger AI analysis upon file uploads, enabling real-time content organization with human-level understanding.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure includes:

- **Cloud Storage Buckets**: Staging bucket for uploads and classification buckets for organized content
- **Cloud Function**: Event-driven processor with Gemini 2.5 integration
- **Service Account**: Secure access with least-privilege permissions
- **IAM Roles**: Appropriate permissions for Vertex AI, Storage, and Logging
- **Eventarc Triggers**: Automatic file processing on upload events
- **API Services**: Vertex AI, Cloud Functions, Storage, and supporting services

## Prerequisites

### Required Tools
- Google Cloud CLI (gcloud) installed and authenticated
- Project with billing enabled
- Appropriate IAM permissions for resource creation

### Required APIs
The following APIs will be automatically enabled during deployment:
- Artifact Registry API
- Cloud Build API
- Cloud Functions API
- Eventarc API
- Cloud Logging API
- Cloud Storage API
- Vertex AI API
- Cloud Run API

### Required Permissions
Your account needs the following roles:
- `roles/storage.admin` - For creating and managing Cloud Storage buckets
- `roles/cloudfunctions.admin` - For deploying Cloud Functions
- `roles/iam.serviceAccountAdmin` - For creating service accounts
- `roles/serviceusage.serviceUsageAdmin` - For enabling APIs
- `roles/aiplatform.admin` - For Vertex AI access
- `roles/eventarc.admin` - For setting up event triggers

### Cost Estimation
Estimated monthly costs for moderate usage (1000 files/month):
- Cloud Storage: $2-5
- Cloud Functions: $5-10
- Vertex AI (Gemini 2.5 Pro): $8-15
- **Total**: $15-30 per month

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create content-classifier \
    --location=${REGION} \
    --source-configs="main.yaml" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe content-classifier \
    --location=${REGION}
```

### Using Terraform

```bash
# Set your project ID and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Apply configuration
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Testing the Deployment

After successful deployment, test the content classification system:

1. **Upload test files to the staging bucket**:
   ```bash
   # Create sample files
   echo "This is a legal contract for services..." > contract.txt
   echo "Invoice #001 - Amount: $1000" > invoice.txt
   echo "Join our amazing product launch event!" > marketing.txt
   
   # Upload to staging bucket
   gsutil cp contract.txt gs://staging-content-*/
   gsutil cp invoice.txt gs://staging-content-*/
   gsutil cp marketing.txt gs://staging-content-*/
   ```

2. **Monitor function execution**:
   ```bash
   # View function logs
   gcloud functions logs read content-classifier \
       --region=${REGION} \
       --limit=10
   ```

3. **Verify file classification**:
   ```bash
   # Check classification buckets
   gsutil ls gs://contracts-*/
   gsutil ls gs://invoices-*/
   gsutil ls gs://marketing-*/
   ```

## Configuration Options

### Customizable Variables

All implementations support these configuration options:

- **project_id**: Your Google Cloud project ID
- **region**: Deployment region (default: us-central1)
- **bucket_prefix**: Prefix for bucket names (default: generated)
- **function_memory**: Cloud Function memory allocation (default: 1024MB)
- **function_timeout**: Cloud Function timeout (default: 540s)
- **max_instances**: Maximum function instances (default: 10)

### Environment-Specific Configurations

For different environments, modify variables:

**Development**:
```bash
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=us-central1" \
    -var="function_memory=512" \
    -var="max_instances=3"
```

**Production**:
```bash
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=us-central1" \
    -var="function_memory=2048" \
    -var="max_instances=50"
```

## Monitoring and Logging

### Viewing Logs

```bash
# Function execution logs
gcloud functions logs read content-classifier \
    --region=${REGION} \
    --format="value(timestamp,message)"

# System logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=content-classifier" \
    --limit=50 \
    --format="value(timestamp,jsonPayload.message)"
```

### Monitoring Metrics

```bash
# Function invocations
gcloud logging metrics create function_invocations \
    --description="Content classifier function invocations" \
    --log-filter="resource.type=cloud_function"

# Classification accuracy (custom metric)
gcloud logging metrics create classification_success \
    --description="Successful content classifications" \
    --log-filter="resource.type=cloud_function AND jsonPayload.message:\"Successfully classified\""
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:content-classifier-sa"
   ```

2. **Files not being classified**:
   ```bash
   # Verify Eventarc trigger
   gcloud eventarc triggers list \
       --location=${REGION}
   
   # Check function logs for errors
   gcloud functions logs read content-classifier \
       --region=${REGION} \
       --severity=ERROR
   ```

3. **Vertex AI permission errors**:
   ```bash
   # Verify AI Platform permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.role:roles/aiplatform.user"
   ```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Update function with debug environment variable
gcloud functions deploy content-classifier \
    --gen2 \
    --set-env-vars="DEBUG=true" \
    --region=${REGION}
```

## Security Considerations

### Best Practices Implemented

- **Least Privilege Access**: Service account has minimal required permissions
- **Network Security**: Function runs in Google's managed environment
- **Data Encryption**: All data encrypted in transit and at rest
- **Audit Logging**: All operations logged for compliance
- **API Quotas**: Vertex AI quotas protect against unexpected usage

### Additional Security Measures

1. **Enable VPC Service Controls** (for enterprise environments):
   ```bash
   # Create service perimeter
   gcloud access-context-manager perimeters create content-classification \
       --policy=${ACCESS_POLICY_ID} \
       --title="Content Classification Perimeter"
   ```

2. **Implement IAM Conditions** for time-based access:
   ```bash
   # Add conditional IAM binding
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="serviceAccount:content-classifier-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
       --role="roles/aiplatform.user" \
       --condition="expression=request.time.getHours() >= 9 && request.time.getHours() <= 17"
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete content-classifier \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources deleted
gcloud functions list --regions=${REGION}
gcloud storage buckets list --filter="name:staging-content OR name:contracts OR name:invoices OR name:marketing OR name:miscellaneous"
gcloud iam service-accounts list --filter="email:content-classifier-sa"
```

## Advanced Configurations

### High Availability Setup

For production environments, consider:

1. **Multi-region deployment**:
   ```bash
   # Deploy in multiple regions
   for region in us-central1 us-east1 europe-west1; do
       terraform apply \
           -var="project_id=${PROJECT_ID}" \
           -var="region=${region}"
   done
   ```

2. **Cross-region bucket replication**:
   ```bash
   # Enable bucket replication
   gsutil replication set classification-replication.json gs://contracts-bucket
   ```

### Performance Optimization

1. **Optimize function memory based on file types**:
   ```bash
   # For image-heavy workloads
   terraform apply \
       -var="function_memory=4096" \
       -var="function_timeout=900"
   ```

2. **Implement batch processing for high volumes**:
   ```bash
   # Deploy with higher max instances
   terraform apply \
       -var="max_instances=100" \
       -var="concurrent_requests=100"
   ```

## Integration Examples

### BigQuery Analytics Integration

```bash
# Create BigQuery dataset for classification analytics
bq mk --dataset \
    --description "Content classification analytics" \
    ${PROJECT_ID}:content_analytics

# Create table for classification results
bq mk --table \
    ${PROJECT_ID}:content_analytics.classifications \
    schema.json
```

### Cloud DLP Integration

```bash
# Deploy with DLP integration
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="enable_dlp=true" \
    -var="dlp_template_id=projects/${PROJECT_ID}/inspectTemplates/pii-template"
```

## Support and Documentation

### Additional Resources

- [Original Recipe Documentation](../smart-content-classification-gemini-storage.md)
- [Vertex AI Gemini 2.5 Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/models/gemini/2-5-pro)
- [Cloud Functions Event-Driven Architecture](https://cloud.google.com/functions/docs/writing/write-event-driven-functions)
- [Cloud Storage Automated Classification](https://cloud.google.com/sensitive-data-protection/docs/automating-classification-of-data-uploaded-to-cloud-storage)

### Getting Help

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Check Cloud Logging for detailed error messages

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate with multiple file types and sizes
3. Ensure security best practices are maintained
4. Update documentation for any new features

---

**Note**: This infrastructure code implements the complete solution described in the Smart Content Classification recipe, providing production-ready deployment options with comprehensive monitoring, security, and operational features.