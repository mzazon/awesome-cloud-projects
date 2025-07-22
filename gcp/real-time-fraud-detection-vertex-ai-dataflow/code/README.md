# Infrastructure as Code for Implementing Real-Time Fraud Detection with Vertex AI and Cloud Dataflow

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Real-Time Fraud Detection with Vertex AI and Cloud Dataflow".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for automated resource management

## Architecture Overview

This IaC deploys a complete real-time fraud detection system that includes:

- **Cloud Pub/Sub**: Message streaming for transaction ingestion
- **Cloud Dataflow**: Stream processing pipeline for feature engineering
- **Vertex AI**: Machine learning platform for fraud detection models
- **BigQuery**: Data warehouse for analytics and fraud alerts
- **Cloud Storage**: ML artifacts and training data storage
- **Cloud Monitoring**: System observability and alerting

## Prerequisites

### Required Tools
- Google Cloud CLI (`gcloud`) v445.0.0 or later installed and configured
- Terraform v1.5.0 or later (for Terraform deployment)
- Python 3.8+ with pip (for custom pipeline components)
- Bash shell environment (Linux, macOS, or WSL)

### Required Permissions
Your Google Cloud account needs the following IAM roles:
- `roles/owner` OR the following granular roles:
  - `roles/compute.admin`
  - `roles/dataflow.admin`
  - `roles/pubsub.admin`
  - `roles/bigquery.admin`
  - `roles/aiplatform.admin`
  - `roles/storage.admin`
  - `roles/logging.admin`
  - `roles/monitoring.admin`

### Project Setup
- Google Cloud project with billing enabled
- Required APIs will be enabled automatically during deployment
- Estimated deployment cost: $50-100 for testing (can be minimized with cleanup)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-fraud-detection-project"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/fraud-detection-deployment \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/fraud-detection-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-fraud-detection-project" \
               -var="region=us-central1"

# Deploy infrastructure
terraform apply -var="project_id=your-fraud-detection-project" \
                -var="region=us-central1"

# View important outputs
terraform output
```

### Using Bash Scripts (Quick Deploy)

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-fraud-detection-project"
export REGION="us-central1"

# Deploy complete infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud projects describe ${PROJECT_ID}
```

## Configuration Options

### Infrastructure Manager Configuration

Edit `infrastructure-manager/inputs.yaml` to customize:

```yaml
project_id: "your-fraud-detection-project"
region: "us-central1"
zone: "us-central1-a"
fraud_detection_suffix: "prod"
enable_monitoring: true
enable_advanced_logging: true
dataset_location: "US"
bucket_storage_class: "STANDARD"
dataflow_max_workers: 10
vertex_ai_region: "us-central1"
```

### Terraform Variables

Customize deployment by editing `terraform/terraform.tfvars`:

```hcl
project_id = "your-fraud-detection-project"
region = "us-central1"
zone = "us-central1-a"

# Resource Configuration
bucket_location = "US"
dataset_location = "US"
pubsub_message_retention = "604800s"  # 7 days

# Dataflow Configuration
dataflow_machine_type = "n1-standard-2"
dataflow_max_workers = 10
dataflow_network = "default"

# Vertex AI Configuration
vertex_ai_training_machine_type = "n1-standard-4"
vertex_ai_prediction_machine_type = "n1-standard-2"

# Monitoring Configuration
enable_detailed_monitoring = true
create_alert_policies = true

# Security Configuration
enable_uniform_bucket_level_access = true
enable_bigquery_cmek = false

# Cost Optimization
enable_preemptible_workers = true
auto_scaling_enabled = true
```

### Script Configuration

Bash scripts use environment variables for configuration:

```bash
# Required Variables
export PROJECT_ID="your-fraud-detection-project"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional Customization
export RANDOM_SUFFIX="custom"  # Custom suffix for resource names
export BUCKET_STORAGE_CLASS="STANDARD"  # Storage class for ML bucket
export DATAFLOW_MAX_WORKERS="10"  # Maximum Dataflow workers
export ENABLE_MONITORING="true"  # Enable advanced monitoring
export DATASET_LOCATION="US"  # BigQuery dataset location
```

## Deployment Verification

After deployment, verify the infrastructure:

### Check Core Resources

