# Daily Status Reports Infrastructure with Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying an automated daily system status reporting solution on Google Cloud Platform. The solution uses Cloud Scheduler to trigger a Cloud Function that collects system metrics and sends email reports via Gmail.

## Architecture Overview

The infrastructure creates the following resources:

- **Cloud Function**: Python-based serverless function for report generation
- **Cloud Scheduler**: Cron-based job for daily function triggering  
- **Service Account**: IAM identity with minimal required permissions
- **Storage Bucket**: Houses the Cloud Function source code
- **IAM Roles**: Monitoring viewer and function invoker permissions

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (gcloud CLI)
- Valid Google Cloud Project with billing enabled

### Required Permissions

Your user account or service account needs the following IAM roles:

- `roles/owner` or `roles/editor` on the target GCP project
- `roles/iam.serviceAccountAdmin` 
- `roles/cloudfunctions.admin`
- `roles/cloudscheduler.admin`
- `roles/storage.admin`

### Gmail Configuration

1. Enable 2-factor authentication on your Gmail account
2. Generate an App Password:
   - Go to Google Account Settings > Security > App passwords
   - Select "Mail" and generate a 16-character password
   - Use this password (not your regular Gmail password) in the configuration

## Quick Start

### 1. Authentication Setup

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your default project
gcloud config set project YOUR_PROJECT_ID
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your specific configuration
nano terraform.tfvars
```

Required variables in `terraform.tfvars`:

```hcl
project_id      = "your-gcp-project-id"
region          = "us-central1"
sender_email    = "your-sender@gmail.com"
sender_password = "your-gmail-app-password"
recipient_email = "admin@yourcompany.com"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Test the Cloud Function manually
gcloud functions call $(terraform output -raw function_name) --region=$(terraform output -raw region)

# View function logs
gcloud functions logs read $(terraform output -raw function_name) --region=$(terraform output -raw region) --limit=10

# Trigger the scheduler job manually
gcloud scheduler jobs run $(terraform output -raw scheduler_job_name) --location=$(terraform output -raw region)
```

## Configuration Options

### Basic Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID | - | Yes |
| `region` | GCP region | `us-central1` | No |
| `sender_email` | Gmail sender address | - | Yes |
| `sender_password` | Gmail app password | - | Yes |
| `recipient_email` | Report recipient email | - | Yes |

### Advanced Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment label | `dev` |
| `cron_schedule` | Cron expression for scheduling | `0 9 * * *` |
| `timezone` | Timezone for job execution | `UTC` |
| `function_memory` | Function memory in MB | `256` |
| `function_timeout` | Function timeout in seconds | `60` |
| `monitoring_period_hours` | Hours of metrics to collect | `24` |

### Scheduling Examples

```hcl
# Daily at 9 AM UTC (default)
cron_schedule = "0 9 * * *"

# Every 6 hours
cron_schedule = "0 */6 * * *"

# Weekdays only at 8 AM
cron_schedule = "0 8 * * 1-5"

# Every 30 minutes (for testing)
cron_schedule = "*/30 * * * *"
```

## Customization

### Email Templates

To customize the email report format, modify the `format_report_body()` function in `function_code/main.py` before deployment.

### Additional Metrics

Add new metric collection by extending the `collect_system_metrics()` function:

```python
# Add custom metrics collection
def collect_custom_metrics(client, project_name, interval):
    # Your custom metrics logic here
    return custom_data
```

### Multi-Project Monitoring

For monitoring multiple projects, create separate Terraform workspaces or modules:

```bash
# Create workspace for production
terraform workspace new production
terraform apply -var-file="production.tfvars"

# Create workspace for staging  
terraform workspace new staging
terraform apply -var-file="staging.tfvars"
```

## Monitoring and Troubleshooting

### View Resources

```bash
# List all created resources
terraform show

# Get specific outputs
terraform output function_url
terraform output scheduler_job_name
```

### Function Logs

```bash
# View recent function logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --limit=20

# Follow logs in real-time
gcloud functions logs tail $(terraform output -raw function_name) \
  --region=$(terraform output -raw region)
```

### Scheduler Status

```bash
# Check job status
gcloud scheduler jobs describe $(terraform output -raw scheduler_job_name) \
  --location=$(terraform output -raw region)

# View job history
gcloud scheduler jobs describe $(terraform output -raw scheduler_job_name) \
  --location=$(terraform output -raw region) \
  --format="table(status.lastRunTime,status.lastAttemptTime,status.status)"
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Email not sending | Invalid Gmail app password | Regenerate app password |
| Function timeout | Large project with many metrics | Increase `function_timeout` |
| Permission denied | Insufficient IAM roles | Add required roles to service account |
| No metrics data | API not enabled | Verify APIs are enabled via terraform |

## Cost Optimization

### Estimated Costs

- **Cloud Function**: ~$0.0000004 per invocation
- **Cloud Scheduler**: ~$0.10 per job per month  
- **Storage**: ~$0.020 per GB per month (minimal)
- **Total**: ~$0.13-$2.00 per month for typical usage

### Cost Reduction Tips

1. Use smaller memory allocation (128MB minimum)
2. Reduce monitoring frequency for non-critical environments
3. Set appropriate `max_instances` limit
4. Enable storage lifecycle rules for function source

```hcl
# Cost-optimized configuration
function_memory = 128
cron_schedule = "0 9 * * 1-5"  # Weekdays only
max_instances = 3
```

## Security Best Practices

### Secrets Management

Instead of using variables for sensitive data, consider Google Secret Manager:

```bash
# Store password in Secret Manager
gcloud secrets create gmail-app-password --data-file=password.txt

# Update Terraform to use Secret Manager
# (requires code modification)
```

### Network Security

For enhanced security, enable VPC connector:

```hcl
enable_vpc_connector = true
vpc_connector_name = "your-vpc-connector"
```

### IAM Hardening

The service account uses minimal permissions:
- `roles/monitoring.viewer` - Read-only access to metrics
- `roles/cloudfunctions.invoker` - Allow scheduler to invoke function

## Backup and Disaster Recovery

### State Management

Use remote state for production:

```hcl
# Configure in versions.tf
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "daily-status-reports"
  }
}
```

### Resource Backup

```bash
# Export current configuration
terraform show -json > infrastructure-backup.json

# Export function source code
gcloud functions describe $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --format="export" > function-backup.yaml
```

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify all resources are removed
terraform show
```

## Support and Contributing

For issues related to this Terraform code:

1. Check the [troubleshooting section](#monitoring-and-troubleshooting)
2. Review Terraform and provider documentation
3. Verify GCP quotas and limits
4. Check function logs for runtime errors

## Version Compatibility

- **Terraform**: >= 1.0
- **Google Provider**: ~> 6.0  
- **Python Runtime**: 3.12
- **Google Cloud APIs**: Latest stable versions

This infrastructure code is maintained and tested with the latest stable versions of all dependencies.