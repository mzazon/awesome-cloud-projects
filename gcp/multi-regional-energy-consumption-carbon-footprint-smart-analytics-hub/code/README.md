# Infrastructure as Code for Multi-Regional Energy Consumption with Cloud Carbon Footprint and Smart Analytics Hub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Regional Energy Consumption with Cloud Carbon Footprint and Smart Analytics Hub".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Terraform installed (version 1.0 or later) for Terraform deployment
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (Developer/Admin)
  - BigQuery (Data Editor/Admin)
  - Cloud Scheduler (Admin)
  - Analytics Hub (Admin)
  - Cloud Monitoring (Editor)
  - Project IAM Admin (for service account management)
- Estimated cost: $50-100 for BigQuery storage and compute, Cloud Functions executions, and API calls during testing

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create carbon-footprint-deployment \
    --location=us-central1 \
    --source-blueprint=./main.yaml \
    --input-values=project_id=$(gcloud config get-value project),region=us-central1

# Monitor deployment progress
gcloud infra-manager deployments describe carbon-footprint-deployment \
    --location=us-central1

# View deployment outputs
gcloud infra-manager deployments describe carbon-footprint-deployment \
    --location=us-central1 \
    --format="value(latestRevision.outputs)"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region = "us-central1"
billing_account_id = "your-billing-account-id"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BILLING_ACCOUNT_ID="your-billing-account-id"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/validate.sh
```

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment accepts the following input values:

- `project_id`: Google Cloud project ID (required)
- `region`: Primary deployment region (default: us-central1)
- `dataset_location`: BigQuery dataset location (default: US)
- `function_memory`: Cloud Function memory allocation (default: 512MB)
- `scheduler_frequency`: Carbon optimization frequency in cron format (default: "0 */2 * * *")

### Terraform Variables

Customize the deployment by modifying `terraform.tfvars`:

```hcl
# Required variables
project_id = "your-project-id"
region = "us-central1"
billing_account_id = "your-billing-account-id"

# Optional variables
dataset_location = "US"
function_memory = 512
scheduler_frequency = "0 */2 * * *"
enable_monitoring = true
carbon_intensity_threshold = 0.5

# Multi-regional configuration
regions = ["us-central1", "europe-west1", "asia-northeast1"]
```

### Environment Variables for Bash Scripts

Set these environment variables before running the bash scripts:

```bash
# Required
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BILLING_ACCOUNT_ID="your-billing-account-id"

# Optional
export DATASET_LOCATION="US"
export FUNCTION_MEMORY="512"
export SCHEDULER_FREQUENCY="0 */2 * * *"
export CARBON_THRESHOLD="0.5"
```

## Architecture Overview

This implementation deploys:

1. **BigQuery Dataset and Tables**: Central data warehouse for carbon footprint analytics
2. **Analytics Hub Exchange**: Data sharing platform for sustainability metrics
3. **Cloud Functions**: Serverless processing for carbon data collection and workload optimization
4. **Cloud Scheduler Jobs**: Automated carbon optimization triggers
5. **Cloud Monitoring**: Custom metrics and alerting for carbon intensity
6. **IAM Service Accounts**: Secure access control for all components

## Monitoring and Validation

### Check Deployment Status

```bash
# Verify BigQuery dataset
bq ls --dataset_id=${PROJECT_ID}:carbon_analytics_*

# Check Cloud Functions
gcloud functions list --filter="name:carbon-optimizer OR name:workload-migration"

# Verify Analytics Hub exchange
bq ls --data_exchange --location=${REGION}

# Check Cloud Scheduler jobs
gcloud scheduler jobs list --location=${REGION}
```

### Test Carbon Data Collection

```bash
# Trigger carbon data collection function
FUNCTION_URL=$(gcloud functions describe carbon-optimizer-function \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

curl -X GET "${FUNCTION_URL}"

# Verify data in BigQuery
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as records FROM \`${PROJECT_ID}.carbon_analytics_*.carbon_footprint\`"
```

### Monitor Optimization Performance

```bash
# Check workload optimization recommendations
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.carbon_analytics_*.workload_schedules\` 
     ORDER BY timestamp DESC LIMIT 10"

# View regional efficiency scores
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.carbon_analytics_*.regional_efficiency_scores\`"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete carbon-footprint-deployment \
    --location=us-central1 \
    --delete-policy=DELETE

# Verify cleanup
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Clean up Terraform state
rm -rf .terraform terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are removed
./scripts/validate_cleanup.sh
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your account has the required IAM permissions listed in Prerequisites
2. **API Not Enabled**: The deployment automatically enables required APIs, but manual enabling may be needed:
   ```bash
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable cloudscheduler.googleapis.com
   gcloud services enable bigquery.googleapis.com
   ```

3. **Function Deployment Timeout**: Increase the timeout in the configuration if functions fail to deploy

4. **BigQuery Dataset Location**: Ensure the dataset location matches your data residency requirements

### Debugging

Enable debug logging for detailed troubleshooting:

```bash
# For Terraform
export TF_LOG=DEBUG
terraform apply

# For gcloud commands
gcloud config set core/verbosity debug

# Check Cloud Function logs
gcloud functions logs read carbon-optimizer-function --region=${REGION}
```

### Support Resources

- [Google Cloud Carbon Footprint Documentation](https://cloud.google.com/carbon-footprint/docs)
- [Analytics Hub Documentation](https://cloud.google.com/analytics-hub/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Security Considerations

This implementation follows Google Cloud security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **Network Security**: Functions are deployed with appropriate VPC settings
- **Data Encryption**: All data is encrypted at rest and in transit
- **Secret Management**: No hardcoded credentials in the infrastructure code
- **Audit Logging**: All API calls are logged for security monitoring

## Cost Optimization

To minimize costs during testing:

1. Use the smallest Cloud Function memory allocation (128MB) for development
2. Set short data retention periods for BigQuery tables
3. Limit the frequency of scheduler jobs during testing
4. Clean up resources promptly after testing

## Customization

### Adding New Regions

To monitor additional regions, update the regions list in your configuration:

```hcl
# In terraform.tfvars
regions = [
  "us-central1",
  "europe-west1", 
  "asia-northeast1",
  "australia-southeast1",
  "southamerica-east1"
]
```

### Custom Carbon Thresholds

Modify carbon intensity thresholds for your organization's sustainability goals:

```hcl
# In terraform.tfvars
carbon_intensity_threshold = 0.3  # Stricter threshold
high_carbon_alert_threshold = 0.6
```

### Integration with Existing Systems

The infrastructure outputs provide integration endpoints:

- BigQuery dataset for analytics integration
- Cloud Function URLs for API integration
- Analytics Hub exchange for data sharing
- Cloud Monitoring metrics for dashboard integration

## Next Steps

After successful deployment:

1. Configure additional data sources for enhanced carbon optimization
2. Set up Looker Studio dashboards for carbon footprint visualization
3. Integrate with CI/CD pipelines for automated workload optimization
4. Extend to multi-cloud environments for comprehensive carbon management
5. Implement machine learning models for predictive carbon optimization

For advanced features and extensions, refer to the Challenge section in the original recipe documentation.