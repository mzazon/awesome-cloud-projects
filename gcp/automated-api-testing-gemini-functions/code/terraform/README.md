# Infrastructure as Code for Automated API Testing with Gemini and Functions

This directory contains Terraform Infrastructure as Code (IaC) for deploying the complete automated API testing solution on Google Cloud Platform. The solution uses Vertex AI Gemini 2.0 Flash for intelligent test case generation, Cloud Functions for orchestration, Cloud Run for scalable test execution, and Cloud Storage for persistent result storage.

## Architecture Overview

The infrastructure deploys the following components:

- **Vertex AI**: Gemini 2.0 Flash model for AI-powered test case generation
- **Cloud Functions**: HTTP-triggered function for test case generation
- **Cloud Run**: Containerized service for test execution with concurrent processing
- **Cloud Storage**: Bucket with versioning for test results and artifacts storage
- **IAM**: Service accounts with least-privilege permissions
- **Monitoring**: Cloud Monitoring alerts for function and service errors
- **Secret Manager**: Optional secure configuration storage
- **KMS**: Optional encryption for enhanced security

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: Active project with billing enabled
2. **Terraform**: Version >= 1.5 installed locally
3. **Google Cloud CLI**: Latest version installed and authenticated
4. **Required Permissions**: Project Owner or Editor role in the target project
5. **APIs**: The Terraform will enable required APIs automatically

### Required Google Cloud APIs

The following APIs will be enabled automatically:
- AI Platform API (`aiplatform.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Secret Manager API (`secretmanager.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/automated-api-testing-gemini-functions/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment         = "dev"
resource_prefix     = "api-testing"
gemini_model       = "gemini-2.0-flash"
function_memory    = "1Gi"
cloud_run_memory   = "2Gi"
cloud_run_cpu      = "2"

# Security settings
allow_unauthenticated_access = false  # Set to true for testing
enable_secret_manager        = true
enable_audit_logs           = true

# Cost optimization
enable_cost_optimization = true
function_min_instances   = 0
cloud_run_min_instances  = 0

# Monitoring
enable_cloud_monitoring = true
enable_cloud_logging    = true

# Custom labels
custom_labels = {
  team        = "platform"
  cost-center = "engineering"
  application = "api-testing"
}
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Confirm deployment
# Type 'yes' when prompted
```

### 4. Verify Deployment

After successful deployment, Terraform will output important information including:

```bash
# Test the Cloud Function
curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "api_specification": "Sample API spec",
    "endpoints": ["https://httpbin.org/get"],
    "request_id": "test-deployment"
  }'

# Test the Cloud Run service
curl "$CLOUD_RUN_URL/health"

# List bucket contents
gsutil ls -r gs://$BUCKET_NAME/
```

## Configuration Options

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `resource_prefix` | Prefix for resource names | `api-testing` | No |

### Compute Resources

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `function_runtime` | Cloud Functions runtime | `python312` | `python39`, `python310`, `python311`, `python312` |
| `function_memory` | Function memory allocation | `1Gi` | `128Mi` to `32Gi` |
| `function_timeout` | Function timeout (seconds) | `300` | 60-3600 |
| `cloud_run_memory` | Cloud Run memory allocation | `2Gi` | `128Mi` to `32Gi` |
| `cloud_run_cpu` | Cloud Run CPU allocation | `2` | `0.25`, `0.5`, `1`, `2`, `4`, `6`, `8` |
| `cloud_run_timeout` | Cloud Run timeout (seconds) | `900` | 300-3600 |

### AI Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `gemini_model` | Vertex AI model to use | `gemini-2.0-flash` | `gemini-1.5-pro`, `gemini-1.5-flash`, `gemini-1.0-pro` |
| `vertex_ai_location` | Vertex AI location | Same as region | Any supported region |

### Storage Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `storage_class` | Cloud Storage class | `STANDARD` | `NEARLINE`, `COLDLINE`, `ARCHIVE` |
| `versioning_enabled` | Enable bucket versioning | `true` | `true`, `false` |
| `test_results_retention_days` | Days to retain test results | `90` | 30-365 |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `allow_unauthenticated_access` | Allow public access | `false` |
| `enable_secret_manager` | Enable Secret Manager | `true` |
| `enable_audit_logs` | Enable audit logging | `true` |
| `cors_origins` | CORS origins for Cloud Run | `["*"]` |

### Cost Optimization

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cost_optimization` | Enable cost features | `true` |
| `function_min_instances` | Minimum function instances | `0` |
| `cloud_run_min_instances` | Minimum Cloud Run instances | `0` |
| `function_max_instances` | Maximum function instances | `100` |
| `cloud_run_max_instances` | Maximum Cloud Run instances | `10` |

