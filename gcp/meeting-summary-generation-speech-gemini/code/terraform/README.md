# Terraform Infrastructure for Meeting Summary Generation

This directory contains Terraform Infrastructure as Code (IaC) for deploying an automated meeting summary generation system using Google Cloud Platform services.

## Architecture Overview

The infrastructure deploys:
- **Cloud Storage Bucket**: Stores meeting recordings, transcripts, and summaries
- **Cloud Functions (Gen2)**: Processes audio files using event-driven triggers
- **Speech-to-Text API**: Converts audio to text with speaker diarization
- **Vertex AI Gemini**: Generates intelligent meeting summaries
- **IAM Service Account**: Manages secure access between services
- **Cloud Monitoring**: Tracks function performance and errors

## Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (gcloud CLI)
- A Google Cloud Project with billing enabled

### Required Permissions
Your Google Cloud account needs the following IAM roles:
- `roles/owner` OR the combination of:
  - `roles/editor`
  - `roles/iam.serviceAccountAdmin`
  - `roles/cloudfunctions.admin`
  - `roles/storage.admin`
  - `roles/serviceusage.serviceUsageAdmin`

### Authentication Setup
```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project (replace with your project ID)
export GOOGLE_CLOUD_PROJECT="your-project-id"
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

## Quick Start

### 1. Initialize Terraform
```bash
cd terraform/
terraform init
```

### 2. Create terraform.tfvars
```bash
cat > terraform.tfvars << EOF
project_id = "your-gcp-project-id"
region     = "us-central1"
environment = "dev"

# Optional customizations
function_memory       = 1024
function_timeout     = 540
speech_language_code = "en-US"
gemini_model        = "gemini-1.5-pro"
EOF
```

### 3. Review the Plan
```bash
terraform plan
```

### 4. Deploy Infrastructure
```bash
terraform apply
```

### 5. Test the System
```bash
# Upload a test audio file (replace with your file)
gsutil cp your-meeting.wav gs://$(terraform output -raw bucket_name)/

# Monitor processing
gcloud functions logs read $(terraform output -raw function_name) --region $(terraform output -raw region)

# Check for outputs
gsutil ls gs://$(terraform output -raw bucket_name)/transcripts/
gsutil ls gs://$(terraform output -raw bucket_name)/summaries/
```

## Configuration Options

### Required Variables
- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region (default: us-central1)

### Optional Variables
```hcl
# Function Configuration
function_memory         = 1024        # MB, range: 128-8192
function_timeout       = 540         # seconds, max: 3600
function_max_instances = 10          # max concurrent instances

# AI Configuration
speech_language_code   = "en-US"     # language for transcription
speaker_count_min     = 2           # minimum speakers for diarization
speaker_count_max     = 6           # maximum speakers for diarization
gemini_model          = "gemini-1.5-pro"  # AI model for summaries
vertex_ai_location    = "us-central1"     # Vertex AI region

# Storage Configuration
bucket_storage_class  = "STANDARD"   # STANDARD, NEARLINE, COLDLINE, ARCHIVE
lifecycle_age_days    = 30          # auto-delete after N days
enable_versioning     = false       # bucket versioning

# Environment
environment = "dev"                 # environment label
```

### Supported Regions
Cloud Functions Gen2 is available in:
- **US**: us-central1, us-east1, us-east4, us-west1, us-west2, us-west3, us-west4
- **Europe**: europe-central2, europe-north1, europe-west1, europe-west2, europe-west3, europe-west4, europe-west6
- **Asia**: asia-east1, asia-east2, asia-northeast1, asia-northeast2, asia-southeast1, asia-southeast2
- **Australia**: australia-southeast1

## Usage Instructions

### Uploading Meeting Recordings

#### Supported Audio Formats
- WAV (recommended for best quality)
- MP3 (widely supported)
- FLAC (lossless compression)
- M4A (Apple format)

#### Upload Methods

**Using gcloud CLI:**
```bash
gsutil cp meeting-recording.wav gs://$(terraform output -raw bucket_name)/
```

**Using Google Cloud Console:**
1. Navigate to [Cloud Storage](https://console.cloud.google.com/storage)
2. Find your bucket (name from `terraform output bucket_name`)
3. Upload files directly via the web interface

**Using code (Python example):**
```python
from google.cloud import storage

client = storage.Client()
bucket = client.bucket('your-bucket-name')
blob = bucket.blob('meeting-recording.wav')
blob.upload_from_filename('local-file.wav')
```

### Monitoring Processing

#### Function Logs
```bash
# View recent logs
gcloud functions logs read $(terraform output -raw function_name) --region $(terraform output -raw region) --limit 20

# Follow logs in real-time
gcloud functions logs read $(terraform output -raw function_name) --region $(terraform output -raw region) --follow
```

#### Function Status
```bash
gcloud functions describe $(terraform output -raw function_name) --region $(terraform output -raw region)
```

#### Storage Contents
```bash
# List all bucket contents
gsutil ls -la gs://$(terraform output -raw bucket_name)/

