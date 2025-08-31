# Infrastructure as Code for Automated Cost Analytics with Worker Pools and BigQuery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Cost Analytics with Worker Pools and BigQuery".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Run Admin
  - BigQuery Admin  
  - Pub/Sub Admin
  - Cloud Scheduler Admin
  - Service Account Admin
  - Billing Account Viewer
- Docker installed (for Cloud Run container builds)

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Infrastructure Manager API enabled
- Cloud Build API enabled
- Deployment Manager API enabled

#### Terraform
- Terraform CLI (version >= 1.0) installed
- Google Cloud provider for Terraform

## Architecture Overview

This solution deploys:
- BigQuery dataset with partitioned cost analytics tables
- Cloud Run service for cost processing workers
- Pub/Sub topic and subscription for event-driven processing
- Cloud Scheduler job for automated daily cost analysis
- IAM service accounts with least-privilege permissions
- Monitoring and logging configuration

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

1. **Initialize deployment**:
   ```bash
   cd infrastructure-manager/
   
   # Set your project ID
   export PROJECT_ID="your-project-id"
   gcloud config set project ${PROJECT_ID}
   
   # Enable required APIs
   gcloud services enable config.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

2. **Create deployment**:
   ```bash
   gcloud infra-manager deployments create cost-analytics-deployment \
       --location=us-central1 \
       --config=main.yaml \
       --input-values="project_id=${PROJECT_ID},region=us-central1"
   ```

3. **Monitor deployment**:
   ```bash
   gcloud infra-manager deployments describe cost-analytics-deployment \
       --location=us-central1
   ```

### Using Terraform

1. **Initialize Terraform**:
   ```bash
   cd terraform/
   
   # Initialize Terraform with Google Cloud provider
   terraform init
   ```

2. **Configure variables**:
   ```bash
   # Create terraform.tfvars file
   cat > terraform.tfvars << EOF
   project_id = "your-project-id"
   region     = "us-central1"
   zone       = "us-central1-a"
   EOF
   ```

3. **Plan and apply**:
   ```bash
   # Review planned changes
   terraform plan
   
   # Apply infrastructure
   terraform apply
   ```

4. **Verify deployment**:
   ```bash
   # Check outputs
   terraform output
   ```

### Using Bash Scripts

1. **Make scripts executable**:
   ```bash
   chmod +x scripts/deploy.sh scripts/destroy.sh
   ```

2. **Run deployment**:
   ```bash
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   ./scripts/deploy.sh
   ```

3. **Verify resources**:
   ```bash
   # Check Cloud Run service
   gcloud run services list --region=${REGION}
   
   # Check BigQuery dataset
   bq ls
   
   # Check Pub/Sub topics
   gcloud pubsub topics list
   ```

## Configuration Options

### Variables (Terraform/Infrastructure Manager)

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `zone` | GCP zone for zonal resources | `us-central1-a` | No |
| `dataset_name` | BigQuery dataset name | `cost_analytics` | No |
| `service_name` | Cloud Run service name | `cost-worker` | No |
| `schedule` | Cloud Scheduler cron expression | `0 1 * * *` | No |
| `worker_memory` | Cloud Run memory allocation | `1Gi` | No |
| `worker_cpu` | Cloud Run CPU allocation | `1` | No |
| `max_instances` | Maximum Cloud Run instances | `10` | No |

### Environment Variables (Bash Scripts)

```bash
# Required
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Optional
export ZONE="us-central1-a"
export DATASET_NAME="cost_analytics"
export TOPIC_NAME="cost-processing"
export SERVICE_NAME="cost-worker"
```

## Post-Deployment Setup

### 1. Configure Billing Account Access

```bash
# Get your billing account ID
gcloud billing accounts list

# Grant billing viewer access to service account
export BILLING_ACCOUNT="your-billing-account-id"
export SA_EMAIL="cost-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud billing accounts add-iam-policy-binding ${BILLING_ACCOUNT} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/billing.viewer"
```

### 2. Test the Cost Processing Pipeline

```bash
# Trigger manual cost processing
export TOPIC_NAME=$(terraform output -raw pubsub_topic_name)
gcloud pubsub topics publish ${TOPIC_NAME} \
    --message='{"test":"manual_trigger","timestamp":"'$(date -Iseconds)'"}'

# Check processing logs
export SERVICE_NAME=$(terraform output -raw cloud_run_service_name)
gcloud logs read "resource.type=cloud_run_revision" \
    --filter="resource.labels.service_name=${SERVICE_NAME}" \
    --limit=10