## Advanced Configuration

### VPC Connector (Optional)

For private networking, you can configure a VPC connector:

```hcl
enable_vpc_connector = true
vpc_connector_name   = "projects/PROJECT_ID/locations/REGION/connectors/CONNECTOR_NAME"
```

### Custom Monitoring

Enable additional monitoring features:

```hcl
enable_cloud_trace    = true
enable_cloud_profiler = true
enable_error_reporting = true
log_retention_days    = 30
```

### Custom Labels

Apply custom labels to all resources:

```hcl
custom_labels = {
  team        = "platform"
  cost-center = "engineering"
  environment = "production"
  application = "api-testing"
  owner       = "platform-team"
}
```

## Outputs

After deployment, Terraform provides comprehensive outputs including:

### Service URLs
- `function_url`: Cloud Function HTTP trigger URL
- `cloud_run_url`: Cloud Run service URL
- `bucket_url`: Cloud Storage bucket URL

### Resource Information
- `bucket_name`: Storage bucket name
- `function_name`: Cloud Function name
- `cloud_run_service_name`: Cloud Run service name

### Configuration Details
- `vertex_ai_location`: Vertex AI location
- `gemini_model`: Configured Gemini model
- Resource memory and CPU allocations

### Verification Commands
- Commands to test deployed services
- Environment variable setup
- Monitoring dashboard URLs

### Sample Usage
- Example API specification
- Test commands
- Workflow setup instructions

## Usage Examples

### Basic Test Generation

```bash
# Set environment variables from Terraform outputs
export FUNCTION_URL="$(terraform output -raw function_url)"
export CLOUD_RUN_URL="$(terraform output -raw cloud_run_url)"
export BUCKET_NAME="$(terraform output -raw bucket_name)"

# Generate test cases
curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "api_specification": {
      "openapi": "3.0.0",
      "info": {"title": "Sample API", "version": "1.0.0"},
      "paths": {
        "/users": {
          "get": {
            "summary": "Get users",
            "responses": {"200": {"description": "Success"}}
          }
        }
      }
    },
    "endpoints": ["https://jsonplaceholder.typicode.com/users"],
    "test_types": ["functional", "security"],
    "request_id": "example-test"
  }'
```

### Execute Generated Tests

```bash
# Execute test cases (example payload)
curl -X POST "$CLOUD_RUN_URL/run-tests" \
  -H "Content-Type: application/json" \
  -d '{
    "test_cases": [
      {
        "id": "test-001",
        "name": "Get Users Test",
        "endpoint": "https://jsonplaceholder.typicode.com/users",
        "method": "GET",
        "expected_status": 200
      }
    ],
    "test_run_id": "example-run"
  }'
```

### Monitor Results

```bash
# List test results
gsutil ls gs://$BUCKET_NAME/test-results/

# View test reports
gsutil ls gs://$BUCKET_NAME/reports/

# Check function logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --limit=10
```

## Monitoring and Maintenance

### Cloud Monitoring

The infrastructure includes pre-configured monitoring:

- **Function Error Rate**: Alerts when Cloud Function error rate exceeds 5/minute
- **Cloud Run Error Rate**: Alerts when Cloud Run error rate exceeds 10/minute
- **Resource Utilization**: Monitor CPU, memory, and request metrics

Access monitoring dashboards:
```bash
# Open monitoring console
echo "https://console.cloud.google.com/monitoring?project=$(terraform output -raw project_id)"
```

### Log Analysis

View logs across all services:

```bash
# Function logs
gcloud logging read 'resource.type="cloud_function"' --limit=50

# Cloud Run logs
gcloud logging read 'resource.type="cloud_run_revision"' --limit=50

# Storage access logs
gcloud logging read 'resource.type="storage_bucket"' --limit=50
```

