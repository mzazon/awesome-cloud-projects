# Interview Practice Assistant - Terraform Infrastructure

This directory contains Terraform infrastructure code for deploying the Interview Practice Assistant on Google Cloud Platform. The solution uses Vertex AI Gemini for interview analysis, Speech-to-Text for transcription, and Cloud Functions for serverless processing.

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage Bucket**: Stores audio files and function source code with lifecycle management
- **Three Cloud Functions**: 
  - Speech-to-Text function for audio transcription
  - Gemini Analysis function for interview feedback
  - Orchestration function for workflow coordination
- **Service Account**: Custom IAM with least privilege access
- **API Enablement**: Required Google Cloud APIs
- **Sample Data**: Optional interview questions dataset

## Prerequisites

1. **Google Cloud Account**: With billing enabled
2. **Terraform**: Version 1.5 or later ([Install Terraform](https://developer.hashicorp.com/terraform/downloads))
3. **Google Cloud CLI**: Installed and authenticated ([Install gcloud](https://cloud.google.com/sdk/docs/install))
4. **Required Permissions**: 
   - Project Owner or Editor role
   - Service Account Admin
   - Cloud Functions Admin
   - Storage Admin
   - Vertex AI User

## Quick Start

### 1. Authentication

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project (optional if specified in terraform.tfvars)
export GOOGLE_CLOUD_PROJECT="your-project-id"
```

### 2. Initialize Terraform

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

### 4. Test the Deployment

After deployment, use the output values to test:

```bash
# Test the analysis function (works immediately)
curl -X POST [ANALYSIS_FUNCTION_URL] \
  -H "Content-Type: application/json" \
  -d '{
    "transcription": "I am a software engineer with five years of experience in full-stack development.",
    "question": "Tell me about yourself",
    "confidence": 0.95
  }'

# Upload audio file and test complete workflow
gsutil cp your_audio_file.wav gs://[BUCKET_NAME]/
curl -X POST [ORCHESTRATION_FUNCTION_URL] \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "[BUCKET_NAME]",
    "file": "your_audio_file.wav",
    "question": "Tell me about yourself"
  }'
```

## Configuration

### Required Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required
project_id = "your-gcp-project-id"

# Optional (with defaults)
region     = "us-central1"
environment = "dev"
prefix     = "interview-assistant"
```

### Complete Variable Options

```hcl
# Basic Configuration
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
environment = "dev"
prefix     = "interview-assistant"

# Function Configuration
function_memory_mb = {
  speech        = 512
  analysis      = 1024
  orchestration = 256
}

function_timeout_seconds = {
  speech        = 120
  analysis      = 120
  orchestration = 300
}

# AI Model Configuration
gemini_model           = "gemini-1.5-pro"  # or "gemini-1.5-flash" for cost optimization
speech_model           = "latest_long"
speech_language_code   = "en-US"
enable_enhanced_speech = true

# Storage Configuration
bucket_lifecycle_age_days = 30
force_destroy_bucket     = false

# Security Configuration
allow_unauthenticated_functions = false  # Set to true for testing
service_account_name           = "interview-assistant"

# Features
enable_apis        = true
create_sample_data = true

# Labels
labels = {
  purpose     = "interview-practice"
  environment = "dev"
  managed-by  = "terraform"
  team        = "your-team"
}
```

## Important Configuration Notes

### Security Settings

- **`allow_unauthenticated_functions`**: Set to `false` for production
- For production, implement proper authentication using Google Cloud IAM
- The service account uses least privilege access

### Cost Optimization

- **Gemini Model**: Use `gemini-1.5-flash` instead of `gemini-1.5-pro` for lower costs
- **Memory Allocation**: Adjust function memory based on actual usage patterns
- **Lifecycle Policy**: Automatically deletes audio files after 30 days

### Regional Considerations

Ensure your chosen region supports all required services:
- Vertex AI (Gemini models)
- Speech-to-Text API with enhanced models
- Cloud Functions (2nd generation)

## Deployment Commands

### Standard Deployment

```bash
# Initialize and plan
terraform init
terraform plan -var-file="terraform.tfvars"

# Deploy
terraform apply -var-file="terraform.tfvars"
```

### Development Deployment

```bash
# Quick development deployment with unauthenticated access
terraform apply \
  -var="project_id=your-dev-project" \
  -var="allow_unauthenticated_functions=true" \
  -var="environment=dev"
```

### Production Deployment

```bash
# Production deployment with security hardening
terraform apply \
  -var-file="production.tfvars" \
  -var="allow_unauthenticated_functions=false" \
  -var="environment=prod"
```

## Validation and Testing

### Check Deployment Status

```bash
# List deployed functions
gcloud functions list --region=us-central1

# Check bucket
gsutil ls -L gs://your-bucket-name

# View service account
gcloud iam service-accounts list --filter="email:interview-assistant*"
```

### Function Testing

```bash
# Test analysis function
curl -X POST $(terraform output -raw analysis_function_url) \
  -H "Content-Type: application/json" \
  -d '{
    "transcription": "I have been working as a software engineer for five years, specializing in cloud architecture and machine learning.",
    "question": "Tell me about your background",
    "confidence": 0.92
  }'

# Upload test audio file
echo "Test audio content" > test_audio.txt
gsutil cp test_audio.txt gs://$(terraform output -raw storage_bucket_name)/test_audio.wav

# Test orchestration (requires actual audio file)
curl -X POST $(terraform output -raw orchestration_function_url) \
  -H "Content-Type: application/json" \
  -d "{
    \"bucket\": \"$(terraform output -raw storage_bucket_name)\",
    \"file\": \"test_audio.wav\",
    \"question\": \"Tell me about yourself\"
  }"
```

### Log Monitoring

```bash
# View function logs
gcloud functions logs read interview-assistant-speech --region=us-central1 --limit=10
gcloud functions logs read interview-assistant-analysis --region=us-central1 --limit=10
gcloud functions logs read interview-assistant-orchestrate --region=us-central1 --limit=10
```

## Outputs Reference

After deployment, Terraform provides these useful outputs:

- **Function URLs**: Direct HTTP endpoints for testing
- **Bucket Information**: Storage bucket details and access commands
- **Test Commands**: Ready-to-use curl commands for validation
- **Configuration Details**: Deployed model versions and settings

Access outputs:

```bash
# View all outputs
terraform output

# Get specific output
terraform output orchestration_function_url
terraform output storage_bucket_name
```

## Cleanup

### Remove All Resources

```bash
# Destroy all infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Partial Cleanup

```bash
# Remove only functions (keep bucket)
terraform destroy -target=google_cloudfunctions_function.speech_function
terraform destroy -target=google_cloudfunctions_function.analysis_function  
terraform destroy -target=google_cloudfunctions_function.orchestration_function
```

### Force Bucket Cleanup

If you encounter issues with bucket deletion:

```bash
# Empty bucket first
gsutil -m rm -r gs://your-bucket-name/**

# Then run destroy
terraform destroy
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure `enable_apis = true` in your configuration
2. **Permissions Error**: Verify your Google Cloud account has necessary roles
3. **Function Deployment Failed**: Check function logs and source code syntax
4. **Bucket Already Exists**: Use a different prefix or bucket name suffix

### Debug Commands

```bash
# Check enabled APIs
gcloud services list --enabled

# Verify IAM bindings
gcloud projects get-iam-policy your-project-id

# Function details
gcloud functions describe function-name --region=us-central1

# Storage access
gsutil iam get gs://your-bucket-name
```

### Getting Help

1. Check Terraform logs: `TF_LOG=DEBUG terraform apply`
2. Review Google Cloud Console for resource status
3. Verify function source code in the generated `function_source/` directories
4. Check Cloud Build logs if function deployment fails

## Next Steps

After successful deployment:

1. **Security**: Configure authentication for production use
2. **Monitoring**: Set up Cloud Monitoring alerts and dashboards
3. **Frontend**: Build a web interface to interact with the functions
4. **Testing**: Upload various audio formats to test transcription accuracy
5. **Optimization**: Monitor costs and adjust model/memory settings

## Cost Estimation

Typical usage costs (USD per month):

- **Light Usage (50 sessions)**: $5-10
- **Moderate Usage (200 sessions)**: $15-25  
- **Heavy Usage (1000 sessions)**: $50-100

Cost factors:
- Function invocations and execution time
- Speech-to-Text API usage (per minute)
- Vertex AI Gemini token processing
- Cloud Storage (minimal for audio files)

Monitor costs in Google Cloud Console under Billing.