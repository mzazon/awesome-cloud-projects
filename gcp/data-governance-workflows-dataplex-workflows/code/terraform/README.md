# Data Governance Workflows with Dataplex and Cloud Workflows - Terraform Infrastructure

This Terraform configuration deploys a comprehensive data governance solution on Google Cloud Platform using Dataplex Universal Catalog, Cloud DLP, BigQuery, Cloud Workflows, and Cloud Functions.

## Architecture Overview

The infrastructure implements an intelligent data governance system that:

- **Dataplex Universal Catalog** - Provides unified data asset management across zones
- **Cloud DLP** - Automatically detects and classifies sensitive data
- **BigQuery** - Stores governance metrics and compliance reports
- **Cloud Workflows** - Orchestrates end-to-end governance processes
- **Cloud Functions** - Performs automated data quality assessments
- **Cloud Monitoring** - Provides alerts for governance violations

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) >= 400.0.0
- [Git](https://git-scm.com/downloads)

### Google Cloud Setup

1. Create a new GCP project or use an existing one
2. Enable billing for the project
3. Authenticate with Google Cloud:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```
4. Set your project ID:
   ```bash
   export PROJECT_ID="your-project-id"
   gcloud config set project $PROJECT_ID
   ```

### Required Permissions

Your user account or service account needs the following IAM roles:

- `roles/owner` OR the following specific roles:
  - `roles/dataplex.admin`
  - `roles/dlp.admin`
  - `roles/bigquery.admin`
  - `roles/workflows.admin`
  - `roles/cloudfunctions.admin`
  - `roles/storage.admin`
  - `roles/monitoring.admin`
  - `roles/logging.admin`
  - `roles/cloudkms.admin`
  - `roles/serviceusage.serviceUsageAdmin`

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/data-governance-workflows-dataplex-workflows/code/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Create Variables File

Create a `terraform.tfvars` file with your specific values:

```hcl
# Required variables
project_id = "your-project-id"
region     = "us-central1"
environment = "dev"

# Optional customizations
organization_domain = "your-company.com"
quality_threshold = 0.8
data_retention_days = 90

# Additional labels
labels = {
  team        = "data-engineering"
  cost_center = "analytics"
  owner       = "data-team"
}
```

### 4. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### 5. Verify Deployment

After deployment, verify the resources:

```bash
# Check Dataplex lake
gcloud dataplex lakes list --location=us-central1

# Check workflow
gcloud workflows list --location=us-central1

# Check BigQuery dataset
bq ls
```

## Configuration

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | GCP project ID | `my-governance-project` |
| `region` | GCP region | `us-central1` |
| `environment` | Environment name | `dev`, `staging`, `prod` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `organization_domain` | Organization domain for BigQuery access | `example.com` |
| `quality_threshold` | Minimum acceptable quality score | `0.8` |
| `data_retention_days` | Data retention period | `90` |
| `dlp_scan_frequency` | DLP scan frequency in seconds | `604800` (weekly) |
| `function_memory_mb` | Cloud Function memory | `512` |
| `enable_encryption` | Enable customer-managed encryption | `true` |

See [variables.tf](variables.tf) for complete variable documentation.

## Deployment

### Development Environment

```bash
# Deploy with minimal resources for development
terraform apply -var="environment=dev" -var="quality_threshold=0.7"
```

### Production Environment

```bash
# Deploy with production-ready configuration
terraform apply -var="environment=prod" -var="quality_threshold=0.9" -var="data_retention_days=2555"
```

### Custom Configuration

```bash
# Deploy with custom DLP scanning frequency (daily)
terraform apply -var="dlp_scan_frequency=86400"
```

## Testing

### 1. Execute Governance Workflow

```bash
# Get workflow name from Terraform output
WORKFLOW_NAME=$(terraform output -raw governance_workflow_name)

# Execute the workflow
gcloud workflows run $WORKFLOW_NAME \
    --location=us-central1 \
    --data='{"trigger": "manual", "scope": "full_scan"}'
```

### 2. Test Data Quality Function

```bash
# Get function URL from Terraform output
FUNCTION_URL=$(terraform output -raw data_quality_function_https_trigger_url)

# Test the function
curl -X POST $FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d '{"asset_name": "test-asset", "zone": "raw-data-zone"}'
```

### 3. Verify BigQuery Data

```bash
# Check governance metrics
DATASET_ID=$(terraform output -raw bigquery_dataset_id)
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as total_records FROM \`$PROJECT_ID.$DATASET_ID.data_quality_metrics\`"
```

### 4. Test DLP Scanning

```bash
# Upload test data with sensitive information
BUCKET_NAME=$(terraform output -raw data_lake_bucket_name)
echo "Customer: john.doe@example.com, Phone: 555-123-4567" > test-data.txt
gsutil cp test-data.txt gs://$BUCKET_NAME/test-data.txt

# Check DLP results (may take a few minutes)
gcloud dlp job-triggers list
```

## Monitoring

### Cloud Monitoring

- **Data Quality Alerts**: Triggered when quality scores drop below threshold
- **Compliance Violations**: Alerts for non-compliant data assets
- **Workflow Execution**: Monitoring of governance workflow runs

### Logging

- **Workflow Logs**: Detailed execution logs in Cloud Logging
- **Function Logs**: Data quality assessment execution logs
- **Audit Logs**: Complete audit trail of governance activities

### Dashboards

Access the monitoring dashboard:
```bash
# Get monitoring console URL
terraform output monitoring_console_url
```

## Maintenance

### Updating the Infrastructure

```bash
# Update to latest version
git pull origin main
terraform plan
terraform apply
```

### Scaling

#### Increase Function Memory

```bash
terraform apply -var="function_memory_mb=1024"
```

#### Adjust Quality Thresholds

```bash
terraform apply -var="quality_threshold=0.85"
```

#### Change Scan Frequency

```bash
# Daily scanning
terraform apply -var="dlp_scan_frequency=86400"
```

### Backup and Recovery

The infrastructure includes automatic backups:

- **BigQuery**: Automatic daily backups
- **Cloud Storage**: Versioning enabled
- **KMS Keys**: Lifecycle management with prevent_destroy

## Troubleshooting

### Common Issues

#### 1. API Not Enabled
```bash
# Enable required APIs
gcloud services enable dataplex.googleapis.com
gcloud services enable workflows.googleapis.com
gcloud services enable dlp.googleapis.com
```

#### 2. Insufficient Permissions
```bash
# Check current permissions
gcloud projects get-iam-policy $PROJECT_ID

# Add required roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:your-email@domain.com" \
    --role="roles/dataplex.admin"
```

#### 3. Function Deployment Issues
```bash
# Check function logs
gcloud functions logs read data-quality-assessor --region=us-central1
```

#### 4. Workflow Execution Failures
```bash
# Check workflow execution details
gcloud workflows executions list --workflow=WORKFLOW_NAME --location=us-central1
```

### Debug Mode

Enable debug logging:
```bash
export TF_LOG=DEBUG
terraform apply
```

## Security

### Encryption

- **Data at Rest**: Customer-managed KMS keys
- **Data in Transit**: TLS encryption
- **Function Code**: Encrypted storage

### Access Control

- **Service Account**: Least privilege principle
- **BigQuery**: Organization-level access control
- **Cloud Storage**: Uniform bucket-level access

### Compliance

- **Audit Logging**: Complete audit trail
- **Data Classification**: Automated sensitive data detection
- **Retention Policies**: Configurable data retention

## Cost Management

### Resource Costs

Estimated monthly costs for different usage levels:

| Usage Level | BigQuery | Cloud Storage | Functions | Workflows | DLP | Total |
|-------------|----------|---------------|-----------|-----------|-----|-------|
| Light       | $10      | $5           | $5        | $2        | $10 | $32   |
| Medium      | $50      | $20          | $15       | $8        | $40 | $133  |
| Heavy       | $200     | $100         | $50       | $25       | $150| $525  |

### Cost Optimization

1. **Adjust scan frequency** based on data change patterns
2. **Set table expiration** for temporary data
3. **Use lifecycle policies** for Cloud Storage
4. **Monitor BigQuery slots** usage

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy
```

### Partial Cleanup

```bash
# Remove specific resources
terraform destroy -target=google_cloudfunctions_function.data_quality_assessor
```

### Manual Cleanup

Some resources may require manual cleanup:

1. **KMS Keys**: Keys with prevent_destroy lifecycle rule
2. **BigQuery Data**: Exported data in Cloud Storage
3. **Monitoring Dashboards**: Custom dashboards

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:

1. Check the [troubleshooting section](#troubleshooting)
2. Review Google Cloud documentation
3. Create an issue in the repository

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Additional Resources

- [Dataplex Documentation](https://cloud.google.com/dataplex/docs)
- [Cloud DLP Documentation](https://cloud.google.com/dlp/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)