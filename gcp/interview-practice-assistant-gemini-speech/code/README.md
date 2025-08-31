# Infrastructure as Code for Interview Practice Assistant using Gemini and Speech-to-Text

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Interview Practice Assistant using Gemini and Speech-to-Text".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions
  - Cloud Storage
  - Vertex AI
  - Speech-to-Text API
  - IAM Service Accounts
- For Terraform: Terraform CLI installed (version 1.0+)
- For Infrastructure Manager: `gcloud infra-manager` commands available

## Quick Start

### Using Infrastructure Manager (GCP Native)

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create interview-assistant \
    --location=${REGION} \
    --source=. \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe interview-assistant \
    --location=${REGION}
```

### Using Terraform

Terraform provides cross-cloud compatibility and advanced state management.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Deploy infrastructure
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

For simple deployment without additional tools, use the provided bash scripts.

```bash
# Navigate to scripts directory
cd scripts/

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# View deployment status
gcloud functions list --filter="name:interview-assistant"
```

## Architecture Overview

This infrastructure deploys:

1. **Cloud Storage Bucket**: Stores audio files and interview questions
2. **Cloud Functions**: Three serverless functions for processing
   - Speech-to-Text function for audio transcription
   - Gemini analysis function for interview feedback
   - Orchestration function for workflow coordination
3. **IAM Service Account**: Secure service-to-service communication
4. **API Enablement**: Required Google Cloud APIs

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `bucket_retention_days` | Storage bucket lifecycle (days) | `30` | No |
| `function_memory` | Cloud Function memory allocation | `512MB` | No |
| `service_account_name` | Custom service account name | `interview-assistant` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `bucket_name_suffix` | Unique suffix for bucket name | `random` | No |
| `function_timeout` | Function timeout in seconds | `120` | No |
| `enable_apis` | Enable required Google Cloud APIs | `true` | No |

### Bash Script Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `BUCKET_NAME` | Storage bucket name | `auto-generated` | No |
| `FUNCTION_PREFIX` | Prefix for function names | `interview-assistant` | No |

## Post-Deployment

After successful deployment, you will have:

1. **Function URLs** for API access:
   - Speech-to-Text Function: `https://{region}-{project}.cloudfunctions.net/interview-assistant-speech`
   - Analysis Function: `https://{region}-{project}.cloudfunctions.net/interview-assistant-analysis`
   - Orchestration Function: `https://{region}-{project}.cloudfunctions.net/interview-assistant-orchestrate`

2. **Storage Bucket** for audio files:
   - Bucket URL: `gs://interview-audio-{suffix}`

3. **Test Framework** for validation:
   - Run tests using the provided test scripts
   - Upload sample audio files for end-to-end testing

## Testing Your Deployment

### Quick Validation

```bash
# Test analysis function with sample text
curl -X POST "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/interview-assistant-analysis" \
    -H "Content-Type: application/json" \
    -d '{
        "transcription": "I am a software engineer with five years of experience.",
        "question": "Tell me about yourself",
        "confidence": 0.95
    }'
```

### Complete Workflow Test

```bash
# Upload test audio file
gsutil cp sample_audio.wav gs://your-bucket-name/test_audio.wav

# Test orchestration endpoint
curl -X POST "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/interview-assistant-orchestrate" \
    -H "Content-Type: application/json" \
    -d '{
        "bucket": "your-bucket-name",
        "file": "test_audio.wav",
        "question": "Tell me about your professional background"
    }'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete interview-assistant \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Verify cleanup
gcloud functions list --filter="name:interview-assistant"
gsutil ls | grep interview-audio
```

## Cost Optimization

This infrastructure uses pay-per-use pricing:

- **Cloud Functions**: Charged per invocation and compute time
- **Cloud Storage**: Charged per GB stored and operations
- **Speech-to-Text**: Charged per minute of audio processed
- **Vertex AI**: Charged per request and tokens processed

