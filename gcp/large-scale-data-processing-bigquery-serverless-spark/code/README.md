# Infrastructure as Code for Large-Scale Data Processing with BigQuery Serverless Spark

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Large-Scale Data Processing with BigQuery Serverless Spark".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions:
  - BigQuery Admin
  - Storage Admin
  - Dataproc Serverless Admin
  - Service Account User
  - Project Editor (for API enablement)
- Required APIs enabled:
  - BigQuery API
  - Cloud Storage API
  - Dataproc API
  - Cloud Notebooks API

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/spark-data-processing \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --local-source=infrastructure-manager/ \
    --inputs-file=infrastructure-manager/terraform.tfvars
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
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

## Architecture Overview

The infrastructure code deploys the following Google Cloud resources:

### Core Components

- **Cloud Storage Bucket**: Data lake storage for raw and processed data
  - Configured with versioning enabled
  - Organized folder structure (raw-data/, processed-data/, scripts/)
  - Standard storage class in specified region

- **BigQuery Dataset**: Analytics dataset for storing processed results
  - Location set to match regional requirements
  - Configured for optimal query performance
  - Tables for customer, product, and location analytics

- **IAM Configuration**: Service accounts and permissions
  - Dataproc Serverless service account
  - BigQuery data editor permissions
  - Storage object admin permissions

### Processing Resources

- **Sample Data**: Pre-configured e-commerce transaction dataset
  - CSV format with realistic transaction data
  - Multiple product categories and customer segments
  - Time-series data for trend analysis

- **PySpark Script**: Advanced data processing pipeline
  - Customer segmentation and analytics
  - Product performance analysis
  - Location-based revenue insights
  - Optimized for Serverless Spark execution

### Monitoring and Governance

- **Cloud Logging**: Centralized log collection for Spark jobs
- **Cloud Monitoring**: Resource utilization and performance metrics
- **IAM Policies**: Least privilege access controls

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
bucket_name_suffix = "unique-identifier"
dataset_name_suffix = "unique-identifier"
```

### Terraform Variables

Available variables in `terraform/variables.tf`:

- `project_id`: Google Cloud Project ID (required)
- `region`: Deployment region (default: "us-central1")
- `zone`: Deployment zone (default: "us-central1-a")
- `bucket_name_suffix`: Unique suffix for storage bucket
- `dataset_name_suffix`: Unique suffix for BigQuery dataset
- `enable_apis`: Enable required Google Cloud APIs (default: true)

### Script Configuration

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export BUCKET_NAME_SUFFIX="$(date +%s)"
export DATASET_NAME_SUFFIX="$(date +%s)"
```

## Post-Deployment Steps

After infrastructure deployment, follow these steps to execute the data processing pipeline:

### 1. Submit Serverless Spark Job

```bash
# Get the bucket name from terraform output
BUCKET_NAME=$(terraform output -raw bucket_name)
DATASET_NAME=$(terraform output -raw dataset_name)

# Submit the processing job
gcloud dataproc batches submit pyspark \
    gs://${BUCKET_NAME}/scripts/data_processing_spark.py \
    --batch=${DATASET_NAME}-processing-job \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --jars=gs://spark-lib/bigquery/spark-bigquery-latest.jar \
    --properties="spark.executor.instances=2,spark.executor.memory=4g,spark.executor.cores=2" \
    --ttl=30m \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com
```

### 2. Monitor Job Progress

```bash
# Check job status
gcloud dataproc batches describe ${DATASET_NAME}-processing-job \
    --region=${REGION} \
    --format="value(state)"

# View job logs
gcloud dataproc batches describe ${DATASET_NAME}-processing-job \
    --region=${REGION} \
    --format="value(runtimeInfo.outputUri)"
```

### 3. Validate Results

```bash
# Query processed analytics data
bq query --use_legacy_sql=false \
"SELECT customer_id, customer_segment, transaction_count, total_spent 
 FROM \`${PROJECT_ID}.${DATASET_NAME}.customer_analytics\` 
 ORDER BY total_spent DESC LIMIT 10"
```

## Cost Estimation

### Expected Costs (US regions)

- **Cloud Storage**: ~$0.02/GB/month for standard storage
- **BigQuery**: 
  - Storage: ~$0.02/GB/month
  - Queries: ~$6.25/TB processed
- **Serverless Spark**: ~$0.056/vCPU-hour + $0.00375/GB-hour
- **Sample workload**: Estimated $5-20 for complete recipe execution

### Cost Optimization Tips

- Use regional storage for better performance and lower costs
- Leverage BigQuery's automatic clustering for frequently queried tables
- Configure Spark job TTL to prevent long-running jobs
- Use preemptible instances for development workloads

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/spark-data-processing
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
# Remove any running Spark jobs
gcloud dataproc batches cancel ${DATASET_NAME}-processing-job --region=${REGION}

# Force delete storage bucket
gsutil -m rm -r gs://${BUCKET_NAME}

# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:${DATASET_NAME}
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs manually
   gcloud services enable bigquery.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable dataproc.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Spark Job Failures**
   ```bash
   # Check job logs for detailed error information
   gcloud dataproc batches describe ${JOB_NAME} --region=${REGION}
   ```

4. **Resource Quota Limits**
   ```bash
   # Check current quotas
   gcloud compute project-info describe --project=${PROJECT_ID}
   ```

### Debug Mode

Enable debug logging for bash scripts:

```bash
export DEBUG=true
./scripts/deploy.sh
```

## Security Considerations

### IAM Best Practices

- Service accounts use least privilege principle
- BigQuery datasets configured with appropriate access controls
- Cloud Storage buckets use uniform bucket-level access
- Audit logging enabled for all resource access

### Data Protection

- Cloud Storage versioning enabled for data protection
- BigQuery datasets encrypted at rest by default
- Network traffic encrypted in transit
- No hardcoded credentials in any configuration files

### Compliance

- All resources tagged with appropriate labels
- Cloud Asset Inventory integration for resource tracking
- Cloud Security Command Center integration available
- Supports VPC Service Controls when configured

## Advanced Configuration

### Custom PySpark Jobs

To deploy custom PySpark scripts:

1. Place your script in the `scripts/` directory
2. Update the `data_processing_spark.py` filename in deployment configurations
3. Modify Spark job properties as needed in the submission command

### Multi-Region Deployment

For cross-region deployments:

1. Modify `region` and `zone` variables
2. Consider data residency requirements
3. Update BigQuery dataset locations accordingly
4. Review network egress costs

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy Spark Infrastructure
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: google-github-actions/setup-gcloud@v1
      - name: Deploy Infrastructure
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

## Support and Documentation

### Additional Resources

- [BigQuery Serverless Spark Documentation](https://cloud.google.com/bigquery/docs/spark-overview)
- [Dataproc Serverless Guide](https://cloud.google.com/dataproc-serverless/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation for specific services
3. Consult the original recipe documentation
4. Contact your cloud administrator for permission issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Google Cloud best practices
3. Update documentation accordingly
4. Consider backward compatibility