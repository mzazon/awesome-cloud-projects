# Infrastructure as Code for Automated Infrastructure Documentation using Asset Inventory and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Infrastructure Documentation using Asset Inventory and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code (HCL)
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated documentation system that:
- Uses Cloud Asset Inventory to discover all Google Cloud resources
- Processes asset data with Cloud Functions to generate documentation
- Stores multi-format outputs (HTML, Markdown, JSON) in Cloud Storage
- Schedules automatic updates via Cloud Scheduler
- Provides real-time infrastructure visibility for compliance and operational needs

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Terraform >= 1.0 (for Terraform implementation)
- Appropriate Google Cloud permissions:
  - `roles/cloudasset.viewer` - Access to Asset Inventory
  - `roles/cloudfunctions.admin` - Deploy Cloud Functions
  - `roles/storage.admin` - Manage Cloud Storage
  - `roles/pubsub.admin` - Create Pub/Sub topics
  - `roles/cloudscheduler.admin` - Create scheduled jobs
  - `roles/iam.serviceAccountAdmin` - Manage service accounts
- Project with billing enabled and required APIs activated:
  - Cloud Asset Inventory API
  - Cloud Functions API
  - Cloud Scheduler API
  - Pub/Sub API
  - Cloud Storage API

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution for managing cloud resources declaratively.

```bash
# Create a deployment with Infrastructure Manager
gcloud infra-manager deployments create asset-documentation \
    --location=us-central1 \
    --gcs-source=gs://YOUR_CONFIG_BUCKET/infrastructure-manager/main.yaml \
    --input-values="project_id=YOUR_PROJECT_ID,region=us-central1"

# Monitor deployment progress
gcloud infra-manager deployments describe asset-documentation \
    --location=us-central1

# Get deployment outputs
gcloud infra-manager deployments describe asset-documentation \
    --location=us-central1 \
    --format="value(outputs)"
```

### Using Terraform

Terraform provides a mature, multi-cloud approach with extensive provider ecosystem and state management capabilities.

```bash
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View important outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simple, CLI-based deployment approach ideal for quick testing and CI/CD integration.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Verify deployment
gcloud functions list --regions=${REGION}
gsutil ls gs://asset-docs-*
```

## Customization

### Key Configuration Parameters

All implementations support these customization options:

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `project_id` | Google Cloud Project ID | Required | `my-org-assets-prod` |
| `region` | Deployment region | `us-central1` | `europe-west1` |
| `schedule` | Cron schedule for documentation generation | `0 9 * * *` | `0 */6 * * *` |
| `function_memory` | Cloud Function memory allocation | `512MB` | `1GB` |
| `function_timeout` | Function timeout in seconds | `300` | `600` |
| `bucket_retention_days` | Documentation retention period | `90` | `365` |

### Terraform Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
project_id = "my-infrastructure-docs"
region = "us-central1"

# Custom naming
bucket_suffix = "company-assets"
function_name = "asset-documentation-generator"

# Scheduling
documentation_schedule = "0 6 * * *"  # Daily at 6 AM

# Performance tuning
function_memory = "1024MB"
function_timeout = 600

# Retention policy
enable_versioning = true
retention_days = 365

# Multi-project scanning (optional)
# organization_id = "123456789012"
# scan_all_projects = true
```

### Infrastructure Manager Variables

Create an `inputs.yaml` file for Infrastructure Manager:

```yaml
project_id: "my-infrastructure-docs"
region: "us-central1"
bucket_suffix: "company-assets"
function_name: "asset-documentation-generator"
documentation_schedule: "0 6 * * *"
function_memory: "1024MB"
function_timeout: 600
retention_days: 365
```

### Advanced Customization Options

1. **Multi-Project Scanning**: Configure organization-level asset inventory access
2. **Custom Documentation Templates**: Modify function code to include company branding
3. **Integration Endpoints**: Add webhooks to notify external systems of documentation updates
4. **Advanced Filtering**: Customize asset type filtering for specific compliance requirements
5. **Export Formats**: Add additional output formats (PDF, CSV, Excel)

## Outputs and Artifacts

After successful deployment, the following resources are available:

### Generated Documentation
- **HTML Reports**: `gs://BUCKET_NAME/reports/infrastructure-report.html`
- **Markdown Documentation**: `gs://BUCKET_NAME/reports/infrastructure-docs.md`
- **JSON Exports**: `gs://BUCKET_NAME/exports/asset-inventory.json`

### Monitoring and Logs
- **Function Logs**: Available in Cloud Logging under the Cloud Functions service
- **Scheduler Execution**: Monitor in Cloud Scheduler console
- **Asset Inventory Status**: Check Cloud Asset Inventory service for data freshness

### Access URLs
- **Cloud Function**: Available via Cloud Functions console or gcloud CLI
- **Storage Browser**: Access generated reports via Cloud Storage browser
- **Scheduler Jobs**: Monitor and manually trigger via Cloud Scheduler console

