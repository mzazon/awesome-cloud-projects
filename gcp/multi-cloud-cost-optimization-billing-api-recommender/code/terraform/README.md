# Multi-Cloud Cost Optimization with Cloud Billing API and Cloud Recommender - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive cost optimization system on Google Cloud Platform. The solution automatically analyzes billing data across multiple projects using the Cloud Billing API and Cloud Recommender to generate actionable recommendations and automate cost optimization workflows.

## Architecture Overview

The solution deploys:

- **BigQuery Dataset**: Centralized analytics for cost data and recommendations
- **Cloud Storage**: Secure storage for reports and optimization artifacts
- **Cloud Functions**: Serverless processing for cost analysis, recommendation generation, and automation
- **Pub/Sub Topics**: Event-driven messaging between components
- **Cloud Scheduler**: Automated triggering of cost analysis workflows
- **Cloud Monitoring**: Alerting and observability for the optimization system

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK** installed and configured
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.0)
   ```bash
   terraform version
   ```

3. **Required Permissions**:
   - Billing Account Administrator or Editor
   - Project Editor for the target project
   - BigQuery Admin for analytics capabilities
   - Cloud Functions Developer
   - Pub/Sub Admin

4. **APIs Enabled**: The Terraform will automatically enable required APIs, but you can pre-enable them:
   ```bash
   gcloud services enable cloudbilling.googleapis.com \
     cloudfunctions.googleapis.com \
     pubsub.googleapis.com \
     bigquery.googleapis.com \
     storage.googleapis.com \
     recommender.googleapis.com \
     cloudscheduler.googleapis.com \
     monitoring.googleapis.com
   ```

## Quick Start

### 1. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:

```hcl
project_id         = "your-cost-optimization-project"
billing_account_id = "XXXXXX-XXXXXX-XXXXXX"
region            = "us-central1"
notification_email = "admin@yourcompany.com"
cost_threshold    = 100
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 3. Verify Deployment

After deployment, verify the components:

```bash
# Check BigQuery dataset
bq ls --project_id YOUR_PROJECT_ID

# List Cloud Functions
gcloud functions list

# View Pub/Sub topics
gcloud pubsub topics list

# Check Cloud Scheduler jobs
gcloud scheduler jobs list
```

## Configuration Options

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID for resources | - | Yes |
| `billing_account_id` | Billing account to monitor | - | Yes |
| `region` | GCP region for deployment | `us-central1` | No |

### Cost Optimization Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `cost_threshold` | Alert threshold (USD) | `100` |
| `notification_email` | Email for alerts | `""` |
| `slack_webhook_url` | Slack webhook URL | `""` |

### Scheduling Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `cost_analysis_schedule` | Daily analysis cron | `"0 9 * * *"` |
| `weekly_report_schedule` | Weekly report cron | `"0 8 * * 1"` |
| `monthly_review_schedule` | Monthly review cron | `"0 7 1 * *"` |

### Resource Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `function_runtime` | Cloud Functions runtime | `python39` |
| `function_memory` | Function memory allocation | `512MB` |
| `dataset_location` | BigQuery dataset location | `US` |
| `storage_class` | Storage bucket class | `STANDARD` |

## Usage

### Manual Cost Analysis

Trigger a manual cost analysis:

```bash
# Get the topic name from Terraform output
TOPIC_NAME=$(terraform output -raw main_topic_name)

# Trigger analysis
gcloud pubsub topics publish $TOPIC_NAME \
  --message='{"trigger": "manual_analysis", "type": "comprehensive"}'
```

### Query Cost Data

Access cost analysis data in BigQuery:

```bash
# Get dataset ID
DATASET_ID=$(terraform output -raw bigquery_dataset_id)

# Query total costs by project
bq query --use_legacy_sql=false \
  "SELECT project_id, SUM(cost) as total_cost, SUM(optimization_potential) as total_savings 
   FROM \`YOUR_PROJECT_ID.${DATASET_ID}.cost_analysis\` 
   GROUP BY project_id 
   ORDER BY total_cost DESC"
```

### View Recommendations

Check generated recommendations:

```bash
# Get bucket name
BUCKET_NAME=$(terraform output -raw storage_bucket_name)

# List recommendation reports
gsutil ls gs://$BUCKET_NAME/recommendations/

# Download latest report
gsutil cp gs://$BUCKET_NAME/recommendations/* ./latest-recommendations.json
```

## Monitoring and Alerts

### View Function Logs

```bash
# Get function names from output
terraform output cloud_functions

# View logs for cost analysis function
gcloud functions logs read analyze-costs-SUFFIX --limit=20

# View logs for recommendation engine
gcloud functions logs read generate-recommendations-SUFFIX --limit=20
```

