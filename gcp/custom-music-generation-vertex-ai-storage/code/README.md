# Infrastructure as Code for Custom Music Generation with Vertex AI and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Custom Music Generation with Vertex AI and Storage".

## Recipe Overview

This solution builds a serverless music generation system using Vertex AI's Lyria 2 model for high-fidelity audio synthesis, Cloud Storage for secure file management, and Cloud Functions for API orchestration. The system transforms text prompts into instrumental tracks, automatically stores generated content with metadata, and provides a scalable API for integration with content creation workflows.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The IaC implementations deploy the following Google Cloud resources:

- **Cloud Storage Buckets**: Separate buckets for input prompts and generated music files with lifecycle policies
- **Cloud Functions**: 
  - Music Generator Function (event-driven, triggered by Cloud Storage)
  - REST API Function (HTTP-triggered for client requests)
- **IAM Service Accounts**: Dedicated service accounts with least-privilege permissions
- **IAM Policy Bindings**: Secure access configuration for Vertex AI and Cloud Storage
- **API Enablement**: Required Google Cloud APIs (Vertex AI, Cloud Functions, Cloud Storage)

## Prerequisites

### General Requirements
- Google Cloud account with billing enabled
- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate permissions for resource creation:
  - Cloud Storage Admin
  - Cloud Functions Admin
  - Vertex AI User
  - IAM Admin
  - Service Usage Admin

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager API enabled
- `gcloud` version 420.0.0 or later

#### Terraform
- Terraform >= 1.5.0
- Google Cloud provider >= 4.84.0
- Valid Google Cloud credentials configured

#### Bash Scripts
- `bash` shell environment
- `curl` for API testing
- `python3` with `requests` library for client testing

### Cost Considerations
- Estimated cost: $15-25 for running this recipe
- Includes Vertex AI inference, Cloud Storage, and Cloud Functions usage
- Cloud Storage lifecycle policies help optimize long-term costs

## Quick Start

### Using Infrastructure Manager (GCP Native)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/music-generation \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="main.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/music-generation
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./deploy.sh

# The script will output the API URL for testing
```

## Configuration Options

### Key Variables/Parameters

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | GCP region for deployment | `us-central1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `function_memory` | Memory allocation for Cloud Functions | `512MB` | No |
| `function_timeout` | Timeout for Cloud Functions | `540s` | No |
| `storage_class` | Cloud Storage class | `STANDARD` | No |
| `enable_versioning` | Enable Cloud Storage versioning | `true` | No |

### Infrastructure Manager Configuration

```yaml
# Example inputs in main.yaml
inputs:
  project_id: "your-project-id"
  region: "us-central1"
  environment: "production"
  function_memory: "1024MB"
  enable_monitoring: true
```

### Terraform Configuration

```bash
# Using terraform.tfvars file
echo 'project_id = "your-project-id"' > terraform.tfvars
echo 'region = "us-central1"' >> terraform.tfvars
echo 'environment = "production"' >> terraform.tfvars
```

## Post-Deployment Testing

### Test the API Endpoint

```bash
# Get the API URL from outputs
API_URL=$(terraform output -raw api_url)  # For Terraform
# or check deployment outputs for Infrastructure Manager

# Test with curl
curl -X POST ${API_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "prompt": "Peaceful ambient sounds for focus and productivity",
        "style": "ambient",
        "duration_seconds": 30,
        "tempo": "slow"
    }'
```

### Verify Cloud Storage Buckets

```bash
# List created buckets
gsutil ls -p ${PROJECT_ID}

# Check lifecycle policies
gsutil lifecycle get gs://music-prompts-*
gsutil lifecycle get gs://generated-music-*
```

### Monitor Cloud Functions

```bash
# List deployed functions
gcloud functions list --gen2

# Check function logs
gcloud functions logs read music-generator-* --gen2 --region=${REGION} --limit=10
gcloud functions logs read music-api-* --gen2 --region=${REGION} --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/music-generation

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify Cloud Functions are deleted
gcloud functions list --gen2

# Verify Cloud Storage buckets are deleted
gsutil ls -p ${PROJECT_ID}

# Check IAM policy bindings (optional)
gcloud projects get-iam-policy ${PROJECT_ID}
```

