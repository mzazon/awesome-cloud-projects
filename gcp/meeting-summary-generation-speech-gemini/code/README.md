# Infrastructure as Code for Meeting Summary Generation with Speech-to-Text and Gemini

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Meeting Summary Generation with Speech-to-Text and Gemini".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud CLI) installed and configured
- Appropriate permissions for Cloud Storage, Cloud Functions, Speech-to-Text, and Vertex AI
- Billing enabled on your Google Cloud project
- Basic understanding of serverless functions and AI APIs

## Quick Start

### Using Infrastructure Manager (GCP)
```bash
# Create a new deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/meeting-summary-deployment \
    --service-account SERVICE_ACCOUNT_EMAIL \
    --local-source ./infrastructure-manager/

# Check deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/meeting-summary-deployment
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
gcloud functions list --filter="name:process-meeting"
```

## Architecture Components

This IaC deploys the following Google Cloud resources:

- **Cloud Storage Bucket**: Stores meeting audio files with lifecycle policies
- **Cloud Functions**: Serverless function for processing audio files
- **IAM Roles**: Service accounts and permissions for secure access
- **API Enablement**: Required Google Cloud APIs (Speech-to-Text, Vertex AI, etc.)

## Configuration Variables

### Infrastructure Manager Variables
- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `bucket_name_suffix`: Unique suffix for storage bucket
- `function_name_suffix`: Unique suffix for Cloud Function

### Terraform Variables
- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `bucket_location`: Storage bucket location (default: US)
- `function_timeout`: Function timeout in seconds (default: 540)
- `function_memory`: Function memory allocation (default: 1024MB)

## Outputs

Both implementations provide these outputs:
- `bucket_name`: Name of the created Cloud Storage bucket
- `function_name`: Name of the deployed Cloud Function
- `function_url`: Trigger URL for the Cloud Function
- `upload_command`: Example command to upload audio files

## Testing the Deployment

After successful deployment, test the meeting processing pipeline:

```bash
# Upload a test audio file
gsutil cp your_meeting.wav gs://BUCKET_NAME/

# Monitor function execution
gcloud functions logs read FUNCTION_NAME --region REGION --limit 10

# Check for generated outputs
gsutil ls gs://BUCKET_NAME/transcripts/
gsutil ls gs://BUCKET_NAME/summaries/
```

## Cleanup

### Using Infrastructure Manager (GCP)
```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/meeting-summary-deployment
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --filter="name:process-meeting"
gsutil ls gs://meeting-recordings-*
```

## Customization

### Function Configuration
Modify the Cloud Function settings in your chosen IaC implementation:
- **Memory allocation**: Adjust based on audio file sizes
- **Timeout**: Increase for longer meeting recordings
- **Environment variables**: Add custom configuration options
- **Trigger settings**: Modify file type filters or processing rules

### AI Model Settings
Customize the AI processing behavior:
- **Speech-to-Text model**: Change to latest or specialized models
- **Language settings**: Support multiple languages
- **Speaker diarization**: Adjust speaker count parameters
- **Gemini model**: Switch between different Vertex AI models

### Storage Configuration
Adjust storage settings for your needs:
- **Lifecycle policies**: Modify retention periods
- **Storage class**: Change for cost optimization
- **Regional settings**: Deploy in specific regions for compliance

## Security Considerations

This implementation includes several security best practices:
- **IAM least privilege**: Service accounts with minimal required permissions
- **Uniform bucket access**: Consistent security policies across storage
- **Encryption**: Data encrypted in transit and at rest
- **API scoping**: Functions only access required Google Cloud APIs

For production deployments, consider:
- Implementing VPC Service Controls
- Adding Cloud KMS encryption keys
- Setting up audit logging
- Implementing access controls for sensitive meeting data

## Monitoring and Logging

Monitor your deployment using:
- **Cloud Functions logs**: `gcloud functions logs read FUNCTION_NAME`
- **Cloud Monitoring**: Set up alerts for function failures
- **Cloud Storage logs**: Monitor file upload and access patterns
- **Vertex AI usage**: Track AI service consumption and costs

## Troubleshooting

Common issues and solutions:

### Function Deployment Fails
- Verify all required APIs are enabled
- Check IAM permissions for the deploying user
- Ensure Cloud Build API is enabled for function deployment

### Transcription Errors
- Verify audio file format is supported (WAV, MP3, FLAC, M4A)
- Check audio file size limits (10MB for synchronous, 1GB for asynchronous)
- Ensure Speech-to-Text API quota is not exceeded

### Summary Generation Issues
- Verify Vertex AI API is enabled and accessible
- Check that the transcript content is not empty
- Monitor Vertex AI quotas and rate limits

## Cost Optimization

To optimize costs:
- Set appropriate Cloud Storage lifecycle policies
- Monitor Speech-to-Text API usage and batch processing
- Use appropriate Vertex AI model sizes for your use case
- Implement function concurrency limits to control parallel processing

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation for detailed implementation guidance
2. Refer to Google Cloud documentation for service-specific troubleshooting
3. Review Cloud Functions logs for runtime errors
4. Consult Vertex AI documentation for AI service issues

## Related Resources

- [Google Cloud Speech-to-Text Documentation](https://cloud.google.com/speech-to-text/docs)
- [Vertex AI Generative AI Documentation](https://cloud.google.com/vertex-ai/docs/generative-ai)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)