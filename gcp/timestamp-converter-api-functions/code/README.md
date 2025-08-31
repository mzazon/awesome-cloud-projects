# Infrastructure as Code for Timestamp Converter API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Timestamp Converter API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Following APIs enabled:
  - Cloud Functions API
  - Cloud Build API
  - Cloud Run API
  - Cloud Logging API
  - Cloud Resource Manager API
- Appropriate IAM permissions:
  - Cloud Functions Developer
  - Cloud Build Editor
  - Storage Admin
  - Service Usage Admin

## Architecture Overview

This infrastructure deploys:
- Cloud Run function (2nd generation) with HTTP trigger
- Cloud Storage bucket for function source code backup
- IAM roles and permissions for function execution
- Cloud Logging configuration for monitoring

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/timestamp-converter \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/"

# Check deployment status
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/timestamp-converter
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

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the function URL upon successful deployment
```

## Testing the Deployed API

Once deployed, test your timestamp converter API:

```bash
# Get the function URL (from terraform output or deployment logs)
FUNCTION_URL="https://timestamp-converter-[hash]-uc.a.run.app"

# Test current timestamp
curl "${FUNCTION_URL}/?timestamp=now&timezone=UTC&format=human"

# Test specific timestamp with timezone conversion
curl "${FUNCTION_URL}/?timestamp=1609459200&timezone=US/Eastern&format=iso"

# Test with POST request
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"timestamp": "1609459200", "timezone": "Europe/London", "format": "human"}'
```

Expected response format:
```json
{
  "unix_timestamp": 1609459200,
  "timezone": "US/Eastern",
  "formatted": {
    "iso": "2021-01-01T00:00:00-05:00",
    "rfc": "Fri, 01 Jan 2021 00:00:00 -0500",
    "human": "2021-01-01 00:00:00 EST",
    "date": "2021-01-01",
    "time": "00:00:00 EST"
  },
  "requested_format": "2021-01-01 00:00:00 EST"
}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/timestamp-converter
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Variables and Parameters

#### Infrastructure Manager Variables (main.yaml)
- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_name`: Cloud Function name (default: timestamp-converter)
- `function_memory`: Memory allocation (default: 256Mi)
- `function_timeout`: Function timeout (default: 60s)
- `max_instances`: Maximum concurrent instances (default: 10)

#### Terraform Variables (variables.tf)
- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: "us-central1")
- `function_name`: Cloud Function name (default: "timestamp-converter")
- `function_memory`: Memory allocation (default: "256Mi")
- `function_timeout`: Function timeout in seconds (default: 60)
- `max_instances`: Maximum concurrent instances (default: 10)
- `environment_variables`: Map of environment variables for the function

#### Bash Script Variables
Set these environment variables before running scripts:
- `PROJECT_ID`: Your Google Cloud project ID
- `REGION`: Deployment region (default: us-central1)
- `FUNCTION_NAME`: Function name (default: timestamp-converter)

### Modifying Function Configuration

To customize the function behavior:

1. **Memory and CPU**: Adjust `function_memory` in terraform/variables.tf or Infrastructure Manager configuration
2. **Scaling**: Modify `max_instances` to control maximum concurrent executions
3. **Timeout**: Change `function_timeout` for longer-running requests
4. **Environment Variables**: Add custom environment variables through the `environment_variables` map

### Advanced Configuration

#### Custom Domain Setup
```bash
# Map custom domain (requires domain verification)
gcloud run domain-mappings create \
    --service timestamp-converter \
    --domain api.yourdomain.com \
    --region ${REGION}
```

#### VPC Connector (for private resources)
Add VPC connector configuration to access private resources:
```hcl
# In terraform/main.tf
resource "google_vpc_access_connector" "connector" {
  name          = "timestamp-converter-connector"
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"
  region        = var.region
}
```

## Monitoring and Logging

### View Function Logs
```bash
# View recent logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=timestamp-converter" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"

# Follow logs in real-time
gcloud logging tail "resource.type=cloud_run_revision AND resource.labels.service_name=timestamp-converter"
```

### Monitor Function Metrics
```bash
# View function metrics
gcloud monitoring metrics list --filter="resource.type=cloud_run_revision"

# Create uptime check
gcloud monitoring uptime create \
    --display-name="Timestamp Converter API" \
    --http-check-path="/?timestamp=now" \
    --hostname="timestamp-converter-[hash]-uc.a.run.app"
```

## Security Considerations

### Authentication
The default deployment allows unauthenticated access. For production use:

```bash
# Require authentication
gcloud run services update timestamp-converter \
    --no-allow-unauthenticated \
    --region ${REGION}

# Grant specific users access
gcloud run services add-iam-policy-binding timestamp-converter \
    --member="user:user@example.com" \
    --role="roles/run.invoker" \
    --region ${REGION}
```

### API Security
Consider implementing:
- Rate limiting with Cloud Endpoints
- API key authentication
- Request validation and sanitization
- CORS policy restrictions

## Cost Optimization

- **Free Tier**: Cloud Run functions include 2M requests/month free
- **Right-sizing**: Monitor memory usage and adjust allocation
- **Cold Starts**: Consider min-instances for latency-sensitive applications
- **Regional Deployment**: Choose regions closest to your users

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure required APIs are enabled and IAM roles are correct
2. **Function Won't Deploy**: Check source code syntax and requirements.txt
3. **Cold Start Latency**: Consider setting min-instances > 0
4. **Memory Errors**: Increase function memory allocation
5. **Timeout Errors**: Increase function timeout value

### Debug Commands
```bash
# Check function status
gcloud run services describe timestamp-converter --region ${REGION}

# View build logs
gcloud builds list --limit=5

# Test function locally (requires Functions Framework)
functions-framework --target=timestamp_converter --debug
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud Functions documentation
3. Verify IAM permissions and API enablement
4. Review Cloud Build logs for deployment issues

## Contributing

When modifying this infrastructure:
1. Update variable descriptions and defaults
2. Test changes in a development project
3. Update this README with any new configuration options
4. Follow Google Cloud best practices for security and cost optimization