```bash
# Verify Pub/Sub resources
gcloud pubsub topics list --filter="name:transaction-stream"
gcloud pubsub subscriptions list --filter="name:fraud-processor"

# Verify BigQuery dataset
bq ls --filter="datasetId:fraud_detection"

# Verify Cloud Storage bucket
gsutil ls -b gs://*fraud-ml*

# Verify Dataflow job status
gcloud dataflow jobs list --region=${REGION} --status=active

# Verify Vertex AI resources
gcloud ai endpoints list --region=${REGION}
```

### Test Data Flow

```bash
# Send test transaction to Pub/Sub
gcloud pubsub topics publish transaction-stream-* \
    --message='{"transaction_id":"test_001","user_id":"user_123","amount":150.00,"merchant":"test_merchant","timestamp":"2025-01-15T10:30:00Z","location":"NYC","payment_method":"credit_card"}'

# Check BigQuery for processed data (after 2-3 minutes)
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as transaction_count FROM \`${PROJECT_ID}.fraud_detection_*.transactions\` WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)"
```

### Monitor System Health

```bash
# Check system logs
gcloud logging read "resource.type=dataflow_job AND severity>=WARNING" --limit=10

# View monitoring metrics
gcloud monitoring metrics list --filter="metric.type:pubsub" --limit=5

# Check fraud alerts
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as alert_count FROM \`${PROJECT_ID}.fraud_detection_*.fraud_alerts\` WHERE alert_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)"
```

## Testing the Fraud Detection System

### Generate Test Data

The deployment includes a transaction simulator for testing:

```bash
# Navigate to scripts directory
cd scripts/

# Run transaction simulator
python3 transaction_simulator.py ${PROJECT_ID} transaction-stream-*

# Monitor processing in real-time
watch "bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM \`${PROJECT_ID}.fraud_detection_*.transactions\`'"
```

### Fraud Detection Validation

```bash
# Check fraud detection performance
bq query --use_legacy_sql=false \
    "SELECT 
        COUNT(*) as total_transactions,
        AVG(fraud_score) as avg_fraud_score,
        SUM(CASE WHEN is_fraud THEN 1 ELSE 0 END) as fraud_count,
        SUM(CASE WHEN is_fraud THEN 1 ELSE 0 END) / COUNT(*) as fraud_rate
     FROM \`${PROJECT_ID}.fraud_detection_*.transactions\`
     WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)"

# View recent fraud alerts
bq query --use_legacy_sql=false \
    "SELECT 
        alert_id,
        transaction_id,
        fraud_score,
        alert_timestamp,
        status
     FROM \`${PROJECT_ID}.fraud_detection_*.fraud_alerts\`
     ORDER BY alert_timestamp DESC
     LIMIT 10"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/fraud-detection-deployment \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" \
                  -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud compute instances list --filter="name:dataflow*"
gcloud pubsub topics list --filter="name:transaction-stream*"
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
echo "Checking for remaining resources..."

# Dataflow jobs
gcloud dataflow jobs list --region=${REGION} --status=active

# Vertex AI resources
gcloud ai endpoints list --region=${REGION}
gcloud ai datasets list --region=${REGION}

# Storage buckets
gsutil ls -b gs://*fraud*

# BigQuery datasets
bq ls --filter="datasetId:fraud_detection"

# Pub/Sub resources
gcloud pubsub topics list --filter="name:transaction"
gcloud pubsub subscriptions list --filter="name:fraud"
```

## Troubleshooting

### Common Issues

**1. API Not Enabled Error**
```bash
# Enable required APIs manually
gcloud services enable compute.googleapis.com dataflow.googleapis.com \
    pubsub.googleapis.com bigquery.googleapis.com aiplatform.googleapis.com \
    storage.googleapis.com logging.googleapis.com monitoring.googleapis.com
```

**2. Insufficient Permissions**
```bash
# Check current permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Add required roles
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:your-email@domain.com" \
    --role="roles/owner"
```

**3. Dataflow Job Fails**
```bash
# Check Dataflow job logs
gcloud dataflow jobs list --region=${REGION}
JOB_ID=$(gcloud dataflow jobs list --region=${REGION} --status=failed --limit=1 --format="value(id)")
gcloud dataflow jobs describe ${JOB_ID} --region=${REGION}
```

**4. BigQuery Access Issues**
```bash
# Verify BigQuery dataset permissions
bq show --format=prettyjson ${PROJECT_ID}:fraud_detection_*
```

