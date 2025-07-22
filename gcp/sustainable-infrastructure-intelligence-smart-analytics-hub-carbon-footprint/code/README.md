# Infrastructure as Code for Sustainable Infrastructure Intelligence with Smart Analytics Hub and Cloud Carbon Footprint

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Sustainable Infrastructure Intelligence with Smart Analytics Hub and Cloud Carbon Footprint".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - BigQuery Admin
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Storage Admin
  - Cloud Scheduler Admin
  - Service Account Admin
  - BigQuery Data Transfer Admin
- Basic knowledge of BigQuery, Cloud Functions, and data analytics
- Existing Google Cloud infrastructure with resource usage for carbon footprint analysis

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply carbon-intelligence-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --location=${REGION} \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables to match your environment
# Required variables:
# - project_id: Your Google Cloud project ID
# - region: Deployment region (e.g., us-central1)
# - billing_account_id: Your billing account ID

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BILLING_ACCOUNT_ID="your-billing-account-id"

# Run deployment script
./scripts/deploy.sh
```

## Infrastructure Components

This solution deploys the following Google Cloud resources:

### Data Infrastructure
- **BigQuery Dataset**: Central repository for carbon footprint data and analytics
- **BigQuery Data Transfer**: Automated export of Carbon Footprint API data
- **BigQuery Views**: Analytical views for Smart Analytics Hub sharing
- **Smart Analytics Hub**: Data exchange and listings for sustainability metrics

### Processing & Intelligence
- **Cloud Functions**: 
  - Data processing function for emissions analysis and pattern detection
  - Recommendations engine for automated sustainability suggestions
- **Cloud Storage Bucket**: Repository for sustainability reports and recommendations
- **Pub/Sub Topic**: Real-time alerting for carbon emission events

### Automation & Monitoring
- **Cloud Scheduler**: Automated execution of weekly recommendations and monthly processing
- **Service Accounts**: Dedicated accounts for Looker Studio access and function execution
- **IAM Roles**: Least-privilege permissions for all components

### Estimated Costs

- BigQuery: $10-30/month (varies by query volume and storage)
- Cloud Functions: $5-15/month (based on execution frequency)
- Cloud Storage: $1-5/month (depending on report retention)
- Pub/Sub: $1-3/month (based on message volume)
- Cloud Scheduler: <$1/month
- **Total estimated cost**: $20-55/month

> **Note**: Costs may vary based on actual usage patterns and data volume. Carbon Footprint data is provided at no additional charge.

## Configuration Options

### Environment Variables

- `PROJECT_ID`: Google Cloud project ID (required)
- `REGION`: Deployment region, recommend `us-central1` for carbon efficiency (required)
- `BILLING_ACCOUNT_ID`: Billing account ID for Carbon Footprint export (required)
- `DATASET_NAME`: BigQuery dataset name (default: `carbon_intelligence`)
- `BUCKET_NAME`: Storage bucket name (auto-generated with suffix)
- `TOPIC_NAME`: Pub/Sub topic name (default: `carbon-alerts`)

### Customization Options

1. **Alert Thresholds**: Modify the 20% increase threshold in the data processing function
2. **Report Frequency**: Adjust Cloud Scheduler cron expressions for different reporting intervals
3. **Regional Configuration**: Change default region for lower carbon footprint
4. **Data Retention**: Configure BigQuery table expiration and Cloud Storage lifecycle policies
5. **Notification Channels**: Extend Pub/Sub alerts to include email, Slack, or webhook integrations

## Post-Deployment Setup

### 1. Looker Studio Dashboard Configuration

After deployment, set up Looker Studio visualization:

```bash
# Get service account email for Looker Studio
gcloud iam service-accounts list --filter="displayName:Looker Studio Service Account"

# Use this service account to connect Looker Studio to BigQuery
# Dataset: carbon_intelligence
# Tables: monthly_emissions_trend, service_emissions_analysis
```

### 2. Carbon Footprint Data Availability

- Carbon footprint data is processed monthly on the 15th
- Historical data is available from January 2021
- Initial reports may be empty until first data export completes

### 3. Smart Analytics Hub Sharing

```bash
# List available data exchanges
bq ls --data_exchanges --location=${REGION}

