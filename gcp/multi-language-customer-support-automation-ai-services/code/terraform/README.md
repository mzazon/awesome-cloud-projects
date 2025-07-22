# Multi-Language Customer Support Automation - Terraform Infrastructure

This directory contains Terraform infrastructure as code for deploying a complete multilingual customer support automation system using Google Cloud AI services.

## Architecture Overview

The infrastructure deploys:

- **Google Cloud AI Services**: Speech-to-Text, Translation, Natural Language, Text-to-Speech
- **Cloud Functions**: Serverless AI processing pipeline
- **Cloud Workflows**: Orchestration for complex support scenarios
- **Firestore**: NoSQL database for conversation management
- **Cloud Storage**: Audio files and configuration storage
- **Cloud Monitoring**: Comprehensive observability and alerting

## Prerequisites

### Required Software

1. **Terraform**: Version 1.0 or higher
   ```bash
   # Install via package manager or download from terraform.io
   terraform version
   ```

2. **Google Cloud SDK**: Latest version
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   gcloud --version
   ```

3. **Authentication**: Google Cloud authentication configured
   ```bash
   # Authenticate with your Google account
   gcloud auth login
   
   # Set up application default credentials
   gcloud auth application-default login
   ```

### Google Cloud Project Setup

1. **Create or select a project**:
   ```bash
   # Create a new project
   gcloud projects create your-project-id --name="Multilingual Support"
   
   # Or list existing projects
   gcloud projects list
   
   # Set the project
   gcloud config set project your-project-id
   ```

2. **Enable billing** for the project (required for AI services)

3. **Required IAM permissions**:
   - Project Editor or Owner role
   - Or these specific roles:
     - Cloud Functions Admin
     - Storage Admin
     - Firestore Service Agent
     - Workflows Admin
     - Service Account Admin
     - Project IAM Admin

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd gcp/multi-language-customer-support-automation-ai-services/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your project details
vim terraform.tfvars  # or use your preferred editor
```

### 2. Initialize Terraform

```bash
# Initialize Terraform (downloads providers and modules)
terraform init

# Validate the configuration
terraform validate

# Format the code (optional)
terraform fmt
```

### 3. Plan and Deploy

```bash
# Create an execution plan
terraform plan

# Review the plan carefully, then apply
terraform apply

# Type 'yes' when prompted to confirm deployment
```

### 4. Verify Deployment

```bash
# Check the outputs
terraform output

# Test the function endpoint
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "audio_data": "'$(base64 -w 0 sample-audio.wav)'",
    "customer_id": "test-customer-123",
    "session_id": "test-session-456"
  }' \
  "$(terraform output -raw multilang_processor_function_url)"
```

## Configuration

### Required Variables

Edit `terraform.tfvars` and set these required values:

```hcl
# Your Google Cloud Project ID
project_id = "your-gcp-project-id"

# Deployment region
region = "us-central1"
```

### Important Configuration Options

#### Language Support
```hcl
# Supported languages for the system
supported_languages = [
  "en-US", "es-ES", "fr-FR", "de-DE", 
  "it-IT", "pt-BR", "ja-JP", "ko-KR", "zh-CN"
]

# Voice configuration for text-to-speech
tts_voice_config = {
  "en-US" = {
    name         = "en-US-Neural2-J"
    ssmlGender   = "FEMALE"
    languageCode = "en-US"
  }
  # ... more languages
}
```

#### Resource Scaling
```hcl
# Cloud Function scaling
function_max_instances = 100
function_min_instances = 0
function_memory = "1Gi"

# Sentiment analysis thresholds
sentiment_thresholds = {
  negative = -0.2
  positive = 0.2
  urgency  = -0.5
}
```

#### Security and Networking
```hcl
# CORS configuration
cors_origins = ["https://yourdomain.com"]

# Enable private networking (optional)
enable_vpc_connector = true
enable_private_google_access = true
```

## Monitoring and Alerting

### Built-in Monitoring

The deployment includes:

1. **Cloud Monitoring Dashboard**: Visualizes key metrics
2. **Alert Policies**: 
   - Function error rate monitoring
   - Negative sentiment detection
3. **Log-based Metrics**: 
   - Sentiment score tracking
   - Language detection analytics

### Accessing Monitoring

```bash
# Get monitoring dashboard URL
terraform output monitoring_dashboard_url

# View function logs
gcloud functions logs read $(terraform output -raw multilang_processor_function_name) \
  --region=$(terraform output -raw region) --limit=50
```

### Setting Up Notifications

