# Weather API Infrastructure with Terraform

This Terraform configuration deploys a complete serverless weather API solution on Google Cloud Platform using Cloud Functions and Cloud Storage for intelligent caching.

## Architecture Overview

The infrastructure includes:

- **Cloud Function**: Serverless weather API with Python 3.12 runtime
- **Cloud Storage**: Intelligent caching bucket with lifecycle management
- **Service Account**: Least-privilege IAM for security
- **Monitoring**: Cloud Monitoring alerts and logging
- **Storage Management**: Automated lifecycle policies for cost optimization

## Prerequisites

1. **Google Cloud Account**: Active GCP account with billing enabled
2. **Terraform**: Version 1.0 or later installed locally
3. **Google Cloud CLI**: Installed and authenticated (`gcloud auth login`)
4. **Project Permissions**: Owner or Editor role on target GCP project
5. **APIs Enabled**: The following APIs will be enabled automatically:
   - Cloud Functions API
   - Cloud Storage API
   - Cloud Build API
   - Cloud Run API
   - Artifact Registry API
   - Eventarc API

## Quick Start

### 1. Clone and Navigate

```bash
cd gcp/weather-api-functions-storage/code/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"

# Optional customizations
region            = "us-central1"
function_name     = "weather-api"
weather_api_key   = "your-openweathermap-api-key"  # or "demo_key" for testing
function_memory   = 256
function_timeout  = 60

# Labels for resource management
labels = {
  environment = "production"
  team        = "backend"
  cost-center = "engineering"
}
```

### 4. Plan and Apply

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Test the API

After deployment, test your weather API:

```bash
# Get the function URL from Terraform output
FUNCTION_URL=$(terraform output -raw function_url)

# Test with different cities
curl "${FUNCTION_URL}?city=London" | jq
curl "${FUNCTION_URL}?city=Tokyo" | jq
curl "${FUNCTION_URL}?city=Paris" | jq
```

## Configuration Options

### Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `project_id` | Google Cloud Project ID | string |

### Optional Variables

| Variable | Description | Default | Valid Values |
|----------|-------------|---------|--------------|
| `region` | GCP region for deployment | `us-central1` | Any valid GCP region |
| `function_name` | Name of the Cloud Function | `weather-api` | Valid function name |
| `weather_api_key` | External weather API key | `demo_key` | API key or `demo_key` |
| `function_memory` | Function memory in MB | `256` | 128, 256, 512, 1024, 2048, 4096, 8192 |
| `function_timeout` | Function timeout in seconds | `60` | 1-540 |
| `function_max_instances` | Maximum concurrent instances | `10` | 1-3000 |
| `function_min_instances` | Minimum warm instances | `0` | 0-1000 |
| `bucket_location` | Storage bucket location | `US` | Valid GCS location |
| `bucket_storage_class` | Storage class for bucket | `STANDARD` | STANDARD, NEARLINE, COLDLINE, ARCHIVE |
| `cache_duration_minutes` | Cache duration in minutes | `10` | 1-1440 |

### Advanced Configuration

```hcl
# Cost optimization settings
bucket_storage_class = "STANDARD"
cache_duration_minutes = 10

# Performance settings
function_memory = 512
function_max_instances = 50
function_min_instances = 1

# Security settings
labels = {
  environment = "production"
  security-level = "public"
  data-classification = "public"
}
```

## Outputs

The deployment provides comprehensive outputs:

| Output | Description |
|--------|-------------|
| `function_url` | HTTP endpoint for the weather API |
| `cache_bucket_name` | Name of the caching storage bucket |
| `function_service_account_email` | Service account email for the function |
| `monitoring_dashboard_url` | Direct link to monitoring dashboard |
| `logs_url` | Direct link to function logs |
| `api_examples` | Example API calls for testing |

## Features

### Intelligent Caching
- 10-minute default cache duration (configurable)
- Automatic cache expiration and cleanup
- Up to 90% reduction in external API calls
- Regional storage for improved performance

### Cost Optimization
- Pay-per-invocation serverless model
- Automatic lifecycle management (7-day retention)
- Storage class transitions (Standard → Nearline after 1 day)
- Configurable scaling parameters

### Security
- Least-privilege service account
- Uniform bucket-level access
- CORS configuration for web applications
- Structured logging and monitoring

### Monitoring & Observability
- Cloud Monitoring alerts for error rates
- Structured logging with Cloud Logging
- Performance metrics and dashboards
- Automated log exports to storage

## API Usage

### Endpoints

The deployed function provides a single HTTP endpoint:

```
GET https://[region]-[project-id].cloudfunctions.net/[function-name]?city=[city-name]
```

### Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `city` | Yes | Name of the city | `London`, `New York`, `Tokyo` |

### Response Format

```json
{
  "city": "London",
  "country": "GB",
  "temperature": 15.2,
  "feels_like": 14.1,
  "description": "scattered clouds",
  "humidity": 72,
  "pressure": 1013,
  "wind_speed": 3.5,
  "visibility": 10.0,
  "cached_at": "2025-01-15T10:30:00Z",
  "from_cache": false,
  "cache_status": "miss",
  "cache_duration_minutes": 10,
  "api_version": "1.0"
}
```

### Error Handling

The API provides structured error responses:

```json
{
  "error": "City not found",
  "message": "Please check the city name and try again",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

## Monitoring and Maintenance

### Health Checks

Monitor your deployment using these commands:

```bash
# Check function status
gcloud functions describe weather-api --region=us-central1

# View recent logs
gcloud functions logs read weather-api --limit=50

# Check bucket contents
gsutil ls gs://$(terraform output -raw cache_bucket_name)/
```

### Performance Optimization

1. **Monitor Cache Hit Rates**: Check logs for cache hit/miss ratios
2. **Adjust Cache Duration**: Increase `cache_duration_minutes` for stable weather
3. **Scale Configuration**: Modify `function_max_instances` based on traffic
4. **Storage Class**: Consider NEARLINE or COLDLINE for archival data

### Cost Management

- Review monthly costs in Google Cloud Console
- Adjust lifecycle policies based on usage patterns
- Monitor function invocation patterns
- Consider regional optimization for global deployments

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**
   ```bash
   # Check API enablement status
   gcloud services list --enabled
   
   # Verify permissions
   gcloud auth list
   ```

2. **External API Errors**
   ```bash
   # Test with demo key
   terraform apply -var="weather_api_key=demo_key"
   ```

3. **Storage Access Issues**
   ```bash
   # Check service account permissions
   gsutil iam get gs://$(terraform output -raw cache_bucket_name)
   ```

### Debug Logging

Enable detailed logging by setting the function environment variable:

```hcl
service_config {
  environment_variables = {
    LOG_LEVEL = "DEBUG"
  }
}
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all data in the storage bucket and cannot be undone.

## Security Considerations

1. **API Key Management**: Store production API keys in Secret Manager
2. **Access Control**: Consider implementing authentication for production use
3. **Network Security**: Use VPC Service Controls for sensitive deployments
4. **Data Privacy**: Review data residency requirements for your use case

## Support and Contributing

For issues with this Terraform configuration:

1. Check the [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
2. Review [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
3. Consult the original recipe documentation

## License

This infrastructure code is provided as part of the cloud recipes collection. See the main repository for license information.