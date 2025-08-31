# Infrastructure as Code for Website Status Monitor with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Website Status Monitor with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (cloudfunctions.invoker, cloudfunctions.developer)
  - Cloud Build (cloudbuild.builds.editor)
  - Service Usage (serviceusage.serviceUsageAdmin)
  - IAM (iam.serviceAccountUser)
- For Terraform: Terraform CLI v1.0+ installed
- For Infrastructure Manager: Infrastructure Manager API enabled

## Quick Start

### Using Infrastructure Manager (Google Cloud)

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses Terraform-compatible syntax.

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/website-monitor \
    --service-account=projects/PROJECT_ID/serviceAccounts/SERVICE_ACCOUNT_EMAIL \
    --local-source="infrastructure-manager/"

# Check deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/website-monitor
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
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

# Test the deployed function
curl "$(gcloud functions describe website-status-monitor --region=${REGION} --format='value(httpsTrigger.url)')?url=https://www.google.com"
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:
- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region (default: us-central1)
- `function_name`: Cloud Function name (default: website-status-monitor)
- `function_memory`: Memory allocation (default: 256MB)
- `function_timeout`: Function timeout (default: 30s)

### Terraform Variables

Available variables in `terraform/variables.tf`:
- `project_id`: Your Google Cloud Project ID (required)
- `region`: Deployment region (default: us-central1)
- `function_name`: Cloud Function name (default: website-status-monitor)
- `function_memory`: Memory allocation in MB (default: 256)
- `function_timeout`: Function timeout in seconds (default: 30)
- `function_source_archive_bucket`: Bucket for function source code

Example terraform.tfvars file:
```hcl
project_id = "my-monitoring-project"
region     = "us-west2"
function_name = "custom-website-monitor"
function_memory = 512
```

### Environment Variables for Scripts

Required environment variables for bash scripts:
```bash
export PROJECT_ID="your-project-id"        # Required
export REGION="us-central1"                # Optional, defaults to us-central1
export FUNCTION_NAME="website-status-monitor"  # Optional
```

## Deployment Details

### What Gets Created

All implementations create the following Google Cloud resources:
- Cloud Function (HTTP trigger, Python 3.12 runtime)
- IAM bindings for function invocation
- Cloud Build trigger for function deployment
- Service account for function execution
- Required API enablements (Cloud Functions, Cloud Build, Logging)

### Function Features

The deployed Cloud Function provides:
- HTTP endpoint for website status monitoring
- Support for both GET and POST requests
- CORS headers for web application integration
- Comprehensive error handling and timeout management
- Structured JSON responses with detailed metrics
- Integration with Cloud Logging and Monitoring

### Security Configuration

- Function allows unauthenticated access for monitoring use cases
- Service account with minimal required permissions
- HTTPS-only endpoint with automatic SSL certificate management
- Input validation and sanitization for URL parameters
- Request timeout limits to prevent abuse

## Testing Your Deployment

After deployment, test the function with various scenarios:

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe website-status-monitor --region=${REGION} --format="value(httpsTrigger.url)")

# Test healthy website
curl "${FUNCTION_URL}?url=https://www.google.com" | jq .

# Test with POST request
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"url": "https://httpbin.org/status/200"}' | jq .

# Test error handling
curl "${FUNCTION_URL}?url=https://httpbin.org/status/500" | jq .

# Test timeout handling
curl "${FUNCTION_URL}?url=https://httpbin.org/delay/15" | jq .
```

## Monitoring and Observability

### View Function Logs

```bash
# View recent logs
gcloud functions logs read website-status-monitor --region=${REGION} --limit=50

# Follow logs in real-time
gcloud functions logs tail website-status-monitor --region=${REGION}
```

### Monitor Function Metrics

```bash
# View function metrics in Cloud Console
gcloud functions describe website-status-monitor --region=${REGION} --format="value(httpsTrigger.url)"
```

Access Cloud Monitoring dashboard: https://console.cloud.google.com/monitoring

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/website-monitor
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --regions=${REGION}
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Check current authentication
   gcloud auth list
   
   # Ensure proper IAM roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:$(gcloud config get-value account)" \
       --role="roles/cloudfunctions.developer"
   ```

2. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

3. **Function Deployment Timeout**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # View specific build logs
   gcloud builds log BUILD_ID
   ```

4. **Terraform State Issues**
   ```bash
   # Reset Terraform state (use carefully)
   terraform init -reconfigure
   ```

### Getting Help

- Function logs: `gcloud functions logs read website-status-monitor --region=${REGION}`
- Cloud Build logs: `gcloud builds list`
- Cloud Console: https://console.cloud.google.com/functions
- Terraform documentation: https://registry.terraform.io/providers/hashicorp/google/latest
- Infrastructure Manager documentation: https://cloud.google.com/infrastructure-manager/docs

## Cost Optimization

### Estimated Costs

- Cloud Functions: Free tier includes 2M invocations/month
- Cloud Build: Free tier includes 120 build-minutes/day
- Cloud Logging: Free tier includes 50 GB/month
- Typical monthly cost: $0.05-$0.20 for moderate usage

### Cost Management Tips

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Website Monitor Budget" \
    --budget-amount=10USD

# Monitor function costs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=website-status-monitor" \
    --limit=100 \
    --format="table(timestamp,resource.labels.function_name,labels.execution_id)"
```

## Customization Examples

### Adding Authentication

To add authentication to your function, modify the IAM bindings:

```bash
# Remove public access
gcloud functions remove-iam-policy-binding website-status-monitor \
    --region=${REGION} \
    --member="allUsers" \
    --role="roles/cloudfunctions.invoker"

# Add specific user access
gcloud functions add-iam-policy-binding website-status-monitor \
    --region=${REGION} \
    --member="user:example@gmail.com" \
    --role="roles/cloudfunctions.invoker"
```

### Scaling Configuration

Modify function concurrency and instance settings:

```bash
# Update function configuration
gcloud functions deploy website-status-monitor \
    --region=${REGION} \
    --max-instances=10 \
    --min-instances=1 \
    --memory=512MB \
    --timeout=60s
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation
4. Check Cloud Console for error messages and logs

## Version Information

- Infrastructure Manager: Compatible with latest Google Cloud APIs
- Terraform: Requires Google Cloud provider v4.0+
- Google Cloud SDK: Requires gcloud CLI v400.0+
- Function Runtime: Python 3.12