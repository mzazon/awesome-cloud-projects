# Infrastructure as Code for Data Migration Workflows with Cloud Storage Bucket Relocation and Eventarc

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Migration Workflows with Cloud Storage Bucket Relocation and Eventarc".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Storage Admin
  - Cloud Functions Admin
  - Eventarc Admin
  - Cloud Audit Logs Viewer
  - Service Account Admin
  - BigQuery Admin
  - Cloud Monitoring Admin
- Terraform installed (version 1.0 or later) if using Terraform implementation
- `jq` utility installed for JSON processing in scripts

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/migration-workflow \
    --service-account SERVICE_ACCOUNT_EMAIL \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=PROJECT_ID,region=REGION,source_region=SOURCE_REGION,dest_region=DEST_REGION"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=PROJECT_ID" -var="region=REGION"

# Deploy the infrastructure
terraform apply -var="project_id=PROJECT_ID" -var="region=REGION"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export SOURCE_REGION="us-west1"
export DEST_REGION="us-east1"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Storage Bucket**: Source bucket with sample data and configurations
- **Cloud Functions**: Three functions for migration workflow automation
  - Pre-migration validator
  - Migration progress monitor
  - Post-migration validator
- **Eventarc Triggers**: Event-driven automation for storage operations
- **Service Account**: IAM service account with necessary permissions
- **BigQuery Dataset**: Audit log storage and analysis
- **Cloud Monitoring**: Alert policies for migration events
- **Audit Log Sinks**: Comprehensive logging for compliance

## Configuration Variables

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id: "your-project-id"
  region: "us-central1"
  source_region: "us-west1"
  dest_region: "us-east1"
  bucket_name_prefix: "migration-demo"
  enable_versioning: true
  enable_audit_logs: true
```

### Terraform Variables

Available in `terraform/variables.tf`:

- `project_id`: GCP project ID
- `region`: Primary region for functions and triggers
- `source_region`: Source bucket region
- `dest_region`: Destination region for migration
- `bucket_name_prefix`: Prefix for bucket names
- `enable_versioning`: Enable bucket versioning
- `enable_audit_logs`: Enable comprehensive audit logging
- `alert_email`: Email for monitoring alerts

Example `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
source_region = "us-west1"
dest_region = "us-east1"
bucket_name_prefix = "migration-demo"
enable_versioning = true
enable_audit_logs = true
alert_email = "admin@example.com"
```

### Bash Script Variables

Set these environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export SOURCE_REGION="us-west1"
export DEST_REGION="us-east1"
export BUCKET_NAME_PREFIX="migration-demo"
export ALERT_EMAIL="admin@example.com"
```

## Deployment Steps

### 1. Pre-Deployment Validation

```bash
# Verify CLI authentication
gcloud auth list

# Check project permissions
gcloud projects get-iam-policy $PROJECT_ID

# Verify required APIs are enabled
gcloud services list --enabled --filter="name:storage.googleapis.com OR name:cloudfunctions.googleapis.com OR name:eventarc.googleapis.com"
```

### 2. Deploy Infrastructure

Choose one of the deployment methods above based on your preference.

### 3. Post-Deployment Verification

```bash
# Verify Cloud Functions are deployed
gcloud functions list --region=$REGION

# Check Eventarc triggers
gcloud eventarc triggers list --location=$REGION

# Verify BigQuery dataset
bq ls -d migration_audit

# Test bucket creation
gsutil ls gs://migration-source-*
```

## Testing the Migration Workflow

### 1. Trigger Migration

```bash
# Get the source bucket name
SOURCE_BUCKET=$(gsutil ls gs://migration-source-* | head -1 | sed 's/gs:\/\///' | sed 's/\///')

# Initiate bucket relocation
gcloud storage buckets relocate gs://$SOURCE_BUCKET --location=$DEST_REGION --async
```

### 2. Monitor Progress

