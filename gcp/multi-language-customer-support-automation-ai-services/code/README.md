# Infrastructure as Code for Multi-Language Customer Support Automation with Cloud AI Services

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Language Customer Support Automation with Cloud AI Services".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Storage (Storage Admin)
  - Cloud Functions (Cloud Functions Admin)
  - Firestore (Datastore Owner)
  - Cloud Workflows (Workflows Admin)
  - AI Platform APIs (AI Platform Admin)
  - Cloud Monitoring (Monitoring Admin)
- Terraform installed (version 1.0 or later) - for Terraform implementation
- Basic understanding of Google Cloud AI services and serverless architecture

## Estimated Costs

- **Development/Testing**: $20-50 per month
- **Production**: $100-500 per month (varies by usage volume)
- **Key Cost Drivers**: 
  - AI API calls (Speech-to-Text, Translation, Natural Language, Text-to-Speech)
  - Cloud Functions compute time
  - Firestore read/write operations
  - Cloud Storage requests

> **Cost Optimization Tip**: Use Cloud AI free tier limits for initial testing and implement request batching for production workloads.

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy infrastructure
gcloud infra-manager deployments apply \
    --location=${REGION} \
    --source=. \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat << EOF > terraform.tfvars
project_id = "${PROJECT_ID}"
region     = "${REGION}"
EOF

# Plan and apply
terraform plan
terraform apply
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This implementation creates a complete multilingual customer support automation system using Google Cloud AI services:

### Core Components

- **Cloud Storage**: Audio file storage and configuration management
- **Cloud Functions**: Serverless AI service orchestration
- **Firestore**: Conversation history and session management
- **Cloud Workflows**: Complex support scenario handling and escalation
- **Cloud Monitoring**: System observability and alerting

### AI Services Integration

- **Cloud Speech-to-Text**: Multi-language voice recognition
- **Cloud Translation**: Real-time language translation
- **Cloud Natural Language**: Sentiment analysis and entity extraction
- **Cloud Text-to-Speech**: Natural voice response generation

### Data Flow

1. Customer audio input → Speech-to-Text conversion
2. Language detection and sentiment analysis
3. Translation to/from English if needed
4. Intelligent response generation based on sentiment
5. Text-to-Speech conversion for natural audio output
6. Conversation logging and analytics

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `BUCKET_NAME` | Storage bucket name | Auto-generated | No |
| `FUNCTION_NAME` | Cloud Function name | Auto-generated | No |
| `WORKFLOW_NAME` | Cloud Workflow name | Auto-generated | No |

### Customization Options

#### Language Support
Edit the language configuration in your terraform.tfvars or Infrastructure Manager inputs:

```hcl
supported_languages = [
  "en-US",  # English (US)
  "es-ES",  # Spanish (Spain)
  "fr-FR",  # French (France)
  "de-DE",  # German (Germany)
  "it-IT",  # Italian (Italy)
  "pt-BR",  # Portuguese (Brazil)
  "ja-JP",  # Japanese (Japan)
  "ko-KR",  # Korean (Korea)
  "zh-CN"   # Chinese (China)
]
```

#### Sentiment Thresholds
Adjust sentiment analysis thresholds:

```hcl
sentiment_config = {
  negative_threshold = -0.2   # Values below this trigger negative handling
  positive_threshold = 0.2    # Values above this trigger positive handling
  urgency_threshold  = -0.5   # Values below this trigger escalation
}
```

#### Voice Configuration
Customize Text-to-Speech voices:

```hcl
voice_config = {
  "en-US" = "en-US-Neural2-J"
  "es-ES" = "es-ES-Neural2-F"
  "fr-FR" = "fr-FR-Neural2-C"
  "de-DE" = "de-DE-Neural2-F"
}
```

## API Endpoints

After deployment, the system provides these endpoints:

### Cloud Function Endpoint
```
https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}
```

**Method**: POST  
**Content-Type**: application/json

**Request Body**:
```json
{
  "audio_data": "base64-encoded-audio",
  "customer_id": "unique-customer-identifier",
  "session_id": "conversation-session-id"
}
```

**Response**:
```json
{
  "transcript": "Recognized speech text",
  "detected_language": "en-US",
  "sentiment_score": 0.3,
  "response_text": "Generated response",
  "audio_response": "base64-encoded-audio-response"
}
```