### Cost Monitoring

Monitor costs and optimize:

1. **View cost breakdown** in Google Cloud Console billing section
2. **Set budget alerts** for unexpected cost increases
3. **Review resource utilization** in monitoring dashboards
4. **Adjust scaling settings** based on usage patterns

### Performance Tuning

Optimize performance based on usage:

```hcl
# For high-volume workloads
function_memory        = "2Gi"
function_max_instances = 200
cloud_run_memory      = "4Gi"
cloud_run_cpu         = "4"
cloud_run_max_instances = 20

# For development/testing
function_memory        = "512Mi"
function_max_instances = 10
cloud_run_memory      = "1Gi"
cloud_run_cpu         = "1"
cloud_run_max_instances = 5
```

## Security Best Practices

### IAM Security

The infrastructure follows least-privilege principles:

- **Service Accounts**: Dedicated accounts for each service
- **Role Binding**: Minimal required permissions only
- **No Default Roles**: Custom role assignments based on needs

### Data Security

- **Encryption**: KMS encryption for storage buckets (optional)
- **Secrets**: Sensitive configuration in Secret Manager
- **Audit Logs**: Comprehensive audit trail
- **Network Security**: Optional VPC connector for private communication

### Access Control

```hcl
# For production environments
allow_unauthenticated_access = false
enable_secret_manager        = true
enable_audit_logs           = true

# Configure authentication (example)
# You would need to set up IAM policies for authenticated access
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs manually if needed
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable run.googleapis.com
   ```

2. **Permission Denied**
   ```bash
   # Check your IAM permissions
   gcloud projects get-iam-policy PROJECT_ID
   ```

3. **Function Deployment Fails**
   ```bash
   # Check function logs
   gcloud functions logs read FUNCTION_NAME --region=REGION
   ```

4. **Cloud Run Service Unavailable**
   ```bash
   # Check service status
   gcloud run services describe SERVICE_NAME --region=REGION
   ```

### Debugging Commands

```bash
# Terraform debugging
export TF_LOG=DEBUG
terraform plan

# Validate configuration
terraform validate

# Check state
terraform show

# Force refresh state
terraform refresh
```

### Resource Cleanup

To clean up individual resources:

```bash
# Delete specific resources
terraform destroy -target=google_cloudfunctions2_function.test_generator
terraform destroy -target=google_cloud_run_v2_service.test_runner

# Complete cleanup
terraform destroy
```

## Customization and Extension

### Adding Custom Test Types

Modify the function code to support additional test types:

1. Update the `test_types` validation in `variables.tf`
2. Modify the prompt in `function_code/main.py`
3. Redeploy the function

### Integrating with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy API Testing Infrastructure
on:
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Init
        run: terraform init
      - name: Terraform Plan
        run: terraform plan
      - name: Terraform Apply
        run: terraform apply -auto-approve
```

### Custom Function Logic

To modify the AI prompt or test generation logic:

1. Edit `function_code/main.py`
2. Update the prompt in `create_test_generation_prompt()`
3. Deploy with `terraform apply`

### Additional Services

Extend the infrastructure with additional GCP services:

```hcl
# Example: Add Cloud Scheduler for automated testing
resource "google_cloud_scheduler_job" "daily_tests" {
  name        = "daily-api-tests"
  schedule    = "0 9 * * *"  # 9 AM daily
  description = "Trigger daily API tests"
  
  http_target {
    uri = google_cloudfunctions2_function.test_generator.service_config[0].uri
    http_method = "POST"
    
    body = base64encode(jsonencode({
      api_specification = "scheduled-test-spec"
      request_id       = "scheduled-daily"
    }))
  }
}
```

## Support and Contributing

### Getting Help

1. **Documentation**: Refer to Google Cloud documentation for each service
2. **Community**: Ask questions on Stack Overflow with relevant tags
3. **Issues**: Report bugs or request features in the project repository

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Version History

- **v1.0**: Initial release with basic functionality
- **v1.1**: Added monitoring and alerting
- **v1.2**: Enhanced security features
- **v1.3**: Added cost optimization options

---

For more information about the automated API testing solution, refer to the main recipe documentation at `../automated-api-testing-gemini-functions.md`.