# Cloud Asset Governance Infrastructure as Code

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive Cloud Asset Governance system on Google Cloud Platform. The infrastructure implements automated policy evaluation, compliance monitoring, and governance workflows using Cloud Asset Inventory, Cloud Workflows, Cloud Functions, and supporting services.

## Architecture Overview

The governance system consists of:

- **Cloud Asset Inventory**: Monitors resource changes across your organization
- **Pub/Sub**: Handles event-driven asset change notifications
- **Cloud Functions**: Executes policy evaluation and workflow triggering logic
- **Cloud Workflows**: Orchestrates governance processes and remediation
- **BigQuery**: Stores compliance data and violation analytics
- **Cloud Storage**: Manages governance artifacts and policies
- **Cloud Monitoring**: Provides alerting and operational visibility

## Prerequisites

### Required Tools

- [Terraform](https://terraform.io/downloads.html) >= 1.0
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) >= 400.0.0
- Google Cloud project with billing enabled
- Organization-level access for Cloud Asset Inventory

### Required Permissions

The deploying user/service account needs:

- `Organization Admin` or `Security Admin` (for asset feeds)
- `Project Owner` or equivalent permissions:
  - `BigQuery Admin`
  - `Cloud Functions Admin` 
  - `Workflows Admin`
  - `Pub/Sub Admin`
  - `Storage Admin`
  - `Service Account Admin`
  - `Monitoring Admin`

### Google Cloud APIs

The following APIs will be automatically enabled:

