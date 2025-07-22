# Infrastructure as Code for Podcast Content Generation with Text-to-Speech and Natural Language

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Podcast Content Generation with Text-to-Speech and Natural Language".

## Architecture Overview

This infrastructure deploys a complete podcast generation pipeline using:

- **Google Cloud Text-to-Speech API**: Neural voice synthesis with SSML markup
- **Google Cloud Natural Language API**: Sentiment analysis and entity extraction
- **Cloud Storage**: Content repository and audio file storage
- **Cloud Functions**: Serverless processing engine
- **Cloud Monitoring**: Performance tracking and alerting
- **Cloud Logging**: Comprehensive logging and metrics

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud Platform account with billing enabled
- Google Cloud CLI (`gcloud`) installed and configured
- Terraform >= 1.0 installed
- Appropriate permissions for resource creation:
  - Project Editor or custom role with specific permissions
  - Service Account Admin
  - Cloud Functions Admin
  - Storage Admin

## Quick Start

### Using Infrastructure Manager

1. **Enable Infrastructure Manager API**:
   ```bash
   # Enable Infrastructure Manager API
   gcloud services enable config.googleapis.com
   
   # Set environment variables
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   export DEPLOYMENT_NAME="podcast-generator-$(date +%s)"
   ```

2. **Configure Deployment**:
   ```bash
   # Navigate to Infrastructure Manager directory
   cd infrastructure-manager/
   
   # Edit inputs.yaml with your project details
   # Or use environment variables for quick setup
   sed -i "s/PROJECT_ID_PLACEHOLDER/$PROJECT_ID/g" inputs.yaml
   ```

3. **Deploy Infrastructure**:
   ```bash
   # Create deployment
   gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/$DEPLOYMENT_NAME \
     --service-account="projects/$PROJECT_ID/serviceAccounts/infra-manager@$PROJECT_ID.iam.gserviceaccount.com" \
     --local-source="." \
     --inputs-file="inputs.yaml"
   
   # Monitor deployment status
   gcloud infra-manager deployments describe projects/$PROJECT_ID/locations/$REGION/deployments/$DEPLOYMENT_NAME
   ```

4. **Test the Deployment**:
   ```bash
   # Get deployment outputs
   gcloud infra-manager deployments describe projects/$PROJECT_ID/locations/$REGION/deployments/$DEPLOYMENT_NAME \
     --format="value(latestRevision.terraformBlueprint.outputs)"
   ```

### Using Terraform

1. **Initialize and Configure**:
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Copy and customize variables
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your project details
   ```

2. **Plan and Deploy**:
   ```bash
   # Review the deployment plan
   terraform plan -var="project_id=your-project-id"
   
   # Deploy the infrastructure
   terraform apply -var="project_id=your-project-id"
   ```

3. **Test the Deployment**:
   ```bash
   # Get the function URL from Terraform output
   FUNCTION_URL=$(terraform output -raw function_trigger_url)
   BUCKET_NAME=$(terraform output -raw storage_bucket_name)
   
   # Test with sample content
   curl -X POST $FUNCTION_URL \
     -H "Content-Type: application/json" \
     -d "{\"bucket_name\": \"$BUCKET_NAME\", \"file_name\": \"sample-article.txt\"}"
   ```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Clean up resources
./scripts/destroy.sh
```

## Configuration

### Terraform Variables

Key variables that can be customized in `terraform.tfvars`:

```hcl
# Required
project_id = "your-gcp-project-id"

# Optional customizations
region                = "us-central1"
environment          = "dev"
bucket_name_prefix   = "podcast-content"
function_name        = "podcast-processor"
function_memory      = 1024
function_timeout     = 540

# Cost optimization
bucket_storage_class  = "STANDARD"
lifecycle_age_days   = 30
enable_versioning    = true

# Monitoring and logging
enable_monitoring = true
enable_logging   = true

# Scaling configuration
function_min_instances = 0
function_max_instances = 100
```

### Infrastructure Manager Configuration

Customize your deployment by editing `infrastructure-manager/inputs.yaml`:

```yaml
# Required
project_id: "your-gcp-project-id"

# Optional customizations
region: "us-central1"
environment: "dev"
bucket_name_prefix: "podcast-content"
function_name: "podcast-processor"
function_memory: 1024
function_timeout: 540

# Cost optimization
bucket_storage_class: "STANDARD"
lifecycle_age_days: 30
enable_versioning: true

# Monitoring and logging
enable_monitoring: true
enable_logging: true

# Scaling configuration
function_min_instances: 0
function_max_instances: 100
```

### Environment-Specific Deployments

Create separate variable files for different environments:

```bash
# Development
terraform apply -var-file="environments/dev.tfvars"

# Staging
terraform apply -var-file="environments/staging.tfvars"

# Production
terraform apply -var-file="environments/prod.tfvars"
```