## Customization

### Modifying Music Generation Parameters

Update the Cloud Function environment variables to change default behavior:

```yaml
# In Infrastructure Manager main.yaml
environment_variables:
  DEFAULT_STYLE: "classical"
  DEFAULT_DURATION: "60"
  DEFAULT_TEMPO: "moderate"
  MODEL_NAME: "lyria-002"
```

### Adding Custom Storage Policies

Modify lifecycle policies in the storage configuration:

```yaml
lifecycle:
  rule:
    - action:
        type: "SetStorageClass"
        storageClass: "NEARLINE"
      condition:
        age: 15  # Changed from 30 days
    - action:
        type: "Delete"
      condition:
        age: 365  # Add deletion after 1 year
```

### Scaling Configuration

Adjust Cloud Functions scaling and performance:

```yaml
# For high-volume scenarios
function_config:
  memory: "1024MB"
  timeout: "900s"
  max_instances: 100
  min_instances: 1
```

## Monitoring and Observability

### Enable Additional Monitoring

```bash
# Enable Cloud Monitoring API
gcloud services enable monitoring.googleapis.com

# Create custom metrics and alerts for the music generation pipeline
gcloud alpha monitoring policies create --policy-from-file=monitoring-policy.yaml
```

### Log Analysis

```bash
# Search for specific log patterns
gcloud logging read "resource.type=cloud_function AND textPayload:\"Music generation completed\"" --limit=10

# Monitor error rates
gcloud logging read "resource.type=cloud_function AND severity>=ERROR" --limit=10
```

## Security Considerations

### IAM Best Practices

The IaC implementations follow security best practices:

- **Least Privilege**: Service accounts have minimal required permissions
- **Separation of Concerns**: Separate buckets for input and output with different access patterns
- **Audit Logging**: Cloud Audit Logs enabled for all resource access
- **Network Security**: Cloud Functions deployed with appropriate VPC connector when needed

### Data Protection

- **Encryption**: All Cloud Storage buckets use Google-managed encryption
- **Access Control**: Fine-grained IAM policies for bucket access
- **Versioning**: Object versioning enabled for data protection
- **Lifecycle Management**: Automatic data retention and archival policies

## Troubleshooting

### Common Issues

1. **Vertex AI API Not Enabled**
   ```bash
   gcloud services enable aiplatform.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/storage.admin"
   ```

3. **Cloud Function Timeout**
   - Increase timeout in function configuration
   - Check Vertex AI API quotas and limits

4. **Storage Access Denied**
   - Verify service account permissions
   - Check bucket IAM policies

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# For Terraform
export TF_LOG=DEBUG
terraform apply

# For gcloud operations
export CLOUDSDK_CORE_VERBOSITY=debug
gcloud functions deploy ...
```

## Performance Optimization

### Regional Deployment

Deploy resources in the same region for optimal performance:

```yaml
# Recommended regions for Vertex AI
recommended_regions:
  - us-central1
  - us-east1
  - europe-west1
  - asia-southeast1
```

### Caching and CDN

For production deployments, consider adding:

```bash
# Enable Cloud CDN for generated music files
gcloud compute backend-buckets create music-backend \
    --gcs-bucket-name=generated-music-bucket

gcloud compute url-maps create music-cdn \
    --default-backend-bucket=music-backend
```

## Support and Resources

### Documentation References

- [Vertex AI Lyria Music Generation](https://cloud.google.com/vertex-ai/generative-ai/docs/music/generate-music)
- [Cloud Storage Lifecycle Management](https://cloud.google.com/storage/docs/lifecycle)
- [Cloud Functions Event-driven Processing](https://cloud.google.com/functions/docs/concepts/events-triggers)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

- **Recipe Issues**: Refer to the original recipe documentation
- **Google Cloud Support**: Use Google Cloud Console support center
- **Community**: Google Cloud Community forums and Stack Overflow

### Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Generator Version**: 1.3
- **Supported Terraform Provider**: google >= 4.84.0
- **Supported Infrastructure Manager**: API version v1