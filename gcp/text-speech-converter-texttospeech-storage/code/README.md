# Infrastructure as Code for Text-to-Speech Converter with Text-to-Speech and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Text-to-Speech Converter with Text-to-Speech and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate permissions for resource creation:
  - `texttospeech.googleapis.com` API access
  - `storage.googleapis.com` API access
  - `cloudbuild.googleapis.com` API access (for Infrastructure Manager)
  - Storage bucket creation and management permissions
  - Service account creation permissions (if using service accounts)
- Python 3.8+ with pip (for testing the solution)
- Terraform 1.0+ (if using Terraform implementation)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's managed service for infrastructure as code, providing GitOps workflows and state management.

```bash
# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Set your project ID and deployment name
export PROJECT_ID="your-project-id"
export DEPLOYMENT_NAME="text-speech-converter"
export REGION="us-central1"

# Create the deployment
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/$DEPLOYMENT_NAME \
    --source-repo="." \
    --source-revision="main"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/$PROJECT_ID/locations/$REGION/deployments/$DEPLOYMENT_NAME
```

### Using Terraform

Terraform provides cross-cloud infrastructure management with extensive provider ecosystem support.

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide simple, direct deployment using gcloud CLI commands for quick setup and testing.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Test the deployment (optional)
./scripts/test.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Environment Variables

Set these environment variables to customize your deployment:

```bash
# Required
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"                    # GCP region for resources

# Optional customization
export BUCKET_NAME="tts-audio-${PROJECT_ID}"   # Cloud Storage bucket name
export SERVICE_ACCOUNT_NAME="tts-service"      # Service account for API access
export ENABLE_PUBLIC_ACCESS="true"             # Make bucket publicly readable
export STORAGE_CLASS="STANDARD"                # Cloud Storage class (STANDARD, NEARLINE, COLDLINE)
```

### Terraform Variables

Customize your Terraform deployment by creating a `terraform.tfvars` file:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
bucket_name = "custom-tts-bucket-name"
storage_class = "STANDARD"
enable_public_access = true

# Optional: Custom labels for resources
resource_labels = {
  environment = "demo"
  project     = "text-to-speech"
  owner       = "your-name"
}
```

### Infrastructure Manager Variables

For Infrastructure Manager deployments, update the `main.yaml` file or use deployment-time variables:

```bash
# Deploy with custom variables
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/$DEPLOYMENT_NAME \
    --source-repo="." \
    --source-revision="main" \
    --inputs="project_id=$PROJECT_ID,region=$REGION,bucket_name=custom-bucket-name"
```

## Architecture Overview

The infrastructure creates:

1. **Google Cloud Storage Bucket**: Stores generated audio files with configurable access controls
2. **API Enablement**: Enables Text-to-Speech and Cloud Storage APIs
3. **IAM Configuration**: Sets up appropriate service accounts and permissions
4. **Bucket Policies**: Configures access permissions for audio file storage and retrieval

## Testing the Deployment

After successful deployment, test the Text-to-Speech functionality:

```bash
# Install required Python libraries
pip install google-cloud-texttospeech google-cloud-storage

# Set authentication (if using service account)
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"

# Test basic text-to-speech conversion
python3 << 'EOF'
from google.cloud import texttospeech
from google.cloud import storage
import os

# Initialize clients
tts_client = texttospeech.TextToSpeechClient()
storage_client = storage.Client()

# Test text-to-speech synthesis
text_input = texttospeech.SynthesisInput(text="Hello from Google Cloud Text-to-Speech!")
voice = texttospeech.VoiceSelectionParams(
    language_code="en-US",
    name="en-US-Wavenet-D",
    ssml_gender=texttospeech.SsmlVoiceGender.NEUTRAL
)
audio_config = texttospeech.AudioConfig(
    audio_encoding=texttospeech.AudioEncoding.MP3
)

response = tts_client.synthesize_speech(
    input=text_input,
    voice=voice,
    audio_config=audio_config
)

