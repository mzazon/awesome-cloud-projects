# Infrastructure as Code for AI-Powered Cost Analytics with BigQuery Analytics Hub and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI-Powered Cost Analytics with BigQuery Analytics Hub and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - BigQuery Admin
  - Storage Admin
  - AI Platform Admin
  - Monitoring Admin
  - Analytics Hub Admin
  - Service Usage Admin
- Estimated cost: $50-100 for BigQuery storage/compute, Vertex AI training, and data transfer

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution that provides native integration with Google Cloud services.

```bash
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/cost-analytics \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo" \
    --git-source-directory="gcp/ai-powered-cost-analytics-bigquery-analytics-hub-vertex-ai/code/infrastructure-manager" \
    --git-source-ref="main"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/cost-analytics
```

### Using Terraform

Terraform provides declarative infrastructure management with state tracking and plan/apply workflows.

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide automated deployment with error handling and progress tracking.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud projects describe ${PROJECT_ID}
```

## Architecture Overview

This infrastructure deploys:

- **BigQuery Dataset**: Cost analytics data warehouse with partitioned billing tables
- **Analytics Hub Exchange**: Data sharing platform for cost-related datasets
- **Vertex AI Model**: Machine learning model for cost prediction and anomaly detection
- **Cloud Storage Bucket**: Model artifacts and training data storage
- **Cloud Monitoring**: Cost alerting and anomaly detection alerts
- **IAM Roles**: Least-privilege service accounts and permissions

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default |
|----------|-------------|---------|
| project_id | Google Cloud Project ID | Required |
| region | Deployment region | us-central1 |
| dataset_id | BigQuery dataset name | cost_analytics |
| bucket_name | Storage bucket name | Generated with random suffix |
| model_name | Vertex AI model name | Generated with random suffix |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| project_id | Google Cloud Project ID | string | Required |
| region | Deployment region | string | us-central1 |
| zone | Deployment zone | string | us-central1-a |
| dataset_id | BigQuery dataset identifier | string | cost_analytics |
| exchange_id | Analytics Hub exchange ID | string | cost_data_exchange |
| enable_monitoring | Enable Cloud Monitoring alerts | bool | true |
| model_machine_type | Vertex AI endpoint machine type | string | n1-standard-2 |

### Environment Variables (Bash Scripts)

```bash
export PROJECT_ID="your-project-id"          # Required: GCP Project ID
export REGION="us-central1"                  # Optional: Default region
export ZONE="us-central1-a"                  # Optional: Default zone
export DATASET_ID="cost_analytics"           # Optional: BigQuery dataset
export EXCHANGE_ID="cost_data_exchange"      # Optional: Analytics Hub exchange
```

## Deployment Validation

After deployment, validate the infrastructure:

```bash
# Verify BigQuery dataset and tables
bq ls ${PROJECT_ID}:${DATASET_ID}

# Check Analytics Hub exchange
bq ls --data_exchange --location=${REGION}

# Verify Vertex AI model deployment
gcloud ai models list --region=${REGION}

# Test cost prediction endpoint
gcloud ai endpoints list --region=${REGION}

# Verify monitoring alerts
gcloud alpha monitoring policies list --filter="displayName:'High Cost Anomaly Alert'"
```

## Usage Examples

### Making Cost Predictions

```bash
# Prepare prediction input
cat > prediction_input.json << EOF
[{
  "day_of_week": 2,
  "hour_of_day": 14,
  "service_description": "Compute Engine",
  "project_id": "sample-project",
  "usage_amount": 50.0,
  "previous_cost": 75.5,
  "cost_week_ago": 70.0
}]
EOF

# Get endpoint ID
ENDPOINT_ID=$(gcloud ai endpoints list --region=${REGION} --format="value(name)" | head -n1 | cut -d'/' -f6)

# Make prediction
gcloud ai endpoints predict ${ENDPOINT_ID} \
    --region=${REGION} \
    --json-request=prediction_input.json
```

### Querying Cost Analytics

```bash
# Query daily cost summary
bq query --use_legacy_sql=false "
SELECT 
  usage_date, 
  service_description, 
  SUM(total_cost) as daily_total
