# Infrastructure as Code for Scientific Workflow Orchestration with Cloud Batch API and Vertex AI Workbench

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scientific Workflow Orchestration with Cloud Batch API and Vertex AI Workbench".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for command-line deployment

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for creating:
  - Cloud Batch jobs and compute resources
  - Vertex AI Workbench instances
  - Cloud Storage buckets
  - BigQuery datasets and tables
  - Service accounts and IAM bindings
- Basic understanding of genomics workflows and machine learning concepts
- Estimated cost: $150-300 for complete workflow execution (varies by data size and compute duration)

## Required APIs

The following Google Cloud APIs must be enabled in your project:

```bash
gcloud services enable batch.googleapis.com
gcloud services enable notebooks.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable iam.googleapis.com
```

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code with native integration to Google Cloud services.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set your project ID and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/genomics-workflow \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/genomics-workflow
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive module ecosystem for Google Cloud resources.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View important outputs
terraform output
```

### Using Bash Scripts

For users who prefer command-line deployment or need to integrate with existing automation workflows.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# The script will create:
# - Cloud Storage bucket for genomic data
# - BigQuery dataset with variant and analysis tables
# - Vertex AI Workbench instance
# - Sample processing scripts and notebooks
# - Cloud Batch job configurations
```

## Configuration

### Environment Variables

All implementations support these configuration options:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | - | Yes |
| `REGION` | Primary deployment region | `us-central1` | No |
| `ZONE` | Compute zone for instances | `us-central1-a` | No |
| `BUCKET_NAME` | Cloud Storage bucket name | Auto-generated | No |
| `DATASET_NAME` | BigQuery dataset name | Auto-generated | No |
| `WORKBENCH_NAME` | Vertex AI Workbench instance name | Auto-generated | No |
| `MACHINE_TYPE` | Workbench instance machine type | `n1-standard-4` | No |
| `BOOT_DISK_SIZE` | Workbench boot disk size (GB) | `100` | No |
| `DATA_DISK_SIZE` | Workbench data disk size (GB) | `200` | No |

### Customization

#### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
workbench_machine_type = "n1-standard-4"
enable_gpu = false
boot_disk_size_gb = 100
data_disk_size_gb = 200
```

#### Infrastructure Manager Configuration

Modify `infrastructure-manager/terraform.tfvars` with your specific requirements:

```hcl
project_id = "your-project-id"
region = "us-central1"
genomic_data_retention_days = 30
enable_advanced_security = true
batch_job_parallelism = 3
```

## Post-Deployment Setup

### 1. Access Vertex AI Workbench

After deployment, access your Workbench instance:

```bash
# Get Workbench instance status
gcloud notebooks instances describe ${WORKBENCH_NAME} \
    --location=${ZONE} \
    --format="value(state)"

# Get access URL
echo "Workbench URL: https://${WORKBENCH_NAME}-dot-${ZONE}-dot-notebooks.googleusercontent.com/"
```

### 2. Upload Sample Data

```bash
# Create sample genomic data structure
gsutil -m cp /dev/null gs://${BUCKET_NAME}/raw-data/.keep
gsutil -m cp /dev/null gs://${BUCKET_NAME}/processed-data/.keep
gsutil -m cp /dev/null gs://${BUCKET_NAME}/results/.keep

# Upload processing scripts (automatically included in deployment)
gsutil ls gs://${BUCKET_NAME}/scripts/
```

### 3. Verify BigQuery Setup

```bash
# List created tables
bq ls ${DATASET_NAME}

# Query table schemas
bq show ${PROJECT_ID}:${DATASET_NAME}.variant_calls
bq show ${PROJECT_ID}:${DATASET_NAME}.analysis_results
```

### 4. Submit Initial Batch Job

```bash
# Submit sample genomic processing job
export JOB_NAME="genomic-processing-$(date +%s)"
gcloud batch jobs submit ${JOB_NAME} \
    --location=${REGION} \
    --config=batch_job_config.json
```

## Monitoring and Operations

### Check Deployment Status

```bash
# Infrastructure Manager
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/genomics-workflow

# Terraform
terraform show

# Batch Jobs
gcloud batch jobs list --location=${REGION}

# Workbench Instances
gcloud notebooks instances list --location=${ZONE}
```

### View Logs

```bash
# Batch job logs
gcloud batch jobs describe ${JOB_NAME} \
    --location=${REGION} \
    --format="value(status.taskGroups[0].instances[0].logUri)"

# Cloud Logging for all resources
gcloud logging read "resource.type=batch_job" --limit=50
```

### Performance Monitoring

```bash
# Monitor BigQuery job performance
bq ls -j --max_results=10

# Check Cloud Storage usage
gsutil du -sh gs://${BUCKET_NAME}

# Monitor Vertex AI Workbench resource utilization
gcloud notebooks instances get-instance-health ${WORKBENCH_NAME} \
    --location=${ZONE}
