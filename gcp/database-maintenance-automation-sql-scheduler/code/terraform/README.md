# Database Maintenance Automation - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete database maintenance automation solution on Google Cloud Platform. The solution implements intelligent database maintenance using Cloud SQL, Cloud Functions, Cloud Scheduler, and Cloud Monitoring.

## Architecture Overview

The infrastructure deploys the following components:

- **Cloud SQL MySQL Instance**: Managed database with performance monitoring and automated backups
- **Cloud Functions**: Serverless maintenance execution with comprehensive database operations
- **Cloud Scheduler**: Automated job scheduling with retry policies and monitoring
- **Cloud Storage**: Maintenance logs, reports, and function source code storage
- **Cloud Monitoring**: Performance dashboards, alerting policies, and custom metrics
- **IAM Resources**: Service accounts with least privilege permissions

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) >= 400.0.0
- Valid Google Cloud Project with billing enabled

### Required Permissions

Your user account or service account needs the following IAM roles:

- `roles/editor` (or combination of specific roles below)
- `roles/cloudsql.admin`
- `roles/cloudfunctions.admin`
- `roles/cloudscheduler.admin`
- `roles/monitoring.admin`
- `roles/storage.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/serviceusage.serviceUsageAdmin`

### Google Cloud APIs

The following APIs will be automatically enabled during deployment:

- Cloud SQL Admin API (`sqladmin.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)

## Quick Start

### 1. Clone and Setup

```bash
# Clone the repository (if not already done)
git clone <repository-url>
cd gcp/database-maintenance-automation-sql-scheduler/code/terraform

# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project
gcloud config set project YOUR_PROJECT_ID
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your specific configuration
nano terraform.tfvars
```

**Minimum required variables:**

```hcl
project_id  = "your-project-id"
db_password = "secure-password-here"
alert_email = "admin@yourcompany.com"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check Cloud SQL instance
gcloud sql instances list

# Verify Cloud Function
gcloud functions list --regions=us-central1

# Check scheduled jobs
gcloud scheduler jobs list --location=us-central1

# Test function manually
curl -X POST $(terraform output -raw function_url) \
  -H "Content-Type: application/json" \
  -d '{"action": "performance_monitoring"}'
```

## Configuration Reference

### Core Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project_id` | string | **Required** | Google Cloud Project ID |
| `region` | string | `us-central1` | Deployment region |
| `db_password` | string | **Required** | Database user password |
| `alert_email` | string | `""` | Email for monitoring alerts |

### Database Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `db_tier` | string | `db-f1-micro` | Cloud SQL instance tier |
| `db_disk_size` | number | `10` | Initial disk size (GB) |
| `backup_retention_count` | number | `7` | Number of backups to retain |
| `enable_deletion_protection` | bool | `false` | Prevent accidental deletion |

### Scheduler Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `maintenance_schedule` | string | `"0 2 * * *"` | Daily maintenance cron |
| `monitoring_schedule` | string | `"0 */6 * * *"` | Monitoring cron |
| `timezone` | string | `"America/New_York"` | Scheduler timezone |
| `scheduler_retry_count` | number | `3` | Maximum retry attempts |

### Feature Flags

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_monitoring_dashboard` | bool | `true` | Create monitoring dashboard |
| `enable_alerting_policies` | bool | `true` | Create alert policies |
| `enable_performance_monitoring` | bool | `true` | Enable monitoring job |
| `enable_bucket_versioning` | bool | `true` | Enable storage versioning |

## Advanced Configuration

### Multi-Environment Setup

Create environment-specific variable files:

```bash
# Development environment
cp terraform.tfvars.example terraform.tfvars.dev
# Edit for development settings

# Production environment  
cp terraform.tfvars.example terraform.tfvars.prod
# Edit for production settings

# Deploy to specific environment
terraform apply -var-file="terraform.tfvars.prod"
```

### Custom Security Configuration

```hcl
# Restrict database access to specific networks
authorized_networks = [
  {
    name  = "office-network"
    value = "203.0.113.0/24"
  },
  {
    name  = "vpn-gateway"
    value = "198.51.100.1/32"
  }
]

# Enable SSL requirement
require_ssl = true

# Enable deletion protection
enable_deletion_protection = true
```

### Performance Tuning

```hcl
# High-performance configuration
db_tier = "db-n1-standard-4"
db_disk_size = 100
function_memory = 512
function_timeout = 540

# Extended retention
log_retention_days = 2555  # 7 years
backup_retention_count = 30
```

## Monitoring and Maintenance

### Viewing Maintenance Reports

```bash
# List maintenance reports
gsutil ls gs://$(terraform output -raw storage_bucket_name)/maintenance-reports/

# Download latest report
gsutil cp gs://$(terraform output -raw storage_bucket_name)/maintenance-reports/latest.json .
```

### Monitoring Dashboard

Access the monitoring dashboard:

```bash
# Get dashboard URL
terraform output monitoring_dashboard_url

# Or navigate to Cloud Console
echo "https://console.cloud.google.com/monitoring/dashboards"
```

### Manual Maintenance Execution

```bash
# Get function URL
FUNCTION_URL=$(terraform output -raw function_url)

# Run daily maintenance
curl -X POST $FUNCTION_URL \
  -H "Content-Type: application/json" \
  -d '{"action": "daily_maintenance"}'

# Run performance monitoring only
curl -X POST $FUNCTION_URL \
  -H "Content-Type: application/json" \
  -d '{"action": "performance_monitoring"}'
```

### Log Analysis

```bash
# View function logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --limit=50

# View scheduler logs
gcloud logging read "resource.type=cloud_scheduler_job" \
  --limit=20 \
  --format=json
```

## Troubleshooting

### Common Issues

#### 1. API Not Enabled

```
Error: Error creating instance: googleapi: Error 403: Access Not Configured
```

**Solution**: Ensure all required APIs are enabled:

```bash
gcloud services enable sqladmin.googleapis.com cloudfunctions.googleapis.com \
  cloudscheduler.googleapis.com monitoring.googleapis.com \
  logging.googleapis.com storage.googleapis.com
```

#### 2. Insufficient Permissions

```
Error: Error creating service account: googleapi: Error 403: Permission denied
```

**Solution**: Verify your account has required IAM roles:

```bash
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)"
```

#### 3. Function Deployment Fails

```
Error: Error creating function: source archive does not exist
```

**Solution**: Ensure function source directory exists and contains required files:

```bash
ls -la function-source/
# Should contain: main.py, requirements.txt
```

#### 4. Database Connection Issues

```
Error: Can't connect to MySQL server
```

**Solution**: Check authorized networks and firewall rules:

```bash
# Verify instance status
gcloud sql instances describe $(terraform output -raw sql_instance_name)