FROM \`${PROJECT_ID}.${DATASET_ID}.daily_cost_summary\`
WHERE usage_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY usage_date, service_description
ORDER BY usage_date DESC, daily_total DESC
"

# Check for cost anomalies
bq query --use_legacy_sql=false "
SELECT 
  usage_date, 
  service_description, 
  anomaly_score, 
  severity
FROM \`${PROJECT_ID}.${DATASET_ID}.cost_anomalies\`
WHERE severity IN ('HIGH', 'MEDIUM')
ORDER BY anomaly_score DESC
LIMIT 10
"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/cost-analytics --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify state cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource cleanup
gcloud projects describe ${PROJECT_ID}
```

## Security Considerations

This infrastructure implements several security best practices:

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Data Encryption**: Encryption at rest for BigQuery and Cloud Storage
- **Network Security**: Private service access where applicable
- **Audit Logging**: Cloud Audit Logs enabled for all API calls
- **Resource Labels**: Consistent labeling for cost tracking and governance

## Cost Optimization

- **BigQuery**: Uses partitioned tables and clustered indexes for query optimization
- **Vertex AI**: Implements auto-scaling endpoints with minimum replica counts
- **Storage**: Uses Standard storage class with lifecycle policies
- **Monitoring**: Configures cost-based alerting to prevent runaway spending

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**
   ```bash
   # Check current IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@example.com" \
       --role="roles/bigquery.admin"
   ```

2. **API Not Enabled**
   ```bash
   # Enable all required APIs
   gcloud services enable bigquery.googleapis.com aiplatform.googleapis.com \
       storage.googleapis.com monitoring.googleapis.com \
       cloudbilling.googleapis.com datacatalog.googleapis.com
   ```

3. **Quota Exceeded**
   ```bash
   # Check current quotas
   gcloud compute project-info describe --project=${PROJECT_ID}
   
   # Request quota increase if needed
   gcloud alpha compute quotas update --region=${REGION}
   ```

4. **Billing Not Enabled**
   ```bash
   # Verify billing account
   gcloud billing projects describe ${PROJECT_ID}
   
   # Link billing account if needed
   gcloud billing projects link ${PROJECT_ID} --billing-account=BILLING_ACCOUNT_ID
   ```

## Monitoring and Maintenance

### Health Checks

```bash
# Check BigQuery job status
bq ls -j --max_results=10

# Monitor Vertex AI model performance
gcloud ai endpoints describe ${ENDPOINT_ID} --region=${REGION}

# Review Cloud Monitoring metrics
gcloud logging read "resource.type=bigquery_dataset" --limit=10
```

### Performance Optimization

- Monitor BigQuery slot usage and consider reservations for predictable workloads
- Review Vertex AI endpoint traffic patterns and adjust auto-scaling parameters
- Optimize BigQuery queries using the Query Plan Explanation
- Implement BigQuery BI Engine for accelerated analytics queries

## Extensions and Customizations

### Adding Data Sources

```bash
# Create additional tables for external cost data
bq mk --table ${PROJECT_ID}:${DATASET_ID}.aws_billing_data schema.json

# Set up federated queries for multi-cloud cost analysis
bq mk --external_table_definition=@external_table_def.json \
    ${PROJECT_ID}:${DATASET_ID}.external_costs
```

### Enhanced Machine Learning

```bash
# Deploy additional models for different cost prediction scenarios
gcloud ai models upload --region=${REGION} \
    --display-name=cost-optimization-recommendations \
    --artifact-uri=gs://${BUCKET_NAME}/models/optimization
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for context
2. Check Google Cloud documentation for service-specific guidance
3. Verify IAM permissions and quotas
4. Review Cloud Audit Logs for detailed error information

## Related Resources

- [BigQuery Analytics Hub Documentation](https://cloud.google.com/bigquery/docs/analytics-hub-introduction)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Google Cloud Cost Management](https://cloud.google.com/cost-management)
- [Infrastructure Manager Best Practices](https://cloud.google.com/infrastructure-manager/docs/best-practices)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)