## Resource Details

### Created Resources

1. **Cloud Storage Bucket**:
   - Organized folder structure (input/, processed/, audio/)
   - Lifecycle management for cost optimization
   - Versioning enabled for content protection
   - Sample content files for testing

2. **Cloud Function**:
   - Python 3.11 runtime
   - Configurable memory and timeout
   - Auto-scaling based on demand
   - Environment variables for configuration

3. **Service Account**:
   - Least privilege access to required APIs
   - Dedicated IAM roles for security
   - Service account key for authentication

4. **API Enablement**:
   - Text-to-Speech API
   - Natural Language API
   - Cloud Storage API
   - Cloud Functions API
   - Cloud Build API

5. **Monitoring Resources** (optional):
   - Log-based metrics
   - Alert policies for error detection
   - Notification channels for alerts

### Security Features

- **Least Privilege Access**: Service account with minimal required permissions
- **HTTPS Only**: Function accessible only via HTTPS
- **Uniform Bucket Access**: Consistent IAM-based access control
- **API Security**: Secure API endpoints with proper authentication

## Testing and Validation

### Function Testing

```bash
# Test the deployed function
FUNCTION_URL=$(terraform output -raw function_trigger_url)
BUCKET_NAME=$(terraform output -raw storage_bucket_name)

curl -X POST $FUNCTION_URL \
  -H "Content-Type: application/json" \
  -d "{
    \"bucket_name\": \"$BUCKET_NAME\",
    \"file_name\": \"sample-article.txt\"
  }"
```

### Validate Generated Content

```bash
# Check generated audio files
gsutil ls gs://$(terraform output -raw storage_bucket_name)/audio/

# Review analysis metadata
gsutil cat gs://$(terraform output -raw storage_bucket_name)/processed/sample-article_analysis.json
```

### Monitor Function Execution

```bash
# View function logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/$DEPLOYMENT_NAME

# Verify deletion
gcloud infra-manager deployments list --location=$REGION
```

### Using Terraform

```bash
# Destroy all resources
terraform destroy

# Destroy with variable file
terraform destroy -var-file="terraform.tfvars"
```

### Using Scripts

```bash
# Clean up all resources
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete specific resources manually
gcloud functions delete podcast-processor --region=us-central1
gsutil -m rm -r gs://your-bucket-name
gcloud iam service-accounts delete podcast-generator@project-id.iam.gserviceaccount.com
```

## Cost Optimization

### Monitoring Costs

1. **Cloud Storage**:
   - Use lifecycle policies to manage old files
   - Choose appropriate storage classes
   - Monitor bucket usage regularly

2. **Cloud Functions**:
   - Optimize memory allocation
   - Set appropriate timeout values
   - Monitor execution frequency

3. **API Usage**:
   - Text-to-Speech: ~$4 per 1M characters
   - Natural Language: ~$1 per 1,000 units
   - Monitor API quotas and usage

### Cost-Saving Tips

- Set reasonable lifecycle policies (default: 30 days)
- Use NEARLINE or COLDLINE storage for archival content
- Optimize function memory allocation based on actual usage
- Implement request batching for high-volume scenarios

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs manually
   gcloud services enable texttospeech.googleapis.com
   gcloud services enable language.googleapis.com
   ```

2. **Permission Denied**:
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy your-project-id
   ```

3. **Function Deployment Failure**:
   ```bash
   # Check build logs
   gcloud functions logs read your-function-name --region=your-region
   ```

4. **Storage Access Issues**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://your-bucket-name
   ```

### Debugging Steps

1. Check Terraform state: `terraform show`
2. Validate configuration: `terraform validate`
3. Review logs: `gcloud logging read`
4. Test APIs directly: Use Cloud Console API Explorer

## Advanced Configuration

### Custom Voice Models

Modify the function code to use custom voice models:

```python
# In main.py.tpl, update configure_voice_for_sentiment function
voice_config = texttospeech.VoiceSelectionParams(
    language_code="en-US",
    name="your-custom-voice-name"
)
```

### Batch Processing

Enable batch processing for multiple files:

```bash
# Use the batch processing script (created during deployment)
./batch-podcast-generator.sh $FUNCTION_URL $BUCKET_NAME
```

### VPC Integration

Enable VPC connector for private network access:

```hcl
# In terraform.tfvars
enable_vpc_connector = true
vpc_connector_name  = "your-vpc-connector"
```

## Support

For issues with this infrastructure code:

1. Check the [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
2. Review [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
3. Consult [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
4. Review [Cloud Storage documentation](https://cloud.google.com/storage/docs)
5. Refer to the original recipe documentation

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update variable descriptions and validation rules
3. Maintain compatibility with existing deployments
4. Update documentation for any new features
5. Follow Terraform best practices and style guidelines