```bash
# Check Cloud Function logs
gcloud logging read "resource.type=\"cloud_function\" AND timestamp>=\"$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)\"" --limit=10

# Monitor relocation operations
gcloud storage operations list --filter="metadata.verb=relocate"

# Check BigQuery audit logs
bq query --use_legacy_sql=false "SELECT timestamp, protopayload_auditlog.methodName FROM \`$PROJECT_ID.migration_audit.cloudaudit_googleapis_com_activity_*\` WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR) ORDER BY timestamp DESC LIMIT 10"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/migration-workflow
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=PROJECT_ID" -var="region=REGION"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining buckets
gsutil ls gs://migration-* | xargs gsutil -m rm -r

# Delete Cloud Functions
gcloud functions delete pre-migration-validator --region=$REGION --quiet
gcloud functions delete migration-progress-monitor --region=$REGION --quiet
gcloud functions delete post-migration-validator --region=$REGION --quiet

# Delete Eventarc triggers
gcloud eventarc triggers delete bucket-admin-trigger --location=$REGION --quiet
gcloud eventarc triggers delete object-event-trigger --location=$REGION --quiet

# Delete BigQuery dataset
bq rm -r -f migration_audit

# Delete service account
gcloud iam service-accounts delete migration-automation@$PROJECT_ID.iam.gserviceaccount.com --quiet
```

## Monitoring and Observability

### Cloud Monitoring Dashboards

The infrastructure creates monitoring resources for:

- Migration operation metrics
- Cloud Function execution metrics
- Storage operation counters
- Error rate monitoring

### Logging and Audit

- **Cloud Audit Logs**: Comprehensive tracking of all API operations
- **BigQuery Integration**: Structured audit log analysis
- **Cloud Function Logs**: Application-level migration workflow logs
- **Eventarc Event Logs**: Event processing and trigger execution logs

### Alerting

Pre-configured alerts for:

- Migration operation failures
- Cloud Function execution errors
- Bucket accessibility issues
- Compliance validation failures

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check service account permissions
   gcloud iam service-accounts get-iam-policy migration-automation@$PROJECT_ID.iam.gserviceaccount.com
   ```

2. **Function Deployment Failures**
   ```bash
   # Check function logs
   gcloud logging read "resource.type=\"cloud_function\" AND severity>=ERROR" --limit=10
   ```

3. **Eventarc Trigger Issues**
   ```bash
   # List trigger status
   gcloud eventarc triggers list --location=$REGION
   ```

4. **BigQuery Access Issues**
   ```bash
   # Verify dataset permissions
   bq show --format=prettyjson migration_audit
   ```

### Debug Mode

Enable debug logging in bash scripts:

```bash
export DEBUG=true
./scripts/deploy.sh
```

## Cost Considerations

### Estimated Costs

- **Cloud Storage**: ~$0.02/GB/month (Standard class)
- **Cloud Functions**: ~$0.40/million invocations
- **Eventarc**: ~$0.40/million events
- **BigQuery**: ~$5/TB processed
- **Cloud Monitoring**: Free tier usually sufficient

### Cost Optimization

- Use appropriate storage classes for different data types
- Configure lifecycle policies to automatically transition data
- Set up BigQuery partitioning for audit logs
- Use Cloud Function concurrency limits to control costs

## Security Best Practices

### IAM Configuration

- Service accounts follow principle of least privilege
- Separate service accounts for different functions
- Regular IAM policy reviews

### Data Protection

- Encryption at rest enabled by default
- Bucket versioning for data protection
- Audit logging for compliance

### Network Security

- VPC firewall rules for function access
- Private Google Access for internal traffic
- HTTPS-only access for all services

## Customization

### Adding Custom Validation Logic

Edit Cloud Function source code in the deployed functions:

```python
# Add custom validation rules in pre-migration validator
def custom_compliance_check(bucket):
    # Your custom logic here
    return True
```

### Extending Monitoring

Add custom metrics in the progress monitor function:

```python
# Custom metric creation
series.metric.type = 'custom.googleapis.com/migration/your-metric'
```

### Integration with External Systems

Modify functions to integrate with:
- External compliance systems
- Custom notification services
- Data governance platforms

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../data-migration-workflows-storage-bucket-relocation-eventarc.md)
2. Review [Google Cloud Storage documentation](https://cloud.google.com/storage/docs)
3. Consult [Eventarc documentation](https://cloud.google.com/eventarc/docs)
4. Reference [Cloud Functions documentation](https://cloud.google.com/functions/docs)

## License

This infrastructure code is provided under the same license as the recipe collection.