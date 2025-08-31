# Infrastructure as Code for Automated API Testing with Gemini and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated API Testing with Gemini and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Project owner or editor permissions for resource creation
- Python 3.12+ for local development and testing
- Basic understanding of API testing concepts

### Required APIs

The following APIs will be automatically enabled during deployment:

- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)

## Quick Start

### Using Infrastructure Manager (Recommended)

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Set project context
gcloud config set project $PROJECT_ID

# Deploy infrastructure
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/api-testing-deployment \
    --service-account $PROJECT_ID@$PROJECT_ID.iam.gserviceaccount.com \
    --local-source infrastructure-manager/ \
    --inputs-file infrastructure-manager/inputs.yaml

# Monitor deployment progress
gcloud infra-manager deployments describe projects/$PROJECT_ID/locations/$REGION/deployments/api-testing-deployment
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy all resources
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Architecture Overview

The deployed infrastructure includes:

- **Cloud Storage Bucket**: Stores test specifications, results, and reports
- **Cloud Function**: AI-powered test case generator using Vertex AI Gemini 2.0 Flash
- **Cloud Run Service**: Scalable test execution engine with concurrent processing
- **IAM Roles**: Least-privilege service accounts for secure component interaction
- **Monitoring**: Cloud Logging integration for observability

## Configuration Options

### Infrastructure Manager Configuration

Edit `infrastructure-manager/inputs.yaml` to customize:

```yaml
project_id: "your-project-id"
region: "us-central1"
random_suffix: "abc123"
bucket_location: "US"
function_memory: "1024MB"
function_timeout: "300s"
service_memory: "2Gi"
service_cpu: "2"
service_max_instances: 10
```

### Terraform Configuration

Edit `terraform/terraform.tfvars` to customize:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
function_memory_mb    = 1024
function_timeout_s    = 300
service_memory        = "2Gi"
service_cpu          = "2"
service_max_instances = 10
bucket_location      = "US"
```

## Testing the Deployment

After deployment, test the system using the provided workflow:

```bash
# Get deployment outputs
FUNCTION_URL=$(gcloud functions describe api-test-orchestrator-* --region=$REGION --format="value(serviceConfig.uri)")
SERVICE_URL=$(gcloud run services describe api-test-runner-* --region=$REGION --format="value(status.url)")

# Run end-to-end test
export FUNCTION_URL=$FUNCTION_URL
export SERVICE_URL=$SERVICE_URL
python3 ../test-workflow.py
```

### Manual Testing

Test individual components:

```bash
# Test Cloud Function
curl -X POST "$FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d '{
        "api_specification": "Sample OpenAPI spec",
        "endpoints": ["https://httpbin.org/get"],
        "request_id": "manual-test"
    }'

# Test Cloud Run service
curl -X POST "$SERVICE_URL/run-tests" \
    -H "Content-Type: application/json" \
    -d '{
        "test_cases": [{
            "id": "test-1",
            "name": "Health Check",
            "endpoint": "https://httpbin.org/status/200",
            "method": "GET",
            "expected_status": 200
        }],
        "test_run_id": "manual-test"
    }'
```

## Monitoring and Observability

### View Logs

```bash
# Cloud Function logs
gcloud functions logs read api-test-orchestrator-* --region=$REGION

# Cloud Run logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=api-test-runner-*" --limit=50

# View test results in Cloud Storage
gsutil ls -r gs://$PROJECT_ID-test-results-*/
```

### Monitoring Dashboard

Access Cloud Monitoring for:

- Function invocation rates and errors
- Cloud Run request latency and concurrency
- Storage usage and access patterns
- Vertex AI API usage and costs

## Cost Optimization

### Estimated Costs

- **Vertex AI Gemini**: ~$0.10-0.50 per 1K test cases generated
- **Cloud Functions**: ~$0.40 per 1M invocations + compute time
- **Cloud Run**: ~$0.24 per vCPU hour (only when processing)
- **Cloud Storage**: ~$0.02 per GB per month
- **Total**: $5-15 per month for moderate usage

### Cost Optimization Tips

1. **Function Memory**: Reduce to 512MB if test specs are small
2. **Service Scaling**: Lower max instances for lighter workloads
3. **Storage Lifecycle**: Implement automatic deletion of old test results
4. **Gemini Usage**: Cache test cases for similar API specs

## Security Considerations

### Service Accounts

The deployment creates minimal-privilege service accounts:

- **Function Service Account**: Access to Vertex AI and Cloud Storage
- **Cloud Run Service Account**: Access to Cloud Storage and Logging

### Network Security

- Cloud Function: Public HTTPS endpoint (can be restricted to authenticated users)
- Cloud Run: Public HTTPS endpoint with IAM-based access control
- Storage: Private bucket with service account access only

### API Keys and Secrets

- No hardcoded credentials in the infrastructure
- Service account keys are automatically managed by Google Cloud
- Consider using Secret Manager for additional API keys

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/api-testing-deployment
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
gcloud functions list --filter="name:api-test-orchestrator"
gcloud run services list --filter="metadata.name:api-test-runner"
gsutil ls -p $PROJECT_ID | grep test-results

# Disable APIs if no longer needed (optional)
gcloud services disable aiplatform.googleapis.com
gcloud services disable cloudfunctions.googleapis.com
gcloud services disable run.googleapis.com
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your account has Project Editor or Owner role
3. **Quota Limits**: Check Vertex AI and Compute Engine quotas in Console
4. **Region Availability**: Verify Vertex AI Gemini is available in your region

### Debug Commands

```bash
# Check function deployment status
gcloud functions describe api-test-orchestrator-* --region=$REGION

# Check Cloud Run deployment status
gcloud run services describe api-test-runner-* --region=$REGION

# Check storage bucket permissions
gsutil iam get gs://$PROJECT_ID-test-results-*

# Verify Vertex AI access
gcloud ai models list --region=$REGION
```

### Log Analysis

```bash
# Function errors
gcloud functions logs read api-test-orchestrator-* --region=$REGION --limit=10 --filter="severity>=ERROR"

# Service errors
gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" --limit=10

# Test execution patterns
gcloud logging read "jsonPayload.message:\"Test execution\"" --limit=20
```

## Customization

### Adding New Test Types

1. Modify the Cloud Function to support additional test patterns
2. Update the Gemini prompt to generate specific test scenarios
3. Extend the Cloud Run service to handle new test validation logic

### Integration with CI/CD

```bash
# Example GitHub Actions integration
curl -X POST "$FUNCTION_URL" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -d @api-specification.json
```

### Custom Metrics

Add Cloud Monitoring custom metrics:

```python
# In Cloud Function or Cloud Run
from google.cloud import monitoring_v3

client = monitoring_v3.MetricServiceClient()
# Create custom metrics for test success rates
```

## Support

### Documentation Links

- [Vertex AI Gemini Documentation](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Console for service status
3. Examine Cloud Logging for error details
4. Consult Google Cloud support documentation

### Contributing

To improve this infrastructure code:

1. Test changes in a development project
2. Validate against security best practices
3. Update documentation with changes
4. Consider backward compatibility

## Version Information

- **Recipe Version**: 1.1
- **Infrastructure Manager**: Compatible with Google Cloud CLI latest
- **Terraform**: Requires Terraform >= 1.0, Google Provider >= 4.0
- **Generated**: 2025-07-12
- **Last Updated**: 2025-07-12