## Testing and Validation

### Manual Testing

```bash
# Trigger immediate documentation generation
gcloud pubsub topics publish asset-inventory-trigger \
    --message='{"trigger": "manual_test"}'

# Check function execution logs
gcloud functions logs read asset-doc-generator \
    --region=${REGION} \
    --limit=20

# Verify generated files
gsutil ls -la gs://asset-docs-*/reports/
gsutil ls -la gs://asset-docs-*/exports/

# Download and review reports
gsutil cp gs://asset-docs-*/reports/infrastructure-report.html ./
gsutil cp gs://asset-docs-*/reports/infrastructure-docs.md ./
```

### Automated Validation

```bash
# Verify all required APIs are enabled
gcloud services list --enabled --filter="name:cloudasset.googleapis.com OR name:cloudfunctions.googleapis.com OR name:cloudscheduler.googleapis.com"

# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:service-${PROJECT_NUMBER}@gcf-admin-robot.iam.gserviceaccount.com"

# Validate scheduler configuration
gcloud scheduler jobs describe daily-asset-docs \
    --location=${REGION} \
    --format="value(state,schedule,lastAttemptTime)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete asset-documentation \
    --location=us-central1 \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Clean up Terraform state (optional)
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify resource cleanup
gcloud functions list --regions=${REGION}
gsutil ls gs://asset-docs-* 2>/dev/null || echo "Storage buckets cleaned up"
gcloud scheduler jobs list --location=${REGION}
```

### Manual Cleanup Verification

```bash
# Check for any remaining resources
echo "=== Cloud Functions ==="
gcloud functions list --regions=${REGION}

echo "=== Storage Buckets ==="
gsutil ls -p ${PROJECT_ID} | grep asset-docs

echo "=== Pub/Sub Topics ==="
gcloud pubsub topics list --filter="name:asset-inventory-trigger"

echo "=== Scheduler Jobs ==="
gcloud scheduler jobs list --location=${REGION} --filter="name:daily-asset-docs"

echo "=== Service Accounts ==="
gcloud iam service-accounts list --filter="email:gcf-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

## Monitoring and Maintenance

### Performance Monitoring

- **Function Execution Time**: Monitor via Cloud Monitoring metrics
- **Memory Usage**: Track memory consumption and adjust allocation as needed
- **Error Rates**: Set up alerts for function failures or timeouts
- **Asset Inventory Quota**: Monitor API quota usage for large organizations

### Cost Optimization

- **Function Concurrency**: Limit concurrent executions to control costs
- **Storage Lifecycle**: Implement automatic deletion of old documentation versions
- **Scheduling Frequency**: Adjust documentation generation frequency based on change velocity
- **Regional Deployment**: Deploy in cost-effective regions while considering data locality

### Security Best Practices

- **Service Account Permissions**: Regularly audit and minimize IAM roles
- **Bucket Access**: Ensure documentation buckets have appropriate access controls
- **Function Code**: Keep function dependencies updated for security patches
- **Asset Inventory Access**: Monitor access patterns and implement least privilege

## Troubleshooting

### Common Issues

1. **Function Timeout**: Increase timeout for large organizations or adjust memory allocation
2. **Permission Denied**: Verify service account has required Asset Inventory access
3. **Storage Errors**: Check bucket existence and permissions
4. **Schedule Not Running**: Verify Cloud Scheduler job is enabled and properly configured

### Debug Commands

```bash
# Check function deployment status
gcloud functions describe asset-doc-generator --region=${REGION}

# Review recent function logs
gcloud functions logs read asset-doc-generator \
    --region=${REGION} \
    --limit=50 \
    --format="table(timestamp,textPayload)"

# Test Pub/Sub connectivity
gcloud pubsub topics publish asset-inventory-trigger \
    --message='{"debug": true}'

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:*gcf-admin-robot*"
```

## Support and Documentation

- **Recipe Documentation**: Refer to the original recipe markdown file for detailed implementation steps
- **Google Cloud Asset Inventory**: [Official Documentation](https://cloud.google.com/asset-inventory/docs)
- **Cloud Functions**: [Best Practices Guide](https://cloud.google.com/functions/docs/bestpractices)
- **Infrastructure Manager**: [Getting Started Guide](https://cloud.google.com/infrastructure-manager/docs)
- **Terraform Google Provider**: [Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

To improve this infrastructure code:

1. Follow Google Cloud best practices for resource naming and configuration
2. Ensure all changes maintain security and compliance requirements
3. Test infrastructure changes in development environments first
4. Update documentation to reflect any configuration changes
5. Consider backward compatibility when modifying existing resources

---

**Note**: This infrastructure as code is designed to work with the automated infrastructure documentation recipe. Customize the configuration based on your organization's specific requirements for compliance, security, and operational needs.