# Grant access to other teams/projects as needed
bq add-listing-subscribers sustainability_exchange.monthly_emissions_listing \
    --subscribers="projects/other-project-id"
```

## Validation & Testing

### Verify Deployment

```bash
# Check BigQuery dataset and tables
bq ls ${PROJECT_ID}:carbon_intelligence

# Verify Cloud Functions
gcloud functions list --regions=${REGION}

# Test recommendations engine
FUNCTION_URL=$(gcloud functions describe recommendations-engine --region=${REGION} --format="value(httpsTrigger.url)")
curl -X POST "${FUNCTION_URL}"

# Check scheduled jobs
gcloud scheduler jobs list --location=${REGION}
```

### Monitor Operations

```bash
# View function logs
gcloud functions logs read carbon-processor --region=${REGION}

# Check Pub/Sub messages
gcloud pubsub subscriptions pull carbon-alerts-sub --limit=10

# Monitor BigQuery jobs
bq ls -j --max_results=10 --project_id=${PROJECT_ID}
```

## Troubleshooting

### Common Issues

1. **Carbon Footprint Export Not Working**:
   - Verify billing account permissions
   - Check if Carbon Footprint API is enabled
   - Ensure project has resource usage data

2. **Cloud Functions Timeout**:
   - Increase memory allocation in function configuration
   - Optimize BigQuery queries for better performance
   - Consider breaking large datasets into chunks

3. **Smart Analytics Hub Access Issues**:
   - Verify IAM permissions for data exchange
   - Check listing visibility settings
   - Ensure subscribers have proper access

4. **Recommendations Engine Empty Results**:
   - Verify sufficient historical data (6+ months recommended)
   - Check if resources have measurable carbon emissions
   - Review query filters and thresholds

### Support Resources

- [Google Cloud Carbon Footprint Documentation](https://cloud.google.com/carbon-footprint/docs)
- [Smart Analytics Hub Guide](https://cloud.google.com/analytics-hub/docs)
- [BigQuery Best Practices](https://cloud.google.com/bigquery/docs/best-practices)
- [Cloud Functions Troubleshooting](https://cloud.google.com/functions/docs/troubleshooting)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete carbon-intelligence-deployment \
    --location=${REGION} \
    --quiet
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

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud functions list --regions=${REGION}
gcloud scheduler jobs list --location=${REGION}
bq ls ${PROJECT_ID}:carbon_intelligence
gsutil ls gs://carbon-reports-*
gcloud pubsub topics list
```

## Security Considerations

### Data Protection
- All data is encrypted in transit and at rest
- Service accounts follow least-privilege principles
- BigQuery datasets use IAM for access control
- Cloud Storage buckets have versioning enabled

### Access Management
- Separate service accounts for each component
- IAM roles scoped to minimum required permissions
- Smart Analytics Hub listings require explicit subscriber approval
- Function-to-function communication uses service identities

### Compliance
- Carbon footprint data follows GHG Protocol standards
- BigQuery audit logs track all data access
- Pub/Sub messages include metadata for audit trails
- Cloud Storage maintains object versioning for accountability

## Extending the Solution

### Integration Options

1. **Multi-Cloud Carbon Tracking**: Extend to include AWS and Azure emissions data
2. **Real-Time Optimization**: Add automatic resource scaling based on carbon intensity
3. **Financial Integration**: Connect with billing data for cost-carbon correlation
4. **ML Predictions**: Implement Vertex AI models for carbon footprint forecasting
5. **Workflow Automation**: Use Cloud Workflows for complex sustainability processes

### Additional Dashboards

- Executive sustainability KPI dashboard
- Team-specific carbon budgets and tracking
- Regional carbon intensity comparison
- Service-level carbon efficiency metrics

For implementation guidance on extensions, refer to the original recipe's Challenge section.