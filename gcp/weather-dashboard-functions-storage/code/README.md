# Infrastructure as Code for Weather Dashboard with Cloud Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather Dashboard with Cloud Functions and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate permissions for resource creation:
  - Cloud Functions Developer
  - Storage Admin
  - Service Usage Admin
- OpenWeatherMap API key (free tier available at [openweathermap.org](https://openweathermap.org/api))

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WEATHER_API_KEY="your_openweathermap_api_key"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-dashboard \
    --service-account "projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source "infrastructure-manager/" \
    --inputs-file "infrastructure-manager/inputs.yaml"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"
export TF_VAR_weather_api_key="your_openweathermap_api_key"

# Plan and apply
terraform plan
terraform apply
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WEATHER_API_KEY="your_openweathermap_api_key"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure creates:

- **Cloud Function (Gen 2)**: Serverless function that fetches weather data from OpenWeatherMap API
- **Cloud Storage Bucket**: Hosts the static HTML dashboard with public read access
- **IAM Roles**: Proper service account permissions for function execution
- **Website Configuration**: Static website hosting configuration for the dashboard

The solution provides:
- Automatic scaling based on demand
- Pay-per-use pricing model
- Global content delivery through Cloud Storage
- CORS-enabled API for browser requests
- Responsive web interface with error handling

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment accepts these inputs in `infrastructure-manager/inputs.yaml`:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `weather_api_key`: Your OpenWeatherMap API key
- `function_name`: Name for the Cloud Function (default: weather-api)
- `bucket_name`: Name for the storage bucket (auto-generated if not specified)

### Terraform Variables

The Terraform configuration supports these variables in `terraform/variables.tf`:

- `project_id`: Your Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `weather_api_key`: Your OpenWeatherMap API key (required)
- `function_name`: Name for the Cloud Function (default: weather-api)
- `bucket_name`: Name for the storage bucket (optional, auto-generated)
- `function_memory`: Memory allocation for function (default: 256Mi)
- `function_timeout`: Function timeout in seconds (default: 60s)

### Script Configuration

The bash scripts use environment variables:

- `PROJECT_ID`: Your Google Cloud project ID (required)
- `REGION`: Deployment region (required)
- `WEATHER_API_KEY`: Your OpenWeatherMap API key (required)
- `FUNCTION_NAME`: Function name (optional, defaults to weather-api)
- `BUCKET_NAME`: Bucket name (optional, auto-generated)

## Outputs

After successful deployment, you'll receive:

- **Function URL**: HTTPS endpoint for the weather API
- **Website URL**: Public URL for the weather dashboard
- **Bucket Name**: Name of the created storage bucket
- **Function Name**: Name of the deployed Cloud Function

## Validation

After deployment, validate the infrastructure:

```bash
# Test the weather API function
curl "$(gcloud functions describe weather-api --region=us-central1 --format='value(serviceConfig.uri)')?city=London"

# Check website accessibility
BUCKET_NAME=$(gsutil ls -p ${PROJECT_ID} | grep weather-dashboard | sed 's/gs:\/\/\([^\/]*\)\/.*/\1/')
curl -I "https://storage.googleapis.com/${BUCKET_NAME}/index.html"

# Verify function logs
gcloud functions logs read weather-api --region=us-central1 --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-dashboard
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Cost Estimation

This solution uses Google Cloud's serverless pricing model:

- **Cloud Functions**: $0.0000004 per invocation + $0.0000025 per GB-second
- **Cloud Storage**: $0.020 per GB per month for Standard storage
- **Network Egress**: $0.12 per GB (first 1 GB free per month)

Expected monthly cost for moderate usage (1000 requests/month): $0.01 - $0.50

## Security Considerations

The infrastructure implements these security practices:

- **IAM Roles**: Function uses minimal required permissions
- **CORS Configuration**: Proper CORS headers for browser security
- **API Key Protection**: Weather API key stored as environment variable
- **Public Access**: Storage bucket configured for read-only public access
- **HTTPS Only**: All endpoints use HTTPS encryption

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**:
   - Verify Cloud Functions API is enabled
   - Check IAM permissions for deployment
   - Ensure function source code is valid

2. **Website Not Accessible**:
   - Verify bucket public access is configured
   - Check bucket website configuration
   - Ensure HTML files are uploaded correctly

3. **API Key Issues**:
   - Verify OpenWeatherMap API key is valid
   - Check API key quotas and limits
   - Ensure environment variable is set correctly

4. **CORS Errors**:
   - Verify function CORS headers are configured
   - Check browser console for specific errors
   - Test API endpoint directly with curl

### Debugging

```bash
# Check function status
gcloud functions describe weather-api --region=us-central1

# View function logs
gcloud functions logs read weather-api --region=us-central1

# Test bucket access
gsutil ls -b gs://your-bucket-name

# Verify bucket permissions
gsutil iam get gs://your-bucket-name
```

## Customization

### Adding Features

1. **Custom Domain**: Configure Cloud Load Balancer for custom domain
2. **Monitoring**: Add Cloud Monitoring alerts for function errors
3. **Caching**: Implement Redis cache for weather data
4. **Authentication**: Add user authentication with Firebase Auth
5. **Database**: Store weather history in Cloud Firestore

### Scaling Considerations

- **Function Concurrency**: Default limit is 1000 concurrent executions
- **Storage Bandwidth**: Standard storage provides high bandwidth
- **API Limits**: Monitor OpenWeatherMap API quotas
- **Cold Starts**: Consider min instances for frequently accessed functions

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify API quotas and billing settings
4. Consult Google Cloud support for service-specific issues

## Related Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Storage Static Website Hosting](https://cloud.google.com/storage/docs/hosting-static-website)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [OpenWeatherMap API Documentation](https://openweathermap.org/api)