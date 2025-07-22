# Infrastructure as Code for Distributed Data Processing Workflows with Cloud Dataproc and Cloud Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Distributed Data Processing Workflows with Cloud Dataproc and Cloud Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud Project with billing enabled
- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Appropriate IAM permissions for:
  - Cloud Dataproc (Editor role)
  - Cloud Scheduler (Admin role)
  - Cloud Storage (Admin role)
  - BigQuery (Data Editor role)
  - Service Account creation and management
- Basic understanding of Apache Spark and data processing workflows

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Infrastructure Manager API enabled in your Google Cloud project
- Cloud Resource Manager API enabled

#### Terraform
- Terraform installed (version 1.0 or later)
- Google Cloud provider for Terraform

### Estimated Costs
- $10-25 for running this tutorial (primarily Compute Engine and BigQuery usage)
- Costs are minimized through ephemeral cluster usage

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create dataproc-workflow-deployment \
    --location=${REGION} \
    --source-file=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe dataproc-workflow-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Architecture Overview

This infrastructure creates:

- **Cloud Storage Buckets**: Data lake storage for input files and staging
- **BigQuery Dataset**: Analytics data warehouse for processed results
- **Dataproc Workflow Template**: Reusable Apache Spark job definition with ephemeral cluster
- **Cloud Scheduler Job**: Automated cron-based workflow execution
- **IAM Service Account**: Secure authentication for scheduler operations
- **Sample Data**: Synthetic sales dataset for testing and demonstration

## Key Features

### Cost Optimization
- **Ephemeral Clusters**: Automatically created and deleted for each job execution
- **Auto-scaling**: Dynamic cluster sizing based on workload demands
- **Preemptible Instances**: Optional cost reduction for fault-tolerant workloads
- **Standard Storage**: Cost-effective data retention with lifecycle policies

### Security & Compliance
- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Audit Logging**: Comprehensive audit trails for compliance requirements
- **VPC Controls**: Optional network isolation for enhanced security
- **Encryption**: Data encrypted at rest and in transit

### Monitoring & Observability
- **Cloud Logging**: Centralized log collection and analysis
- **Cloud Monitoring**: Infrastructure and application metrics
- **Job Status Tracking**: Real-time workflow execution monitoring
- **Error Alerting**: Automated notification for failed job executions

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Google Cloud region"
    default: "us-central1"
    type: string
  workflow_schedule:
    description: "Cron schedule for workflow execution"
    default: "0 2 * * *"
    type: string
```

### Terraform Variables

Key variables in `terraform.tfvars`:

```hcl
# Project Configuration
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Dataproc Configuration
cluster_config = {
  num_workers        = 2
  worker_machine_type = "e2-standard-4"
  worker_disk_size   = "50GB"
  enable_autoscaling = true
  max_workers       = 4
}

# Scheduler Configuration
workflow_schedule = "0 2 * * *"  # Daily at 2 AM
time_zone        = "America/New_York"

# Storage Configuration
enable_versioning = true
lifecycle_rules   = true
```

### Bash Script Environment Variables

Set these variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export WORKFLOW_SCHEDULE="0 2 * * *"
export ENABLE_AUTOSCALING="true"
export MAX_WORKERS="4"
```

## Deployment Validation

After deployment, verify the infrastructure:

### Check Cloud Storage Buckets
```bash
gsutil ls -p ${PROJECT_ID}
gsutil ls -r gs://dataproc-data-*/
```

### Verify BigQuery Dataset
```bash
bq ls --project_id=${PROJECT_ID}
bq show ${PROJECT_ID}:analytics_results
```

### Test Workflow Template
```bash
gcloud dataproc workflow-templates list --region=${REGION}
gcloud dataproc workflow-templates instantiate sales-analytics-workflow --region=${REGION}
```

### Check Scheduler Job
```bash
gcloud scheduler jobs list --location=${REGION}
gcloud scheduler jobs describe sales-analytics-daily --location=${REGION}
```

