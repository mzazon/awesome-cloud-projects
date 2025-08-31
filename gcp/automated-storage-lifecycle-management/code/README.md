# Infrastructure as Code for Automated Storage Lifecycle Management with Cloud Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Storage Lifecycle Management with Cloud Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (`gcloud`)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Storage (Storage Admin)
  - Cloud Scheduler (Cloud Scheduler Admin)
  - Cloud Functions (Cloud Functions Admin)
  - Service Usage (Service Usage Admin)
  - App Engine (App Engine Admin)
  - Logging (Logging Admin)
- For Terraform: Terraform CLI installed (version 1.0+)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for deploying and managing infrastructure using infrastructure as code.

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="storage-lifecycle-demo"

# Create the Infrastructure Manager deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/inputs.yaml"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides a consistent workflow for managing Google Cloud resources with state management and planning capabilities.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct gcloud CLI commands for straightforward deployment and cleanup.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Run deployment script
./scripts/deploy.sh

# Check deployment status
gcloud storage buckets list --filter="name:storage-lifecycle-demo-*"
gcloud scheduler jobs list --location=${REGION}
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml` to customize:

```yaml
project_id: "your-project-id"
region: "us-central1"
bucket_location: "US"
lifecycle_standard_days: 30
lifecycle_nearline_days: 90
lifecycle_coldline_days: 365
lifecycle_delete_days: 2555
scheduler_frequency: "0 9 * * 1"  # Weekly on Monday at 9 AM
```

### Terraform Variables

Customize deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
bucket_location = "US"

# Lifecycle policy configuration
lifecycle_rules = {
  standard_to_nearline = 30
  nearline_to_coldline = 90
  coldline_to_archive = 365
  delete_after_days = 2555
}

# Scheduler configuration
scheduler_job_schedule = "0 9 * * 1"
scheduler_timezone = "America/New_York"
```

### Bash Script Environment Variables

Set these environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BUCKET_LOCATION="US"
export LIFECYCLE_STANDARD_DAYS=30
export LIFECYCLE_NEARLINE_DAYS=90
export LIFECYCLE_COLDLINE_DAYS=365
export LIFECYCLE_DELETE_DAYS=2555
export SCHEDULER_FREQUENCY="0 9 * * 1"
```

## Resource Overview

This infrastructure creates the following Google Cloud resources:

- **Cloud Storage Bucket**: Primary storage bucket with lifecycle policies
- **Cloud Storage Bucket (Logs)**: Secondary bucket for audit logs
- **Lifecycle Policy**: Automated storage class transitions and deletion rules
- **Cloud Scheduler Job**: Weekly automation for lifecycle reporting
- **Cloud Logging Sink**: Centralized logging for storage events
- **IAM Service Accounts**: Proper permissions for automation components
- **API Enablement**: Required Google Cloud APIs

## Lifecycle Policy Details

The deployed lifecycle policy implements these transitions:

1. **Standard → Nearline**: After 30 days
2. **Nearline → Coldline**: After 90 days (total: 120 days)
3. **Coldline → Archive**: After 365 days (total: 485 days)
4. **Delete Objects**: After 2555 days (~7 years)

## Cost Optimization

Expected cost reductions through lifecycle management:

- **Nearline Storage**: ~50% cost reduction from Standard
- **Coldline Storage**: ~75% cost reduction from Standard  
- **Archive Storage**: ~80% cost reduction from Standard
- **Automated Deletion**: Eliminates long-term storage costs

## Monitoring and Validation

### Check Deployment Status

```bash
# Verify bucket creation and lifecycle policy
gcloud storage buckets describe gs://storage-lifecycle-demo-* --format="yaml(lifecycle,location)"

# Check scheduler job status
gcloud scheduler jobs list --location=${REGION} --format="table(name,schedule,state)"

# View logging sink configuration
gcloud logging sinks list --filter="name:storage-lifecycle-sink"

# Monitor storage usage
gcloud storage du gs://storage-lifecycle-demo-* --summarize
```

### View Logs and Metrics

```bash
# View lifecycle-related logs
gcloud logging read 'resource.type="gcs_bucket" AND jsonPayload.eventType="OBJECT_FINALIZE"' --limit=10

# Check scheduler job execution history
gcloud scheduler jobs describe storage-lifecycle-job --location=${REGION} --format="yaml(status,lastAttemptTime)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} --quiet

# Verify resource cleanup
gcloud storage buckets list --filter="name:storage-lifecycle-demo-*"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup completed
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
gcloud storage buckets list --filter="name:storage-lifecycle-demo-*"
gcloud scheduler jobs list --location=${REGION} --filter="name:*lifecycle*"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure required APIs are enabled
   ```bash
   gcloud services list --enabled --filter="name:(storage.googleapis.com OR cloudscheduler.googleapis.com)"
   ```

2. **Insufficient Permissions**: Verify IAM roles
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:user:YOUR_EMAIL"
   ```

3. **App Engine Required**: Cloud Scheduler requires App Engine
   ```bash
   gcloud app describe --format="yaml(id,locationId)"
   ```

4. **Lifecycle Policy Delay**: Policies take up to 24 hours to take effect
   ```bash
   # Check policy application status
   gcloud storage buckets describe gs://your-bucket-name --format="yaml(lifecycle)"
   ```

### Validation Commands

```bash
# Test scheduler job manually
gcloud scheduler jobs run lifecycle-cleanup-job --location=${REGION}

# Upload test files to verify lifecycle behavior
echo "test data" | gcloud storage cp - gs://your-bucket-name/test-file.txt

# Monitor object storage class over time
gcloud storage ls -L gs://your-bucket-name/ --format="table(name,storageClass,timeCreated)"
```

## Security Considerations

- Lifecycle policies are applied automatically and cannot be bypassed
- IAM permissions follow least-privilege principle
- Logging captures all storage operations for audit compliance
- Scheduled jobs use service accounts with minimal required permissions
- Bucket access is controlled through uniform bucket-level access

## Best Practices

1. **Test Before Production**: Validate lifecycle policies with test data first
2. **Monitor Costs**: Use Cloud Billing alerts to track storage cost changes
3. **Regular Reviews**: Periodically review and adjust lifecycle rules based on usage patterns
4. **Backup Critical Data**: Ensure important data has appropriate backup strategies before deletion rules take effect
5. **Document Retention**: Align lifecycle policies with organizational data retention requirements

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation in the parent directory
2. Check Google Cloud documentation for service-specific guidance
3. Verify IAM permissions and API enablement
4. Review Cloud Logging for detailed error messages
5. Consult Google Cloud support for platform-specific issues

## Related Resources

- [Cloud Storage Lifecycle Management](https://cloud.google.com/storage/docs/lifecycle)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Infrastructure Manager Guide](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Storage Cost Optimization](https://cloud.google.com/architecture/framework/cost-optimization)