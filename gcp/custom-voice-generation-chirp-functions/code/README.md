# Infrastructure as Code for Custom Voice Generation with Chirp 3 and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Custom Voice Generation with Chirp 3 and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Text-to-Speech API usage
  - Cloud Functions deployment
  - Cloud Storage bucket management
  - Cloud SQL instance creation
  - IAM service account management
- Node.js 18+ for local function development (if modifying functions)

## Quick Start

### Using Infrastructure Manager

```bash
# Enable required APIs
gcloud services enable config.googleapis.com

# Deploy infrastructure
gcloud infra-manager deployments apply deployment-voice-gen \
    --location=us-central1 \
    --service-account="PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/PROJECT_ID/r/REPO_NAME" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Get deployment outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud functions list
gsutil ls
gcloud sql instances list
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Storage Bucket**: Stores audio samples and generated voice files
- **Cloud SQL Database**: PostgreSQL instance for voice profile metadata
- **Cloud Functions**: 
  - Profile Manager: RESTful API for voice profile management
  - Voice Synthesis: Chirp 3 HD voice generation endpoint
- **IAM Service Account**: Secure service-to-service authentication
- **API Enablement**: Text-to-Speech, Cloud Functions, Storage, and SQL APIs

## Configuration Variables

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id: "your-project-id"
  region: "us-central1"
  zone: "us-central1-a"
  bucket_name: "voice-audio-unique-suffix"
  db_instance_name: "voice-profiles-instance"
  function_memory: "512MB"
  function_timeout: "120s"
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or pass via command line:

```bash
terraform apply \
  -var="project_id=your-project-id" \
  -var="region=us-central1" \
  -var="bucket_name=voice-audio-$(date +%s)"
```

Common variables:
- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `zone`: Compute zone (default: us-central1-a)
- `bucket_name`: Cloud Storage bucket name (must be globally unique)
- `db_instance_name`: Cloud SQL instance name
- `function_memory`: Memory allocation for Cloud Functions
- `function_timeout`: Timeout for Cloud Functions

## Deployment Outputs

After successful deployment, you'll receive:

- **Profile Manager URL**: HTTP endpoint for voice profile management
- **Voice Synthesis URL**: HTTP endpoint for text-to-speech generation
- **Storage Bucket Name**: Bucket containing audio files
- **Database Instance**: Cloud SQL instance for metadata
- **Service Account Email**: IAM service account for authentication

## Testing the Deployment

### Create a Voice Profile

```bash
# Get the profile manager URL from outputs
PROFILE_URL=$(terraform output -raw profile_manager_url)

# Create a sample voice profile
curl -X POST ${PROFILE_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "profileName": "customer-service-assistant",
      "voiceStyle": "en-US-Chirp3-HD-Achernar",
      "languageCode": "en-US",
      "synthesisConfig": {
        "speakingRate": 1.0,
        "pitch": 0.0,
        "volumeGainDb": 2.0
      }
    }'
```

### Generate Voice Synthesis

```bash
# Get the synthesis URL from outputs
SYNTHESIS_URL=$(terraform output -raw voice_synthesis_url)

# Synthesize speech using Chirp 3 HD
curl -X POST ${SYNTHESIS_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "text": "Welcome to our customer service. How may I assist you today?",
      "profileId": "1",
      "voiceStyle": "en-US-Chirp3-HD-Achernar"
    }' | python3 -m json.tool
```

### Verify Storage and Database

```bash
# List generated audio files
BUCKET_NAME=$(terraform output -raw bucket_name)
gsutil ls gs://${BUCKET_NAME}/generated/

# Check database connectivity
DB_INSTANCE=$(terraform output -raw db_instance_name)
gcloud sql connect ${DB_INSTANCE} --user=postgres
```

## Chirp 3 Voice Styles

Available Chirp 3 HD voice styles for testing:

- `en-US-Chirp3-HD-Achernar`: Professional, clear
- `en-US-Chirp3-HD-Charon`: Warm, conversational
- `en-US-Chirp3-HD-Vega`: Energetic, friendly
- `en-US-Chirp3-HD-Sirius`: Authoritative, confident

## Monitoring and Troubleshooting

### Check Function Logs

```bash
# View profile manager logs
gcloud functions logs read profile-manager --limit=50

# View synthesis function logs
gcloud functions logs read voice-synthesis --limit=50
```

### Monitor API Usage

```bash
# Check Text-to-Speech API usage
gcloud logging read 'resource.type="consumed_api" resource.labels.service="texttospeech.googleapis.com"' --limit=10

