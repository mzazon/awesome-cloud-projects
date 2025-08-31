# Terraform Infrastructure for Location-Aware Content Generation with Gemini and Maps

This directory contains Terraform infrastructure code for deploying a complete location-aware content generation system using Google Cloud Platform services including Vertex AI, Cloud Functions, and Cloud Storage.

## Architecture Overview

The infrastructure creates:
- **Cloud Function Gen2**: Serverless HTTP API for content generation requests
- **Vertex AI Integration**: Access to Gemini 2.5 Flash with Google Maps grounding
- **Cloud Storage**: Buckets for generated content storage and function logs
- **Service Account**: Dedicated IAM identity with least-privilege permissions
- **API Enablement**: Required Google Cloud APIs for the solution

## Prerequisites

### Required Tools
- [Terraform](https://terraform.io/downloads.html) >= 1.5.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) >= 400.0.0
- Valid Google Cloud account with billing enabled

### Required Permissions
Your Google Cloud user account or service account needs:
- `Project Editor` or `Owner` role on the target project
- `Service Account Admin` role for creating service accounts
- `Cloud Functions Admin` role for deploying functions
- `Storage Admin` role for creating buckets

### Billing Requirements
- Billing account must be outside the European Economic Area (EEA)
- Google Maps grounding is in Preview and may have additional charges
- Estimated cost: $5-15 for testing (varies by usage)

## Quick Start

### 1. Clone and Navigate
```bash
# Navigate to the terraform directory
cd gcp/location-aware-content-gemini-maps/code/terraform/
```

### 2. Configure Variables
```bash
# Copy and edit the example terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars

# Edit with your specific values
vim terraform.tfvars
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

### 4. Test the Deployment
```bash
# Use the output URL to test the function
curl -X POST '[FUNCTION_URL_FROM_OUTPUT]' \
  -H 'Content-Type: application/json' \
  -d '{
    "location": "Times Square, New York City",
    "content_type": "marketing",
    "audience": "tourists"
  }'
```

## Configuration Variables

### Required Variables
```hcl
# terraform.tfvars
project_id = "your-gcp-project-id"
region     = "us-central1"
```

### Optional Variables
```hcl
# Customize resource names and configuration
bucket_name_prefix   = "location-content"
function_name        = "generate-location-content"
function_memory      = "512Mi"
function_timeout     = 60
function_max_instances = 10

# Service account configuration
service_account_name = "location-content-sa"

# Storage configuration
enable_versioning = true
bucket_lifecycle_age_days = 365

# Security configuration
allow_unauthenticated = true  # Set to false for production
```

## File Structure

```
terraform/
├── main.tf                    # Main infrastructure resources
├── variables.tf              # Input variable definitions
├── outputs.tf                # Output value definitions
├── versions.tf               # Terraform and provider versions
├── terraform.tfvars.example  # Example variable values
├── README.md                 # This file
└── function-source/          # Cloud Function source code
    ├── main.py               # Function implementation
    └── requirements.txt      # Python dependencies
```

## Deployed Resources

### Google Cloud APIs
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Resource Manager API (`cloudresourcemanager.googleapis.com`)
- IAM API (`iam.googleapis.com`)

### Compute Resources
- **Cloud Function Gen2**: `generate-location-content`
  - Runtime: Python 3.12
  - Memory: 512Mi (configurable)
  - Timeout: 60 seconds (configurable)
  - Trigger: HTTP
  - Authentication: Public access (configurable)

### Storage Resources
- **Content Bucket**: Stores generated content as JSON files
  - Versioning: Enabled
  - CORS: Configured for web access
  - Lifecycle: Automatic cleanup after 365 days
- **Logs Bucket**: Stores function execution logs
  - Lifecycle: Automatic cleanup after 30 days

### IAM Resources
- **Service Account**: `location-content-sa@[PROJECT].iam.gserviceaccount.com`
  - Roles: `viewer`, `aiplatform.user`, `storage.admin`
  - Purpose: Execute Cloud Function with minimal required permissions

## Usage Examples

### Basic Content Generation
```bash
# Marketing content for tourists
curl -X POST '[FUNCTION_URL]' \
  -H 'Content-Type: application/json' \
  -d '{
    "location": "Golden Gate Bridge, San Francisco",
    "content_type": "marketing",
    "audience": "tourists"
  }'
```

### Travel Guide Generation
```bash
# Travel guide for food enthusiasts
curl -X POST '[FUNCTION_URL]' \
  -H 'Content-Type: application/json' \
  -d '{
    "location": "Pike Place Market, Seattle",
    "content_type": "travel",
    "audience": "food enthusiasts"
  }'
