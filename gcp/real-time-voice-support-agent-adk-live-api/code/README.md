# Infrastructure as Code for Real-Time Voice Support Agent with ADK and Live API

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Voice Support Agent with ADK and Live API".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Python 3.10+ for local development and testing
- Appropriate IAM permissions for resource creation

### Required APIs
- AI Platform API (aiplatform.googleapis.com)
- Cloud Functions API (cloudfunctions.googleapis.com)
- Cloud Build API (cloudbuild.googleapis.com)
- Cloud Logging API (logging.googleapis.com)

### IAM Permissions
Your account needs the following roles:
- Cloud Functions Admin
- Service Account Admin
- AI Platform Admin
- Project IAM Admin
- Cloud Build Editor

### Cost Considerations
- Estimated cost: $3-8 per hour during active development
- Cloud Functions: Pay-per-invocation model
- Vertex AI API calls: Variable based on usage
- Storage and logging: Minimal costs

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to infrastructure manager directory
cd infrastructure-manager/

# Initialize deployment
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/voice-agent-deployment \
    --service-account=YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Check deployment status
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/voice-agent-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment (optional)
gcloud functions list --regions=us-central1
```

## Configuration

### Environment Variables

Before deployment, set these environment variables:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export SERVICE_ACCOUNT_NAME="voice-agent-sa"
export FUNCTION_NAME="voice-support-agent"
```

### Customization Options

#### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "voice-support-agent"
function_memory = "1024"
function_timeout = 300
service_account_display_name = "Voice Support Agent SA"
```

#### Infrastructure Manager Parameters

Edit `infrastructure-manager/inputs.yaml`:

```yaml
project_id:
  type: string
  default: "your-project-id"
region:
  type: string
  default: "us-central1"
function_name:
  type: string
  default: "voice-support-agent"
memory_mb:
  type: integer
  default: 1024
timeout_seconds:
  type: integer
  default: 300
```

## Deployment Details

### Infrastructure Components

This deployment creates:

1. **Service Account**: Dedicated IAM service account for the voice agent function
2. **IAM Bindings**: Appropriate permissions for AI Platform and Cloud Functions access
3. **Cloud Function**: Serverless function hosting the voice support agent
4. **Cloud Storage Bucket**: For function source code deployment
5. **Logging Configuration**: Cloud Logging setup for monitoring and debugging

### Network Configuration

- Cloud Function deployed with public HTTPS trigger
- CORS enabled for web client integration
- Regional deployment for optimal latency

### Security Features

- Least privilege IAM permissions
- Service account authentication for AI Platform access
- Secure environment variable handling
- Function-level access controls

## Testing the Deployment

### Function Health Check

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe voice-support-agent \
    --region=us-central1 \
    --format="value(serviceConfig.uri)")

# Test health endpoint
curl -X GET "$FUNCTION_URL" -H "Content-Type: application/json"
```

### Test Voice Session Initialization

```bash
# Test voice session startup
curl -X POST "$FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "type": "voice_start",
        "session_id": "test-session-123"
    }'
```

### Test Text Interaction

```bash
# Test customer service functions
curl -X POST "$FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "type": "text",
        "message": "I need help with customer 12345",
        "customer_context": {"source": "test"}
    }'
```

## Monitoring and Logging

### View Function Logs

```bash
# View recent logs
gcloud functions logs read voice-support-agent --region=us-central1

# Follow logs in real-time
gcloud functions logs tail voice-support-agent --region=us-central1
```

### Monitor Performance

```bash
# Check function metrics
gcloud functions describe voice-support-agent \
    --region=us-central1 \
    --format="table(name,status,updateTime)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/voice-agent-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

### Manual Cleanup (if needed)

```bash
# Delete function
gcloud functions delete voice-support-agent --region=us-central1 --quiet

# Delete service account
gcloud iam service-accounts delete voice-agent-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com --quiet

# Clean up any remaining storage buckets
gsutil ls -b gs://gcf-v2-sources-* | grep voice-agent | xargs gsutil -m rm -r
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Ensure you have the necessary IAM roles
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
       --member="user:your-email@domain.com" \
       --role="roles/cloudfunctions.admin"
   ```

2. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

3. **Function Deployment Timeout**
   ```bash
   # Check build logs
   gcloud builds list --limit=5
   gcloud builds log [BUILD_ID]
   ```

4. **Service Account Issues**
   ```bash
   # Verify service account exists
   gcloud iam service-accounts list
   
   # Check service account permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   ```

### Debugging Steps

1. **Check Function Status**:
   ```bash
   gcloud functions describe voice-support-agent --region=us-central1
   ```

2. **Review Logs**:
   ```bash
   gcloud functions logs read voice-support-agent --region=us-central1 --limit=50
   ```

3. **Test Local Development**:
   ```bash
   # Test function locally using Functions Framework
   cd function-source/
   python -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   functions-framework --target=voice_support_endpoint --debug
   ```

## Advanced Configuration

### Custom Voice Settings

To modify voice agent behavior, update the agent configuration in the function source:

```python
voice_config={
    "voice_name": "Puck",  # Change voice type
    "language_code": "en-US",  # Change language
    "speaking_rate": 1.0,  # Adjust speaking speed
    "pitch": 0.0  # Adjust voice pitch
}
```

### Scaling Configuration

For production workloads, adjust function scaling:

```bash
# Update function configuration
gcloud functions deploy voice-support-agent \
    --min-instances=1 \
    --max-instances=100 \
    --memory=2GB \
    --timeout=540s
```

### Integration with External Systems

The voice agent can be extended to integrate with:
- Customer Relationship Management (CRM) systems
- Ticketing platforms (ServiceNow, Jira)
- Knowledge bases and documentation systems
- Analytics and monitoring platforms

## Security Considerations

### Best Practices Implemented

- Service account with minimal required permissions
- Function-level authentication and authorization
- Secure environment variable handling
- HTTPS-only communication
- Input validation and sanitization

### Additional Security Measures

Consider implementing for production:
- VPC networking for private communication
- Customer Managed Encryption Keys (CMEK)
- Cloud Armor for DDoS protection
- Audit logging for compliance requirements

## Support and Documentation

### Related Documentation

- [Google Agent Development Kit (ADK)](https://google.github.io/adk-docs/)
- [Gemini Live API Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/live-api)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Google Cloud documentation
3. Refer to the original recipe documentation
4. Contact your Google Cloud support team

### Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation accordingly
4. Validate with security and compliance requirements

## License

This infrastructure code is provided as part of the cloud recipes collection. Please refer to the repository license for usage terms.