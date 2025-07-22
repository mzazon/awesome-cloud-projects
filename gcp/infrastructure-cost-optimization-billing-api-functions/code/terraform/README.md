# Infrastructure Cost Optimization with Cloud Billing API and Cloud Functions - Terraform

This Terraform configuration deploys a comprehensive cost optimization system on Google Cloud Platform that leverages Cloud Billing API, Cloud Functions, BigQuery, and Cloud Monitoring to provide automated cost analysis, anomaly detection, and resource optimization recommendations.

## Architecture Overview

The solution deploys:
- **BigQuery Dataset**: Central data warehouse for billing and cost analytics
- **Cloud Functions**: Serverless functions for cost analysis, anomaly detection, and optimization
- **Pub/Sub**: Event-driven messaging for cost alerts and notifications
- **Cloud Scheduler**: Automated execution of cost analysis functions
- **Cloud Monitoring**: Alert policies for cost anomaly notifications
- **Billing Budgets**: Proactive spending control with threshold alerts
- **IAM Service Account**: Secure access management for all components

## Prerequisites

1. **Google Cloud Project**: Active project with billing enabled
2. **Terraform**: Version >= 1.0 installed
3. **Google Cloud SDK**: Latest version installed and authenticated
4. **Billing Account Access**: Billing Account Administrator or Costs Manager role
5. **Required APIs**: The Terraform configuration will enable required APIs automatically

### Required Permissions

Your account needs the following roles:
- Project Editor or Owner
- Billing Account Administrator (for budget creation)
- Service Account Admin
- Cloud Functions Admin
- BigQuery Admin

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/infrastructure-cost-optimization-billing-api-functions/code/terraform/
```

### 2. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:
- `project_id`: Your Google Cloud project ID
- `billing_account_id`: Your billing account ID
- `region`: Your preferred deployment region
- Other configuration options as needed

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

After successful deployment, verify the components:

```bash
# Check BigQuery dataset
bq ls <project-id>:<dataset-name>

# List Cloud Functions
gcloud functions list --region=<region>

# Verify Pub/Sub topics
gcloud pubsub topics list

# Check Cloud Scheduler jobs
gcloud scheduler jobs list --location=<region>
```

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `billing_account_id` | Billing account ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `resource_prefix` | Prefix for resource names | `cost-opt` | No |

### Function Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `function_runtime` | Cloud Functions runtime | `python311` |
| `function_memory` | Memory allocation | `512Mi` |
| `function_timeout` | Timeout in seconds | `540` |

### Budget Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `budget_amount` | Budget amount in USD | `1000` |
| `budget_thresholds` | Alert thresholds | `[0.5, 0.9, 1.0]` |

### Scheduling Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `cost_analysis_schedule` | Daily analysis cron | `0 9 * * *` |
| `optimization_schedule` | Weekly optimization cron | `0 9 * * 1` |

## Post-Deployment Setup

### 1. Configure Billing Export

Set up billing data export to BigQuery:

```bash
# Enable billing export (replace with your values)
gcloud alpha billing accounts projects link <project-id> \
    --billing-account=<billing-account-id>
```

Navigate to the [Billing Export page](https://console.cloud.google.com/billing/export) and configure BigQuery export to your dataset.

### 2. Test Functions

Test the deployed functions manually:

```bash
# Get function URLs from Terraform outputs
terraform output cost_analysis_function_uri
terraform output optimization_function_uri

# Test cost analysis function
curl -X POST <cost-analysis-function-uri>

# Test optimization function
curl -X POST <optimization-function-uri>
```

### 3. Configure Notifications

Set up notification channels in Cloud Monitoring:

1. Go to [Cloud Monitoring Notification Channels](https://console.cloud.google.com/monitoring/alerting/notifications)
2. Create notification channels (email, Slack, PagerDuty, etc.)
3. Update alert policies to use your notification channels

## Monitoring and Troubleshooting

### View Logs

```bash
# Cloud Functions logs
gcloud functions logs read <function-name> --region=<region>

# Cloud Scheduler logs
gcloud scheduler jobs describe <job-name> --location=<region>
```

### BigQuery Queries

Query cost data and anomalies:

```sql
-- View recent cost anomalies
SELECT *
FROM `<project-id>.<dataset-name>.cost_anomalies`
ORDER BY detection_date DESC
LIMIT 10;

-- View billing export data (if configured)
SELECT *
FROM `<project-id>.<dataset-name>.gcp_billing_export_v1_*`
WHERE DATE(usage_start_time) = CURRENT_DATE()
LIMIT 10;
```

### Common Issues

1. **Billing Export Not Working**: Ensure billing export is properly configured and pointing to the correct BigQuery dataset
2. **Function Timeouts**: Increase `function_timeout` variable if functions are timing out on large datasets
3. **Permission Errors**: Verify service account has necessary BigQuery and Billing API permissions
4. **Budget Creation Failed**: Ensure you have Billing Account Administrator role

## Customization

### Adding Custom Metrics

Extend the functions to include additional metrics:

1. Edit the function source files in the `functions/` directory
2. Add new BigQuery tables for custom metrics
3. Update the Terraform configuration to include new resources

### Custom Alert Policies

Add custom monitoring alert policies:

```hcl
resource "google_monitoring_alert_policy" "custom_alert" {
  display_name = "Custom Cost Alert"
  # Add your custom alert configuration
}
```

### Additional Schedulers

Add more scheduled jobs for different analysis frequencies:

```hcl
resource "google_cloud_scheduler_job" "hourly_check" {
  name     = "hourly-cost-check"
  schedule = "0 * * * *"
  # Configure your hourly job
}
```

## Security Considerations

- Service account follows principle of least privilege
- All resources are tagged with consistent labels
- Functions run with minimal required permissions
- BigQuery dataset has appropriate access controls
- Budget alerts provide financial guardrails

## Cost Optimization

This solution is designed to be cost-effective:
- Cloud Functions only charged during execution
- BigQuery charges for storage and queries
- Pub/Sub charged per message
- Cloud Scheduler charged per job execution

Estimated monthly cost: $15-25 for typical usage patterns.

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will delete all cost optimization infrastructure and data. Ensure you have backups of any important data before destroying.

## Support and Contributing

For issues with this Terraform configuration:
1. Check the [original recipe documentation](../../../infrastructure-cost-optimization-billing-api-functions.md)
2. Review Google Cloud documentation for each service
3. Check Terraform Google provider documentation

## Outputs

After deployment, Terraform provides useful outputs including:
- BigQuery dataset information
- Cloud Function URIs for testing
- Service account details
- Pub/Sub topic names
- Useful Google Cloud Console URLs

Use `terraform output` to view all outputs after deployment.

## License

This Terraform configuration is provided as-is for educational and operational purposes.