### Monitor Pub/Sub Messages

```bash
# Check message flow
gcloud pubsub topics list
gcloud pubsub subscriptions list

# View subscription metrics
gcloud pubsub subscriptions describe cost-analysis-sub
```

### Access Monitoring Dashboard

Open the Cloud Monitoring dashboard:

```bash
# Get monitoring console URL
terraform output monitoring_console_url
```

## Customization

### Adding Custom Recommenders

Modify `function_code/recommendation_engine.py` to include additional recommender types:

```python
recommender_types = [
    "google.compute.instance.MachineTypeRecommender",
    "google.compute.disk.IdleResourceRecommender",
    "google.gke.service.CostRecommender",  # Add GKE recommendations
    "google.cloudsql.instance.CostRecommender"  # Add Cloud SQL recommendations
]
```

### Custom Alert Thresholds

Adjust alerting logic in `function_code/optimization_automation.py`:

```python
# Multi-tier thresholds
if potential_savings > 500:  # Critical threshold
    urgency = "critical"
elif potential_savings > 200:  # High threshold
    urgency = "high"
elif potential_savings > 100:  # Medium threshold
    urgency = "medium"
```

### Scheduling Modifications

Update scheduler frequencies by modifying variables:

```hcl
cost_analysis_schedule = "0 */6 * * *"  # Every 6 hours
weekly_report_schedule = "0 18 * * 5"   # Friday 6 PM
```

## Security Considerations

### IAM Roles

The deployment creates a service account with minimal required permissions:

- `roles/billing.viewer`: Read billing data
- `roles/recommender.viewer`: Access recommendations
- `roles/bigquery.dataEditor`: Write analytics data
- `roles/storage.objectAdmin`: Manage reports
- `roles/pubsub.publisher`: Send messages
- `roles/monitoring.metricWriter`: Create metrics

### Data Protection

- **Encryption**: All data encrypted at rest and in transit
- **Access Control**: Uniform bucket-level access enabled
- **Versioning**: Storage bucket versioning enabled for data protection
- **Retention**: Configurable data retention policies

### Network Security

- Functions deployed with secure defaults
- Private Google Access for enhanced security
- VPC-native deployments where applicable

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   
   # Verify billing account access
   gcloud billing accounts list
   ```

2. **Function Timeout Issues**
   ```bash
   # Increase timeout in variables
   function_timeout = 540  # Maximum for Cloud Functions
   ```

3. **BigQuery Schema Errors**
   ```bash
   # Check table schema
   bq show YOUR_PROJECT_ID:DATASET_ID.cost_analysis
   ```

4. **Pub/Sub Message Delivery**
   ```bash
   # Check subscription status
   gcloud pubsub subscriptions describe cost-analysis-sub
   
   # Monitor dead letter queue
   gcloud pubsub topics list | grep optimization-alerts
   ```

### Logging and Debugging

Enable detailed logging:

```hcl
enable_detailed_monitoring = true
log_retention_days = 30
```

Access comprehensive logs:

```bash
# View all cost optimization logs
gcloud logging read 'resource.type="cloud_function" 
  resource.labels.function_name:("analyze-costs" OR "generate-recommendations" OR "optimize-resources")'
```

## Cost Estimation

Expected monthly costs for moderate usage (10-20 projects):

- **BigQuery**: $10-30 (storage and queries)
- **Cloud Functions**: $15-40 (invocations and compute)
- **Cloud Storage**: $5-15 (storage and operations)
- **Pub/Sub**: $5-10 (messages and storage)
- **Cloud Scheduler**: $1-3 (job executions)
- **Monitoring**: $5-15 (metrics and alerting)

**Total Estimated Cost**: $41-113 per month

Cost scales with:
- Number of projects monitored
- Frequency of analysis
- Volume of recommendations
- Data retention period

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm deletion
# Type 'yes' when prompted
```

**Note**: This will permanently delete all cost optimization data and configurations.

## Support and Contributing

### Getting Help

1. **Check Terraform Output**: Review deployment information
   ```bash
   terraform output
   ```

2. **Review Logs**: Check function and system logs
   ```bash
   terraform output testing_commands
   ```

3. **Verify Configuration**: Ensure all variables are correctly set
   ```bash
   terraform plan
   ```

### Best Practices

- **Version Control**: Store terraform.tfvars securely
- **State Management**: Use remote state for team collaboration
- **Regular Updates**: Keep Terraform and providers updated
- **Monitoring**: Set up comprehensive alerting
- **Testing**: Validate changes in non-production environments

For additional support, refer to the [Google Cloud Cost Optimization documentation](https://cloud.google.com/docs/costs-usage) and [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs).