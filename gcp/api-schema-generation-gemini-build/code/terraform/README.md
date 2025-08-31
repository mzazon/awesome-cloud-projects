# Infrastructure as Code for API Schema Generation with Gemini Code Assist and Cloud Build

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete automated API documentation pipeline using Google Cloud Platform services.

## Architecture Overview

This infrastructure creates an automated API schema generation pipeline that:

- **Analyzes source code** using AI-powered tools and Cloud Build
- **Generates OpenAPI schemas** automatically from API code patterns
- **Validates schemas** against industry standards and best practices
- **Stores artifacts** in organized Cloud Storage structure
- **Monitors pipeline health** with comprehensive alerting
- **Provides CI/CD integration** through Cloud Build triggers

## Infrastructure Components

### Core Services
- **Cloud Storage**: Centralized storage for API schemas, build artifacts, and documentation
- **Cloud Functions**: Serverless functions for schema generation and validation
- **Cloud Build**: CI/CD pipeline automation with multi-stage validation
- **IAM**: Secure service accounts with least-privilege access
- **Cloud Monitoring**: Comprehensive observability and alerting

### Supporting Resources
- **Log Sinks**: Centralized logging for functions and builds
- **Notification Channels**: Email alerts for pipeline failures
- **Alert Policies**: Proactive monitoring of error rates and build failures
- **Random ID Generation**: Unique resource naming for multi-environment deployments

## Quick Start

### Prerequisites

1. **Google Cloud CLI**: Install and authenticate
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform**: Version 1.0 or higher
   ```bash
   terraform version
   ```

3. **Required Permissions**: Ensure your account has:
   - Project Editor or custom roles with necessary permissions
   - Service Account Admin
   - Cloud Functions Admin
   - Cloud Build Editor
   - Storage Admin

### Deployment Steps

1. **Clone and Navigate**
   ```bash
   cd gcp/api-schema-generation-gemini-build/code/terraform/
   ```

2. **Initialize Terraform**
   ```bash
   terraform init
   ```

3. **Configure Variables**
   Create a `terraform.tfvars` file:
   ```hcl
   project_id = "your-gcp-project-id"
   region     = "us-central1"
   environment = "dev"
   notification_email = "alerts@your-domain.com"
   ```

4. **Plan Deployment**
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**
   ```bash
   terraform apply
   ```

## Configuration Options

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud project ID | `my-api-project-123` |
| `region` | Deployment region | `us-central1` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | `dev` | Environment name for labeling |
| `notification_email` | `null` | Email for alerts and notifications |
| `function_memory_mb` | `512` | Memory allocation for functions |
| `bucket_name_prefix` | `api-schemas` | Prefix for storage bucket name |
| `enable_monitoring` | `true` | Enable monitoring and alerting |

### Advanced Configuration

For production deployments, consider:

```hcl
# terraform.tfvars
project_id = "prod-api-project"
region = "us-central1"
environment = "production"
deployment_mode = "production"

# Enhanced security
enable_uniform_bucket_access = true
enable_audit_logs = true
allowed_source_ips = ["10.0.0.0/8"]

# Performance optimization
function_memory_mb = 1024
function_max_instances = 50
build_machine_type = "E2_STANDARD_2"

# Cost optimization
enable_cost_optimization = true
retention_period_days = 90

# Monitoring
notification_email = "devops-alerts@company.com"
alert_threshold_error_rate = 0.05
```

## Usage Examples

### Manual Function Invocation

After deployment, you can test the functions:

```bash
# Get function URLs from outputs
SCHEMA_GENERATOR_URL=$(terraform output -raw schema_generator_function_url)
SCHEMA_VALIDATOR_URL=$(terraform output -raw schema_validator_function_url)

# Generate schema
curl -X POST "$SCHEMA_GENERATOR_URL" \
  -H "Content-Type: application/json" \
  -d '{}'

# Validate schema
curl -X POST "$SCHEMA_VALIDATOR_URL" \
  -H "Content-Type: application/json" \
  -d '{"bucket_name": "your-bucket-name"}'
```

### Cloud Build Trigger

```bash
# Get trigger name
TRIGGER_NAME=$(terraform output -raw build_trigger_name)

# Manually trigger build
gcloud builds triggers run $TRIGGER_NAME --branch=main
```

### Storage Access

```bash
# Get bucket name
BUCKET_NAME=$(terraform output -raw storage_bucket_name)

# List artifacts
gsutil ls -r gs://$BUCKET_NAME/

# Download latest schema
gsutil cp gs://$BUCKET_NAME/docs/openapi-schema.json ./
```

## Monitoring and Observability

### Built-in Monitoring

The infrastructure includes comprehensive monitoring:

- **Function Error Rates**: Alerts when error rates exceed thresholds
- **Build Failure Detection**: Notifications for failed builds
- **Resource Usage Tracking**: Memory, timeout, and performance metrics
- **Cost Monitoring**: Usage tracking with cost optimization

### Accessing Logs

