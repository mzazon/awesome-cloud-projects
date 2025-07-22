# Terraform Infrastructure for GCP Domain Health Monitoring

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive domain health monitoring solution on Google Cloud Platform. The infrastructure automatically monitors SSL certificate expiration, DNS resolution, and HTTP response status for multiple domains.

## Architecture Overview

The solution deploys the following Google Cloud resources:

- **Cloud Function (Gen 2)**: Serverless function performing domain health checks
- **Cloud Storage**: Bucket for function code and monitoring data storage
- **Pub/Sub**: Topic and subscription for alert notifications
- **Cloud Monitoring**: Custom metrics and alert policies
- **Cloud Scheduler**: Automated triggering of health checks
- **Service Account**: Dedicated IAM for the function with least privilege
- **Cloud Logging**: Centralized logging and log sink configuration

## Prerequisites

### Required Tools

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) >= 400.0.0
- Active Google Cloud Project with billing enabled

### Required Permissions

Your Google Cloud user or service account needs the following roles:

- `roles/editor` or `roles/owner` on the target project
- `roles/iam.serviceAccountAdmin`
- `roles/resourcemanager.projectIamAdmin`

### API Requirements

The following APIs will be automatically enabled during deployment:

- Cloud Functions API
- Cloud Scheduler API
- Cloud Monitoring API
- Cloud Domains API
- Cloud Storage API
- Pub/Sub API
- Cloud Build API
- Eventarc API

## Quick Start

### 1. Authentication Setup

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project
gcloud config set project YOUR_PROJECT_ID
```

### 2. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/domain-health-monitoring-domains-functions/code/terraform/
```

### 3. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Domains to monitor
domains_to_monitor = [
  "example.com",
  "yourdomain.com",
  "anotherdomain.net"
]

# Notification configuration
notification_email = "admin@yourdomain.com"

# Monitoring configuration
monitoring_schedule = "0 */6 * * *"  # Every 6 hours
ssl_expiry_warning_days = 30

# Optional: Resource labels
labels = {
  environment = "production"
  team        = "platform"
  project     = "domain-monitoring"
}
```

### 4. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Verify Deployment

```bash
# Check function deployment
gcloud functions list --regions=us-central1

# Trigger manual test
terraform output -raw manual_test_commands
```

## Configuration Variables

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `project_id` | string | Google Cloud project ID |

### Optional Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `region` | string | `us-central1` | GCP region for resources |
| `domains_to_monitor` | list(string) | `["example.com", "google.com"]` | Domains to monitor |
| `monitoring_schedule` | string | `"0 */6 * * *"` | Cron expression for monitoring frequency |
| `ssl_expiry_warning_days` | number | `30` | Days before SSL expiry to alert |
| `function_timeout` | number | `300` | Function timeout in seconds |
| `function_memory` | string | `"512Mi"` | Function memory allocation |
| `notification_email` | string | `""` | Email for alert notifications |
| `enable_cloud_scheduler` | bool | `true` | Enable automatic scheduling |
| `storage_class` | string | `"STANDARD"` | Storage class for bucket |
| `retention_days` | number | `90` | Data retention period |
| `labels` | map(string) | See variables.tf | Resource labels |

## Monitoring and Alerting

### Custom Metrics

The solution creates the following custom metrics in Cloud Monitoring:

- `custom.googleapis.com/domain/ssl_valid` - SSL certificate validity (0/1)
- `custom.googleapis.com/domain/dns_resolves` - DNS resolution status (0/1)
- `custom.googleapis.com/domain/http_responds` - HTTP response status (0/1)

### Alert Policies

Three alert policies are automatically configured:

1. **SSL Certificate Expiring** - Triggers when SSL certificates approach expiration
2. **DNS Resolution Failure** - Triggers when domains fail to resolve
3. **HTTP Response Failure** - Triggers when domains don't respond to HTTP requests

### Notification Channels

If `notification_email` is provided, an email notification channel is automatically configured and linked to all alert policies.

## Data Storage

### Monitoring Results

Health check results are stored in Cloud Storage with the following structure:

```
gs://bucket-name/monitoring-results/
├── 2025-01-15-12-00-00.json
├── 2025-01-15-18-00-00.json
└── ...
```

### Log Data

Function logs are automatically exported to Cloud Storage via a log sink for long-term retention and analysis.

## Security Features

### Service Account

A dedicated service account is created with minimal required permissions:

- `roles/monitoring.metricWriter` - Write custom metrics
- `roles/pubsub.publisher` - Publish alert messages
- `roles/storage.objectAdmin` - Store monitoring results
- `roles/domains.viewer` - Read domain information
- `roles/logging.logWriter` - Write function logs

### Storage Security

- Uniform bucket-level access enabled
- Public access prevention enforced
- Lifecycle policies for data retention
- Object versioning enabled

### Network Security

Optional VPC connector support for private network deployment:

```hcl
enable_private_network = true
vpc_network_name      = "your-vpc-network"
vpc_subnet_name       = "your-subnet"
```

## Customization

### Adding Custom Domains

Update the `domains_to_monitor` variable in your `terraform.tfvars`:

```hcl
domains_to_monitor = [
  "yourdomain.com",
  "api.yourdomain.com",
  "app.yourdomain.com"
]
```

### Modifying Monitoring Frequency

Adjust the `monitoring_schedule` cron expression:

```hcl
# Every hour
monitoring_schedule = "0 * * * *"

