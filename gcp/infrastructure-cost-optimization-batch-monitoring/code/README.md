# Infrastructure as Code for Infrastructure Cost Optimization with Cloud Batch and Cloud Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Cost Optimization with Cloud Batch and Cloud Monitoring".

## Overview

This solution provides automated cost optimization for Google Cloud infrastructure using Cloud Batch for scheduled analysis jobs, Cloud Monitoring for real-time resource tracking, and Cloud Functions for automated remediation actions. The system continuously monitors resource usage patterns, identifies optimization opportunities, and implements automated actions based on configurable policies.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for manual provisioning

## Architecture Components

The infrastructure includes:

- **Cloud Storage**: Analytics data storage with intelligent lifecycle policies
- **BigQuery**: Serverless data warehouse for cost analytics and reporting
- **Cloud Batch**: Managed batch processing for infrastructure analysis
- **Cloud Functions**: Serverless automation for cost optimization actions
- **Pub/Sub**: Event-driven messaging for workflow coordination
- **Cloud Monitoring**: Resource utilization tracking and alerting
- **Cloud Scheduler**: Automated execution of optimization workflows

## Prerequisites

### General Requirements

- Google Cloud project with billing enabled
- gcloud CLI installed and configured (version 400.0.0 or later)
- Appropriate IAM permissions for resource creation:
  - Batch Job Admin
  - Cloud Functions Admin
  - BigQuery Admin
  - Storage Admin
  - Pub/Sub Admin
  - Monitoring Admin
  - Cloud Scheduler Admin
- Basic understanding of Google Cloud cost optimization principles

### Tool-Specific Prerequisites

#### Infrastructure Manager
- gcloud CLI with Infrastructure Manager API enabled
- Cloud Build API enabled (for deployment execution)

#### Terraform
- Terraform installed (version 1.5.0 or later)
- Google Cloud provider plugin (will be downloaded automatically)

#### Bash Scripts
- Bash shell environment (Linux, macOS, or WSL)
- jq for JSON parsing (optional but recommended)

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/cost-optimization \
    --service-account=YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=YOUR_PROJECT_ID,region=us-central1"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Variables

### Required Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `project_id` | Google Cloud project ID | - | `my-cost-optimization-project` |
| `region` | Primary deployment region | `us-central1` | `us-central1` |

### Optional Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `zone` | Primary deployment zone | `us-central1-a` | `us-central1-a` |
| `bucket_location` | Storage bucket location | `US` | `US` |
| `optimization_schedule` | Cron schedule for optimization | `0 2 * * *` | `0 2 * * *` |
| `batch_analysis_schedule` | Cron schedule for batch analysis | `0 3 * * 0` | `0 3 * * 0` |
| `enable_preemptible` | Use preemptible instances for batch jobs | `true` | `true` |
| `alert_threshold_cpu` | CPU utilization threshold for alerts | `0.1` | `0.1` |

## Deployment Instructions

### Step 1: Prepare Environment

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Configure gcloud
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}

# Enable required APIs
gcloud services enable batch.googleapis.com \
    monitoring.googleapis.com \
    cloudfunctions.googleapis.com \
    bigquery.googleapis.com \
    storage.googleapis.com \
    compute.googleapis.com \
    pubsub.googleapis.com \
    run.googleapis.com \
    cloudscheduler.googleapis.com
```

### Step 2: Deploy Infrastructure

Choose one of the deployment methods above based on your preference and organizational standards.

### Step 3: Verify Deployment

```bash
# Check Cloud Storage bucket
gsutil ls gs://cost-optimization-*

# Verify BigQuery dataset
bq ls --project_id=${PROJECT_ID}

# Check Cloud Functions
gcloud functions list --region=${REGION}

# Verify Pub/Sub topics
gcloud pubsub topics list

# Check scheduled jobs
gcloud scheduler jobs list --location=${REGION}
```

### Step 4: Test the System

```bash
# Trigger manual optimization function
FUNCTION_URL=$(gcloud functions describe cost-optimizer \
    --region=${REGION} \
    --format="value(serviceConfig.uri)")

curl -X GET ${FUNCTION_URL} \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)"

# Submit test batch job
gcloud batch jobs submit test-analysis-job \
    --location=${REGION} \
    --config=batch-configs/cost-analysis-job.json
