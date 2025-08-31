# Infrastructure as Code for Automated File Backup with Storage and Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated File Backup with Storage and Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code using YAML configuration
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language (HCL)  
- **Scripts**: Bash deployment and cleanup scripts for direct gcloud CLI automation

## Prerequisites

- Google Cloud account with billing enabled
- Google Cloud CLI installed and configured (or use Cloud Shell)
- Required IAM permissions:
  - `roles/storage.admin` - Manage Cloud Storage buckets and objects
  - `roles/cloudfunctions.admin` - Deploy and manage Cloud Functions
  - `roles/cloudscheduler.admin` - Create and manage Cloud Scheduler jobs
  - `roles/logging.admin` - Configure Cloud Logging and monitoring
  - `roles/monitoring.admin` - Set up monitoring policies and alerts
- Python 3.11+ runtime environment knowledge for Cloud Functions
- Basic understanding of serverless architecture and backup strategies
- Estimated cost: ~$0.50-2.00 USD per month for small-scale backup operations

## Architecture Overview

This solution deploys:

- **Cloud Storage Buckets**: Primary bucket (Standard storage) and backup bucket (Nearline storage) with versioning enabled
- **Cloud Function**: Python-based serverless function that copies files between buckets with error handling and logging
- **Cloud Scheduler**: Cron-based job scheduler that triggers daily backups at 2 AM UTC
- **Cloud Logging**: Centralized logging for backup operations and audit trails
- **Cloud Monitoring**: Alert policies for backup failure notifications

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native IaC service that provides declarative resource management with built-in state management.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply backup-infrastructure \
    --location=${REGION} \
    --config=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe backup-infrastructure \
    --location=${REGION}
```

### Using Terraform

Terraform provides multi-cloud infrastructure management with extensive provider ecosystem and state management capabilities.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review planned infrastructure changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply infrastructure configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View deployed resource outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct gcloud CLI automation for users who prefer imperative infrastructure management.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure using gcloud CLI commands
./scripts/deploy.sh

# Verify deployment
gcloud storage ls --project=${PROJECT_ID}
gcloud functions list --project=${PROJECT_ID}
gcloud scheduler jobs list --location=${REGION} --project=${PROJECT_ID}
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `primary_storage_class`: Primary bucket storage class (default: STANDARD)
- `backup_storage_class`: Backup bucket storage class (default: NEARLINE)
- `backup_schedule`: Cron schedule for backups (default: "0 2 * * *")
- `function_memory`: Cloud Function memory allocation (default: 256MB)
- `function_timeout`: Cloud Function timeout (default: 60s)

### Terraform Variables

Configure in `terraform/terraform.tfvars` or via command line:

```hcl
# terraform.tfvars
project_id = "your-project-id"
region = "us-central1"
primary_bucket_name = "primary-data-bucket"
backup_bucket_name = "backup-data-bucket"
function_name = "backup-files-function"
backup_schedule = "0 2 * * *"
```

### Bash Script Variables

Modify environment variables in `scripts/deploy.sh`:

```bash
# Customize deployment parameters
export REGION="us-central1"
export PRIMARY_STORAGE_CLASS="STANDARD"
export BACKUP_STORAGE_CLASS="NEARLINE"
export FUNCTION_MEMORY="256MB"
export BACKUP_SCHEDULE="0 2 * * *"
```

## Validation and Testing

### Verify Infrastructure

```bash
# Check Cloud Storage buckets
gcloud storage ls --project=${PROJECT_ID}

# Verify Cloud Function deployment
gcloud functions describe backup-files-function \
    --region=${REGION} \
    --project=${PROJECT_ID}

# Check Cloud Scheduler job
gcloud scheduler jobs describe backup-daily-job \
    --location=${REGION} \
    --project=${PROJECT_ID}
```

### Test Backup Functionality

```bash
# Upload test files to primary bucket
echo "Test data - $(date)" > test-file.txt
gcloud storage cp test-file.txt gs://your-primary-bucket/

# Trigger backup function manually
gcloud functions call backup-files-function \
    --region=${REGION} \
    --project=${PROJECT_ID}

# Verify backup creation
gcloud storage ls gs://your-backup-bucket/
```

### Monitor Logs

```bash
# View function execution logs
gcloud functions logs read backup-files-function \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --limit=10

# Check scheduler job execution history
gcloud scheduler jobs describe backup-daily-job \
    --location=${REGION} \
    --project=${PROJECT_ID} \
    --format="table(name,schedule,state,lastAttemptTime)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete backup-infrastructure \
    --location=${REGION} \
    --quiet

# Verify resource cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all managed infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
gcloud storage ls --project=${PROJECT_ID}
gcloud functions list --project=${PROJECT_ID}
gcloud scheduler jobs list --location=${REGION} --project=${PROJECT_ID}
```

## Security Considerations

- **IAM Permissions**: Cloud Function uses service account with minimal required permissions
- **Bucket Access**: Uniform bucket-level access control enabled for consistent security
- **Environment Variables**: Sensitive configuration stored as environment variables, not hardcoded
- **Network Security**: Cloud Function deployed with default VPC security settings
- **Data Encryption**: Cloud Storage provides encryption at rest and in transit by default
- **Audit Logging**: All backup operations logged to Cloud Logging for compliance tracking

## Cost Optimization

- **Storage Classes**: Primary bucket uses Standard storage, backup bucket uses Nearline for cost efficiency
- **Function Sizing**: Cloud Function configured with minimal memory (256MB) for cost optimization
- **Serverless Architecture**: Pay-per-use pricing model scales with actual backup operations
- **Lifecycle Policies**: Consider implementing automatic archival to Archive storage class for long-term retention

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure service account has required IAM roles
2. **API Not Enabled**: Verify all required APIs are enabled in your project
3. **Function Timeout**: Increase timeout for large backup operations
4. **Storage Quota**: Check project quota limits for storage and function resources

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --project=${PROJECT_ID}

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Test function locally (requires Functions Framework)
functions-framework --target=backup_files --debug
```

## Customization

### Extending the Solution

1. **Incremental Backups**: Modify Cloud Function to track file changes and only backup modified files
2. **Cross-Region Replication**: Deploy backup bucket in different region for disaster recovery
3. **Retention Policies**: Implement lifecycle rules to automatically delete old backups
4. **Notification Integration**: Add Pub/Sub or email notifications for backup status
5. **Monitoring Dashboard**: Create custom Cloud Monitoring dashboard for backup metrics

### Additional Features

- **Backup Verification**: Periodic integrity checks of backup files
- **Encryption**: Custom encryption keys for sensitive data protection
- **Compression**: File compression before backup to reduce storage costs
- **Multi-Source Backup**: Support for multiple source buckets or external data sources

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for context and troubleshooting guidance
2. Consult [Google Cloud Storage documentation](https://cloud.google.com/storage/docs) for storage-related issues
3. Check [Cloud Functions documentation](https://cloud.google.com/functions/docs) for function deployment problems
4. Reference [Cloud Scheduler documentation](https://cloud.google.com/scheduler/docs) for scheduling configuration
5. Use [Google Cloud Support](https://cloud.google.com/support) for production issues

## Best Practices

- **Version Control**: Store IaC configurations in version control systems
- **Environment Separation**: Use separate deployments for development, staging, and production
- **State Management**: For Terraform, use remote state storage with Cloud Storage backend
- **Resource Naming**: Follow consistent naming conventions with environment prefixes
- **Documentation**: Maintain up-to-date documentation for custom modifications
- **Testing**: Implement automated testing for infrastructure changes
- **Monitoring**: Set up comprehensive monitoring and alerting for production deployments