# Monitor Cloud Storage access
gcloud logging read 'resource.type="gcs_bucket"' --limit=10
```

### Debug Database Connection

```bash
# Check Cloud SQL instance status
gcloud sql instances describe ${DB_INSTANCE}

# Test database connectivity from Cloud Shell
gcloud sql connect ${DB_INSTANCE} --user=postgres --database=voice_profiles
```

## Security Considerations

This infrastructure implements several security best practices:

- **IAM Service Accounts**: Functions use dedicated service accounts with minimal required permissions
- **Database Security**: Cloud SQL with encrypted connections and strong password authentication
- **Storage Security**: Cloud Storage with appropriate access controls and signed URLs
- **API Security**: Text-to-Speech API with project-level access controls
- **Network Security**: Private IP for Cloud SQL and VPC-native networking where applicable

## Cost Optimization

To optimize costs:

- **Function Scaling**: Functions automatically scale to zero when not in use
- **Storage Classes**: Use Standard storage for active files, consider Nearline for archives
- **Database Sizing**: Start with db-f1-micro and scale based on usage
- **Monitoring**: Use Cloud Monitoring to track usage and optimize resource allocation

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete deployment-voice-gen \
    --location=us-central1 \
    --quiet
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list
gsutil ls
gcloud sql instances list
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
echo "Checking remaining resources..."

# Check functions
echo "Cloud Functions:"
gcloud functions list --filter="name~voice"

# Check storage buckets
echo "Storage Buckets:"
gsutil ls | grep voice

# Check SQL instances
echo "SQL Instances:"
gcloud sql instances list | grep voice

# Check service accounts
echo "Service Accounts:"
gcloud iam service-accounts list --filter="email~voice"
```

## Customization

### Adding New Voice Styles

Modify the synthesis function to support additional Chirp 3 voice styles:

```javascript
// In synthesis function
const voiceStyles = {
  'professional': 'en-US-Chirp3-HD-Achernar',
  'conversational': 'en-US-Chirp3-HD-Charon',
  'energetic': 'en-US-Chirp3-HD-Vega',
  'authoritative': 'en-US-Chirp3-HD-Sirius'
};
```

### Multi-language Support

Add language-specific configurations:

```javascript
const languageConfig = {
  'en-US': {
    voices: ['en-US-Chirp3-HD-Achernar', 'en-US-Chirp3-HD-Charon'],
    defaultVoice: 'en-US-Chirp3-HD-Achernar'
  },
  'es-US': {
    voices: ['es-US-Chirp3-HD-Alpha', 'es-US-Chirp3-HD-Beta'],
    defaultVoice: 'es-US-Chirp3-HD-Alpha'
  }
};
```

### Advanced Audio Configuration

Enhance synthesis requests with advanced audio parameters:

```javascript
const advancedAudioConfig = {
  audioEncoding: 'MP3',
  speakingRate: request.speakingRate || 1.0,
  pitch: request.pitch || 0.0,
  volumeGainDb: request.volumeGainDb || 0.0,
  effectsProfileId: ['telephony-class-application'],
  sampleRateHertz: 24000
};
```

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Verify APIs are enabled
   gcloud services list --enabled
   ```

2. **Database Connection Errors**
   ```bash
   # Check Cloud SQL instance status
   gcloud sql instances describe ${DB_INSTANCE}
   
   # Test connectivity
   gcloud sql connect ${DB_INSTANCE} --user=postgres
   ```

3. **Text-to-Speech API Errors**
   ```bash
   # Check API quota and usage
   gcloud services list --filter="name:texttospeech.googleapis.com"
   
   # Test API directly
   curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d '{"input":{"text":"test"},"voice":{"languageCode":"en-US","name":"en-US-Chirp3-HD-Achernar"},"audioConfig":{"audioEncoding":"MP3"}}' \
        https://texttospeech.googleapis.com/v1/text:synthesize
   ```

4. **Storage Access Issues**
   ```bash
   # Check bucket permissions
   gsutil iam get gs://${BUCKET_NAME}
   
   # Test bucket access
   echo "test" | gsutil cp - gs://${BUCKET_NAME}/test.txt
   ```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../custom-voice-generation-chirp-functions.md)
2. Review [Google Cloud Text-to-Speech documentation](https://cloud.google.com/text-to-speech/docs)
3. Consult [Cloud Functions documentation](https://cloud.google.com/functions/docs)
4. Review [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
5. Check [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Version Information

- **Recipe Version**: 1.1
- **Infrastructure Manager**: Requires Google Cloud CLI 456.0.0+
- **Terraform**: Requires Terraform 1.0+ and Google Provider 5.0+
- **Node.js Runtime**: Cloud Functions use Node.js 18
- **Database**: PostgreSQL 15 on Cloud SQL