```

## Monitoring and Operations

### Viewing Logs

```bash
# View Cloud Function logs
gcloud functions logs read cost-optimizer --region=${REGION}

# View Batch job logs
gcloud logging read "resource.type=batch_job" --limit=50

# View Pub/Sub message processing
gcloud logging read "resource.type=pubsub_topic" --limit=20
```

### Monitoring Costs

```bash
# Query cost optimization analytics
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.cost_analytics_*.resource_utilization\` ORDER BY timestamp DESC LIMIT 10"

# Check optimization actions
bq query --use_legacy_sql=false \
    "SELECT action_type, COUNT(*) as count, SUM(estimated_savings) as total_savings 
     FROM \`${PROJECT_ID}.cost_analytics_*.optimization_actions\` 
     GROUP BY action_type"
```

### Updating Configuration

To modify optimization parameters:

1. **Terraform**: Update variables in `terraform.tfvars` and run `terraform apply`
2. **Infrastructure Manager**: Update input values and redeploy
3. **Bash Scripts**: Modify environment variables and re-run deployment

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/cost-optimization
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud functions list --region=${REGION}
gcloud batch jobs list --location=${REGION}
gcloud scheduler jobs list --location=${REGION}
gsutil ls gs://cost-optimization-*
bq ls --project_id=${PROJECT_ID}
```

## Customization

### Modifying Optimization Logic

The cost optimization function can be customized by:

1. Editing the Cloud Function source code in `cost-optimizer-function/main.py`
2. Updating the batch job analysis logic in `batch-configs/cost-analysis-job.json`
3. Adjusting monitoring alert thresholds in the alerting policy configuration

### Adding New Resource Types

To extend the system to monitor additional resource types:

1. Update the batch job configuration to include new resource queries
2. Modify the Cloud Function to process additional resource types
3. Add new BigQuery table schemas for the resource data
4. Update monitoring policies to include new metrics

### Integration with Existing Systems

The solution can be integrated with:

- **ITSM Systems**: Use Pub/Sub to send optimization recommendations to ticketing systems
- **CI/CD Pipelines**: Trigger optimization checks during deployments
- **Dashboard Tools**: Connect BigQuery data to Looker, Data Studio, or other BI tools
- **Notification Systems**: Configure Cloud Monitoring to send alerts to Slack, PagerDuty, or email

## Troubleshooting

### Common Issues

1. **Batch Job Failures**
   ```bash
   # Check job status and logs
   gcloud batch jobs describe JOB_NAME --location=${REGION}
   gcloud logging read "resource.type=batch_job AND resource.labels.job_uid=JOB_NAME"
   ```

2. **Cloud Function Timeouts**
   ```bash
   # Check function configuration and logs
   gcloud functions describe cost-optimizer --region=${REGION}
   gcloud functions logs read cost-optimizer --region=${REGION}
   ```

3. **BigQuery Permission Issues**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

4. **Pub/Sub Message Backlog**
   ```bash
   # Check subscription metrics
   gcloud pubsub subscriptions describe cost-optimization-processor
   ```

### Support Resources

- [Google Cloud Batch Documentation](https://cloud.google.com/batch/docs)
- [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/best-practices)
- [Cloud Functions Troubleshooting](https://cloud.google.com/functions/docs/troubleshooting)
- [Cost Optimization Framework](https://cloud.google.com/architecture/framework/cost-optimization)

## Security Considerations

- All resources use Google Cloud IAM for access control
- Service accounts follow the principle of least privilege
- Cloud Functions use authenticated HTTPS endpoints
- BigQuery datasets include appropriate access controls
- Batch jobs run with minimal required permissions
- Storage buckets include object lifecycle management for cost optimization

## Cost Optimization

The infrastructure itself is designed for cost efficiency:

- Uses preemptible instances for batch processing
- Implements storage lifecycle policies for historical data
- Leverages serverless technologies (Cloud Functions, Cloud Run) for pay-per-use billing
- Includes automatic resource cleanup and optimization
- Provides detailed cost tracking and reporting through BigQuery

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update variable documentation for any new parameters
3. Ensure cleanup scripts properly remove all new resources
4. Update monitoring and alerting for new components
5. Document any new security considerations

For questions or issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support resources.