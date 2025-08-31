# Infrastructure as Code for Weather API Service with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather API Service with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Required APIs enabled:
  - Cloud Functions API
  - Cloud Storage API
  - Cloud Build API
  - Infrastructure Manager API (for Infrastructure Manager deployment)
- Appropriate IAM permissions:
  - Cloud Functions Developer
  - Storage Admin
  - Project Editor (or custom role with required permissions)
- OpenWeatherMap API key (optional - demo mode available)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses standard Terraform configuration.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-api-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Check deployment status
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-api-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

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
export OPENWEATHER_API_KEY="your-api-key-here"  # Optional

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
gcloud functions list --regions=${REGION}
gsutil ls
```

## Configuration Options

### Infrastructure Manager Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "weather-api"
bucket_name_suffix = "unique-suffix"
openweather_api_key = "your-api-key"  # Optional
memory_mb = 256
timeout_seconds = 60
```

### Terraform Variables

Available variables in `variables.tf`:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_name`: Cloud Function name (default: weather-api)
- `bucket_name_suffix`: Unique suffix for storage bucket
- `openweather_api_key`: OpenWeatherMap API key (optional)
- `memory_mb`: Function memory allocation (default: 256)
- `timeout_seconds`: Function timeout (default: 60)

### Bash Script Environment Variables

Set these variables before running deployment scripts:

```bash
export PROJECT_ID="your-project-id"           # Required
export REGION="us-central1"                   # Optional (default: us-central1)
export FUNCTION_NAME="weather-api"            # Optional (default: weather-api)
export OPENWEATHER_API_KEY="your-api-key"    # Optional (uses demo mode if not set)
```

## Testing Your Deployment

After successful deployment, test the weather API:

```bash
# Get function URL (Terraform and Infrastructure Manager)
FUNCTION_URL=$(terraform output -raw function_url)
# OR
FUNCTION_URL=$(gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-api-deployment \
    --format="value(serviceConfig.uri)")

# Test the API
curl "${FUNCTION_URL}?city=London" | jq '.'

# Test caching behavior
curl "${FUNCTION_URL}?city=Paris" | jq '.'
curl "${FUNCTION_URL}?city=Paris" | jq '.cached'  # Should return true on second call
```

Expected response:
```json
{
  "city": "London",
  "temperature": 20,
  "description": "clear sky",
  "humidity": 65,
  "pressure": 1013,
  "wind_speed": 3.5,
  "cached": false,
  "timestamp": "2025-01-23T10:30:00.123456"
}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/weather-api-deployment \
    --delete-policy="DELETE"

# Verify cleanup
gcloud functions list --regions=${REGION}
gsutil ls | grep weather-cache
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completed
echo "Checking for remaining resources..."
gcloud functions list --regions=${REGION}
gsutil ls | grep weather-cache
```

## Customization

### Adding Weather Providers

To extend the solution with additional weather APIs, modify the function source code in each implementation:

1. **Infrastructure Manager/Terraform**: Update the `main.py` inline source code
2. **Bash Scripts**: Modify the function source during deployment

Example customization for multiple providers:

```python
# Add to main.py
BACKUP_PROVIDERS = [
    {"name": "weatherapi", "url": "https://api.weatherapi.com/v1/current.json"},
    {"name": "openweather", "url": "https://api.openweathermap.org/data/2.5/weather"}
]
```

### Scaling Configuration

For production workloads, consider these adjustments:

```hcl
# In terraform.tfvars or variables
memory_mb = 512          # Increased memory for better performance
timeout_seconds = 120    # Longer timeout for external API calls
min_instances = 1        # Keep warm instances to reduce cold starts
max_instances = 100      # Allow higher concurrency
```

### Security Enhancements

1. **API Key Management**: Use Google Secret Manager instead of environment variables
2. **VPC Connector**: Deploy function in private VPC for enhanced security
3. **IAM Restrictions**: Create custom service accounts with minimal permissions
4. **Audit Logging**: Enable Cloud Audit Logs for compliance

## Architecture Overview

The deployed infrastructure includes:

- **Cloud Function**: Serverless HTTP function handling weather API requests
- **Cloud Storage Bucket**: Caching layer for weather data with lifecycle policies
- **IAM Roles**: Service account with minimal required permissions
- **Function Source**: Python code with dependencies managed automatically

## Monitoring and Observability

Monitor your deployment using these Google Cloud services:

```bash
# View function logs
gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}

# Monitor function metrics
gcloud monitoring metrics list --filter="resource.type=cloud_function"

# Check storage usage
gsutil du -sh gs://weather-cache-*
```

## Cost Optimization

This solution is designed for cost efficiency:

- **Cloud Functions**: 2M invocations/month free tier
- **Cloud Storage**: 5GB free storage and lifecycle policies for automatic cleanup
- **No Always-On Resources**: Zero cost when not in use
- **Caching**: Reduces external API calls and improves response times

Estimated monthly costs for 10,000 requests: $0.00-$0.40 (within free tier limits)

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Check current user permissions
   gcloud auth list
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

3. **Function Not Responding**:
   ```bash
   # Check function status
   gcloud functions describe ${FUNCTION_NAME} --region=${REGION}
   
   # View recent logs
   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION} --limit=50
   ```

4. **Storage Access Issues**:
   ```bash
   # Verify bucket exists and permissions
   gsutil ls -L gs://weather-cache-*
   gsutil iam get gs://weather-cache-*
   ```

### Getting Help

- Review function logs in Cloud Console
- Check Google Cloud Status page for service issues
- Refer to the original recipe documentation
- Consult Google Cloud Functions documentation

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation for [Cloud Functions](https://cloud.google.com/functions/docs)
3. Refer to the original recipe: `weather-api-service-functions.md`
4. Check Google Cloud community forums and Stack Overflow

## Version Information

- **Recipe Version**: 1.1
- **Terraform Google Provider**: ~> 5.0
- **Python Runtime**: 3.12
- **Functions Framework**: 3.8.1
- **Last Updated**: 2025-07-12