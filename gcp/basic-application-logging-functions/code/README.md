# Infrastructure as Code for Basic Application Logging with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic Application Logging with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Required APIs enabled: Cloud Functions, Cloud Logging, Cloud Build
- Appropriate IAM permissions for:
  - Cloud Functions deployment
  - Cloud Logging configuration
  - IAM role management
  - Project resource management

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code, providing native integration with Google Cloud services and built-in state management.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/logging-function-deployment \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive provider ecosystem support, making it ideal for multi-cloud or hybrid infrastructure scenarios.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure changes
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct CLI interaction and are useful for learning, prototyping, or integration with existing shell-based workflows.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployed function
curl -s "$(./scripts/get-function-url.sh)" | python3 -m json.tool
```

## Architecture Overview

The infrastructure creates:

- **Cloud Function**: Python 3.12 runtime with HTTP trigger for logging demonstration
- **Cloud Logging Configuration**: Automatic integration with Google Cloud Logging service
- **IAM Roles**: Necessary permissions for function execution and logging access
- **Source Code Deployment**: Function code with structured logging implementation

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `logging-demo-function` | No |
| `memory` | Function memory allocation | `256MB` | No |
| `timeout` | Function timeout | `60s` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | `string` | - | Yes |
| `region` | Deployment region | `string` | `us-central1` | No |
| `function_name` | Cloud Function name | `string` | `logging-demo-function` | No |
| `memory_mb` | Function memory in MB | `number` | `256` | No |
| `timeout_seconds` | Function timeout in seconds | `number` | `60` | No |
| `runtime` | Python runtime version | `string` | `python312` | No |

### Environment Variables for Bash Scripts

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `FUNCTION_NAME` | Cloud Function name | `logging-demo-function` | No |

## Testing and Validation

After deployment, test the logging functionality:

```bash
# Get function URL (Terraform)
FUNCTION_URL=$(terraform output -raw function_url)

# Get function URL (Infrastructure Manager)
FUNCTION_URL=$(gcloud functions describe logging-demo-function --region=us-central1 --format="value(httpsTrigger.url)")

# Test normal logging
curl -s "${FUNCTION_URL}" | python3 -m json.tool

# Test with test mode parameter
curl -s "${FUNCTION_URL}?mode=test" | python3 -m json.tool

# View generated logs
gcloud logging read "resource.type=\"cloud_function\" AND resource.labels.function_name=\"logging-demo-function\"" --limit=10
```

## Monitoring and Observability

Access your logs through multiple interfaces:

- **Cloud Console**: Navigate to Cloud Logging > Logs Explorer
- **CLI**: Use `gcloud logging` commands for programmatic access
- **API**: Integrate with Cloud Logging API for custom applications

Example log queries:

```bash
# Filter by component
gcloud logging read "jsonPayload.component=\"log-demo-function\"" --limit=5

# Filter by event type
gcloud logging read "jsonPayload.event_type=\"function_start\"" --limit=5

# Filter by severity
gcloud logging read "severity>=WARNING" --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/logging-function-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
gcloud functions list --regions=${REGION}
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Ensure your account has necessary IAM permissions
   - Verify APIs are enabled in your project
   - Check service account permissions

2. **Function Deployment Failures**
   - Verify source code syntax and dependencies
   - Check function memory and timeout settings
   - Ensure Cloud Build API is enabled

3. **Logging Not Appearing**
   - Wait 1-2 minutes for log propagation
   - Verify Cloud Logging API is enabled
   - Check function execution logs for errors

### Debug Commands

```bash
# Check function status
gcloud functions describe ${FUNCTION_NAME} --region=${REGION}

# View function logs
gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}

# List enabled APIs
gcloud services list --enabled
```

## Security Considerations

- Functions run with minimal required permissions
- HTTP trigger allows unauthenticated access for demo purposes
- Structured logging includes request metadata for audit trails
- Cloud Logging automatically encrypts data at rest and in transit

## Cost Optimization

- Cloud Functions free tier includes 2M invocations per month
- Memory allocation set to 256MB for cost efficiency
- Timeout set to 60 seconds to prevent runaway executions
- Cloud Logging provides 50GB monthly free allocation

## Customization

### Adding Custom Log Fields

Modify the function code to include additional structured fields:

```python
logging.info("Custom event", extra={
    "json_fields": {
        "component": "log-demo-function",
        "custom_field": "custom_value",
        "business_metric": 123.45
    }
})
```

### Environment-Specific Configuration

Create separate variable files for different environments:

```bash
# terraform/environments/dev.tfvars
project_id = "my-project-dev"
function_name = "logging-demo-function-dev"
memory_mb = 128

# terraform/environments/prod.tfvars
project_id = "my-project-prod"
function_name = "logging-demo-function-prod"
memory_mb = 512
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions workflow
- name: Deploy with Terraform
  run: |
    cd terraform/
    terraform init
    terraform apply -auto-approve \
      -var="project_id=${{ secrets.GCP_PROJECT_ID }}" \
      -var="region=us-central1"
```

### Monitoring Integration

```bash
# Create log-based metrics
gcloud logging metrics create function_invocations \
    --description="Count of function invocations" \
    --log-filter="resource.type=\"cloud_function\" AND jsonPayload.event_type=\"function_start\""
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify your environment meets all prerequisites
4. Consult provider-specific troubleshooting guides

## Additional Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Logging Best Practices](https://cloud.google.com/logging/docs/best-practices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)