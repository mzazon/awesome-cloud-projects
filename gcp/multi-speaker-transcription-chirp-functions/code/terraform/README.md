# Terraform Infrastructure for Multi-Speaker Transcription with Chirp and Cloud Functions

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete multi-speaker audio transcription solution using Google Cloud Speech-to-Text with Chirp 3 model and Cloud Functions.

## Architecture Overview

The infrastructure creates:
- **Cloud Storage buckets** for input audio files and output transcripts
- **Cloud Function** for serverless audio processing triggered by file uploads
- **Service Account** with minimal required permissions
- **Optional Pub/Sub topic** for notifications
- **IAM bindings** for secure access control

## Prerequisites

- **Google Cloud Account** with billing enabled
- **Terraform** >= 1.0 installed
- **Google Cloud CLI** (`gcloud`) installed and authenticated
- **Project Owner or Editor** permissions in your GCP project
- **APIs that will be enabled** (if `enable_apis = true`):
  - Speech-to-Text API
  - Cloud Functions API
  - Cloud Storage API
  - Cloud Build API
  - Eventarc API
  - Cloud Run API
  - Pub/Sub API

## Quick Start

### 1. Initialize Terraform

```bash
# Clone and navigate to the terraform directory
cd gcp/multi-speaker-transcription-chirp-functions/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment             = "dev"
resource_name_prefix    = "speech-transcription"
function_name          = "process-audio-transcription"
function_memory        = 2048
function_timeout       = 540
function_max_instances = 5

# Speech configuration
speech_model = "chirp_3"
speaker_diarization_config = {
  enable_speaker_diarization = true
  min_speaker_count         = 2
  max_speaker_count         = 6
}
language_codes = ["en-US"]

# Storage configuration
bucket_storage_class     = "STANDARD"
bucket_lifecycle_age_days = 30
enable_bucket_versioning = false
enable_bucket_encryption = true

# Optional notification topic
notification_topic_name = "" # Leave empty to disable

# Labels
labels = {
  component   = "speech-transcription"
  terraform   = "true"
  environment = "dev"
}
```

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### 4. Test the Deployment

```bash
# Upload a test audio file (use the output from terraform apply)
gsutil cp your-audio-file.wav gs://[INPUT_BUCKET_NAME]/

# Wait 30-60 seconds for processing, then check results
gsutil ls gs://[OUTPUT_BUCKET_NAME]/transcripts/

# View function logs
gcloud functions logs read [FUNCTION_NAME] --region=[REGION] --limit=10
```

## Input Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `project_id` | string | GCP project ID where resources will be created |

### Configuration Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `region` | string | "us-central1" | GCP region for resource deployment |
| `environment` | string | "dev" | Environment name (dev/staging/prod) |
| `resource_name_prefix` | string | "speech-transcription" | Prefix for resource names |
| `function_name` | string | "process-audio-transcription" | Cloud Function name |
| `function_memory` | number | 2048 | Function memory allocation (MB) |
| `function_timeout` | number | 540 | Function timeout (seconds) |
| `function_max_instances` | number | 5 | Maximum function instances |

### Speech Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `speech_model` | string | "chirp_3" | Speech-to-Text model |
| `speaker_diarization_config` | object | See below | Speaker diarization settings |
| `language_codes` | list(string) | ["en-US"] | Supported language codes |

Default `speaker_diarization_config`:
```hcl
{
  enable_speaker_diarization = true
  min_speaker_count         = 2
  max_speaker_count         = 6
}
```

### Storage Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `bucket_storage_class` | string | "STANDARD" | Storage class for buckets |
| `bucket_lifecycle_age_days` | number | 30 | Days before object deletion (0 = disabled) |
| `enable_bucket_versioning` | bool | false | Enable bucket versioning |
| `enable_bucket_encryption` | bool | true | Enable default encryption |

## Outputs

After successful deployment, Terraform provides these outputs:

| Output | Description |
|--------|-------------|
| `input_bucket_name` | Name of the input audio bucket |
| `output_bucket_name` | Name of the output transcripts bucket |
| `function_name` | Name of the deployed Cloud Function |
| `upload_instructions` | Command to upload audio files |
| `download_instructions` | Command to download transcripts |
| `function_logs_command` | Command to view function logs |
| `test_upload_command` | Example test command |

## Usage Instructions

### Uploading Audio Files

```bash
# Upload audio files to trigger transcription
gsutil cp your-meeting-recording.wav gs://[INPUT_BUCKET_NAME]/
gsutil cp *.mp3 gs://[INPUT_BUCKET_NAME]/
```

**Supported formats**: WAV, MP3, FLAC, M4A, OGG, AIFF, AU

### Downloading Results

```bash
# List available transcripts
gsutil ls gs://[OUTPUT_BUCKET_NAME]/transcripts/

# Download all transcripts
gsutil -m cp -r gs://[OUTPUT_BUCKET_NAME]/transcripts/ ./transcripts/

# Download specific transcript
gsutil cp gs://[OUTPUT_BUCKET_NAME]/transcripts/your-file.wav_readable.txt ./
```

