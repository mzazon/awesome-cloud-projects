# Weather API Service with Cloud Functions - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless weather API service on Google Cloud Platform using Cloud Functions and Cloud Storage.

## Architecture Overview

The infrastructure creates:
- **Cloud Function (Gen 2)**: Serverless HTTP endpoint for weather API
- **Cloud Storage Bucket**: Intelligent caching layer for weather data
- **Service Account**: Secure identity for function execution
- **IAM Policies**: Least-privilege access controls
- **Monitoring & Logging**: Optional observability components

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK**: Install and configure `gcloud` CLI
   ```bash
   # Install Google Cloud SDK
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Initialize and authenticate
   gcloud init
   gcloud auth application-default login
   ```

2. **Terraform**: Version 1.0 or higher
   ```bash
   # Install Terraform (macOS with Homebrew)
   brew install terraform
   
   # Verify installation
   terraform version
   ```

3. **GCP Project**: Active project with billing enabled
   ```bash
   # Create a new project (optional)
   gcloud projects create your-weather-api-project
   
   # Set as default project
   gcloud config set project your-weather-api-project
   
   # Enable billing (required for Cloud Functions)
   # This must be done through the GCP Console
   ```

4. **Required APIs**: Will be automatically enabled by Terraform
   - Cloud Functions API
   - Cloud Storage API
   - Cloud Build API
   - Cloud Run API (required for Cloud Functions Gen 2)

