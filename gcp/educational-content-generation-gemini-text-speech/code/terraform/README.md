# Terraform Infrastructure for Educational Content Generation with Gemini and Text-to-Speech

This Terraform configuration deploys a complete AI-powered educational content generation pipeline using Google Cloud services including Vertex AI Gemini, Text-to-Speech API, Cloud Functions, and Firestore.

## Architecture Overview

The infrastructure creates:

- **Vertex AI Gemini 2.5 Flash** for intelligent educational content generation
- **Text-to-Speech API** for converting generated content to high-quality audio
- **Cloud Functions** for serverless orchestration and API endpoints
- **Firestore Native** for storing educational content and metadata
- **Cloud Storage** for audio file storage and distribution
- **IAM Service Account** with least-privilege permissions

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project** with billing enabled
2. **Terraform** installed (version >= 1.5)
3. **Google Cloud SDK** installed and authenticated
4. **Required permissions** in your Google Cloud project:
   - Project Editor or custom role with necessary permissions
   - Ability to enable APIs and create service accounts
   - Billing account access for resource creation

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the terraform directory
cd gcp/educational-content-generation-gemini-text-speech/code/terraform/
```

### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment             = "dev"
function_name_prefix    = "content-generator"
bucket_name_prefix      = "edu-audio-content"
max_function_instances  = 10
```

### 4. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Test the Deployment

After deployment, use the provided curl command from the outputs:

```bash
# Get the function URL from terraform output
terraform output function_url

# Test content generation
curl -X POST "$(terraform output -raw function_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "topic": "Introduction to Climate Science",
    "outline": "1. What is climate vs weather? 2. Greenhouse effect basics 3. Human impact on climate 4. Climate change evidence 5. Mitigation strategies",
    "voice_name": "en-US-Studio-M"
  }'
```

## Configuration Variables

### Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `project_id` | Google Cloud Project ID | string |

### Optional Variables

| Variable | Description | Default | Validation |
|----------|-------------|---------|------------|
| `region` | GCP region for resources | `us-central1` | Valid GCP region |
| `environment` | Environment label | `dev` | dev/staging/prod |
| `function_name_prefix` | Cloud Function name prefix | `content-generator` | Valid GCP name |
| `bucket_name_prefix` | Storage bucket name prefix | `edu-audio-content` | Valid bucket name |
| `max_function_instances` | Max function instances | `10` | 1-1000 |
| `enable_public_access` | Enable public access | `true` | boolean |
| `function_memory` | Function memory allocation | `1Gi` | Valid memory size |
| `gemini_model_name` | Vertex AI model | `gemini-2.5-flash` | Valid model name |
| `default_voice_name` | Default TTS voice | `en-US-Studio-M` | Valid voice name |

### Advanced Configuration

```hcl
# Advanced configuration example
function_timeout_seconds    = 540
storage_lifecycle_age_days = 365
enable_versioning          = true
tts_speaking_rate         = 0.9
tts_pitch                 = 0.0

# Custom labels
resource_labels = {
  team        = "education"
  cost_center = "learning-platform"
  owner       = "education-team"
}
```

## API Usage

### Content Generation Endpoint

**POST** `https://[region]-[project].cloudfunctions.net/[function-name]`

#### Request Format

```json
{
  "topic": "Educational Topic Title",
  "outline": "1. Learning objective 1 2. Learning objective 2 3. Learning objective 3",
  "voice_name": "en-US-Studio-M"
}
```

#### Response Format

```json
{
  "status": "success",
  "document_id": "firestore-document-id",
  "content_preview": "First 200 characters of generated content...",
  "audio_url": "gs://bucket-name/lessons/document-id.mp3"
}
```

#### Available Voice Options

- **English (US)**: `en-US-Studio-M`, `en-US-Studio-F`, `en-US-Wavenet-A-F`
- **English (UK)**: `en-GB-Studio-A-F`, `en-GB-Wavenet-A-F`
- **Other Languages**: 380+ voices across 50+ languages available

## Monitoring and Logging

### View Function Logs

```bash
# View Cloud Function logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region)
```

### Monitor Resource Usage

```bash
# View function metrics
gcloud monitoring metrics list --filter="resource.type=cloud_function"

# View storage usage
gcloud monitoring metrics list --filter="resource.type=gcs_bucket"
```

### Firestore Data

```bash
# Query generated content
gcloud firestore query --collection-group=educational_content \
  --filter="status==completed" --limit=5
```

## Cost Optimization

### Resource Scaling

- **Cloud Functions**: Automatically scales to zero when not in use
- **Firestore**: Pay per operation and storage used
- **Text-to-Speech**: Pay per character synthesized
- **Vertex AI**: Pay per token processed
- **Cloud Storage**: Lifecycle policies move old files to cheaper storage

### Cost Monitoring

```bash
# View cost breakdown
gcloud billing budgets list

# Set up budget alerts (recommended)
gcloud billing budgets create \
  --billing-account=[BILLING_ACCOUNT] \
  --display-name="Educational Content Generation Budget" \
  --budget-amount=100USD
```

## Security Configuration

### Service Account Permissions

The deployment creates a service account with minimal required permissions:

- **Vertex AI User**: For Gemini model access
- **Text-to-Speech Developer**: For audio generation
- **Firestore User**: For content storage
- **Storage Object Admin**: For audio file management

### Public Access Configuration

- **Cloud Function**: Public HTTP access for educational content requests
- **Storage Bucket**: Public read access for audio file distribution
- **Firestore**: Private access through service account only

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your account has necessary IAM roles
3. **Quota Limits**: Check Vertex AI and Text-to-Speech quotas
4. **Region Availability**: Ensure selected region supports all services

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# Verify service account permissions
gcloud projects get-iam-policy $(terraform output -raw project_id)

# Test function directly
gcloud functions call $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --data='{"topic":"Test","outline":"Test outline"}'
```

## Cleanup

### Destroy Infrastructure

```bash
# Remove all created resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Manual Cleanup (if needed)

```bash
# Remove Firestore data (if not automatically cleaned)
gcloud firestore databases delete --database="(default)"

# Verify all resources are removed
gcloud functions list
gcloud storage buckets list
```

## Integration Examples

### Learning Management System

```python
import requests
import json

def generate_lesson_content(topic, outline):
    function_url = "https://[region]-[project].cloudfunctions.net/[function-name]"
    
    payload = {
        "topic": topic,
        "outline": outline,
        "voice_name": "en-US-Studio-F"
    }
    
    response = requests.post(function_url, json=payload)
    return response.json()

# Usage
result = generate_lesson_content(
    "Introduction to Physics",
    "1. Newton's Laws 2. Force and Motion 3. Energy Conservation"
)

print(f"Content generated: {result['document_id']}")
print(f"Audio available at: {result['audio_url']}")
```

### Batch Content Generation

```bash
#!/bin/bash
# Batch generate content from curriculum file

FUNCTION_URL=$(terraform output -raw function_url)

while IFS=',' read -r topic outline voice; do
  curl -X POST "$FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d "{\"topic\":\"$topic\",\"outline\":\"$outline\",\"voice_name\":\"$voice\"}"
  
  echo "Generated content for: $topic"
  sleep 2  # Rate limiting
done < curriculum.csv
```

## Support and Documentation

- [Vertex AI Gemini Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/models/gemini)
- [Text-to-Speech API Documentation](https://cloud.google.com/text-to-speech/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## License

This infrastructure code is provided as part of the educational content generation recipe and follows the same licensing terms as the parent project.