# Upload to Cloud Storage
bucket_name = os.environ.get('BUCKET_NAME', 'your-bucket-name')
bucket = storage_client.bucket(bucket_name)
blob = bucket.blob('test-audio.mp3')
blob.upload_from_string(response.audio_content, content_type='audio/mpeg')

print(f"✅ Audio successfully generated and stored in gs://{bucket_name}/test-audio.mp3")
EOF
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/$DEPLOYMENT_NAME

# Verify deletion
gcloud infra-manager deployments list --location=$REGION
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify resources are removed
gcloud storage buckets list --filter="name:tts-audio"
gcloud services list --enabled --filter="name:texttospeech.googleapis.com OR name:storage.googleapis.com"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**
   ```
   Error: googleapi: Error 403: Cloud Text-to-Speech API has not been used
   ```
   **Solution**: Ensure APIs are enabled before resource creation:
   ```bash
   gcloud services enable texttospeech.googleapis.com storage.googleapis.com
   ```

2. **Insufficient Permissions**
   ```
   Error: Permission denied when creating bucket
   ```
   **Solution**: Verify your account has the required IAM roles:
   ```bash
   gcloud projects add-iam-policy-binding $PROJECT_ID \
       --member="user:your-email@domain.com" \
       --role="roles/storage.admin"
   ```

3. **Bucket Name Already Exists**
   ```
   Error: Bucket name already exists globally
   ```
   **Solution**: Use a more unique bucket name by adding a timestamp or random suffix:
   ```bash
   export BUCKET_NAME="tts-audio-$(date +%s)-$(openssl rand -hex 3)"
   ```

4. **Authentication Issues**
   ```
   Error: Application Default Credentials not found
   ```
   **Solution**: Set up authentication:
   ```bash
   gcloud auth application-default login
   ```

### Validation Commands

Verify your deployment with these commands:

```bash
# Check bucket creation and configuration
gcloud storage buckets describe gs://$BUCKET_NAME

# Verify API enablement
gcloud services list --enabled --filter="name:texttospeech.googleapis.com"

# Test API access
gcloud beta services api-keys list

# Check IAM permissions
gcloud projects get-iam-policy $PROJECT_ID
```

## Cost Considerations

- **Cloud Text-to-Speech API**: 
  - Standard voices: $4.00 per million characters
  - WaveNet voices: $16.00 per million characters
  - Chirp 3: HD voices: $30.00 per million characters
- **Cloud Storage**: 
  - Storage: $0.020 per GB per month (Standard class)
  - Operations: $0.05 per 10,000 Class A operations
- **Data Transfer**: 
  - Egress charges apply for downloads outside Google Cloud

## Security Best Practices

1. **Least Privilege Access**: Service accounts have minimal required permissions
2. **Bucket Security**: Public access is configurable and disabled by default
3. **API Key Management**: Use service accounts instead of API keys when possible
4. **Audit Logging**: Enable Cloud Audit Logs for API usage monitoring

## Customization

### Adding Custom Voices

Modify the Terraform `variables.tf` to include custom voice configurations:

```hcl
variable "default_voices" {
  description = "Default voice configurations for text-to-speech"
  type = map(object({
    language_code = string
    name         = string
    ssml_gender  = string
  }))
  default = {
    english_female = {
      language_code = "en-US"
      name         = "en-US-Wavenet-F"
      ssml_gender  = "FEMALE"
    }
    english_male = {
      language_code = "en-US"
      name         = "en-US-Wavenet-D"
      ssml_gender  = "MALE"
    }
  }
}
```

### Multi-Region Deployment

For global applications, deploy buckets in multiple regions:

```hcl
variable "regions" {
  description = "List of regions for multi-region deployment"
  type        = list(string)
  default     = ["us-central1", "europe-west1", "asia-southeast1"]
}
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: 
   - [Text-to-Speech API Documentation](https://cloud.google.com/text-to-speech/docs)
   - [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: Google Cloud Community forums and Stack Overflow

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify according to your organization's requirements and policies.