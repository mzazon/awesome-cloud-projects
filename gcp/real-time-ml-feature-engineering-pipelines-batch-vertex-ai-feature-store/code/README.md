# Infrastructure as Code for Real-Time ML Feature Engineering Pipelines with Cloud Batch and Vertex AI Feature Store

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time ML Feature Engineering Pipelines with Cloud Batch and Vertex AI Feature Store".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for the following services:
  - Vertex AI (AI Platform Admin, BigQuery Admin)
  - Cloud Batch (Batch Job Editor)
  - Pub/Sub (Pub/Sub Admin)
  - BigQuery (BigQuery Admin)
  - Cloud Functions (Cloud Functions Admin)
  - Cloud Storage (Storage Admin)
- Terraform CLI (version >= 1.0) if using Terraform implementation
- Python 3.7+ for feature engineering scripts
- Estimated cost: $50-100 for resources created (varies based on data volume and processing time)

> **Note**: Ensure you have project-level permissions and the required APIs are enabled before deployment.

## Architecture Overview

This infrastructure deploys a complete ML feature engineering pipeline including:

- **BigQuery**: Data warehouse for feature storage and SQL-based transformations
- **Cloud Batch**: Scalable batch processing for feature computation
- **Vertex AI Feature Store**: Managed feature serving with low-latency access
- **Pub/Sub**: Event-driven messaging for pipeline triggers
- **Cloud Functions**: Serverless event processing
- **Cloud Storage**: Artifact storage for batch processing scripts

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/ml-feature-pipeline \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --gcs-source gs://your-config-bucket/infrastructure-manager/main.yaml \
    --input-values project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `dataset_name`: BigQuery dataset name (auto-generated with suffix)
- `feature_table`: Feature table name (default: user_features)
- `batch_job_prefix`: Prefix for batch job names (default: feature-pipeline)
- `pubsub_topic_prefix`: Prefix for Pub/Sub topic names (default: feature-updates)
- `bucket_prefix`: Prefix for Cloud Storage bucket names (default: ml-features-bucket)

### Terraform Variables

Edit `terraform/terraform.tfvars` or pass variables via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
environment = "dev"
enable_monitoring = true
batch_job_cpu_milli = 2000
batch_job_memory_mib = 4096
```

### Script Configuration

Bash scripts read configuration from environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export ENVIRONMENT="dev"
```

## Post-Deployment Steps

After infrastructure deployment, follow these steps to complete the setup:

1. **Upload Feature Engineering Script**:
   ```bash
   # Upload the feature engineering Python script to Cloud Storage
   gsutil cp feature_engineering.py gs://your-bucket-name/scripts/
   ```

2. **Create Sample Data**:
   ```bash
   # Insert sample data into BigQuery for testing
   bq query --use_legacy_sql=false "
   INSERT INTO \`${PROJECT_ID}.${DATASET_NAME}.raw_user_events\` 
   VALUES 
   ('user_1', CURRENT_TIMESTAMP(), 'login', 15.5, 0.0, 'electronics'),
   ('user_1', CURRENT_TIMESTAMP(), 'purchase', 10.0, 99.99, 'electronics'),
   ('user_2', CURRENT_TIMESTAMP(), 'login', 8.2, 0.0, 'clothing')"
   ```

3. **Trigger Initial Feature Processing**:
   ```bash
   # Submit a batch job to compute initial features
   gcloud batch jobs submit initial-feature-job \
       --location=${REGION} \
       --config=batch_job_config.json
   ```

4. **Test Event-Driven Processing**:
   ```bash
   # Send test message to Pub/Sub to trigger the pipeline
   gcloud pubsub topics publish feature-updates-topic \
       --message='{"event": "feature_update_request"}'
   ```

## Validation and Testing

### Verify BigQuery Resources

```bash
# List datasets
bq ls

# Check feature table schema
bq show ${PROJECT_ID}:${DATASET_NAME}.${FEATURE_TABLE}

# Query feature data
bq query --use_legacy_sql=false "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.${FEATURE_TABLE}\` LIMIT 5"
```

### Verify Vertex AI Feature Store

```bash
# List feature groups
gcloud ai feature-groups list --location=${REGION}

# Check feature group details
gcloud ai feature-groups describe ${FEATURE_GROUP_NAME} --location=${REGION}

# List online stores
gcloud ai online-stores list --location=${REGION}
```

### Verify Cloud Batch Jobs

```bash
# List batch jobs
gcloud batch jobs list --location=${REGION}

# Check job status
gcloud batch jobs describe ${BATCH_JOB_NAME} --location=${REGION}
```

### Test Feature Serving

```bash
# Test online feature serving (requires feature view setup)
gcloud ai feature-views read-feature-values ${FEATURE_VIEW_NAME} \
    --online-store=${ONLINE_STORE_NAME} \
    --location=${REGION} \
    --entity-ids=user_1,user_2
```

