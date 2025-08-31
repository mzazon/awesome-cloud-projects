# Terraform Infrastructure for Sustainability Compliance Automation

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive sustainability compliance automation solution on Google Cloud Platform. The solution automates carbon footprint tracking, ESG reporting, and compliance monitoring using Cloud Functions, BigQuery, and Cloud Scheduler.

## Architecture Overview

The infrastructure deploys:

- **BigQuery Dataset & Tables**: Storage for carbon footprint data and processed sustainability metrics
- **Cloud Functions**: Serverless processing for data transformation, report generation, and alerting
- **Cloud Storage**: Secure storage for ESG reports and function source code
- **Cloud Scheduler**: Automated execution of sustainability workflows
- **BigQuery Data Transfer**: Automatic carbon footprint data collection
- **IAM Service Accounts**: Secure access control with least privilege principles

## Prerequisites

### Required Tools
- **Terraform**: Version 1.0 or later ([Installation Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli))
- **Google Cloud SDK**: Latest version ([Installation Guide](https://cloud.google.com/sdk/docs/install))
- **jq**: JSON processor for output formatting (optional)

### Google Cloud Requirements
- Google Cloud project with billing enabled
- Carbon Footprint API access (automatically available for covered services)
- Required APIs will be enabled automatically by Terraform
- Appropriate IAM permissions:
  - Project Editor or equivalent custom role
  - Billing Account Viewer (for Carbon Footprint export)
  - Security Admin (for IAM role assignments)

### Billing Account
- Billing account ID for Carbon Footprint data export
- Find your billing account ID:
  ```bash
  gcloud billing accounts list --format="value(name)"
  ```

## Quick Start

### 1. Authentication Setup
```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set default project (replace with your project ID)
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID
```

### 2. Clone and Navigate
```bash
# Navigate to the Terraform directory
cd gcp/sustainability-compliance-automation-carbon-footprint-functions/code/terraform/
```

### 3. Configure Variables
Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id         = "your-project-id"
billing_account_id = "your-billing-account-id"

# Optional customizations
region                        = "us-central1"
dataset_name                  = "carbon_footprint_data"
function_memory              = 512
function_timeout             = 300
monthly_emissions_threshold   = 1000
growth_threshold             = 0.15
enable_scheduled_processing   = true
enable_alerts                = true

# Resource labels
labels = {
  environment = "production"
  purpose     = "sustainability"
  team        = "esg"
  managed-by  = "terraform"
}
```

### 4. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Verify Deployment
```bash
# Check BigQuery dataset
gcloud auth login && bq ls $PROJECT_ID:$(terraform output -raw bigquery_dataset_id)

# List deployed functions
gcloud functions list --regions=$(terraform output -raw region) --filter='name:carbon'

# Check scheduled jobs
gcloud scheduler jobs list --location=$(terraform output -raw region)
```

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `billing_account_id` | Billing account for Carbon Footprint export | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `dataset_name` | BigQuery dataset name | `carbon_footprint_data` | No |

### Function Configuration

| Variable | Description | Default | Validation |
|----------|-------------|---------|------------|
| `function_memory` | Memory allocation (MB) | `512` | 128, 256, 512, 1024, 2048, 4096 |
| `function_timeout` | Function timeout (seconds) | `300` | 60-540 |
| `function_runtime` | Python runtime version | `python312` | python39, python310, python311, python312 |

### Alert Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|--------|
| `monthly_emissions_threshold` | Alert threshold (kg CO2e) | `1000` | > 0 |
| `growth_threshold` | Growth alert threshold | `0.15` | 0-1 (0-100%) |
| `enable_alerts` | Enable alert monitoring | `true` | true/false |

### Scheduling Options

| Variable | Description | Default | Impact |
|----------|-------------|---------|---------|
| `enable_scheduled_processing` | Enable Cloud Scheduler jobs | `true` | Enables/disables automation |

## Outputs Reference

After deployment, Terraform provides these outputs:

### Resource Identifiers
- `bigquery_dataset_id`: Dataset ID for carbon footprint data
- `esg_reports_bucket_name`: Cloud Storage bucket for reports
- `functions_service_account_email`: Service account email

### Function URLs
- `process_function_url`: Data processing function endpoint
- `report_function_url`: Report generation function endpoint  
- `alert_function_url`: Alert monitoring function endpoint

### Verification Commands
- `verification_commands`: Ready-to-use commands for testing

### Cost Information
- `estimated_monthly_costs`: Cost breakdown and estimates

## Manual Testing

### Test Data Processing Function
```bash
PROCESS_URL=$(terraform output -raw process_function_url)
curl -X POST "$PROCESS_URL" \
     -H "Content-Type: application/json" \
     -d '{"test": true}'
```

### Test Report Generation
```bash
REPORT_URL=$(terraform output -raw report_function_url)
curl -X POST "$REPORT_URL" \
     -H "Content-Type: application/json" \
     -d '{"test": true}'
```

### Test Alert Function
```bash
ALERT_URL=$(terraform output -raw alert_function_url)
curl -X POST "$ALERT_URL" \
     -H "Content-Type: application/json" \
     -d '{"test": true}'
```

### Trigger Scheduled Jobs Manually
```bash
# Process carbon data
gcloud scheduler jobs run process-carbon-data-$(terraform output -raw random_suffix) \
    --location=$(terraform output -raw region)

# Generate reports
gcloud scheduler jobs run generate-esg-reports-$(terraform output -raw random_suffix) \
    --location=$(terraform output -raw region)

# Check alerts
gcloud scheduler jobs run carbon-alerts-check-$(terraform output -raw random_suffix) \
    --location=$(terraform output -raw region)
```

## Monitoring and Logging

### View Function Logs
```bash
# Process function logs
gcloud functions logs read $(terraform output -raw process_function_name) \
    --region=$(terraform output -raw region) --limit=50

# Report function logs  
gcloud functions logs read $(terraform output -raw report_function_name) \
    --region=$(terraform output -raw region) --limit=50

# Alert function logs
gcloud functions logs read $(terraform output -raw alert_function_name) \
    --region=$(terraform output -raw region) --limit=50
```

### BigQuery Data Validation
```bash
# Check for carbon footprint data
bq query --use_legacy_sql=false \
"SELECT COUNT(*) as record_count, MAX(usage_month) as latest_month
FROM \`$(terraform output -raw project_id).$(terraform output -raw bigquery_dataset_id).carbon_footprint\`"

# Check processed metrics
bq query --use_legacy_sql=false \
"SELECT COUNT(*) as metrics_count, MAX(month) as latest_processed  
FROM \`$(terraform output -raw sustainability_metrics_table)\`"
```

### Cloud Storage Reports
```bash
# List generated reports
gsutil ls gs://$(terraform output -raw esg_reports_bucket_name)/

# Download latest report
gsutil cp gs://$(terraform output -raw esg_reports_bucket_name)/esg-report-$(date +%Y-%m-%d).json ./
```

## Security Considerations

### IAM and Access Control
- Service accounts use least privilege principles
- Functions require authentication for invocation
- Bucket-level uniform access control enabled
- All data encrypted at rest and in transit

### Data Protection
- BigQuery datasets use project-level encryption
- Cloud Storage versioning enabled for audit trails
- Function environment variables for sensitive configuration
- Automatic lifecycle management for long-term storage

### Compliance Features
- Audit logging enabled for all operations
- Data retention policies for regulatory compliance
- GHG Protocol compliant carbon calculations
- Comprehensive audit trails for ESG reporting

## Cost Optimization

### Storage Optimization
- Automatic archival of reports after 1 year
- BigQuery slot reservations for predictable workloads
- Function memory optimization based on usage patterns

### Processing Efficiency
- Scheduled processing during off-peak hours
- Incremental data processing to minimize costs
- Alert functions with minimal memory allocation

### Monitoring Costs
```bash
# View current month's costs
gcloud billing budgets list --billing-account=$(terraform output -raw billing_account_id)

# Set up budget alerts (optional)
gcloud billing budgets create \
    --billing-account=$(terraform output -raw billing_account_id) \
    --display-name="Sustainability Solution Budget" \
    --budget-amount=50USD
```

## Troubleshooting

### Common Issues

**Problem**: Carbon Footprint data transfer not working
**Solution**: 
```bash
# Verify billing account access
gcloud billing accounts get-iam-policy $(terraform output -raw billing_account_id)

# Check data transfer status
bq ls -t $(terraform output -raw project_id):$(terraform output -raw bigquery_dataset_id)
```

**Problem**: Functions failing with permission errors
**Solution**:
```bash
# Check service account permissions
gcloud projects get-iam-policy $(terraform output -raw project_id) \
    --flatten="bindings[].members" \
    --filter="bindings.members:$(terraform output -raw functions_service_account_email)"
```

**Problem**: No carbon footprint data available
**Solution**: Carbon Footprint data has a 1-month delay. Data for the current month won't be available until the 15th of the following month.

### Debug Mode
Enable debug logging in functions by updating environment variables:
```bash
gcloud functions deploy $(terraform output -raw process_function_name) \
    --set-env-vars DEBUG=true \
    --region=$(terraform output -raw region)
```

## Cleanup

### Destroy Infrastructure
```bash
# Remove all Terraform-managed resources
terraform destroy

# Confirm deletion
terraform show
```

### Manual Cleanup (if needed)
```bash
# Remove any remaining Cloud Storage objects
gsutil -m rm -r gs://$(terraform output -raw esg_reports_bucket_name)

# Delete any remaining BigQuery jobs
bq ls -j $(terraform output -raw project_id) | grep -E "^[a-z]" | xargs -I {} bq cancel {}
```

## Support and Documentation

### Related Documentation
- [Google Cloud Carbon Footprint](https://cloud.google.com/carbon-footprint/docs)
- [BigQuery Data Transfer Service](https://cloud.google.com/bigquery-transfer/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [GHG Protocol Corporate Standard](https://ghgprotocol.org/corporate-standard)

### Additional Resources
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Google Cloud Sustainability](https://cloud.google.com/sustainability)
- [ESG Reporting Best Practices](https://www.sustainability.com/thinking/esg-reporting-frameworks-guide/)

### Getting Help
1. Check Terraform and Google Cloud documentation
2. Review function logs for specific error messages
3. Verify IAM permissions and API enablement
4. Consult the original recipe documentation for context

---

**Note**: This infrastructure code is generated from the sustainability compliance automation recipe. Refer to the original recipe documentation for detailed implementation guidance and business context.