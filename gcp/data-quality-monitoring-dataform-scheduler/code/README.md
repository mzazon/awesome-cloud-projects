# Infrastructure as Code for Data Quality Monitoring with Dataform and Cloud Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Quality Monitoring with Dataform and Cloud Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate Google Cloud project with billing enabled
- Required IAM permissions:
  - Dataform Admin
  - BigQuery Admin
  - Cloud Scheduler Admin
  - Cloud Monitoring Editor
  - Service Account Admin
- Basic understanding of SQL, data warehousing concepts, and Google Cloud services
- Estimated cost: $20-50/month depending on BigQuery usage and schedule frequency

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/data-quality-monitoring \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# When finished, clean up resources
./scripts/destroy.sh
```

## Architecture Overview

This solution implements an automated data quality monitoring system that includes:

- **BigQuery datasets and tables** with sample e-commerce data
- **Dataform repository and workspace** for SQL-based data quality assertions
- **Data quality assertions** validating email formats, name completeness, order amounts, and referential integrity
- **Cloud Scheduler job** running quality checks every 6 hours
- **Cloud Monitoring alerts** for proactive issue detection
- **Service accounts and IAM roles** with least privilege access

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment supports the following configuration options:

```yaml
# terraform.tfvars
project_id = "your-project-id"
region = "us-central1"
dataset_id = "sample_ecommerce"
repository_id = "data-quality-repo"
workspace_id = "quality-workspace"
scheduler_frequency = "0 */6 * * *"  # Every 6 hours
notification_email = "your-email@example.com"
```

### Terraform Variables

Customize the deployment by modifying `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
dataform_region = "us-central1"
dataset_id = "sample_ecommerce"
repository_id = "data-quality-repo"
workspace_id = "quality-workspace"
scheduler_job_id = "dataform-quality-job"
notification_email = "your-email@example.com"
scheduler_frequency = "0 */6 * * *"
```

### Bash Script Configuration

Edit the script variables at the top of `scripts/deploy.sh`:

```bash
# Configuration variables
PROJECT_ID="your-project-id"
REGION="us-central1"
NOTIFICATION_EMAIL="your-email@example.com"
SCHEDULER_FREQUENCY="0 */6 * * *"
```

## Deployment Steps

### 1. Prerequisites Setup

```bash
# Enable required APIs
gcloud services enable dataform.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable logging.googleapis.com
```

### 2. Infrastructure Deployment

Choose your preferred deployment method from the Quick Start section above.

### 3. Validation

After deployment, verify the solution is working:

```bash
# Check Dataform repository
gcloud dataform repositories list --location=us-central1

# Verify BigQuery datasets
bq ls

# Check Cloud Scheduler job
gcloud scheduler jobs list --location=us-central1

# View data quality summary
bq query --use_legacy_sql=false \
"SELECT * FROM \`PROJECT_ID.DATASET_ID.data_quality_summary\`
 ORDER BY quality_score_percent DESC"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/data-quality-monitoring
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Solution Components

### Data Quality Assertions

The solution includes several types of data quality checks:

1. **Email Validation**: Checks for missing or invalid email addresses in customer data
2. **Name Completeness**: Validates that customer records have complete name information
3. **Order Amount Validation**: Ensures order amounts are valid and positive for completed orders
4. **Referential Integrity**: Verifies that orders reference existing customers

### Monitoring and Alerting

- **Cloud Monitoring Metrics**: Track assertion failures and quality scores
- **Alert Policies**: Automated notifications when quality issues exceed thresholds
- **Log-based Metrics**: Capture detailed assertion failure information
- **Email Notifications**: Configurable alert delivery to specified email addresses

### Automation Features

- **Scheduled Execution**: Cloud Scheduler triggers quality checks every 6 hours
- **Service Account Security**: Dedicated service account with minimal required permissions
- **Automated Reporting**: Data quality summary view provides centralized quality metrics
- **Trend Analysis**: Historical data quality scores for pattern identification

## Customization

### Adding New Data Quality Assertions

1. Create new assertion files in the Dataform definitions/assertions directory
2. Update the data quality summary view to include new assertions
3. Redeploy the Dataform configuration

### Modifying Alert Thresholds

Adjust the alert policy configuration in the IaC templates:

```yaml
# Example alert threshold modification
thresholdValue: 10  # Increase from 5 to 10 failures
duration: "600s"    # Increase from 300s to 600s
```

### Changing Schedule Frequency

Update the scheduler frequency in your configuration:

```bash
# Every 4 hours instead of 6
SCHEDULER_FREQUENCY="0 */4 * * *"

# Daily at 2 AM
SCHEDULER_FREQUENCY="0 2 * * *"

# Twice daily at 6 AM and 6 PM
SCHEDULER_FREQUENCY="0 6,18 * * *"
```

## Security Considerations

- Service accounts use least privilege access principles
- IAM roles are scoped to minimum required permissions
- BigQuery datasets include appropriate access controls
- Notification channels are configured with secure email delivery
- Dataform repositories support Git-based version control and access management

## Cost Management

### Cost Optimization Tips

1. **BigQuery Costs**: Use table expiration dates for temporary assertion results
2. **Scheduler Costs**: Adjust frequency based on data update patterns
3. **Monitoring Costs**: Configure alert policies to avoid excessive notifications
4. **Storage Costs**: Implement lifecycle policies for BigQuery tables

### Estimated Monthly Costs

- Cloud Scheduler: ~$0.10 per job per month
- BigQuery storage: ~$0.02 per GB per month
- BigQuery queries: ~$5 per TB processed
- Cloud Monitoring: Free tier covers most usage
- Dataform: No additional charges

## Troubleshooting

### Common Issues

1. **Permission Errors**: Verify service account has required IAM roles
2. **BigQuery Quota Limits**: Check project quotas for BigQuery usage
3. **Dataform Compilation Errors**: Validate SQL syntax in assertion files
4. **Scheduler Authentication**: Ensure OIDC token configuration is correct

### Debug Commands

```bash
# Check Dataform compilation status
gcloud dataform compilation-results list \
    --location=us-central1 \
    --repository=data-quality-repo

# Verify scheduler job execution
gcloud scheduler jobs describe dataform-quality-job \
    --location=us-central1

# Check Cloud Monitoring metrics
gcloud logging metrics list --filter="name:data_quality_failures"
```

## Advanced Configuration

### Multi-Environment Setup

For production deployments, consider:

1. **Separate projects** for development, staging, and production
2. **Environment-specific configurations** using Terraform workspaces
3. **Automated CI/CD pipelines** for infrastructure deployment
4. **Enhanced monitoring** with custom dashboards and SLOs

### Integration with Data Catalog

Extend the solution by integrating with Google Cloud Data Catalog:

1. Tag BigQuery tables with data quality metadata
2. Create custom entry groups for data quality assets
3. Implement automated documentation for quality assertions
4. Build lineage tracking for quality metric dependencies

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Review Terraform Google Cloud provider documentation
4. Consult Google Cloud support for service-specific issues

## Additional Resources

- [Dataform Documentation](https://cloud.google.com/dataform/docs)
- [Cloud Scheduler Best Practices](https://cloud.google.com/scheduler/docs/best-practices)
- [BigQuery Data Governance](https://cloud.google.com/bigquery/docs/best-practices-governance)
- [Cloud Monitoring Alerting](https://cloud.google.com/monitoring/alerts)
- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)