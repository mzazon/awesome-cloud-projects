# Terraform Infrastructure for Automated File Backup with Storage and Scheduler

This Terraform configuration creates an automated file backup system on Google Cloud Platform using Cloud Storage, Cloud Functions, and Cloud Scheduler.

## Architecture Overview

The solution deploys:
- **Primary Storage Bucket**: Standard storage class for active data
- **Backup Storage Bucket**: Nearline storage class for cost-effective backups
- **Cloud Function**: Python-based backup logic with error handling
- **Cloud Scheduler**: Daily automated backup job at 2 AM UTC
- **Service Accounts**: Minimal privilege accounts for function and scheduler
- **Monitoring**: Log-based metrics and alerting for backup failures
- **Sample Files**: Optional test data for validation

## Prerequisites

1. **Google Cloud Account**: Active GCP project with billing enabled
2. **Terraform**: Version >= 1.0 installed
3. **Google Cloud CLI**: Installed and authenticated
4. **Required APIs**: The following APIs will be enabled automatically:
   - Cloud Functions API
   - Cloud Scheduler API
   - Cloud Storage API
   - Cloud Logging API
   - Cloud Build API

## Required Permissions

Your GCP account/service account needs these IAM roles:
- `roles/storage.admin` - To create and manage storage buckets
- `roles/cloudfunctions.admin` - To deploy Cloud Functions
- `roles/cloudscheduler.admin` - To create scheduled jobs
- `roles/iam.serviceAccountAdmin` - To create service accounts
- `roles/resourcemanager.projectIamAdmin` - To assign IAM roles
- `roles/monitoring.admin` - To create monitoring resources

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd gcp/automated-file-backup-storage-scheduler/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
environment             = "prod"
primary_bucket_name     = "my-primary-data"
backup_bucket_name      = "my-backup-data"
function_name          = "my-backup-function"
backup_schedule        = "0 2 * * *"  # Daily at 2 AM UTC
create_sample_files    = true
enable_versioning      = true

# Storage classes
primary_storage_class = "STANDARD"
backup_storage_class  = "NEARLINE"

# Function configuration
function_memory  = 256
function_timeout = 60

