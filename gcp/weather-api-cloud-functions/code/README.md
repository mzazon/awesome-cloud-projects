# Infrastructure as Code for Weather API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate permissions for Cloud Functions, Cloud Build, and Artifact Registry
- Python 3.13 runtime support in your target region

### Required APIs

The following APIs must be enabled in your Google Cloud project:

- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Artifact Registry API (`artifactregistry.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create weather-api-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-bucket/infrastructure-manager/main.yaml" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe weather-api-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Apply infrastructure
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

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

# The script will output the function URL upon successful deployment
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

- `PROJECT_ID`: Google Cloud project ID (required)
- `REGION`: Deployment region (default: us-central1)
- `FUNCTION_NAME`: Cloud Function name (default: auto-generated with random suffix)

### Infrastructure Manager Variables

When using Infrastructure Manager, you can customize the deployment with these input values:

```yaml
project_id: "your-project-id"
region: "us-central1"
function_name: "weather-api-custom"
memory_mb: 256
timeout_seconds: 60
min_instances: 0
max_instances: 100
```

### Terraform Variables

Customize your Terraform deployment by setting these variables:

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "function_name" {
  description = "Cloud Function name"
  type        = string
  default     = null  # Auto-generated if not provided
}

variable "memory_mb" {
  description = "Memory allocated to the function in MB"
  type        = number
  default     = 256
}

variable "timeout_seconds" {
  description = "Function timeout in seconds"
  type        = number
  default     = 60
}
```

## Testing the Deployment

After successful deployment, test the weather API:

```bash
# Get the function URL from outputs
export FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
    --region=${REGION} \
    --gen2 \
    --format="value(serviceConfig.uri)")

# Test with default city
curl -s "${FUNCTION_URL}" | jq .

# Test with specific city
curl -s "${FUNCTION_URL}?city=Tokyo" | jq .

# Expected response format:
{
  "city": "Tokyo",
  "temperature": 22,
  "condition": "Partly Cloudy",
  "humidity": 65,
  "wind_speed": 12,
  "description": "Current weather for Tokyo",
  "timestamp": "2025-07-23T10:00:00Z"
}
```

## Monitoring and Logging

### View Function Logs

```bash
# View recent logs
gcloud functions logs read ${FUNCTION_NAME} \
    --region=${REGION} \
    --gen2 \
    --limit=10

# Tail logs in real-time
gcloud functions logs tail ${FUNCTION_NAME} \
    --region=${REGION} \
    --gen2
```

### Monitor Function Metrics

```bash
# Get function description with monitoring info
gcloud functions describe ${FUNCTION_NAME} \
    --region=${REGION} \
    --gen2 \
    --format="table(name,state,updateTime,labels)"
```

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete the deployment
gcloud infra-manager deployments delete weather-api-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Clean up Terraform state files
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Customization

### Modifying Function Code

The function source code is embedded in the IaC templates. To modify the weather API logic:

1. **Infrastructure Manager**: Update the `source_archive_bucket` and `source_archive_object` in `main.yaml`
2. **Terraform**: Modify the `source_dir` in the `archive_file` data source
3. **Bash Scripts**: Edit the function code generation in `deploy.sh`

### Adding Environment Variables

To add environment variables to the Cloud Function:

**Infrastructure Manager:**
```yaml
environment_variables:
  WEATHER_API_KEY: "your-api-key"
  DEBUG_MODE: "false"
```

**Terraform:**
```hcl
environment_variables = {
  WEATHER_API_KEY = var.weather_api_key
  DEBUG_MODE      = "false"
}
```

### Configuring IAM Permissions

The implementations include minimal IAM permissions. To add custom roles:

**Infrastructure Manager:**
```yaml
- name: custom-invoker-binding
  type: gcp-types/cloudresourcemanager-v1:virtual.projects.iamMemberBinding
  properties:
    resource: ${PROJECT_ID}
    role: roles/cloudfunctions.invoker
    member: user:your-email@domain.com
```

**Terraform:**
```hcl
resource "google_cloudfunctions2_function_iam_member" "custom_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.weather_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "user:your-email@domain.com"
}
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your account has Cloud Functions Developer role
3. **Region Availability**: Check if Cloud Functions Gen2 is available in your selected region
4. **Build Failures**: Review Cloud Build logs for function deployment issues

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:cloudfunctions"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check function status
gcloud functions describe ${FUNCTION_NAME} \
    --region=${REGION} \
    --gen2 \
    --format="value(state)"
```

### Getting Help

- Review the original recipe documentation for context
- Check [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
- Use `gcloud functions deploy --help` for deployment options
- Monitor [Google Cloud Status](https://status.cloud.google.com/) for service issues

## Cost Optimization

### Free Tier Limits

Google Cloud Functions provides generous free tier limits:
- 2 million invocations per month
- 400,000 GB-seconds of compute time
- 200,000 GHz-seconds of compute time
- 5GB network egress per month

### Cost Monitoring

```bash
# Enable billing budget alerts (requires billing admin role)
gcloud alpha billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Weather API Budget" \
    --budget-amount=10USD

# Monitor function costs
gcloud logging read "resource.type=cloud_function" \
    --format="table(timestamp,resource.labels.function_name,httpRequest.requestMethod)"
```

## Security Considerations

### Authentication Options

1. **Unauthenticated Access** (current): Allows public access to the API
2. **Authenticated Access**: Require valid Google Cloud credentials
3. **API Key Authentication**: Implement custom API key validation

### Enabling Authentication

**Terraform Example:**
```hcl
resource "google_cloudfunctions2_function_iam_member" "authenticated_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.weather_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allAuthenticatedUsers"
}
```

### Network Security

Consider implementing VPC connectors for private network access:

```hcl
resource "google_vpc_access_connector" "weather_api_connector" {
  name          = "weather-api-connector"
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"
  region        = var.region
}
```

## Advanced Configuration

### Performance Tuning

- **Memory Allocation**: Increase memory for better performance (128MB - 8GB)
- **Timeout Configuration**: Adjust timeout based on external API response times
- **Concurrency**: Configure max concurrent instances based on expected load
- **Min Instances**: Set minimum instances to reduce cold start latency

### Integration with Other Services

- **Cloud Endpoints**: Add API management and authentication
- **Cloud CDN**: Cache responses for better performance
- **Cloud Scheduler**: Trigger periodic weather data updates
- **Pub/Sub**: Implement event-driven weather notifications

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation in the parent directory
2. Check Google Cloud Functions documentation and best practices
3. Verify all prerequisites are met and APIs are enabled
4. Use the troubleshooting section for common issues
5. Check Google Cloud support resources for provider-specific issues