```

### 3. Verify BigQuery Integration

```bash
# Check dataset and tables
export DATASET_NAME=$(terraform output -raw bigquery_dataset_id)
bq ls ${PROJECT_ID}:${DATASET_NAME}

# Query sample data (after processing runs)
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as record_count FROM \`${PROJECT_ID}.${DATASET_NAME}.daily_costs\`"
```

## Monitoring and Maintenance

### Health Checks

```bash
# Cloud Run service health
gcloud run services describe ${SERVICE_NAME} \
    --region=${REGION} \
    --format="table(status.conditions[0].type,status.url)"

# Pub/Sub subscription status
gcloud pubsub subscriptions describe cost-processing-sub \
    --format="table(name,pushConfig.pushEndpoint)"

# Scheduler job status
gcloud scheduler jobs describe daily-cost-analysis \
    --location=${REGION} \
    --format="table(name,schedule,state)"
```

### Cost Analysis Queries

```bash
# Monthly cost summary
bq query --use_legacy_sql=false '
SELECT 
  FORMAT_DATE("%Y-%m", usage_date) as month,
  project_id,
  service,
  SUM(cost) as total_cost
FROM `'${PROJECT_ID}'.'${DATASET_NAME}'.daily_costs`
GROUP BY month, project_id, service
ORDER BY month DESC, total_cost DESC
LIMIT 20'

# Cost trend analysis
bq query --use_legacy_sql=false '
SELECT * FROM `'${PROJECT_ID}'.'${DATASET_NAME}'.cost_trend_analysis`
WHERE week_start >= DATE_SUB(CURRENT_DATE(), INTERVAL 4 WEEK)
ORDER BY week_start DESC, weekly_cost DESC
LIMIT 10'
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**:
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Grant necessary roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/editor"
   ```

2. **API Not Enabled**:
   ```bash
   # Enable all required APIs
   gcloud services enable \
       cloudbilling.googleapis.com \
       bigquery.googleapis.com \
       run.googleapis.com \
       pubsub.googleapis.com \
       cloudscheduler.googleapis.com
   ```

3. **Cloud Run Deployment Fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # Check Cloud Run logs
   gcloud logs read "resource.type=cloud_run_revision" --limit=20
   ```

4. **No Billing Data**:
   - Verify billing account permissions
   - Check that billing export is configured
   - Ensure sufficient time has passed for data generation

### Debugging

```bash
# Enable debug logging for deployment
export TF_LOG=DEBUG  # For Terraform
export CLOUDSDK_CORE_VERBOSITY=debug  # For gcloud

# Check resource creation status
gcloud logging read "protoPayload.serviceName=cloudbilling.googleapis.com" \
    --limit=10 \
    --format="table(timestamp,protoPayload.methodName,protoPayload.status)"
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete cost-analytics-deployment \
    --location=us-central1 \
    --delete-policy=DELETE
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

### Manual Cleanup (if needed)

```bash
# Remove Cloud Run service
gcloud run services delete cost-worker --region=us-central1 --quiet

# Remove BigQuery dataset
bq rm -r -f ${PROJECT_ID}:cost_analytics

# Remove Pub/Sub resources
gcloud pubsub subscriptions delete cost-processing-sub --quiet
gcloud pubsub topics delete cost-processing --quiet

# Remove scheduler job
gcloud scheduler jobs delete daily-cost-analysis --location=us-central1 --quiet

# Remove service account
gcloud iam service-accounts delete cost-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Security Considerations

- Service accounts use least-privilege access principles
- Billing data access is restricted to read-only operations
- Cloud Run services use private container images
- All inter-service communication uses Google Cloud's private networks
- Audit logs are enabled for all resource access

## Cost Optimization

- Cloud Run scales to zero when not processing
- BigQuery uses partitioned tables for cost-efficient queries  
- Pub/Sub messages have configurable retention periods
- Cloud Scheduler runs only when needed
- Estimated monthly cost: $5-15 for typical usage patterns

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation:
   - [Cloud Run](https://cloud.google.com/run/docs)
   - [BigQuery](https://cloud.google.com/bigquery/docs)
   - [Pub/Sub](https://cloud.google.com/pubsub/docs)
   - [Cloud Scheduler](https://cloud.google.com/scheduler/docs)
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development project first
2. Update variable documentation
3. Verify cleanup procedures work correctly
4. Update this README with any new requirements