- Cloud Asset API (`cloudasset.googleapis.com`)
- Cloud Workflows API (`workflows.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Pub/Sub API (`pubsub.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd gcp/cloud-asset-governance-asset-inventory-workflows/code/terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your configuration
nano terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Deploy the governance system
terraform apply

# Confirm deployment when prompted
# Type: yes
```

### 4. Verify Deployment

```bash
# Check asset feed status
gcloud asset feeds list --organization=$(terraform output -raw organization_id)

# Verify Pub/Sub infrastructure
gcloud pubsub topics list --filter="name:$(terraform output -raw asset_changes_topic)"

# Check Cloud Functions
gcloud functions list --region=$(terraform output -raw region) --filter="name:governance"

# Verify BigQuery dataset
bq ls $(terraform output -raw bigquery_dataset_id)
```

## Configuration

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `organization_id` | Organization ID for monitoring | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `governance_suffix` | Unique suffix for resource names | Auto-generated | No |

### Asset Monitoring

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `asset_types_to_monitor` | Asset types for governance | Bucket, Instance, Dataset | No |
| `content_type` | Asset feed content type | `RESOURCE` | No |
| `message_retention_days` | Pub/Sub retention period | `7` | No |

### Function Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `function_memory` | Function memory allocation (MB) | `512` | No |
| `function_timeout` | Function timeout (seconds) | `540` | No |
| `max_function_instances` | Maximum function instances | `20` | No |

### Monitoring & Alerting

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_monitoring_alerts` | Enable Cloud Monitoring alerts | `true` | No |
| `notification_email` | Email for governance alerts | - | No |

## Outputs

The Terraform configuration provides comprehensive outputs for verification and integration:

### Key Infrastructure Outputs

- `governance_bucket_name`: Storage bucket for governance artifacts
- `bigquery_dataset_id`: Dataset for compliance analytics
- `asset_changes_topic`: Pub/Sub topic for asset notifications
- `governance_workflow_name`: Main orchestration workflow
- `policy_evaluator_function_url`: Policy evaluation endpoint

### Operational Outputs

- `verification_commands`: Commands to verify deployment
- `sample_queries`: BigQuery queries for governance analysis
- `console_urls`: Direct links to Google Cloud Console resources
- `estimated_monthly_costs`: Cost estimates for planning

### Security Outputs

- `governance_service_account_email`: Service account for operations
- `governance_kms_crypto_key`: Encryption key for governance data

## Usage Examples

### Testing Policy Evaluation

```bash
# Get the policy evaluator function URL
FUNCTION_URL=$(terraform output -raw policy_evaluator_function_url)

# Test with sample storage bucket
curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "asset": {
      "name": "//storage.googleapis.com/projects/test/buckets/my-bucket",
      "assetType": "storage.googleapis.com/Bucket",
      "resource": {
        "data": {
          "name": "my-bucket",
          "location": "US"
        }
      }
    }
  }'
```

### Querying Violations

```bash
# Get dataset ID
DATASET_ID=$(terraform output -raw bigquery_dataset_id)

# Query recent violations
bq query --use_legacy_sql=false \
  "SELECT * FROM \`$DATASET_ID.asset_violations\` 
   WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR) 
   ORDER BY timestamp DESC LIMIT 10"
```

### Monitoring Workflow Executions

```bash
# List recent workflow executions
WORKFLOW_NAME=$(terraform output -raw governance_workflow_name)
REGION=$(terraform output -raw region)

gcloud workflows executions list $WORKFLOW_NAME \
  --location=$REGION \
  --limit=10
```

## Customization

### Adding Custom Policies

1. Modify `function_code/policy_evaluator.py`
2. Add new policy evaluation methods
3. Update the asset evaluation router
4. Redeploy with `terraform apply`

### Custom Asset Types

1. Update `asset_types_to_monitor` variable
2. Add policy evaluation logic for new types
3. Apply changes with `terraform apply`

### Custom Alerting

1. Modify monitoring configuration in `main.tf`
2. Add custom alert policies
3. Configure additional notification channels

## Troubleshooting

### Common Issues

**Asset Feed Creation Fails**
```bash
# Check organization permissions
gcloud organizations get-iam-policy $ORGANIZATION_ID

# Verify billing account
gcloud billing accounts list
```

**Function Deployment Fails**
```bash
# Check function logs
gcloud functions logs read governance-policy-evaluator --region=$REGION

# Verify source code upload
gsutil ls gs://$(terraform output -raw governance_bucket_name)/function-source/
```

**BigQuery Access Issues**
```bash
# Check dataset permissions
bq show --format=prettyjson $(terraform output -raw bigquery_dataset_id)

# Test service account access
gcloud auth activate-service-account --key-file=service-account-key.json
```

### Debug Mode

Enable detailed logging:

```bash
# Export debug variables
export TF_LOG=INFO
export GOOGLE_CLOUD_PROJECT=$(terraform output -raw project_id)

# Run with verbose output
terraform apply -auto-approve
```

## Security Considerations

### Data Protection

- All governance data encrypted with customer-managed keys
- Bucket versioning enabled for audit trails
- Public access prevention enforced
- Service accounts follow least-privilege principle

### Access Control

- Uniform bucket-level access enforced
- IAM bindings limited to specific roles
- Function ingress restricted to internal traffic
- Monitoring alerts for high-severity violations

### Compliance

- 7-day message retention for audit purposes
- Comprehensive logging of all governance activities
- Violation tracking with remediation status
- Regular compliance scoring and reporting

## Cost Optimization

### Estimated Monthly Costs

Based on moderate governance activity:

- Cloud Functions: $10-50
- BigQuery: $10-45 (storage + queries)
- Pub/Sub: $2-10
- Cloud Storage: $2-8
- Workflows: $1-5
- Monitoring: $1-3
- KMS: $1-2

**Total: $27-123/month**

### Cost Reduction Tips

1. Adjust function memory allocations
2. Optimize BigQuery table partitioning
3. Configure storage lifecycle policies
4. Monitor and adjust message retention
5. Use preemptible instances for development

## Cleanup

### Destroy Infrastructure

```bash
# Review resources to be destroyed
terraform plan -destroy

# Destroy all governance infrastructure
terraform destroy

# Confirm destruction when prompted
# Type: yes
```

### Manual Cleanup

Some resources may require manual cleanup:

```bash
# Remove organization asset feeds (if needed)
gcloud asset feeds delete FEED_NAME --organization=$ORGANIZATION_ID

# Clean up any remaining storage objects
gsutil -m rm -r gs://BUCKET_NAME/**
```

## Support and Maintenance

### Updates

- Review Terraform provider updates quarterly
- Monitor Google Cloud service announcements
- Update function dependencies regularly
- Review and update governance policies

### Monitoring

- Set up alerts for function failures
- Monitor BigQuery query costs
- Review violation trends monthly
- Audit service account usage

### Backup and Recovery

- Export BigQuery data regularly
- Backup governance policy configurations
- Document custom policy implementations
- Maintain disaster recovery procedures

## Contributing

When modifying this infrastructure:

1. Test changes in development environment
2. Update documentation for any new variables
3. Follow Terraform best practices
4. Add appropriate resource labels
5. Update cost estimates if needed

For questions or issues, refer to the original recipe documentation or Google Cloud documentation.