### Workflow Execution
```bash
gcloud workflows execute ${WORKFLOW_NAME} \
    --data='{"customer_id":"test-123","audio_data":"...","session_id":"session-456"}'
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **Function Performance**:
   - Invocation count and success rate
   - Execution duration and memory usage
   - Error rates and types

2. **AI Service Usage**:
   - Speech-to-Text API calls and accuracy
   - Translation API usage by language pair
   - Natural Language API sentiment analysis trends
   - Text-to-Speech synthesis requests

3. **Business Metrics**:
   - Average sentiment scores over time
   - Language distribution of customer requests
   - Escalation rates to human agents
   - Response time performance

### Alerts Configuration

The infrastructure includes pre-configured alerts for:

- High negative sentiment trends (below -0.5)
- Function error rates above 5%
- API quota approaching limits
- Unusual spikes in processing time

### Custom Dashboards

Access monitoring dashboards at:
```
https://console.cloud.google.com/monitoring/dashboards/custom/${DASHBOARD_ID}
```

## Testing

### Unit Testing

```bash
# Test individual AI services
cd terraform/
terraform output function_url

# Test speech recognition
curl -X POST "$(terraform output -raw function_url)" \
    -H "Content-Type: application/json" \
    -d @test-payload.json
```

### Integration Testing

```bash
# Run complete end-to-end test
./scripts/test-integration.sh
```

### Load Testing

```bash
# Generate load test traffic
for i in {1..10}; do
  curl -X POST "$(terraform output -raw function_url)" \
      -H "Content-Type: application/json" \
      -d @test-payload-${i}.json &
done
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Errors**:
   ```bash
   # Enable required APIs
   gcloud services enable speech.googleapis.com
   gcloud services enable translate.googleapis.com
   gcloud services enable language.googleapis.com
   gcloud services enable texttospeech.googleapis.com
   ```

2. **Permission Denied Errors**:
   ```bash
   # Verify IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Function Timeout Issues**:
   - Check function logs: `gcloud functions logs read ${FUNCTION_NAME}`
   - Increase timeout in configuration
   - Optimize audio file size and format

4. **Quota Exceeded Errors**:
   - Monitor API quotas in Cloud Console
   - Request quota increases if needed
   - Implement request throttling

### Debug Commands

```bash
# View function logs
gcloud functions logs read ${FUNCTION_NAME} --limit=50

# Check workflow execution status
gcloud workflows executions list --workflow=${WORKFLOW_NAME}

# Monitor Firestore operations
gcloud firestore databases describe --database="(default)"

# View storage bucket contents
gsutil ls -la gs://${BUCKET_NAME}
```

## Security Considerations

### Best Practices Implemented

1. **Least Privilege IAM**: Service accounts have minimal required permissions
2. **Data Encryption**: All data encrypted at rest and in transit
3. **Secure Communications**: HTTPS endpoints with proper authentication
4. **Audit Logging**: Comprehensive logging for compliance and monitoring
5. **Secret Management**: Sensitive configuration stored in Secret Manager

### Security Hardening

```bash
# Enable audit logging
gcloud logging sinks create audit-sink \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/audit_logs \
    --log-filter='protoPayload.@type="type.googleapis.com/google.cloud.audit.AuditLog"'

# Configure VPC Service Controls (optional)
gcloud access-context-manager perimeters create support-perimeter \
    --title="Customer Support Perimeter" \
    --resources=projects/${PROJECT_ID}
```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete deployment-name \
    --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud functions list --regions=${REGION}
gcloud workflows list --location=${REGION}
gsutil ls
gcloud firestore databases list
```

## Performance Optimization

### Scaling Considerations

1. **Function Concurrency**: Adjust max instances based on expected load
2. **Audio Processing**: Implement streaming for real-time scenarios
3. **Caching**: Cache translations for common phrases
4. **Batch Processing**: Group similar requests for efficiency

### Cost Optimization

1. **AI API Usage**: Implement caching for repeated translations
2. **Storage Classes**: Use appropriate storage classes for audio files
3. **Function Memory**: Right-size function memory allocation
4. **Monitoring**: Set up billing alerts and quotas

## Support and Resources

### Documentation Links

- [Cloud Speech-to-Text Documentation](https://cloud.google.com/speech-to-text/docs)
- [Cloud Translation Documentation](https://cloud.google.com/translate/docs)
- [Cloud Natural Language Documentation](https://cloud.google.com/natural-language/docs)
- [Cloud Text-to-Speech Documentation](https://cloud.google.com/text-to-speech/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Google Cloud documentation for specific services
3. Check Cloud Console for error messages and logs
4. Refer to the original recipe documentation

### Contributing

To contribute improvements to this infrastructure code:
1. Test changes in a development environment
2. Ensure all security best practices are maintained
3. Update documentation for any new features
4. Follow Google Cloud deployment best practices

## License

This infrastructure code is provided as-is for educational and development purposes. Review and adapt security configurations for production use.