## Monitoring and Observability

### Cloud Logging

```bash
# View Cloud Batch job logs
gcloud logging read "resource.type=batch_job" --limit=50

# View Cloud Function logs
gcloud logging read "resource.type=cloud_function" --limit=20

# View Pub/Sub logs
gcloud logging read "resource.type=pubsub_topic" --limit=10
```

### Cloud Monitoring

```bash
# View Vertex AI Feature Store metrics
gcloud monitoring metrics list --filter="metric.type:aiplatform.googleapis.com"

# View BigQuery slot utilization
gcloud monitoring metrics list --filter="metric.type:bigquery.googleapis.com"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services enable aiplatform.googleapis.com batch.googleapis.com pubsub.googleapis.com bigquery.googleapis.com
   ```

2. **Insufficient Permissions**: Verify service account has required IAM roles
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Resource Quotas**: Check for regional quotas and limits
   ```bash
   gcloud compute project-info describe --project=${PROJECT_ID}
   ```

4. **Feature Store Sync Issues**: Check feature view sync status
   ```bash
   gcloud ai feature-views describe ${FEATURE_VIEW_NAME} --online-store=${ONLINE_STORE_NAME} --location=${REGION}
   ```

### Debug Commands

```bash
# Enable debug logging for gcloud commands
export CLOUDSDK_CORE_LOG_LEVEL=DEBUG

# Check resource creation status
gcloud logging read "protoPayload.methodName=google.cloud.batch.v1.BatchService.CreateJob" --limit=10

# Verify network connectivity
gcloud compute networks describe default
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/ml-feature-pipeline
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:${DATASET_NAME}

# Delete Cloud Storage bucket
gsutil -m rm -r gs://${BUCKET_NAME}

# Delete Vertex AI resources
gcloud ai feature-groups delete ${FEATURE_GROUP_NAME} --location=${REGION} --quiet

# Delete Pub/Sub resources
gcloud pubsub topics delete ${PUBSUB_TOPIC} --quiet

# Delete Cloud Functions
gcloud functions delete trigger-feature-pipeline --quiet
```

## Cost Optimization

### Resource Optimization Tips

1. **Use Preemptible Instances**: Configure Cloud Batch to use preemptible VMs for cost savings
2. **Optimize BigQuery Storage**: Use partitioned tables and appropriate storage classes
3. **Right-size Batch Jobs**: Adjust CPU and memory allocation based on workload requirements
4. **Feature Store Caching**: Configure appropriate TTL settings for online feature serving
5. **Scheduled Processing**: Use Cloud Scheduler for batch processing during off-peak hours

### Cost Monitoring

```bash
# Enable billing export to BigQuery
gcloud beta billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT_ID}

# Query billing data
bq query --use_legacy_sql=false "
SELECT service.description, SUM(cost) as total_cost
FROM \`${PROJECT_ID}.billing_export.gcp_billing_export_v1_${BILLING_ACCOUNT_ID}\`
WHERE DATE(_PARTITIONTIME) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY service.description
ORDER BY total_cost DESC"
```

## Customization

### Extending the Pipeline

1. **Add Custom Features**: Modify the feature engineering script to include domain-specific features
2. **Implement Feature Validation**: Add data quality checks using Great Expectations
3. **Multi-Model Support**: Extend feature groups to support multiple ML models
4. **Real-time Streaming**: Integrate with Dataflow for real-time feature processing
5. **Feature Lineage**: Implement feature lineage tracking using Cloud Data Catalog

### Security Hardening

1. **VPC Configuration**: Deploy resources within a private VPC
2. **IAM Roles**: Implement least-privilege access patterns
3. **Encryption**: Enable customer-managed encryption keys (CMEK)
4. **Network Security**: Configure Private Google Access and firewall rules
5. **Audit Logging**: Enable comprehensive audit logging for compliance

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example Cloud Build configuration
steps:
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        cd terraform/
        terraform init
        terraform plan -var="project_id=${PROJECT_ID}"
        terraform apply -auto-approve -var="project_id=${PROJECT_ID}"
```

### Monitoring Integration

```yaml
# Example alerting policy for feature pipeline failures
displayName: "Feature Pipeline Failure Alert"
conditions:
  - displayName: "Batch Job Failed"
    conditionThreshold:
      filter: 'resource.type="batch_job" AND severity="ERROR"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 0
```

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../real-time-ml-feature-engineering-pipelines-batch-vertex-ai-feature-store.md)
- [Google Cloud Batch documentation](https://cloud.google.com/batch/docs)
- [Vertex AI Feature Store documentation](https://cloud.google.com/vertex-ai/docs/featurestore)
- [Google Cloud Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## License

This infrastructure code is provided under the same license as the parent repository.