# Labels for resource management
labels = {
  purpose     = "automated-backup"
  environment = "production"
  team        = "infrastructure"
  managed-by  = "terraform"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check storage buckets
gcloud storage ls

# Verify Cloud Function
gcloud functions list --gen2

# Check scheduler job
gcloud scheduler jobs list

# Test the backup function manually
terraform output -raw verification_commands
```

## Configuration Options

### Storage Configuration

- **Primary Bucket**: Use `STANDARD` storage class for frequently accessed data
- **Backup Bucket**: Use `NEARLINE` or `COLDLINE` for cost optimization
- **Versioning**: Enable to protect against accidental deletions
- **Lifecycle Rules**: Automatic transition to cheaper storage classes

### Function Configuration

- **Memory**: 128MB to 8192MB (256MB recommended)
- **Timeout**: 1-540 seconds (60s recommended)
- **Runtime**: Python 3.11 with latest libraries
- **Scaling**: 0-10 instances based on demand

### Backup Schedule

- **Default**: Daily at 2 AM UTC (`0 2 * * *`)
- **Custom**: Use standard cron expressions
- **Timezone**: UTC (modify in `google_cloud_scheduler_job`)
- **Retry**: Automatic retry with exponential backoff

## Cost Optimization Features

1. **Storage Classes**: Automatic lifecycle transitions
   - Primary: STANDARD → NEARLINE (30 days) → COLDLINE (90 days)
   - Backup: NEARLINE → COLDLINE (60 days) → ARCHIVE (180 days)

2. **Serverless Computing**: Pay only for actual function execution time

3. **Monitoring**: Minimal cost for log-based metrics and alerting

## Security Features

- **Uniform Bucket Access**: Consistent IAM across all bucket objects
- **Public Access Prevention**: Blocks public access to sensitive data
- **Service Account**: Minimal required permissions (principle of least privilege)
- **Private Function**: Internal-only ingress settings
- **Audit Logging**: Comprehensive logging for security compliance

## Monitoring and Alerting

The configuration includes:

- **Cloud Logging**: Function execution logs with structured data
- **Log Metrics**: Automated error detection and counting
- **Alert Policies**: Notification on backup failures
- **Monitoring Dashboard**: (Optional) Create custom dashboards

### View Logs

```bash
# Function execution logs
gcloud functions logs read FUNCTION_NAME --gen2 --region=REGION --limit=20

# Scheduler job logs
gcloud logging read 'resource.type="cloud_scheduler_job"' --limit=10

# Error logs only
gcloud logging read 'severity="ERROR" AND resource.labels.function_name="FUNCTION_NAME"'
```

## Backup Strategy

### File Organization

Backups are organized by date for easy management:
```
backup-bucket/
├── backup-20240115/
│   ├── business-data.txt
│   ├── config.json
│   └── users.csv
├── backup-20240116/
│   ├── business-data.txt
│   └── updated-config.json
```

### Retention Policy

- **Automatic Transitions**: Files move to cheaper storage over time
- **Manual Cleanup**: Use lifecycle rules for automatic deletion
- **Compliance**: Adjust retention periods based on business requirements

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy PROJECT_ID
   
   # Verify function service account
   gcloud iam service-accounts get-iam-policy SERVICE_ACCOUNT_EMAIL
   ```

2. **Function Timeouts**
   - Increase `function_timeout` variable
   - Monitor function memory usage
   - Check for large file transfers

3. **Scheduler Job Failures**
   ```bash
   # Check job status
   gcloud scheduler jobs describe JOB_NAME --location=REGION
   
   # View recent executions
   gcloud logging read 'resource.type="cloud_scheduler_job"' --limit=10
   ```

4. **Storage Access Issues**
   - Verify bucket names are globally unique
   - Check IAM permissions on buckets
   - Ensure uniform bucket access is enabled

### Debug Mode

Enable detailed logging by modifying the function environment variables:

```hcl
environment_variables = {
  PRIMARY_BUCKET = google_storage_bucket.primary.name
  BACKUP_BUCKET  = google_storage_bucket.backup.name
  DEBUG_MODE     = "true"
  LOG_LEVEL      = "DEBUG"
}
```

## Customization Examples

### Change Backup Schedule

```hcl
# Backup every 6 hours
backup_schedule = "0 */6 * * *"

# Backup only on weekdays at 3 AM
backup_schedule = "0 3 * * 1-5"

# Backup twice daily (6 AM and 6 PM)
backup_schedule = "0 6,18 * * *"
```

### Multi-Region Backup

```hcl
# Create backup bucket in different region
resource "google_storage_bucket" "disaster_recovery_backup" {
  name     = "${var.backup_bucket_name}-dr-${local.name_suffix}"
  location = "us-east1"  # Different region
  
  storage_class = "COLDLINE"
  # ... other configuration
}
```

### Extended Retention

```hcl
# Keep backups for 7 years (compliance requirement)
lifecycle_rule {
  condition {
    age = 2555  # ~7 years in days
  }
  action {
    type = "Delete"
  }
}
```

## Cleanup

### Destroy Infrastructure

```bash
# Remove all Terraform-managed resources
terraform destroy

# Verify cleanup
gcloud storage ls
gcloud functions list --gen2
gcloud scheduler jobs list
```

### Manual Cleanup (if needed)

```bash
# Delete any remaining storage buckets with data
gsutil -m rm -r gs://BUCKET_NAME

# Delete function artifacts
gcloud storage rm -r gs://function-source-*

# Clean up local files
rm -f function-source.zip
rm -f function_code.py
```

## Outputs Reference

After deployment, Terraform provides useful outputs:

- **Bucket URLs**: Direct links to storage buckets
- **Function URI**: Endpoint for manual testing
- **Verification Commands**: Ready-to-use CLI commands
- **Cost Information**: Storage class and lifecycle details
- **Security Summary**: IAM roles and permissions

## Support and Maintenance

### Regular Maintenance

1. **Update Dependencies**: Keep Python libraries current
2. **Review Logs**: Monitor for errors or performance issues
3. **Cost Analysis**: Review storage usage and costs monthly
4. **Security Audit**: Verify IAM permissions quarterly

### Updates

To update the infrastructure:

```bash
# Update Terraform providers
terraform init -upgrade

# Plan changes
terraform plan

# Apply updates
terraform apply
```

### Backup Testing

Regularly test backup integrity:

```bash
# Manual function execution
curl -X POST "$(terraform output -raw cloud_function_uri)" \
     -H "Content-Type: application/json" \
     -d '{}'

# Download and verify backup files
gsutil cp gs://BACKUP_BUCKET/backup-YYYYMMDD/test-file.txt ./
```

For additional support, refer to the original recipe documentation or Google Cloud Platform documentation.