```bash
# Function logs
gcloud logs read 'resource.type="cloud_function"' --limit=50

# Build logs  
gcloud logs read 'resource.type="build"' --limit=20

# All pipeline logs
gcloud logs read 'labels.component="api-schema-generation"' --limit=100
```

### Dashboard Access

Access pre-configured dashboards through the Google Cloud Console:

```bash
# Get console links
terraform output cloud_console_links
```

## Security Considerations

### Service Account Permissions

The infrastructure creates service accounts with minimal required permissions:

- **Cloud Functions SA**: Storage object admin, log writer
- **Cloud Build SA**: Storage admin, functions invoker, log writer

### Network Security

For enhanced security:

```hcl
# Enable VPC connector for private network access
enable_vpc_connector = true
network_project_id = "shared-vpc-project"
subnet_name = "private-subnet"

# Restrict function access
allowed_source_ips = ["10.0.0.0/8", "172.16.0.0/12"]
```

### Data Protection

- **Encryption**: All data encrypted at rest and in transit
- **Versioning**: Schema history tracking with versioning
- **Retention**: Configurable data retention policies
- **Access Control**: Uniform bucket-level access enabled

## Cost Optimization

### Resource Sizing

Optimize costs based on usage patterns:

```hcl
# Development environment
function_memory_mb = 256
function_max_instances = 5
build_machine_type = "E2_MICRO"

# Production environment  
function_memory_mb = 1024
function_max_instances = 100
build_machine_type = "E2_STANDARD_2"
```

### Lifecycle Management

Automatic cost optimization features:

- **Storage Tiering**: Automatic transition to cheaper storage classes
- **Log Retention**: Configurable retention periods
- **Unused Resource Cleanup**: Automatic cleanup of temporary artifacts

### Cost Monitoring

```bash
# View estimated costs
terraform output estimated_monthly_costs

# Monitor actual usage
gcloud billing budgets list
```

## Troubleshooting

### Common Issues

1. **API Enablement Errors**
   ```bash
   # Enable APIs manually if needed
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

2. **Permission Errors**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy $PROJECT_ID
   ```

3. **Function Deployment Failures**
   ```bash
   # Check function status
   gcloud functions describe schema-generator --region=us-central1
   ```

### Debug Commands

```bash
# Terraform debugging
export TF_LOG=DEBUG
terraform plan

# Resource validation
terraform validate
terraform fmt -check

# State inspection
terraform state list
terraform state show google_storage_bucket.api_schemas
```

### Log Analysis

```bash
# Function execution logs
gcloud logs read 'resource.type="cloud_function" AND severity>=ERROR'

# Build failure analysis
gcloud logs read 'resource.type="build" AND jsonPayload.status="FAILURE"'
```

## Backup and Recovery

### State Management

For production use, configure remote state:

```hcl
# versions.tf
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "api-schema-generation/terraform.tfstate"
  }
}
```

### Resource Recovery

```bash
# Import existing resources if needed
terraform import google_storage_bucket.api_schemas $BUCKET_NAME

# Restore from backup
gsutil -m cp -r gs://backup-bucket/schemas/* gs://$BUCKET_NAME/schemas/
```

## Cleanup

### Destroy Infrastructure

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

### Manual Cleanup

Some resources may require manual cleanup:

```bash
# Check for remaining storage objects
gsutil ls gs://$BUCKET_NAME/

# Clean up log sinks
gcloud logging sinks list
```

## Advanced Topics

### Multi-Environment Deployment

Use Terraform workspaces or separate state files:

```bash
# Create workspace
terraform workspace new production
terraform workspace select production

# Deploy with environment-specific variables
terraform apply -var-file="production.tfvars"
```

### CI/CD Integration

Integrate with your CI/CD pipeline:

```yaml
# .github/workflows/terraform.yml
name: Terraform
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: hashicorp/setup-terraform@v2
    - run: terraform init
    - run: terraform plan
    - run: terraform apply -auto-approve
```

### Custom Function Code

To customize the function code:

1. Modify templates in `templates/` directory
2. Update template variables in `main.tf`
3. Redeploy with `terraform apply`

## Support and Maintenance

### Version Updates

Keep infrastructure current:

```bash
# Update provider versions
terraform init -upgrade

# Check for deprecated resources
terraform plan
```

### Health Checks

Regular maintenance commands:

```bash
# Validate configuration
terraform validate

# Check for drift
terraform plan

# Review security
terraform apply -target=google_project_iam_*
```

### Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Build Configuration Guide](https://cloud.google.com/build/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [OpenAPI Specification](https://spec.openapis.org/oas/v3.0.3)

## Contributing

To contribute to this infrastructure:

1. Fork the repository
2. Create feature branch
3. Test changes thoroughly
4. Submit pull request with detailed description

### Development Workflow

```bash
# Format code
terraform fmt

# Validate configuration
terraform validate

# Plan changes
terraform plan

# Test in development environment
terraform workspace select dev
terraform apply
```

For questions or support, contact the DevOps team or create an issue in the project repository.