**5. Vertex AI Model Training Issues**
```bash
# Check Vertex AI job status
gcloud ai custom-jobs list --region=${REGION}

# View training logs
gcloud logging read "resource.type=aiplatform.googleapis.com/CustomJob" --limit=20
```

### Performance Optimization

**Dataflow Performance**
```bash
# Monitor Dataflow metrics
gcloud monitoring metrics list --filter="metric.type:dataflow"

# Optimize worker configuration
# Edit terraform/variables.tf or infrastructure-manager/inputs.yaml:
# - Increase max_workers for higher throughput
# - Use preemptible workers for cost savings
# - Adjust machine types based on processing requirements
```

**BigQuery Performance**
```bash
# Monitor query performance
bq query --use_legacy_sql=false \
    "SELECT job_id, total_bytes_processed, total_slot_ms 
     FROM \`${PROJECT_ID}\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT 
     WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
     ORDER BY creation_time DESC"
```

### Monitoring and Alerting

**Set up Custom Alerts**
```bash
# Create fraud rate alert policy
gcloud alpha monitoring policies create --policy-from-file=monitoring/fraud-rate-alert.yaml

# Create system health dashboard
gcloud monitoring dashboards create --config-from-file=monitoring/fraud-detection-dashboard.json
```

## Cost Management

### Cost Estimation
- **BigQuery**: ~$5/TB processed + $20/TB stored
- **Dataflow**: ~$0.056/vCPU-hour + $0.003557/GB-hour
- **Vertex AI**: ~$0.25/hour training + $0.50/hour prediction
- **Pub/Sub**: ~$40/TB published + $0.50/million operations
- **Cloud Storage**: ~$20/TB/month (Standard)

### Cost Optimization Tips

```bash
# Use preemptible workers for Dataflow
# Set in terraform/variables.tf:
dataflow_use_preemptible_workers = true

# Optimize BigQuery queries
# Use LIMIT clauses and date partitioning
# Monitor slot usage and optimize complex queries

# Configure lifecycle policies for storage
gsutil lifecycle set lifecycle-config.json gs://your-bucket-name

# Monitor costs
gcloud billing budgets list
```

## Advanced Configuration

### Custom Machine Learning Models

To deploy custom fraud detection models:

1. **Prepare Model Artifacts**
```bash
# Upload model to Cloud Storage
gsutil cp -r ./custom-model gs://${BUCKET_NAME}/custom-models/

# Register model in Vertex AI Model Registry
gcloud ai models upload --region=${REGION} \
    --display-name="custom-fraud-model" \
    --artifact-uri="gs://${BUCKET_NAME}/custom-models/"
```

2. **Update Dataflow Pipeline**
```bash
# Modify dataflow pipeline to use custom model
# Edit dataflow_pipeline/fraud_detection_pipeline.py
# Update FraudScoringFn class to call Vertex AI endpoint
```

### Multi-Region Deployment

For high availability across regions:

```bash
# Deploy to multiple regions
export REGIONS=("us-central1" "us-east1" "europe-west1")

for region in "${REGIONS[@]}"; do
    terraform apply -var="project_id=${PROJECT_ID}" \
                   -var="region=${region}" \
                   -var="deployment_suffix=${region}"
done
```

### Integration with External Systems

**Webhook Integration**
```bash
# Set up webhook for fraud alerts
gcloud functions deploy fraud-alert-webhook \
    --runtime=python39 \
    --trigger-topic=fraud-alerts-topic \
    --source=functions/webhook/
```

**API Gateway Integration**
```bash
# Deploy API Gateway for real-time scoring
gcloud api-gateway gateways create fraud-detection-gateway \
    --api=fraud-detection-api \
    --location=${REGION}
```

## Support and Documentation

### Additional Resources
- [Original Recipe Documentation](../implementing-real-time-fraud-detection-with-vertex-ai-and-cloud-dataflow.md)
- [Google Cloud Dataflow Documentation](https://cloud.google.com/dataflow/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Cloud Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)

### Getting Help
- For infrastructure issues: Check Google Cloud Console and logs
- For recipe-specific questions: Refer to the original recipe documentation
- For Google Cloud support: Use Cloud Support in the Google Cloud Console

### Contributing
To improve this Infrastructure as Code:
1. Test changes in a development environment
2. Update documentation for any configuration changes
3. Validate deployment across all implementation methods
4. Follow Google Cloud best practices for security and performance