# Check specific folders
gsutil ls gs://$(terraform output -raw bucket_name)/transcripts/
gsutil ls gs://$(terraform output -raw bucket_name)/summaries/
```

### Retrieving Results

#### Download Transcripts
```bash
gsutil cp gs://$(terraform output -raw bucket_name)/transcripts/* ./transcripts/
```

#### Download Summaries
```bash
gsutil cp gs://$(terraform output -raw bucket_name)/summaries/* ./summaries/
```

#### View Summary in Terminal
```bash
gsutil cat gs://$(terraform output -raw bucket_name)/summaries/your-meeting_summary.md
```

## Cost Management

### Estimated Costs (USD, approximate)
- **Cloud Storage**: $0.020/GB/month (Standard class)
- **Cloud Functions**: $0.40/million requests + $0.0000025/GB-second
- **Speech-to-Text**: $0.006/15 seconds of audio
- **Vertex AI Gemini**: ~$0.00025/1K input tokens, ~$0.0005/1K output tokens

### Cost Optimization Tips
1. **Lifecycle Policies**: Automatically delete old files (configured: 30 days)
2. **Function Memory**: Use appropriate memory settings (current: 1GB)
3. **Storage Class**: Consider NEARLINE/COLDLINE for archival
4. **Batch Processing**: Process multiple files together when possible
5. **Monitoring**: Set up billing alerts for unexpected usage

### Billing Monitoring
```bash
# View current project billing
gcloud billing accounts list
gcloud billing projects describe $GOOGLE_CLOUD_PROJECT

# Set up budget alerts (optional)
gcloud billing budgets create --billing-account=BILLING_ACCOUNT_ID --amount=100 --currency=USD
```

## Security

### IAM Principles
- **Least Privilege**: Service account has minimal required permissions
- **Resource-Level Access**: Permissions scoped to specific resources
- **No User Credentials**: Functions use service account authentication

### Security Features
- **Uniform Bucket-Level Access**: Consistent IAM across bucket
- **Encryption**: All data encrypted at rest and in transit
- **Audit Logging**: All API calls logged for security monitoring
- **VPC Compatibility**: Can be deployed in VPC if needed

### Security Recommendations
1. Enable Cloud Security Command Center
2. Set up VPC Service Controls for additional isolation
3. Implement Customer-Managed Encryption Keys (CMEK) if required
4. Regular IAM access reviews
5. Enable Cloud Asset Inventory for security monitoring

## Troubleshooting

### Common Issues

#### Function Not Triggering
```bash
# Check function status
gcloud functions describe $(terraform output -raw function_name) --region $(terraform output -raw region)

# Verify trigger configuration
gcloud functions describe $(terraform output -raw function_name) --region $(terraform output -raw region) --format="yaml(eventTrigger)"

# Check IAM permissions
gcloud projects get-iam-policy $GOOGLE_CLOUD_PROJECT
```

#### API Errors
```bash
# Verify APIs are enabled
gcloud services list --enabled --project=$GOOGLE_CLOUD_PROJECT

# Enable missing APIs
gcloud services enable speech.googleapis.com
gcloud services enable aiplatform.googleapis.com
```

#### Storage Access Issues
```bash
# Check bucket permissions
gsutil iam get gs://$(terraform output -raw bucket_name)

# Test upload permissions
echo "test" | gsutil cp - gs://$(terraform output -raw bucket_name)/test.txt
```

#### Function Timeout/Memory Issues
```bash
# Check function metrics
gcloud functions describe $(terraform output -raw function_name) --region $(terraform output -raw region) --format="yaml(serviceConfig)"

# Increase timeout/memory in terraform.tfvars
function_memory = 2048
function_timeout = 900
```

### Getting Help

#### Useful Commands
```bash
# Get all terraform outputs
terraform output

# Debug function locally (requires Functions Framework)
functions-framework --target=process_meeting --debug

# Test Speech-to-Text API directly
gcloud ml speech recognize gs://bucket/audio.wav --language-code=en-US

# Test Vertex AI Gemini
gcloud ai endpoints predict ENDPOINT_ID --region=us-central1 --json-request=request.json
```

#### Log Analysis
```bash
# Search for errors in logs
gcloud functions logs read $(terraform output -raw function_name) --region $(terraform output -raw region) --filter="severity>=ERROR"

# Search for specific terms
gcloud functions logs read $(terraform output -raw function_name) --region $(terraform output -raw region) --filter="textPayload:transcription"
```

## Development and Customization

### Modifying the Function
1. Edit `function-source/main.py`
2. Update `function-source/requirements.txt` if adding dependencies
3. Run `terraform apply` to redeploy

### Adding New Features
- **Multi-language support**: Modify `speech_language_code` variable
- **Custom prompts**: Edit the Gemini prompt in `main.py`
- **Additional outputs**: Modify the `save_results` function
- **Integration with other services**: Add new IAM roles and API calls

### Testing Locally
```bash
# Install Functions Framework
pip install functions-framework

# Run function locally
cd function-source/
functions-framework --target=process_meeting --debug
```

## Cleanup

### Remove All Resources
```bash
terraform destroy
```

### Partial Cleanup
```bash
# Delete only bucket contents (keep infrastructure)
gsutil -m rm -r gs://$(terraform output -raw bucket_name)/*

# Delete specific function
gcloud functions delete $(terraform output -raw function_name) --region $(terraform output -raw region)
```

### Emergency Cleanup
```bash
# Force delete bucket (removes all contents)
gsutil -m rm -r gs://$(terraform output -raw bucket_name)

# Disable APIs (if no longer needed)
gcloud services disable speech.googleapis.com
gcloud services disable aiplatform.googleapis.com
```

## Support and Resources

### Documentation Links
- [Google Cloud Speech-to-Text](https://cloud.google.com/speech-to-text/docs)
- [Vertex AI Gemini](https://cloud.google.com/vertex-ai/docs/generative-ai/start/overview)
- [Cloud Functions](https://cloud.google.com/functions/docs)
- [Cloud Storage](https://cloud.google.com/storage/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Community Support
- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - google-cloud-platform](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Terraform Community](https://discuss.hashicorp.com/c/terraform-core)

### Professional Support
- [Google Cloud Support](https://cloud.google.com/support)
- [HashiCorp Terraform Support](https://www.hashicorp.com/support)

---

For issues with this infrastructure code, refer to the original recipe documentation or consult the troubleshooting section above.