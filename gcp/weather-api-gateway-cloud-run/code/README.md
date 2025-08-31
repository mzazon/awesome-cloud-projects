# Infrastructure as Code for Weather API Gateway with Cloud Run

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather API Gateway with Cloud Run and Cloud Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK installed and authenticated
- A Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Run Admin
  - Storage Admin
  - Service Account Admin
  - Project Editor (for enabling APIs)
- Docker installed (for local container testing)

## Architecture Overview

This implementation deploys:
- A Cloud Run service hosting a containerized weather API gateway
- A Cloud Storage bucket for caching weather data
- IAM service accounts and permissions for secure resource access
- Lifecycle policies for automatic cache cleanup

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/weather-gateway \
    --service-account="YOUR_SERVICE_ACCOUNT" \
    --git-source-repo="https://github.com/your-repo/weather-gateway" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/weather-gateway
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your project settings
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:
- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region (default: us-central1)
- `service_name`: Cloud Run service name
- `bucket_name_suffix`: Unique suffix for storage bucket

### Terraform Variables

Create a `terraform.tfvars` file or pass variables via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
service_name = "weather-api-gateway"
bucket_name_suffix = "unique-suffix"
memory_limit = "512Mi"
cpu_limit = "1"
max_instances = 10
timeout_seconds = 60
```

### Bash Script Configuration

The deployment script will prompt for:
- Project ID
- Region selection
- Service naming preferences
- Memory and CPU allocations

## Deployment Verification

After deployment, verify the setup:

```bash
# Get the Cloud Run service URL
SERVICE_URL=$(gcloud run services describe weather-api-gateway \
    --region=us-central1 \
    --format='value(status.url)')

# Test the health endpoint
curl "${SERVICE_URL}/health"

# Test the weather API
curl "${SERVICE_URL}/weather?city=London"

# Test caching (second request should be faster)
curl "${SERVICE_URL}/weather?city=London"
```

Expected responses:
- Health endpoint: `{"status": "healthy", "service": "weather-api-gateway"}`
- Weather endpoint: JSON with weather data and cache status

## Monitoring and Logging

### View Cloud Run Logs

```bash
# Stream logs from Cloud Run service
gcloud run services logs tail weather-api-gateway --region=us-central1

# View logs in Cloud Console
gcloud run services browse weather-api-gateway --region=us-central1
```

### Monitor Storage Usage

```bash
# Check bucket contents
gsutil ls gs://weather-cache-YOUR_SUFFIX/

# Monitor bucket size
gsutil du -s gs://weather-cache-YOUR_SUFFIX/
```

### Performance Metrics

Access detailed metrics in Google Cloud Console:
- Cloud Run → Services → weather-api-gateway → Metrics
- Cloud Storage → Browser → your-bucket → Monitoring

## Security Considerations

This implementation includes:
- Least privilege IAM permissions for Cloud Run service account
- Automatic HTTPS termination via Cloud Run
- Container isolation and security scanning
- Storage bucket with lifecycle policies for data retention
- No hardcoded credentials or API keys

## Cost Optimization

- Cloud Run scales to zero when not in use (pay-per-request)
- Cloud Storage lifecycle policies automatically delete old cache files
- Regional deployment reduces cross-region data transfer costs
- Memory and CPU limits prevent resource over-allocation

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   
   # Grant required permissions
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
       --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
       --role="roles/storage.objectAdmin"
   ```

2. **Container Build Failures**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # Enable required APIs
   gcloud services enable cloudbuild.googleapis.com
   ```

3. **Service Not Responding**
   ```bash
   # Check service status
   gcloud run services describe weather-api-gateway \
       --region=us-central1 \
       --format="table(status.conditions[].type,status.conditions[].status)"
   ```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
# For Terraform
export TF_LOG=DEBUG

# For gcloud commands
export CLOUDSDK_CORE_VERBOSITY=debug
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/weather-gateway
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify Cloud Run service is deleted
gcloud run services list --region=us-central1

# Verify storage bucket is deleted
gsutil ls -p YOUR_PROJECT_ID

# Check for any remaining resources
gcloud resources list --format="table(name,type,location)"
```

## Customization

### Extending the Weather API

To integrate with real weather services:

1. Add API key management using Secret Manager
2. Update the Python application to call external APIs
3. Implement more sophisticated caching strategies
4. Add rate limiting and authentication

### Multi-Region Deployment

Modify the Terraform configuration to deploy across multiple regions:

```hcl
variable "regions" {
  description = "List of regions for deployment"
  type        = list(string)
  default     = ["us-central1", "europe-west1", "asia-east1"]
}
```

### Advanced Monitoring

Add Cloud Monitoring and alerting:

```bash
# Create uptime check
gcloud monitoring uptime create-http-check \
    --display-name="Weather API Health Check" \
    --hostname="YOUR_SERVICE_URL" \
    --path="/health"
```

## Development Workflow

### Local Testing

```bash
# Build container locally
docker build -t weather-gateway .

# Run locally with environment variables
docker run -p 8080:8080 \
    -e BUCKET_NAME=your-test-bucket \
    -e GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
    weather-gateway
```

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy Weather Gateway
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: google-github-actions/setup-gcloud@v0
        with:
          service_account_key: ${{ secrets.GCP_SA_KEY }}
      - name: Deploy with Terraform
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

## Support and Documentation

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

For issues with this infrastructure code, refer to the original recipe documentation or file an issue in the repository.

## License

This infrastructure code is provided under the same license as the parent repository.