# Every 12 hours
monitoring_schedule = "0 */12 * * *"

# Daily at 2 AM
monitoring_schedule = "0 2 * * *"
```

### Custom Alert Thresholds

Modify the `ssl_expiry_warning_days` variable:

```hcl
# Alert 60 days before expiration
ssl_expiry_warning_days = 60

# Alert 7 days before expiration
ssl_expiry_warning_days = 7
```

## Cost Optimization

### Estimated Monthly Costs

| Component | Estimated Cost |
|-----------|----------------|
| Cloud Functions | $0.01 - $5.00 |
| Cloud Storage | $0.50 - $2.00 |
| Cloud Monitoring | Free tier |
| Pub/Sub | $0.10 - $1.00 |
| Cloud Scheduler | Free tier |
| **Total** | **$1 - $10** |

### Cost Reduction Tips

1. **Reduce monitoring frequency** for non-critical domains
2. **Adjust retention period** to reduce storage costs
3. **Use NEARLINE or COLDLINE** storage for historical data
4. **Monitor free tier usage** to avoid unexpected charges

## Troubleshooting

### Common Issues

#### 1. API Not Enabled

**Error**: `API [service] is not enabled`

**Solution**:
```bash
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable monitoring.googleapis.com
```

#### 2. Insufficient Permissions

**Error**: `Permission denied`

**Solution**: Ensure your account has the required IAM roles listed in Prerequisites.

#### 3. Function Deployment Fails

**Error**: `Function deployment failed`

**Solution**:
```bash
# Check Cloud Build logs
gcloud builds list --limit=5

# Verify source bucket
gsutil ls gs://your-bucket-name
```

#### 4. No Metrics in Monitoring

**Solution**:
```bash
# Trigger function manually
curl -X POST "$(terraform output -raw function_url)" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)"

# Check function logs
gcloud functions logs read function-name --limit=10
```

### Debug Commands

```bash
# View Terraform state
terraform state list

# Check function status
terraform output function_name
gcloud functions describe $(terraform output -raw function_name) --region=$(terraform output -raw region)

# Monitor function execution
gcloud functions logs read $(terraform output -raw function_name) --limit=20

# Check storage bucket contents
gsutil ls gs://$(terraform output -raw storage_bucket_name)/monitoring-results/

# List alert policies
gcloud alpha monitoring policies list --filter="displayName:(SSL OR DNS OR HTTP)"
```

## Maintenance

### Regular Tasks

1. **Monitor costs** monthly in the GCP Console
2. **Review alert policies** quarterly for effectiveness
3. **Update domain list** as needed
4. **Check function logs** for errors
5. **Validate monitoring data** in Cloud Storage

### Updates

To update the infrastructure:

```bash
# Pull latest changes
git pull origin main

# Review changes
terraform plan

# Apply updates
terraform apply
```

### Backup

Important configuration to backup:

- `terraform.tfvars` file
- Domain list configuration
- Custom alert policy modifications

## Cleanup

To remove all infrastructure:

```bash
# Destroy all resources
terraform destroy

# Confirm removal
terraform state list  # Should be empty
```

**Warning**: This will permanently delete all monitoring data and configurations.

## Support

### Documentation Links

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

1. Check the [troubleshooting section](#troubleshooting) above
2. Review function logs in Cloud Logging
3. Validate your `terraform.tfvars` configuration
4. Ensure all required APIs are enabled

For additional support, refer to the original recipe documentation in the parent directory.