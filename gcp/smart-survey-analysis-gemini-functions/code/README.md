# Infrastructure as Code for Smart Survey Analysis with Gemini and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Survey Analysis with Gemini and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 457.0.0 or later)
- Active Google Cloud project with billing enabled
- Required APIs enabled: Cloud Functions, Vertex AI, Firestore, Cloud Build
- Appropriate IAM permissions for:
  - Cloud Functions Admin
  - Vertex AI User
  - Firestore Admin
  - Project Editor (for resource creation)
- Python 3.11+ for local development and testing

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment using Google Cloud's native IaC
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/survey-analysis \
    --service-account=$SERVICE_ACCOUNT \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/$PROJECT_ID/locations/$REGION/deployments/survey-analysis
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform with Google Cloud provider
terraform init

# Review planned infrastructure changes
terraform plan -var="project_id=$PROJECT_ID" -var="region=$REGION"

# Apply infrastructure configuration
terraform apply -var="project_id=$PROJECT_ID" -var="region=$REGION"

# View deployment outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure using automated script
./scripts/deploy.sh

# Check deployment status
gcloud functions list --regions=$REGION
gcloud firestore databases list
```

## Architecture Overview

The infrastructure deploys:

- **Firestore Database**: Native mode database for storing survey responses and AI analysis
- **Cloud Function**: HTTP-triggered function with Vertex AI integration for survey processing
- **IAM Roles**: Service account with appropriate permissions for AI and database access
- **Vertex AI Configuration**: Gemini model access for natural language processing

## Configuration Variables

### Infrastructure Manager Variables

Edit `main.yaml` to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_name`: Cloud Function name
- `database_name`: Firestore database name

### Terraform Variables

Configure via `terraform.tfvars` or command line:

```hcl
project_id    = "your-project-id"
region        = "us-central1"
function_name = "survey-analyzer"
database_name = "survey-db"
```

### Bash Script Variables

Set environment variables before running:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="survey-analyzer"
export FIRESTORE_DATABASE="survey-db"
```

## Post-Deployment

After successful deployment:

1. **Test the Function**:
   ```bash
   # Get function URL
   FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME \
       --region=$REGION \
       --format="value(httpsTrigger.url)")
   
   # Test with sample data
   curl -X POST $FUNCTION_URL \
       -H "Content-Type: application/json" \
       -d '{"survey_id":"test","responses":[{"question":"How was your experience?","answer":"Great service!"}]}'
   ```

2. **Verify Firestore**:
   ```bash
   # Check database status
   gcloud firestore databases describe --database=$FIRESTORE_DATABASE
   
   # List collections
   gcloud firestore collections list --database=$FIRESTORE_DATABASE
   ```

3. **Monitor Function Logs**:
   ```bash
   # View recent logs
   gcloud functions logs read $FUNCTION_NAME --region=$REGION --limit=50
   ```

## Cost Optimization

- **Cloud Functions**: Billed per invocation and execution time
- **Vertex AI (Gemini)**: Pay-per-token pricing for AI analysis
- **Firestore**: Generous free tier, then per-operation pricing
- **Estimated monthly cost**: $10-50 for moderate usage (1000 surveys/month)

## Security Features

- Service accounts with minimal required permissions
- HTTPS-only function endpoints with CORS support
- Firestore security rules (configure based on your access patterns)
- No hardcoded credentials in function code

## Monitoring and Observability

Access monitoring through:

- **Cloud Functions Metrics**: Function invocations, errors, duration
- **Vertex AI Metrics**: Token usage, API latency, error rates
- **Firestore Metrics**: Read/write operations, storage usage
- **Cloud Logging**: Detailed function execution logs

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/survey-analysis
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=$PROJECT_ID" -var="region=$REGION"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --regions=$REGION
gcloud firestore databases list
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com aiplatform.googleapis.com firestore.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Add required roles to your user account
   gcloud projects add-iam-policy-binding $PROJECT_ID \
       --member="user:your-email@domain.com" \
       --role="roles/cloudfunctions.admin"
   ```

3. **Function Timeout**:
   - Increase timeout in function configuration (current: 300s)
   - Monitor Vertex AI API latency in Cloud Monitoring

4. **Firestore Permissions**:
   ```bash
   # Verify Firestore service account permissions
   gcloud projects get-iam-policy $PROJECT_ID \
       --flatten="bindings[].members" \
       --format="table(bindings.role)" \
       --filter="bindings.members:*firestore*"
   ```

### Debug Mode

Enable detailed logging by setting environment variable:

```bash
export CLOUDSDK_CORE_VERBOSITY=debug
```

## Customization

### Function Configuration

Modify function settings in IaC files:

- **Memory**: Increase for complex analysis (current: 1GB)
- **Timeout**: Adjust for processing time (current: 300s)
- **Environment Variables**: Add custom configuration

### Firestore Configuration

- **Multi-region**: Configure for global access
- **Security Rules**: Implement custom access controls
- **Indexes**: Add for complex queries

### AI Model Configuration

- **Model Version**: Switch between Gemini variants
- **Prompt Engineering**: Customize analysis prompts
- **Response Formats**: Modify output structure

## Performance Optimization

1. **Function Cold Starts**: Use minimum instances for production
2. **Firestore Optimization**: Structure documents for efficient queries
3. **Vertex AI Optimization**: Batch requests when possible
4. **Caching**: Implement response caching for similar surveys

## Integration Examples

### With Other GCP Services

```bash
# BigQuery integration for analytics
gcloud functions deploy survey-to-bigquery \
    --trigger-resource=survey_analyses \
    --trigger-event=providers/cloud.firestore/eventTypes/document.create

# Pub/Sub for real-time processing
gcloud pubsub topics create survey-processing
gcloud functions deploy survey-processor \
    --trigger-topic=survey-processing
```

### With Third-party Tools

- **Slack Integration**: Send analysis summaries to Slack channels
- **Email Alerts**: Configure alerting for negative sentiment
- **Dashboard Tools**: Connect to Grafana or similar for visualization

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud Functions documentation
3. Consult Vertex AI Gemini API documentation
4. Verify Firestore configuration guidelines

## Version Information

- **Infrastructure Manager**: Compatible with latest GCP deployment service
- **Terraform**: Tested with Terraform >= 1.0, Google Cloud Provider >= 4.0
- **Python Runtime**: Cloud Functions Python 3.12
- **Vertex AI**: Gemini 1.5 Flash model

## Related Resources

- [Original Recipe Documentation](../smart-survey-analysis-gemini-functions.md)
- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Gemini API Reference](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini)
- [Firestore for AI Applications](https://cloud.google.com/firestore/docs/overview)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)