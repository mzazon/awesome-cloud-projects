# Infrastructure as Code for Unit Converter API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Unit Converter API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions Admin
  - Cloud Build Editor
  - Service Account User
  - Project IAM Admin (for service account creation)
- APIs enabled:
  - Cloud Functions API
  - Cloud Build API
  - Cloud Logging API

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="unit-converter-api"

# Create deployment
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --gcs-source="gs://your-bucket/infrastructure-manager/main.yaml" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# Get function URL
terraform output function_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the function URL upon successful deployment
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud Project ID (required)
- `region`: GCP region for deployment (default: us-central1)
- `function_name`: Name of the Cloud Function (default: unit-converter-api)
- `memory`: Memory allocation for function (default: 256MB)
- `timeout`: Function timeout in seconds (default: 60s)

### Terraform Variables

- `project_id`: Google Cloud Project ID (required)
- `region`: GCP region for deployment (default: us-central1)
- `function_name`: Name of the Cloud Function (default: unit-converter-api)
- `runtime`: Python runtime version (default: python312)
- `memory`: Memory allocation in MB (default: 256)
- `timeout`: Function timeout in seconds (default: 60)
- `allow_unauthenticated`: Allow public access (default: true)

### Bash Script Environment Variables

- `PROJECT_ID`: Google Cloud Project ID (required)
- `REGION`: GCP region for deployment (default: us-central1)
- `FUNCTION_NAME`: Name of the Cloud Function (default: unit-converter-api)

## Testing the Deployed API

After successful deployment, test the API endpoints:

```bash
# Get the function URL (from terraform output or deployment logs)
FUNCTION_URL="https://your-region-project-id.cloudfunctions.net/unit-converter-api"

# Test temperature conversion
curl -X GET "${FUNCTION_URL}?category=temperature&type=celsius_to_fahrenheit&value=25"

# Test with POST request
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "category": "distance",
      "type": "meters_to_feet",
      "value": 100
    }'

# Test error handling
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "category": "invalid_category",
      "type": "some_conversion",
      "value": 100
    }'
```

## Monitoring and Logging

### View Function Logs

```bash
# Using gcloud CLI
gcloud functions logs read unit-converter-api --region=us-central1

# View logs in Cloud Console
echo "https://console.cloud.google.com/functions/details/us-central1/unit-converter-api?project=${PROJECT_ID}&tab=logs"
```

### Monitor Function Metrics

```bash
# View function metrics in Cloud Console
echo "https://console.cloud.google.com/functions/details/us-central1/unit-converter-api?project=${PROJECT_ID}&tab=metrics"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Confirm deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Confirm all resources are deleted
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --region=${REGION}
```

## Architecture Components

This IaC deploys the following Google Cloud resources:

- **Cloud Function**: Serverless HTTP-triggered function with Python runtime
- **Cloud Function Source**: Zip archive containing the unit converter code
- **IAM Policy**: Public invoker permissions for unauthenticated access
- **Cloud Build**: Automatic building and deployment of function source
- **Cloud Logging**: Automatic log collection and retention

## Security Considerations

### Production Deployment

For production environments, consider these security enhancements:

1. **Remove Public Access**: Set `allow_unauthenticated` to `false`
2. **Implement Authentication**: Use Cloud IAM, API keys, or Firebase Auth
3. **Add Rate Limiting**: Implement request throttling
4. **Enable CORS Properly**: Configure specific origins instead of wildcard
5. **Monitor Usage**: Set up alerting for unusual traffic patterns

### IAM Permissions

The default deployment grants public access. For restricted access:

```bash
# Remove public access
gcloud functions remove-iam-policy-binding unit-converter-api \
    --region=us-central1 \
    --member="allUsers" \
    --role="roles/cloudfunctions.invoker"

# Grant specific user access
gcloud functions add-iam-policy-binding unit-converter-api \
    --region=us-central1 \
    --member="user:user@example.com" \
    --role="roles/cloudfunctions.invoker"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure Cloud Functions, Cloud Build, and Cloud Logging APIs are enabled
2. **Insufficient Permissions**: Verify IAM roles for deployment account
3. **Region Mismatch**: Ensure consistent region settings across all commands
4. **Source Code Issues**: Verify function source code is properly formatted
5. **Memory/Timeout**: Adjust function memory and timeout settings if needed

### Debug Deployment

```bash
# Check function status
gcloud functions describe unit-converter-api --region=us-central1

# View build logs
gcloud builds list --limit=5

# Test function locally (if using Functions Framework)
functions-framework --target=convert_units --debug
```

## Cost Optimization

### Monitoring Costs

- Use Cloud Billing alerts to monitor spending
- Review function invocation patterns in Cloud Monitoring
- Consider function memory and timeout optimization
- Monitor egress traffic costs

### Free Tier Limits

Google Cloud Functions includes generous free tier:
- 2 million invocations per month
- 400,000 GB-seconds of compute time
- 200,000 GHz-seconds of compute time

## Support

For issues with this infrastructure code:

1. Check the [Cloud Functions documentation](https://cloud.google.com/functions/docs)
2. Review the [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
3. Consult the [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. Refer to the original recipe documentation for implementation details

## Customization

### Extending the API

To add new conversion categories or types:

1. Modify the `main.py` source code
2. Update the CONVERSIONS dictionary with new formulas
3. Redeploy using your chosen IaC method
4. Test new endpoints with appropriate API calls

### Performance Tuning

Adjust these parameters based on your requirements:

- **Memory**: Increase for complex calculations (128MB - 8GB)
- **Timeout**: Extend for longer processing (1s - 540s)
- **Concurrency**: Configure max concurrent executions
- **Runtime**: Use latest Python version for performance improvements