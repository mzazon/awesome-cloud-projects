# Infrastructure as Code for Educational Content Generation with Gemini and Text-to-Speech

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Educational Content Generation with Gemini and Text-to-Speech".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts for manual resource management

## Prerequisites

### General Requirements
- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Admin
  - Vertex AI User
  - Text-to-Speech Admin
  - Firestore User
  - Storage Admin
  - Service Account Admin
- Estimated cost: $5-15 for testing (based on content generation volume and audio synthesis)

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI version 450.0.0 or later
- Infrastructure Manager API enabled in your project

#### Terraform
- Terraform >= 1.0
- Google Cloud Provider for Terraform
- Service account key file (for authentication) or Application Default Credentials

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/edu-content-gen \
    --service-account projects/YOUR_PROJECT_ID/serviceAccounts/infra-manager@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/edu-content-gen
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployment
./scripts/test-deployment.sh
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `content-generator-${random}` | No |
| `bucket_name` | Storage bucket name | `edu-audio-content-${random}` | No |
| `function_memory` | Function memory allocation | `1024` | No |
| `function_timeout` | Function timeout in seconds | `540` | No |

### Environment-Specific Configuration

#### Development
```bash
# Minimal resources for testing
terraform apply -var="function_memory=512" -var="function_timeout=300"
```

#### Production
```bash
# Enhanced resources for production workloads
terraform apply -var="function_memory=2048" -var="function_timeout=540"
```

## Testing the Deployment

### Verify Services

```bash
# Check Cloud Function deployment
gcloud functions describe content-generator-${RANDOM_SUFFIX} --region=${REGION}

# Verify Firestore database
gcloud firestore databases describe --format="value(name)"

# Check storage bucket
gsutil ls gs://edu-audio-content-${RANDOM_SUFFIX}
```

### Test Content Generation

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe content-generator-${RANDOM_SUFFIX} \
    --region=${REGION} --format="value(httpsTrigger.url)")

# Test content generation
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "topic": "Introduction to Machine Learning",
        "outline": "1. What is ML? 2. Types of learning 3. Common algorithms 4. Real-world applications",
        "voice_name": "en-US-Studio-M"
    }' | jq '.'
```

## Monitoring and Logging

### View Function Logs
```bash
gcloud functions logs read content-generator-${RANDOM_SUFFIX} --region=${REGION}
```

### Monitor Function Metrics
```bash
# View function invocations
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=content-generator-${RANDOM_SUFFIX}" --limit=10
```

### Cost Monitoring
```bash
# View current billing for AI services
gcloud billing budgets list --billing-account=YOUR_BILLING_ACCOUNT
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com aiplatform.googleapis.com texttospeech.googleapis.com
   ```

2. **Permission Denied**
   ```bash
   # Add necessary IAM roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/cloudfunctions.admin"
   ```

3. **Function Timeout**
   ```bash
   # Increase function timeout
   gcloud functions deploy content-generator-${RANDOM_SUFFIX} \
       --timeout=540s --memory=2048MB
   ```

### Debugging

#### Enable Debug Logging
```bash
export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
export FUNCTIONS_EMULATOR=true
functions-framework --target=generate_content --debug
```

#### Check Resource Quotas
```bash
gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/edu-content-gen
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)
```bash
# Delete Cloud Function
gcloud functions delete content-generator-${RANDOM_SUFFIX} --region=${REGION} --quiet

# Delete storage bucket
gsutil -m rm -r gs://edu-audio-content-${RANDOM_SUFFIX}

# Note: Firestore requires manual deletion via console
echo "⚠️  Manually delete Firestore documents via Google Cloud Console"
```

## Customization

### Extending the Solution

1. **Multi-language Support**
   - Modify `main.py` to include translation capabilities
   - Add language parameter to function variables
   - Configure Text-to-Speech for multiple language voices

2. **Content Templates**
   - Create custom prompt templates in Firestore
   - Add template selection to function input
   - Implement dynamic prompt generation

3. **Quality Controls**
   - Add content validation using Vertex AI
   - Implement approval workflows with Cloud Tasks
   - Add content versioning in Firestore

### Advanced Configuration

#### Custom Gemini Model Configuration
```python
# In main.py, modify model initialization
model = GenerativeModel(
    'gemini-2.5-flash',
    generation_config={
        'temperature': 0.7,
        'top_p': 0.8,
        'top_k': 40,
        'max_output_tokens': 2048
    }
)
```

#### Enhanced Audio Configuration
```python
# Customize Text-to-Speech settings
audio_config = texttospeech.AudioConfig(
    audio_encoding=texttospeech.AudioEncoding.MP3,
    speaking_rate=0.9,
    pitch=0.0,
    volume_gain_db=0.0,
    sample_rate_hertz=24000
)
```

## Performance Optimization

### Function Optimization
```bash
# Deploy with optimized settings for high-volume usage
gcloud functions deploy content-generator-${RANDOM_SUFFIX} \
    --memory=2048MB \
    --timeout=540s \
    --max-instances=50 \
    --min-instances=1
```

### Storage Optimization
```bash
# Configure bucket for optimal performance
gsutil lifecycle set lifecycle.json gs://edu-audio-content-${RANDOM_SUFFIX}
```

## Security Considerations

### IAM Best Practices
- Use least privilege principle for service accounts
- Enable audit logging for all resources
- Configure VPC firewall rules if using private networks
- Regularly rotate service account keys

### Data Protection
- Enable Cloud Storage encryption at rest
- Configure Firestore security rules
- Implement API authentication for production use
- Use Secret Manager for sensitive configuration

## Support and Documentation

- [Original Recipe Documentation](../educational-content-generation-gemini-text-speech.md)
- [Vertex AI Gemini Documentation](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini)
- [Cloud Text-to-Speech Documentation](https://cloud.google.com/text-to-speech/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud Provider documentation.