```

### Business Content Generation
```bash
# Business content for entrepreneurs
curl -X POST '[FUNCTION_URL]' \
  -H 'Content-Type: application/json' \
  -d '{
    "location": "Silicon Valley, California",
    "content_type": "business",
    "audience": "entrepreneurs"
  }'
```

## Monitoring and Troubleshooting

### View Function Logs
```bash
# Get function logs
gcloud functions logs read generate-location-content \
  --region=us-central1 \
  --gen2 \
  --limit=50
```

### Check Function Status
```bash
# Get function details
gcloud functions describe generate-location-content \
  --region=us-central1 \
  --gen2
```

### Monitor Storage Usage
```bash
# Check storage usage
gsutil du -sh gs://[BUCKET_NAME]

# List generated content
gsutil ls -la gs://[BUCKET_NAME]/content/
```

### View Generated Content
```bash
# Download and view a content file
gsutil cat gs://[BUCKET_NAME]/content/[FILENAME].json | jq .
```

## Security Considerations

### Production Deployment
For production environments, consider:

1. **Disable Public Access**:
   ```hcl
   allow_unauthenticated = false
   ```

2. **Implement Authentication**:
   - Use Cloud IAM for API access control
   - Implement API keys or OAuth 2.0
   - Consider Cloud Endpoints for API management

3. **Network Security**:
   - Configure VPC connector for private networking
   - Use Cloud Armor for DDoS protection
   - Implement rate limiting

4. **Data Security**:
   - Enable customer-managed encryption keys (CMEK)
   - Configure bucket-level IAM policies
   - Implement data retention policies

### Compliance
- Ensure billing account compliance with Google Maps grounding restrictions
- Review data residency requirements for your use case
- Implement audit logging for content generation activities

## Cost Optimization

### Monitor Costs
```bash
# View current month billing
gcloud billing accounts list
gcloud billing projects describe [PROJECT_ID]
```

### Optimization Strategies
1. **Function Configuration**:
   - Set appropriate memory limits
   - Configure minimum instances to 0 for scale-to-zero
   - Implement request caching

2. **Storage Management**:
   - Configure lifecycle policies
   - Use appropriate storage classes
   - Implement object versioning limits

3. **API Usage**:
   - Monitor Vertex AI API usage
   - Implement content caching
   - Use batch processing for bulk operations

## Cleanup

### Destroy Infrastructure
```bash
# Destroy all Terraform-managed resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Manual Cleanup (if needed)
```bash
# Delete remaining storage objects
gsutil -m rm -r gs://[BUCKET_NAME]
gsutil -m rm -r gs://[BUCKET_NAME]-logs

# Disable APIs (optional)
gcloud services disable cloudfunctions.googleapis.com
gcloud services disable aiplatform.googleapis.com
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```
   Error: Error creating function: googleapi: Error 403: 
   Cloud Functions API has not been used in project [PROJECT] before
   ```
   **Solution**: Wait a few minutes after `terraform apply` for APIs to propagate.

2. **Billing Account Issues**:
   ```
   Error: Google Maps grounding not available for this billing account
   ```
   **Solution**: Ensure billing account is outside the EEA region.

3. **Permission Denied**:
   ```
   Error: googleapi: Error 403: [USER] does not have permission to access [RESOURCE]
   ```
   **Solution**: Verify your account has the required IAM roles listed in Prerequisites.

4. **Function Deployment Timeout**:
   ```
   Error: Error waiting for function to be deployed: timeout while waiting
   ```
   **Solution**: Check Cloud Build logs and increase timeout if necessary.

### Getting Help

1. **Check Terraform State**:
   ```bash
   terraform state list
   terraform state show [RESOURCE_NAME]
   ```

2. **View Google Cloud Console**:
   - [Cloud Functions Console](https://console.cloud.google.com/functions)
   - [Cloud Storage Console](https://console.cloud.google.com/storage)
   - [IAM Console](https://console.cloud.google.com/iam-admin)

3. **Enable Debug Logging**:
   ```bash
   export TF_LOG=DEBUG
   terraform apply
   ```

## Contributing

When making changes to this infrastructure:

1. Test changes in a development environment first
2. Update variable descriptions and validation rules
3. Add appropriate resource tags and labels
4. Update this README with new configuration options
5. Verify all outputs are accurate and useful

## Related Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Gemini Documentation](https://cloud.google.com/vertex-ai/docs/generative-ai/multimodal/overview)
- [Google Maps Grounding Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/grounding/grounding-with-google-maps)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)

## License

This infrastructure code is provided as part of the cloud recipes project. See the main project README for license information.