# Check network configuration
terraform show | grep authorized_networks -A 5
```

### Debug Mode

Enable detailed logging:

```bash
# Set Terraform debug logging
export TF_LOG=DEBUG
export TF_LOG_PATH=terraform-debug.log

# Run terraform with debug output
terraform apply
```

### Support Resources

- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Cost Estimation

### Monthly Cost Breakdown (Estimated)

| Component | Configuration | Estimated Cost |
|-----------|---------------|----------------|
| Cloud SQL (db-f1-micro) | 1 instance, 10GB storage | $7-15/month |
| Cloud Functions | ~60 executions/month | $0-2/month |
| Cloud Scheduler | 2 jobs | $0.10/month |
| Cloud Storage | 10GB with lifecycle | $0.50/month |
| Cloud Monitoring | Custom metrics and alerts | $0-8/month |
| **Total** | | **$8-25/month** |

### Cost Optimization Tips

1. **Use appropriate instance tiers**: Start with `db-f1-micro` for development
2. **Configure lifecycle policies**: Automatically transition old logs to cheaper storage
3. **Monitor usage**: Review Cloud Billing reports regularly
4. **Enable deletion protection**: Prevent accidental resource deletion in production

## Security Best Practices

### Database Security

- Use strong passwords (minimum 8 characters, mixed case, numbers, symbols)
- Enable SSL/TLS encryption for connections
- Restrict authorized networks to minimum required IP ranges
- Enable deletion protection for production instances
- Regularly rotate database passwords

### Function Security

- Use least privilege IAM roles for service accounts
- Avoid hardcoding sensitive values in environment variables
- Use Google Secret Manager for production secrets
- Enable VPC connector for private network access
- Implement proper error handling to avoid information disclosure

### Storage Security

- Enable uniform bucket-level access
- Configure appropriate lifecycle policies
- Use versioning for important data
- Implement proper retention policies for compliance
- Monitor access patterns with Cloud Audit Logs

## Backup and Disaster Recovery

### Automated Backups

The solution includes comprehensive backup strategies:

- **Database Backups**: Automated daily backups with 7-day retention
- **Point-in-Time Recovery**: Enabled with binary logging
- **Cross-Region Backups**: Configure for disaster recovery
- **Maintenance Reports**: Stored in Cloud Storage with lifecycle management

### Recovery Procedures

```bash
# List available backups
gcloud sql backups list --instance=$(terraform output -raw sql_instance_name)

# Restore from backup
gcloud sql backups restore BACKUP_ID \
  --restore-instance=NEW_INSTANCE_NAME \
  --backup-instance=$(terraform output -raw sql_instance_name)
```

## Contributing

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make changes and test locally
4. Submit pull request with comprehensive description
5. Ensure all tests pass and documentation is updated

### Testing

```bash
# Validate Terraform configuration
terraform validate

# Format code
terraform fmt -recursive

# Security scanning (if using tfsec)
tfsec .

# Plan without applying
terraform plan -detailed-exitcode
```

## License

This Infrastructure as Code is provided under the same license as the parent project. See the main repository LICENSE file for details.

## Support

For issues related to this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation for specific services
3. Search existing issues in the repository
4. Create a new issue with detailed information about the problem

For Google Cloud platform support, refer to [Google Cloud Support](https://cloud.google.com/support).