```

## Data Pipeline Workflow

### 1. Data Ingestion

```bash
# Upload genomic data files (FASTQ, BAM, VCF)
gsutil -m cp local-genomic-files/* gs://${BUCKET_NAME}/raw-data/
```

### 2. Batch Processing

```bash
# Submit processing job for multiple samples
gcloud batch jobs submit genomic-processing-$(date +%s) \
    --location=${REGION} \
    --config=batch_job_config.json
```

### 3. Machine Learning Analysis

1. Access Workbench instance via web interface
2. Open the pre-installed genomic analysis notebook
3. Execute cells to perform variant analysis and drug discovery predictions
4. Results are automatically stored in BigQuery

### 4. Results Validation

```bash
# Query processed variants
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as variant_count FROM \`${PROJECT_ID}.${DATASET_NAME}.variant_calls\`"

# Query analysis insights
bq query --use_legacy_sql=false \
    "SELECT clinical_significance, COUNT(*) as count 
     FROM \`${PROJECT_ID}.${DATASET_NAME}.analysis_results\` 
     GROUP BY clinical_significance"
```

## Security Considerations

### Data Protection

- All Cloud Storage buckets are created with encryption at rest
- BigQuery datasets include column-level security
- Vertex AI Workbench instances use secure boot and shielded VMs
- Network traffic is encrypted in transit

### Access Control

- Service accounts follow least privilege principles
- IAM bindings are scoped to specific resources
- Workbench instances are configured with private IP addresses
- Cloud Batch jobs run with dedicated service accounts

### Compliance

This infrastructure supports common compliance requirements for genomic research:

- **HIPAA**: Enable audit logging and access controls for protected health information
- **GDPR**: Implement data retention policies and deletion capabilities
- **FDA 21 CFR Part 11**: Maintain audit trails and electronic signature capabilities

## Troubleshooting

### Common Issues

#### Deployment Failures

```bash
# Check API enablement
gcloud services list --enabled --filter="name:batch.googleapis.com OR name:notebooks.googleapis.com"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check quota limits
gcloud compute project-info describe --project=${PROJECT_ID}
```

#### Batch Job Failures

```bash
# Describe failed job
gcloud batch jobs describe ${JOB_NAME} --location=${REGION}

# Check job logs
gcloud logging read "resource.type=batch_job AND resource.labels.job_id=${JOB_NAME}" --limit=100
```

#### Workbench Access Issues

```bash
# Reset Workbench instance
gcloud notebooks instances reset ${WORKBENCH_NAME} --location=${ZONE}

# Check instance health
gcloud notebooks instances get-instance-health ${WORKBENCH_NAME} --location=${ZONE}
```

#### BigQuery Query Failures

```bash
# Check dataset permissions
bq show --format=prettyjson ${PROJECT_ID}:${DATASET_NAME}

# Verify table schemas
bq show ${PROJECT_ID}:${DATASET_NAME}.variant_calls
```

### Performance Optimization

#### Batch Job Optimization

- Increase `parallelism` in batch job configuration for larger datasets
- Use preemptible instances for cost optimization
- Optimize container images for faster startup times

#### BigQuery Optimization

- Partition tables by sample_id or chromosome for better query performance
- Use clustering on frequently queried columns
- Implement table expiration for temporary analysis results

#### Storage Optimization

- Use Nearline storage class for infrequently accessed genomic data
- Implement lifecycle policies for automatic data archiving
- Enable compression for large genomic files

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/genomics-workflow
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm deletion
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will remove:
# - Vertex AI Workbench instances
# - Cloud Batch jobs
# - BigQuery datasets and tables
# - Cloud Storage buckets and contents
# - Service accounts and IAM bindings
```

### Manual Cleanup Verification

```bash
# Verify resource deletion
gcloud notebooks instances list --location=${ZONE}
gcloud batch jobs list --location=${REGION}
bq ls --project_id=${PROJECT_ID}
gsutil ls -p ${PROJECT_ID}
```

## Cost Optimization

### Resource Management

- Use preemptible instances for Batch jobs to reduce compute costs by up to 80%
- Implement Cloud Storage lifecycle policies to automatically transition data to cheaper storage classes
- Schedule Workbench instances to automatically stop during non-working hours
- Use BigQuery slot reservations for predictable query workloads

### Monitoring Costs

```bash
# Check current spending
gcloud billing budgets list --billing-account=${BILLING_ACCOUNT_ID}

# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Genomics Workflow Budget" \
    --budget-amount=500USD
```

## Support and Documentation

### Additional Resources

- [Google Cloud Batch API Documentation](https://cloud.google.com/batch/docs)
- [Vertex AI Workbench User Guide](https://cloud.google.com/vertex-ai/docs/workbench)
- [BigQuery for Genomics](https://cloud.google.com/life-sciences/docs/tutorials/bigquery)
- [Scientific Computing on Google Cloud](https://cloud.google.com/solutions/hpc-on-gcp)

### Community Support

- [Google Cloud Community Forums](https://www.googlecloudcommunity.com/)
- [Bioinformatics Stack Exchange](https://bioinformatics.stackexchange.com/)
- [Google Cloud Slack Community](https://googlecloud-community.slack.com/)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud provider documentation.