### Verify Processed Results
```bash
# Query BigQuery results
bq query --use_legacy_sql=false \
"SELECT region, category, total_sales, transaction_count 
FROM \`${PROJECT_ID}.analytics_results.sales_summary\` 
ORDER BY total_sales DESC LIMIT 10"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable dataproc.googleapis.com
   gcloud services enable cloudscheduler.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable bigquery.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current user permissions
   gcloud auth list
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Cluster Creation Failures**
   - Check Compute Engine quotas
   - Verify network configuration
   - Review Dataproc service account permissions

4. **Scheduler Job Failures**
   - Verify service account permissions
   - Check workflow template configuration
   - Review Cloud Scheduler logs

### Monitoring Commands

```bash
# Monitor workflow execution
gcloud dataproc operations list --region=${REGION}

# Check scheduler job history
gcloud scheduler jobs describe sales-analytics-daily --location=${REGION}

# View Dataproc cluster logs
gcloud logging read "resource.type=dataproc_cluster" --limit=50
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete dataproc-workflow-deployment \
    --location=${REGION} \
    --delete-policy=DELETE

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
gcloud scheduler jobs list --location=${REGION}
gcloud dataproc workflow-templates list --region=${REGION}
gsutil ls -p ${PROJECT_ID}
```

### Manual Cleanup (if needed)

```bash
# Delete specific resources if automated cleanup fails
gcloud scheduler jobs delete sales-analytics-daily --location=${REGION} --quiet
gcloud dataproc workflow-templates delete sales-analytics-workflow --region=${REGION} --quiet
gsutil -m rm -r gs://dataproc-data-* gs://dataproc-staging-*
bq rm -r -f analytics_results
gcloud iam service-accounts delete dataproc-scheduler@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Advanced Configuration

### Custom Spark Applications

To deploy your own Spark applications:

1. Upload PySpark scripts to Cloud Storage
2. Modify workflow template job configuration
3. Update input/output parameters
4. Adjust cluster specifications for workload requirements

### Multi-Environment Deployment

For production environments:

```bash
# Use environment-specific variables
export ENVIRONMENT="production"
export PROJECT_ID="your-prod-project"
export CLUSTER_SIZE="large"
export ENABLE_PREEMPTIBLE="false"
```

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy Dataproc Workflow
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: google-github-actions/setup-gcloud@v0
      - run: ./scripts/deploy.sh
```

## Cost Optimization Tips

1. **Use Preemptible Instances**: Reduce costs by up to 80% for fault-tolerant workloads
2. **Right-size Clusters**: Monitor resource utilization and adjust machine types
3. **Schedule Off-peak**: Run workflows during low-demand periods
4. **Implement Lifecycle Policies**: Automatically delete old data and logs
5. **Monitor Spending**: Set up budget alerts and cost monitoring

## Security Best Practices

1. **Service Account Keys**: Use workload identity instead of service account keys
2. **VPC Security**: Deploy in private subnets with restricted internet access
3. **Data Encryption**: Enable customer-managed encryption keys (CMEK)
4. **Audit Logging**: Enable all audit log categories
5. **Network Controls**: Implement VPC Service Controls for data perimeter security

## Performance Tuning

### Spark Configuration
- Adjust executor memory and cores based on data size
- Enable dynamic allocation for variable workloads
- Use Kryo serialization for better performance
- Configure appropriate parallelism levels

### Storage Optimization
- Use Parquet format for columnar storage benefits
- Implement proper partitioning strategies
- Consider BigQuery external tables for cost optimization
- Use Cloud Storage transfer acceleration for large datasets

## Support and Documentation

- [Google Cloud Dataproc Documentation](https://cloud.google.com/dataproc/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Apache Spark on Dataproc](https://cloud.google.com/dataproc/docs/concepts/jobs/spark-jobs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support resources.