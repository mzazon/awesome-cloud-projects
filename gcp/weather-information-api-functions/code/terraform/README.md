# Weather Information API - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying the Weather Information API using Google Cloud Functions.

## Architecture Overview

The Terraform configuration deploys:

- **Cloud Function**: HTTP-triggered serverless function for weather API
- **Cloud Storage**: Bucket for function source code storage
- **Service Account**: Dedicated IAM service account with minimal permissions
- **Monitoring**: Uptime checks and error rate alerting
- **Logging**: Centralized logging configuration
- **APIs**: Enables required Google Cloud APIs automatically

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) >= 400.0.0
- Active Google Cloud project with billing enabled

### Required Permissions

Your Google Cloud account needs the following IAM roles:

```bash
roles/owner
# OR the following specific roles:
roles/cloudfunctions.admin
roles/storage.admin
roles/iam.serviceAccountAdmin
roles/serviceusage.serviceUsageAdmin
roles/monitoring.admin
roles/logging.admin
```

### API Key Setup (Optional)

1. Get a free API key from [OpenWeatherMap](https://openweathermap.org/api)
2. Sign up for a free account
3. Generate an API key in your account dashboard
4. Configure the key in your `terraform.tfvars` file

> **Note**: The function works with demo data if no API key is provided

## Quick Start

### 1. Configure Authentication

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your default project
gcloud config set project YOUR_PROJECT_ID
```

### 2. Prepare Configuration

```bash
# Clone or navigate to the terraform directory
cd ./gcp/weather-information-api-functions/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your settings
nano terraform.tfvars
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Test the Deployment

```bash
# Get the function URL from Terraform output
export FUNCTION_URL=$(terraform output -raw function_url)

# Test the weather API
curl "$FUNCTION_URL?city=London"

# Test error handling
curl "$FUNCTION_URL"
```

## Configuration Options

### Required Variables

```hcl
project_id = "your-gcp-project-id"  # Your Google Cloud project ID
```

### Common Variables

```hcl
# Function configuration
function_name    = "weather-api"        # Name of the Cloud Function
function_runtime = "python312"          # Python runtime version
function_memory  = 256                  # Memory allocation (MB)
function_timeout = 60                   # Function timeout (seconds)

# Weather API
weather_api_key = "your-api-key"        # OpenWeatherMap API key (optional)

# Security
enable_public_access = true             # Allow unauthenticated access
cors_origins        = ["*"]             # CORS allowed origins

# Labels
labels = {
  environment = "development"
  project     = "weather-api"
  managed-by  = "terraform"
}
```

### Security Configuration

For production deployments, consider these security settings:

```hcl
# Restrict public access
enable_public_access = false

# Limit CORS origins
cors_origins = ["https://yourdomain.com", "https://app.yourdomain.com"]

# Use internal-only ingress
ingress_settings = "ALLOW_INTERNAL_ONLY"

# Connect to VPC
vpc_connector = "projects/your-project/locations/us-central1/connectors/your-connector"
```

## Resource Management

### Viewing Resources

```bash
# List all created resources
terraform state list

# Show specific resource details
terraform show google_cloudfunctions_function.weather_api

# View all outputs
terraform output
```

### Updating Configuration

```bash
# Modify terraform.tfvars or *.tf files
# Then apply changes
terraform plan
terraform apply
```

### Scaling Configuration

The function automatically scales based on demand. You can configure limits:

```hcl
function_max_instances = 1000    # Maximum concurrent instances
function_memory       = 512     # Increase for better performance
```

## Monitoring and Logging

### View Function Logs

```bash
# Using gcloud CLI
gcloud functions logs read weather-api --region=us-central1

# Using Google Cloud Console
# Navigate to Cloud Functions > weather-api > Logs
```

### Monitor Function Performance

```bash
# Get monitoring URLs from Terraform output
terraform output documentation_links
```

### Uptime Monitoring

The configuration includes:

- **Uptime Check**: Monitors function availability every 5 minutes
- **Error Rate Alert**: Alerts when error rate exceeds 10%
- **Log Sink**: Stores function logs in Cloud Storage

## Cost Management

### Estimated Costs

Google Cloud Functions pricing (as of 2024):

- **Invocations**: First 2M per month free, then $0.40 per 1M invocations
- **Compute Time**: First 400K GB-seconds free, then $0.0000025 per GB-second
- **Network**: Outbound data charges may apply

### Cost Optimization

```hcl
# Reduce memory for simple operations
function_memory = 128

# Reduce timeout for quick responses
function_timeout = 30

# Limit concurrent instances
function_max_instances = 100
```

## Troubleshooting

### Common Issues

#### Authentication Errors

```bash
# Re-authenticate if needed
gcloud auth application-default login
```

#### API Not Enabled

```bash
# Check enabled APIs
gcloud services list --enabled

# Enable required APIs manually
gcloud services enable cloudfunctions.googleapis.com
```

#### Function Deployment Fails

```bash
# Check function logs
gcloud functions logs read weather-api --region=us-central1

# Verify source archive
terraform apply -target=google_storage_bucket_object.function_source
```

#### Permission Errors

```bash
# Check current permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID

# Verify service account permissions
gcloud iam service-accounts get-iam-policy weather-api-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

### Debug Mode

Enable detailed logging:

```hcl
log_level = "DEBUG"
```

Then redeploy:

```bash
terraform apply -var="log_level=DEBUG"
```

## Testing

### Basic Functionality

```bash
# Test successful request
curl "$FUNCTION_URL?city=London"

# Test error handling
curl "$FUNCTION_URL"
curl "$FUNCTION_URL?city="

# Test CORS headers
curl -H "Origin: https://example.com" "$FUNCTION_URL?city=Paris"
```

### Load Testing

```bash
# Simple load test with Apache Bench
ab -n 1000 -c 10 "$FUNCTION_URL?city=London"

# Or use wrk for more advanced testing
wrk -t10 -c100 -d30s "$FUNCTION_URL?city=London"
```

### Integration Testing

```bash
# Test with different cities
cities=("London" "New York" "Tokyo" "Sydney" "Mumbai")
for city in "${cities[@]}"; do
  echo "Testing $city..."
  curl -s "$FUNCTION_URL?city=$city" | jq '.city, .temperature'
done
```

## Security Best Practices

### Production Checklist

- [ ] Use a dedicated service account with minimal permissions
- [ ] Configure specific CORS origins (not "*")
- [ ] Set up VPC connector for internal communication
- [ ] Enable audit logging
- [ ] Use Secret Manager for API keys
- [ ] Implement rate limiting
- [ ] Set up monitoring and alerting
- [ ] Regular security scanning

### Secret Management

For production, use Google Secret Manager:

```hcl
# Create secret in Secret Manager first
resource "google_secret_manager_secret" "weather_api_key" {
  secret_id = "weather-api-key"
  
  replication {
    automatic = true
  }
}

# Reference in function environment
environment_variables = {
  WEATHER_API_KEY = "projects/${var.project_id}/secrets/weather-api-key/versions/latest"
}
```

## Cleanup

### Remove All Resources

```bash
# Destroy all Terraform-managed resources
terraform destroy

# Confirm the destruction
# Type 'yes' when prompted
```

### Selective Cleanup

```bash
# Remove specific resources
terraform destroy -target=google_cloudfunctions_function.weather_api
```

### Clean Up Local Files

```bash
# Remove Terraform state and temp files
rm -rf .terraform
rm terraform.tfstate*
rm weather-function-source.zip
```

## Advanced Configuration

### Custom Domain

To use a custom domain with your function:

1. Set up Firebase Hosting or Cloud Load Balancer
2. Configure SSL certificates
3. Route traffic to your function URL

### Multiple Environments

Create environment-specific variable files:

```bash
# Development
terraform.tfvars.dev

# Staging  
terraform.tfvars.staging

# Production
terraform.tfvars.prod
```

Deploy with specific configurations:

```bash
terraform apply -var-file="terraform.tfvars.prod"
```

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy Weather API
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Init
        run: terraform init
      - name: Terraform Apply
        run: terraform apply -auto-approve
        env:
          GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_SA_KEY }}
```

## Support and Documentation

### Terraform Resources

- [Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Functions Resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloudfunctions_function)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

### Google Cloud Documentation

- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Functions Python Runtime](https://cloud.google.com/functions/docs/concepts/python-runtime)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)

### OpenWeatherMap API

- [API Documentation](https://openweathermap.org/api)
- [Weather API Guide](https://openweathermap.org/guide)
- [API Key Management](https://home.openweathermap.org/api_keys)

## Contributing

When contributing to this Terraform configuration:

1. Follow [Terraform style conventions](https://www.terraform.io/docs/language/syntax/style.html)
2. Add comments for complex configurations
3. Update documentation for new variables
4. Test changes with `terraform plan`
5. Validate with `terraform validate`

## License

This infrastructure code is provided as-is for educational and development purposes.