# Infrastructure as Code for Weather API with Cloud Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather API with Cloud Functions and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate permissions for resource creation:
  - Cloud Functions Admin
  - Storage Admin
  - Service Account Admin
  - Project IAM Admin
- OpenWeatherMap API key (or similar weather service API key)
- For Terraform: Terraform CLI installed (>= 1.0)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's managed service for deploying and managing infrastructure using infrastructure as code.

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/weather-api \
    --service-account=projects/PROJECT_ID/serviceAccounts/SERVICE_ACCOUNT@PROJECT_ID.iam.gserviceaccount.com \
    --git-source-repo=https://github.com/your-org/your-repo.git \
    --git-source-directory=gcp/weather-api-functions-storage/code/infrastructure-manager \
    --git-source-ref=main \
    --input-values=project_id=PROJECT_ID,region=REGION,weather_api_key=YOUR_API_KEY

# Monitor deployment
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/weather-api
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" \
                -var="region=us-central1" \
                -var="weather_api_key=YOUR_API_KEY"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" \
                 -var="region=us-central1" \
                 -var="weather_api_key=YOUR_API_KEY"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WEATHER_API_KEY="your-api-key"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Configuration Options

### Infrastructure Manager Variables

Configure your deployment by modifying the input values:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `weather_api_key`: API key for weather service
- `function_name`: Cloud Function name (default: weather-api)
- `bucket_name_suffix`: Suffix for storage bucket name
- `function_memory`: Memory allocation for function (default: 256Mi)
- `function_timeout`: Function timeout in seconds (default: 60s)

### Terraform Variables

Customize your deployment using terraform.tfvars or command-line variables:

```hcl
project_id = "your-project-id"
region = "us-central1"
weather_api_key = "your-weather-api-key"
function_name = "weather-api"
bucket_name_suffix = "cache"
function_memory = 256
function_timeout = 60
max_instances = 10
min_instances = 0
```

### Bash Script Environment Variables

Set these environment variables before running the deployment script:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WEATHER_API_KEY="your-api-key"
export FUNCTION_NAME="weather-api"  # Optional
export BUCKET_NAME_SUFFIX="cache"   # Optional
```

## Architecture Overview

The infrastructure creates:

1. **Cloud Storage Bucket**: Stores cached weather data with lifecycle policies
2. **Cloud Function**: Serverless HTTP endpoint for weather API
3. **IAM Service Account**: Secure access between Cloud Function and Storage
4. **IAM Bindings**: Least-privilege permissions for function execution

## Post-Deployment Validation

After deployment, validate your infrastructure:

```bash
# Test the weather API endpoint
FUNCTION_URL=$(gcloud functions describe weather-api --region=us-central1 --format="value(httpsTrigger.url)")
curl "${FUNCTION_URL}?city=London"

# Check storage bucket
gsutil ls gs://weather-cache-*/

# View function logs
gcloud functions logs read weather-api --region=us-central1 --limit=10
```

## Monitoring and Observability

Access monitoring through Google Cloud Console:

- **Cloud Functions**: Monitor invocations, duration, and errors
- **Cloud Storage**: Track bucket usage and access patterns
- **Cloud Logging**: View detailed function execution logs
- **Cloud Monitoring**: Set up custom metrics and alerts

## Security Considerations

The infrastructure implements security best practices:

- Service account with minimal required permissions
- HTTPS-only function endpoints
- CORS configuration for web applications
- Environment variable management for API keys
- Storage bucket with appropriate access controls

## Cost Optimization

This deployment is designed for cost efficiency:

- Cloud Functions: Pay-per-invocation with generous free tier
- Cloud Storage: Standard storage class with lifecycle management
- Intelligent caching reduces external API calls
- Auto-scaling from zero to minimize idle costs

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/weather-api

# Verify deletion
gcloud infra-manager deployments list --project=PROJECT_ID
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID" \
                   -var="region=us-central1" \
                   -var="weather_api_key=YOUR_API_KEY"

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completed
./scripts/verify-cleanup.sh
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify Cloud Functions API is enabled
   - Check service account permissions
   - Ensure Python runtime version is supported

2. **Storage bucket access denied**:
   - Verify IAM bindings are correct
   - Check bucket name uniqueness
   - Ensure service account has Storage Object Admin role

3. **API key issues**:
   - Verify weather API key is valid
   - Check API key permissions and quotas
   - Ensure environment variable is set correctly

### Debugging Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com OR name:storage.googleapis.com"

# Verify service account
gcloud iam service-accounts describe FUNCTION_SA_EMAIL

# Check function environment variables
gcloud functions describe weather-api --region=us-central1 --format="value(environmentVariables)"

# Test storage access
gsutil ls -p PROJECT_ID
```

## Customization

### Adding Features

To extend the infrastructure:

1. **Add authentication**: Implement Cloud Identity-Aware Proxy
2. **Enhanced monitoring**: Add custom Cloud Monitoring metrics
3. **Multi-region deployment**: Deploy functions across multiple regions
4. **API management**: Integrate with Cloud Endpoints or API Gateway

### Performance Tuning

Optimize for your use case:

- Adjust function memory allocation based on usage patterns
- Modify cache duration in function code
- Implement regional storage buckets for global deployments
- Configure Cloud CDN for additional caching layers

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud Functions documentation
3. Consult Google Cloud Storage best practices
4. Reference Terraform Google Cloud provider documentation

## Version Information

- Infrastructure Manager: Compatible with latest Google Cloud config service
- Terraform: Requires >= 1.0, uses Google Cloud provider >= 4.0
- Google Cloud CLI: Requires latest version for full compatibility
- Python Runtime: Cloud Functions Gen2 with Python 3.12

## Additional Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Weather API Recipe](../weather-api-functions-storage.md)