5. **OpenWeatherMap API Key** (Optional): Free account at [openweathermap.org](https://openweathermap.org/api)

## Quick Start

### 1. Clone and Initialize

```bash
# Navigate to the terraform directory
cd gcp/weather-api-service-functions/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required Variables
project_id = "your-gcp-project-id"

# Optional Variables (with defaults shown)
region             = "us-central1"
function_name      = "weather-api"
function_memory    = 256
function_timeout   = 60
function_runtime   = "python312"

# Storage Configuration
bucket_name_prefix   = "weather-cache"
bucket_storage_class = "STANDARD"
cache_lifecycle_days = 1

# API Configuration (leave empty for demo mode)
openweather_api_key    = ""  # Add your API key here
enable_cors            = true
allow_unauthenticated  = true

# Resource Labels
labels = {
  environment = "development"
  application = "weather-api"
  managed-by  = "terraform"
}
```

### 3. Plan and Deploy

```bash
# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply

# Confirm deployment when prompted
# Type: yes
```

### 4. Test the Deployment

After successful deployment, test your weather API:

```bash
# Get the function URL from outputs
FUNCTION_URL=$(terraform output -raw function_url)

# Test the API
curl "${FUNCTION_URL}?city=London" | jq '.'

# Test with different cities
curl "${FUNCTION_URL}?city=Paris" | jq '.'
curl "${FUNCTION_URL}?city=Tokyo" | jq '.'
```

Expected response format:
```json
{
  "city": "London",
  "country": "GB",
  "temperature": {
    "current": 15.2,
    "feels_like": 14.8,
    "unit": "celsius"
  },
  "weather": {
    "main": "Clear",
    "description": "clear sky",
    "icon": "01d"
  },
  "humidity": 65,
  "pressure": 1013,
  "wind": {
    "speed": 3.5,
    "direction": 180
  },
  "data_source": "live_api",
  "cached": false,
  "timestamp": "2025-07-12T10:30:00.123456",
  "api_version": "2.0"
}
```

## Configuration Options

### Core Infrastructure Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP Project ID | - | Yes |
| `region` | GCP Region | `us-central1` | No |

### Function Configuration

| Variable | Description | Default | Validation |
|----------|-------------|---------|------------|
| `function_name` | Cloud Function name | `weather-api` | Must match pattern |
| `function_memory` | Memory allocation (MB) | `256` | 128-8192 MB |
| `function_timeout` | Timeout (seconds) | `60` | 1-540 seconds |
| `function_runtime` | Python runtime version | `python312` | Supported runtimes |

### Storage Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `bucket_storage_class` | Storage class | `STANDARD` | STANDARD, NEARLINE, COLDLINE, ARCHIVE |
| `cache_lifecycle_days` | Auto-delete cache after N days | `1` | 1-365 days |

### API Configuration

| Variable | Description | Default | Notes |
|----------|-------------|---------|-------|
| `openweather_api_key` | OpenWeatherMap API key | `""` | Leave empty for demo mode |
| `enable_cors` | Enable CORS headers | `true` | Required for web apps |
| `allow_unauthenticated` | Allow public access | `true` | Set false for private APIs |

## Production Deployment

For production environments, consider these additional configurations:

### 1. Enhanced Security

```hcl
# terraform.tfvars
allow_unauthenticated = false
enable_cors          = false

labels = {
  environment = "production"
  application = "weather-api"
  managed-by  = "terraform"
  team        = "platform"
}
```

### 2. Performance Optimization

```hcl
# terraform.tfvars
function_memory         = 512
function_timeout        = 30
bucket_storage_class    = "STANDARD"
cache_lifecycle_days    = 7
```

### 3. Monitoring and Alerting

```hcl
# terraform.tfvars
enable_function_logs = true
log_level           = "INFO"
```

## Monitoring and Observability

### Cloud Functions Metrics

Monitor your weather API through Google Cloud Console:

```bash
# View function metrics
gcloud functions describe weather-api --region=us-central1

# View function logs
gcloud functions logs read weather-api --region=us-central1

# Monitor function performance
gcloud logging read "resource.type=cloud_function resource.labels.function_name=weather-api"
```

### Storage Usage

```bash
# Check bucket contents
gsutil ls gs://your-bucket-name/

# Monitor storage usage
gsutil du -s gs://your-bucket-name/
```

### Cost Monitoring

Track costs through Cloud Billing:
- Cloud Functions: $0.40 per million invocations (after free tier)
- Cloud Storage: $0.020 per GB/month
- Network Egress: Various rates by destination

## Troubleshooting

### Common Issues

1. **Function Not Accessible**
   ```bash
   # Check IAM permissions
   gcloud functions get-iam-policy weather-api --region=us-central1
   
   # Verify function status
   gcloud functions describe weather-api --region=us-central1
   ```

2. **Cache Not Working**
   ```bash
   # Check bucket permissions
   gsutil iam get gs://your-bucket-name/
   
   # Verify service account has access
   gcloud projects get-iam-policy your-project-id
   ```

3. **API Rate Limits**
   - Free tier: 60 calls/minute, 1000 calls/day
   - Upgrade to paid plan for higher limits

### Debug Mode

Enable detailed logging:

```bash
# Deploy with debug logging
terraform apply -var="log_level=DEBUG"

# View detailed logs
gcloud functions logs read weather-api --region=us-central1
```

## Cleanup

### Destroy Infrastructure

```bash
# Review resources to be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
# Type: yes
```

### Manual Cleanup (if needed)

```bash
# Delete function
gcloud functions delete weather-api --region=us-central1

# Delete storage bucket
gsutil rm -r gs://your-bucket-name/

# Delete service account
gcloud iam service-accounts delete weather-api-sa@your-project-id.iam.gserviceaccount.com
```

## Advanced Configuration

### Custom Domain Setup

To use a custom domain with your weather API:

1. Set up Cloud Load Balancer
2. Configure SSL certificate
3. Point domain to load balancer
4. Update CORS settings if needed

### API Authentication

For authenticated access:

```hcl
# terraform.tfvars
allow_unauthenticated = false
```

Then use service account keys or OAuth tokens:

```bash
# Test with authentication
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     "${FUNCTION_URL}?city=London"
```

### Multi-Region Deployment

Deploy to multiple regions for global coverage:

```bash
# Deploy to additional regions
terraform apply -var="region=europe-west1"
terraform apply -var="region=asia-east1"
```

## Integration Examples

### JavaScript/Web Application

```javascript
// Fetch weather data
async function getWeather(city) {
  try {
    const response = await fetch(`${FUNCTION_URL}?city=${encodeURIComponent(city)}`);
    const data = await response.json();
    return data;
  } catch (error) {
    console.error('Weather API error:', error);
    throw error;
  }
}
```

### Python Application

```python
import requests

def get_weather(city, function_url):
    """Fetch weather data from the deployed API."""
    try:
        response = requests.get(f"{function_url}?city={city}")
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Weather API error: {e}")
        raise
```

## Support and Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Google Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [OpenWeatherMap API Documentation](https://openweathermap.org/api)

## License

This infrastructure code is provided as part of the Weather API Service recipe and follows the same licensing terms as the parent project.