1. Create notification channels in Google Cloud Console
2. Add channel IDs to `terraform.tfvars`:
   ```hcl
   notification_channels = [
     "projects/your-project/notificationChannels/your-channel-id"
   ]
   ```
3. Run `terraform apply` to update alert policies

## Cost Management

### Estimated Costs

**Monthly estimates for moderate usage**:
- Cloud Functions: $10-30 (based on requests and compute time)
- AI APIs: $50-200 (varies significantly with usage)
  - Speech-to-Text: ~$0.006 per 15 seconds
  - Translation: ~$20 per million characters
  - Natural Language: ~$0.50 per 1K requests
  - Text-to-Speech: ~$4 per million characters
- Cloud Storage: $1-5 (for audio files and configurations)
- Firestore: $5-20 (based on read/write operations)
- Monitoring: Free tier usually sufficient

### Cost Optimization

1. **Scale-to-zero functions**:
   ```hcl
   function_min_instances = 0
   ```

2. **Storage lifecycle management**:
   ```hcl
   lifecycle_age_days = 7  # Delete old files sooner
   ```

3. **Regional deployment**: Use regions close to your users

4. **Monitor usage**: Use the built-in dashboard to track API usage

## Security Best Practices

### Production Deployment

1. **Restrict CORS origins**:
   ```hcl
   cors_origins = ["https://yourdomain.com"]
   ```

2. **Use private networking**:
   ```hcl
   enable_vpc_connector = true
   enable_private_google_access = true
   ```

3. **Enable audit logging**:
   ```hcl
   enable_audit_logs = true
   ```

4. **Configure proper backup retention**:
   ```hcl
   backup_retention_days = 90
   log_retention_days = 90
   ```

### Service Account Security

The deployment creates a dedicated service account with minimal required permissions:
- AI Platform user access
- Storage object admin (for bucket access only)
- Firestore user access
- Function invoker access

## Troubleshooting

### Common Issues

1. **API not enabled error**:
   ```bash
   # Manually enable required APIs
   gcloud services enable speech.googleapis.com
   gcloud services enable translate.googleapis.com
   # ... other APIs
   ```

2. **Permission denied**:
   ```bash
   # Check your IAM permissions
   gcloud projects get-iam-policy your-project-id
   ```

3. **Function deployment fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   ```

4. **Quota exceeded**:
   - Check quotas in Google Cloud Console
   - Request quota increases if needed

### Debug Mode

Enable debug logging:
```bash
export TF_LOG=DEBUG
terraform plan
```

### Function Logs

```bash
# View real-time function logs
gcloud functions logs tail $(terraform output -raw multilang_processor_function_name) \
  --region=$(terraform output -raw region)

# View workflow execution logs
gcloud workflows executions list \
  --workflow=$(terraform output -raw support_workflow_name) \
  --location=$(terraform output -raw region)
```

## Cleanup

### Destroy Resources

```bash
# Destroy all created resources
terraform destroy

# Type 'yes' when prompted to confirm destruction
```

### Selective Cleanup

```bash
# Remove specific resources
terraform destroy -target=google_cloudfunctions2_function.multilang_processor

# Or remove from state without destroying
terraform state rm google_storage_bucket.customer_support_storage
```

### Important Notes

- Firestore databases cannot be deleted via Terraform; manual deletion required
- Storage buckets with `force_destroy = false` will prevent destruction
- IAM permissions may persist after resource deletion

## Advanced Configuration

### Custom Domain Setup

For production deployments, consider setting up custom domains:

```bash
# Map custom domain to Cloud Function
gcloud functions add-iam-policy-binding your-function \
  --region=your-region \
  --member="allUsers" \
  --role="roles/cloudfunctions.invoker"
```

### Integration with Existing Systems

The workflow includes placeholder API calls for:
- Support system escalation
- Survey system integration
- Follow-up scheduling

Update the workflow template with your actual API endpoints.

### Multi-Environment Setup

Use Terraform workspaces for multiple environments:

```bash
# Create development workspace
terraform workspace new development

# Create production workspace
terraform workspace new production

# Switch between workspaces
terraform workspace select production
```

## Support and Contributing

### Getting Help

1. Check the [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
2. Review [Google Cloud AI service documentation](https://cloud.google.com/ai-platform/docs)
3. Check the generated monitoring dashboard for system health

### Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any new variables or outputs
3. Follow Terraform best practices for resource naming and organization
4. Add appropriate validation rules for new variables

## Version History

- **v1.0**: Initial deployment with core AI services
- **v1.1**: Added comprehensive monitoring and alerting
- **v1.2**: Enhanced security and networking options

## License

This Terraform configuration is part of the cloud recipes repository. See the repository license for details.