### Output Files

For each processed audio file, you'll get:
- `filename_transcript.json` - Complete transcription data with timestamps and speaker information
- `filename_readable.txt` - Human-readable transcript with speaker labels
- `filename_speaker_summary.txt` - Speaker analysis and statistics

### Monitoring and Troubleshooting

```bash
# View function logs
gcloud functions logs read [FUNCTION_NAME] --region=[REGION] --limit=20

# Check function status
gcloud functions describe [FUNCTION_NAME] --region=[REGION]

# Monitor storage events
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name="[FUNCTION_NAME]"' --limit=10

# Check for errors
gcloud functions logs read [FUNCTION_NAME] --region=[REGION] --filter="severity>=ERROR"
```

## Customization Examples

### Multi-Language Support

```hcl
language_codes = ["en-US", "es-ES", "fr-FR"]
```

### Production Configuration

```hcl
environment            = "prod"
function_memory        = 4096
function_max_instances = 20
bucket_storage_class   = "STANDARD"
enable_bucket_versioning = true

speaker_diarization_config = {
  enable_speaker_diarization = true
  min_speaker_count         = 2
  max_speaker_count         = 10
}
```

### Cost-Optimized Configuration

```hcl
function_memory        = 1024
function_max_instances = 3
bucket_storage_class   = "NEARLINE"
bucket_lifecycle_age_days = 7

# Disable diarization for lower costs
speaker_diarization_config = {
  enable_speaker_diarization = false
  min_speaker_count         = 1
  max_speaker_count         = 1
}
```

## Security Considerations

### Service Account Permissions

The created service account has minimal required permissions:
- `roles/speech.editor` - For Speech-to-Text API access
- `roles/storage.objectAdmin` - For reading/writing storage objects
- `roles/logging.logWriter` - For function logging

### Storage Security

- **Uniform bucket-level access** enabled
- **Default encryption** enabled (configurable)
- **Internal-only function access** configured
- **IAM-based access control** for all resources

### Network Security

- Cloud Function configured with `ALLOW_INTERNAL_ONLY` ingress
- No public endpoints exposed
- Event-driven architecture with Storage triggers

## Cost Optimization

### Expected Costs

**Speech-to-Text API** (primary cost driver):
- Chirp 3 model: ~$0.006-0.024 per minute of audio
- Speaker diarization: Additional charges may apply

**Cloud Functions**:
- First 2M invocations free monthly
- $0.40 per million invocations after free tier
- $0.0000025 per GB-second of compute time

**Cloud Storage**:
- Standard storage: $0.020 per GB/month
- Operations: $0.05 per 10,000 operations

### Cost Optimization Tips

1. **Use lifecycle policies** to automatically delete old files
2. **Choose appropriate storage class** based on access patterns
3. **Optimize function memory** allocation for your audio file sizes
4. **Use regional storage** instead of multi-regional when possible
5. **Monitor usage** with Cloud Billing alerts

## Troubleshooting

### Common Issues

**Function deployment fails**:
```bash
# Check API enablement
gcloud services list --enabled --filter="name:speech OR name:cloudfunctions"

# Verify permissions
gcloud projects get-iam-policy [PROJECT_ID]
```

**Transcription fails**:
```bash
# Check function logs for errors
gcloud functions logs read [FUNCTION_NAME] --region=[REGION] --filter="severity>=ERROR"

# Verify audio file format
file your-audio-file.wav
```

**No output files generated**:
```bash
# Check if function was triggered
gcloud functions logs read [FUNCTION_NAME] --region=[REGION] --filter="textPayload:Processing file upload"

# Verify bucket permissions
gsutil iam get gs://[OUTPUT_BUCKET_NAME]
```

### Performance Tuning

**For large audio files**:
- Increase `function_memory` to 4096 or 8192 MB
- Increase `function_timeout` to maximum (540 seconds)
- Consider splitting very large files before processing

**For high volume**:
- Increase `function_max_instances`
- Monitor and adjust based on processing queue length
- Consider using Pub/Sub for more complex workflows

## Cleanup

To destroy all created resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm destruction
# Type "yes" when prompted
```

**Note**: This will permanently delete all transcripts and audio files in the created buckets.

## Advanced Configuration

### Custom Domain Integration

For integration with custom domains or API gateways, you can reference the function URI from outputs:

```bash
# Get function URI
terraform output function_uri
```

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy Speech Transcription
on:
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Apply
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
        env:
          GOOGLE_CREDENTIALS: ${{ secrets.GCP_SA_KEY }}
```

## Support and Documentation

- [Google Cloud Speech-to-Text Documentation](https://cloud.google.com/speech-to-text/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Chirp 3 Model Documentation](https://cloud.google.com/speech-to-text/v2/docs/chirp_3-model)

For issues with this Terraform configuration, please refer to the original recipe documentation or create an issue in the repository.