# Infrastructure as Code for Currency Converter API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Currency Converter API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a serverless currency conversion API using:

- **Cloud Functions**: HTTP-triggered serverless function for currency conversion
- **Secret Manager**: Secure storage for exchange rate API keys
- **IAM**: Service account permissions for secure secret access

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Required APIs enabled:
  - Cloud Functions API (`cloudfunctions.googleapis.com`)
  - Secret Manager API (`secretmanager.googleapis.com`)
- Appropriate IAM permissions:
  - Cloud Functions Admin
  - Secret Manager Admin
  - IAM Admin (for service account management)
- For Terraform: Terraform CLI installed (version >= 1.0)
- Exchange rate API key from [fixer.io](https://fixer.io) (free tier available)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended way to manage infrastructure using standard Terraform configurations with native GCP integration.

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_ID="currency-converter-$(date +%s)"

# Navigate to infrastructure manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_ID} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_ID}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="exchange_api_key=your-fixer-io-api-key"

# Apply infrastructure
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="exchange_api_key=your-fixer-io-api-key"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a guided deployment experience with error handling and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export EXCHANGE_API_KEY="your-fixer-io-api-key"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployed function
curl "$(gcloud functions describe currency-converter --region=${REGION} --format='value(httpsTrigger.url)')?from=USD&to=EUR&amount=100"
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `FUNCTION_NAME` | Cloud Function name | `currency-converter` | No |
| `SECRET_NAME` | Secret Manager secret name | `exchange-api-key-<random>` | No |
| `EXCHANGE_API_KEY` | API key for exchange rate service | - | Yes |

### Terraform Variables

All implementations support these customization options:

```hcl
# terraform/terraform.tfvars example
project_id = "my-project-123"
region = "us-central1"
function_name = "currency-converter"
memory_mb = 256
timeout_seconds = 60
exchange_api_key = "your-api-key-here"

# Optional: Custom labels
labels = {
  environment = "production"
  team        = "platform"
  cost-center = "engineering"
}
```

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Test basic currency conversion
FUNCTION_URL=$(gcloud functions describe currency-converter --region=${REGION} --format='value(httpsTrigger.url)')

# GET request test
curl "${FUNCTION_URL}?from=USD&to=EUR&amount=100"

# POST request test
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"from": "GBP", "to": "JPY", "amount": 50}'

# Test error handling
curl "${FUNCTION_URL}?from=INVALID&to=EUR&amount=100"

# Test CORS headers
curl -X OPTIONS "${FUNCTION_URL}" -I
```

Expected responses:
- Successful conversion: JSON with `success: true` and conversion results
- Error cases: JSON with `success: false` and error messages
- CORS headers: `Access-Control-Allow-Origin: *` and other CORS headers

## Monitoring & Observability

### Cloud Functions Monitoring

```bash
# View function logs
gcloud functions logs read currency-converter --region=${REGION} --limit=50

# Monitor function metrics in Cloud Monitoring
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=currency-converter" --limit=10
```

### Secret Manager Audit

```bash
# View secret access logs
gcloud logging read "protoPayload.serviceName=secretmanager.googleapis.com" --limit=10
```

## Security Considerations

This implementation follows security best practices:

1. **Secret Management**: API keys stored in Secret Manager with encryption at rest
2. **IAM Least Privilege**: Function service account has minimal required permissions
3. **HTTPS Only**: All endpoints use HTTPS encryption in transit
4. **CORS Configuration**: Proper CORS headers for web browser security
5. **Input Validation**: Function validates and sanitizes input parameters

## Cost Optimization

- **Pay-per-use**: Functions only incur charges during execution
- **Memory Optimization**: Default 256MB memory allocation (adjustable)
- **Timeout Configuration**: 60-second timeout prevents runaway executions
- **Free Tier Benefits**:
  - Cloud Functions: 2M invocations/month free
  - Secret Manager: 6 secret operations/month free
  - Minimal networking costs for HTTPS requests

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_ID}

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="exchange_api_key=your-fixer-io-api-key"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification
gcloud functions list --regions=${REGION}
gcloud secrets list
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check API enablement
   gcloud services list --enabled | grep -E "(cloudfunctions|secretmanager)"
   
   # Verify IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Secret access denied**:
   ```bash
   # Check service account permissions
   gcloud secrets get-iam-policy ${SECRET_NAME}
   
   # Grant access if needed
   gcloud secrets add-iam-policy-binding ${SECRET_NAME} \
       --member="serviceAccount:${PROJECT_ID}@appspot.gserviceaccount.com" \
       --role="roles/secretmanager.secretAccessor"
   ```

3. **Function returns errors**:
   ```bash
   # Check function logs
   gcloud functions logs read currency-converter --region=${REGION}
   
   # Test secret access
   gcloud secrets versions access latest --secret=${SECRET_NAME}
   ```

### Error Codes

| Error | Cause | Solution |
|-------|-------|----------|
| `403 Forbidden` | IAM permissions missing | Grant required roles to service account |
| `404 Not Found` | Function not deployed | Verify deployment completed successfully |
| `500 Internal Error` | API key invalid or quota exceeded | Check fixer.io API key and usage limits |
| `CORS Error` | Browser blocking request | Verify CORS headers in function response |

## Performance Tuning

### Memory Optimization

```bash
# Monitor memory usage
gcloud functions logs read currency-converter --region=${REGION} | grep "Memory"

# Adjust memory allocation (in terraform/variables.tf)
memory_mb = 128  # Reduce for simple operations
memory_mb = 512  # Increase for complex processing
```

### Timeout Configuration

```bash
# Monitor execution time
gcloud functions logs read currency-converter --region=${REGION} | grep "Duration"

# Adjust timeout (in terraform/variables.tf)
timeout_seconds = 30   # Reduce for faster operations
timeout_seconds = 120  # Increase for complex processing
```

## Extensions & Enhancements

Consider these enhancements for production use:

1. **Caching Layer**: Add Cloud Memorystore Redis for response caching
2. **Rate Limiting**: Implement per-client rate limiting with Firestore
3. **Multiple Providers**: Add failover to multiple exchange rate APIs
4. **Analytics**: Store conversion history in BigQuery
5. **Authentication**: Add API key authentication for client identification
6. **Regional Deployment**: Deploy functions in multiple regions for lower latency

## Support & Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Secret Manager Best Practices](https://cloud.google.com/secret-manager/docs/best-practices)
- [Infrastructure Manager Guide](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## License

This infrastructure code is provided as-is for educational and development purposes. Ensure compliance with your organization's policies and the terms of service for external APIs used.