Estimated costs for development/testing:
- Light usage (10 interviews/month): $5-10/month
- Moderate usage (100 interviews/month): $25-50/month
- Heavy usage (1000 interviews/month): $150-300/month

### Cost Reduction Tips

1. Use lifecycle policies to automatically delete old audio files
2. Optimize function memory allocation based on usage patterns
3. Consider batch processing for multiple interviews
4. Monitor usage with Google Cloud's cost management tools

## Security Considerations

### Default Security Features

- **IAM Service Account**: Least privilege access to required services
- **Function Authentication**: HTTP functions with configurable authentication
- **Storage Encryption**: Automatic encryption at rest and in transit
- **API Access Control**: Functions can be restricted to specific networks

### Production Hardening

For production deployments, consider:

1. **Private Networking**: Deploy functions in VPC with private Google Access
2. **Identity and Access Management**: Implement OAuth 2.0 or Identity-Aware Proxy
3. **Audit Logging**: Enable Cloud Audit Logs for compliance
4. **Data Loss Prevention**: Integrate Cloud DLP for sensitive data scanning
5. **Network Security**: Configure Cloud Armor for DDoS protection

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services list --enabled
   ```

2. **Permission Denied**: Verify IAM permissions
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Function Timeout**: Check function logs for performance issues
   ```bash
   gcloud functions logs read interview-assistant-speech
   ```

4. **Storage Access**: Verify bucket permissions and existence
   ```bash
   gsutil ls -L gs://your-bucket-name
   ```

### Debug Commands

```bash
# Check function status
gcloud functions describe interview-assistant-speech --region=${REGION}

# View recent logs
gcloud logging read "resource.type=cloud_function" --limit=10

# Test API connectivity
curl -I "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/interview-assistant-speech"

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:interview-assistant@*"
```

## Customization

### Adding New Interview Categories

1. Update the `interview_questions.json` file in Cloud Storage
2. Modify the analysis function to handle new question types
3. Extend the Gemini prompts for category-specific feedback

### Scaling Modifications

1. **Increase Function Resources**: Modify memory and timeout settings
2. **Add Caching**: Implement Redis or Memorystore for frequent queries
3. **Batch Processing**: Add Cloud Tasks for handling multiple interviews
4. **Load Balancing**: Use Cloud Load Balancing for high traffic scenarios

### Integration Options

1. **Web Frontend**: Deploy using Cloud Run or App Engine
2. **Mobile App**: Integrate with Firebase for mobile applications
3. **Slack/Teams**: Add chatbot integration using Cloud Functions
4. **LMS Integration**: Connect with learning management systems

## Monitoring and Observability

### Built-in Monitoring

- **Cloud Functions Metrics**: Execution count, duration, memory usage
- **Storage Metrics**: Request rates, data transfer, storage usage
- **AI API Metrics**: Request volume, latency, error rates

### Advanced Monitoring Setup

```bash
# Create custom dashboard
gcloud monitoring dashboards create --config-from-file=monitoring-dashboard.yaml

# Set up alerting policies
gcloud alpha monitoring policies create --policy-from-file=alerting-policy.yaml

# Enable detailed logging
gcloud logging sinks create interview-assistant-logs \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/interview_logs
```

## Support and Documentation

### Additional Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Gemini API Reference](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini)
- [Speech-to-Text API Guide](https://cloud.google.com/speech-to-text/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

1. **Google Cloud Support**: Use Cloud Console support options
2. **Community Forums**: Stack Overflow with `google-cloud-platform` tag
3. **GitHub Issues**: Report infrastructure code issues
4. **Documentation**: Refer to official Google Cloud documentation

## Version Information

- **Recipe Version**: 1.1
- **Infrastructure Manager**: Compatible with current GCP deployment
- **Terraform**: Requires Google provider version 4.0+
- **Bash Scripts**: Compatible with Google Cloud SDK latest version

## License

This infrastructure code is provided as-is for educational and development purposes. Ensure compliance with your organization's infrastructure policies and Google Cloud terms of service.