# Infrastructure as Code for Interactive Data Pipeline Prototypes with Cloud Data Fusion and Colab Enterprise

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Interactive Data Pipeline Prototypes with Cloud Data Fusion and Colab Enterprise".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Following APIs enabled:
  - Cloud Data Fusion API
  - Notebooks API
  - BigQuery API
  - Cloud Storage API
  - Compute Engine API
- Appropriate IAM permissions:
  - Data Fusion Admin
  - BigQuery Admin
  - Storage Admin
  - Notebooks Admin
  - Compute Admin
- Estimated cost: $50-75 per day for moderate usage

> **Note**: Cloud Data Fusion instances incur charges while running. The Developer edition is recommended for prototyping to minimize costs.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended IaC solution for managing cloud resources.

```bash
# Set project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/data-pipeline-infrastructure \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/data-pipeline-infrastructure
```

### Using Terraform

Terraform provides cross-cloud infrastructure management with the Google Cloud provider.

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide a familiar CLI-based deployment approach.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the interactive prompts for configuration
```

## Architecture

This IaC deployment creates the following infrastructure:

- **Cloud Data Fusion Instance**: Developer edition for cost-effective pipeline development
- **Cloud Storage Buckets**: Data lake and staging buckets with versioning enabled
- **BigQuery Dataset**: Analytics destination with appropriate location settings
- **Sample Data**: Representative CSV and JSON datasets for pipeline testing
- **IAM Service Accounts**: Properly configured service accounts with minimal required permissions
- **Colab Enterprise Configuration**: Runtime template and integration settings

## Configuration Options

### Infrastructure Manager Variables

Configure the deployment by modifying variables in `infrastructure-manager/main.yaml`:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  fusion_edition:
    description: "Data Fusion edition (developer or enterprise)"
    type: string
    default: "developer"
  enable_monitoring:
    description: "Enable Cloud Monitoring integration"
    type: bool
    default: true
```

### Terraform Variables

Customize the deployment using `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Data Fusion configuration
fusion_instance_name = "data-fusion-dev"
fusion_edition = "developer"
enable_stackdriver_logging = true
enable_stackdriver_monitoring = true

# Storage configuration
bucket_storage_class = "STANDARD"
enable_bucket_versioning = true

# BigQuery configuration
dataset_location = "us-central1"
dataset_description = "Analytics dataset for pipeline prototyping"

# Cost optimization
auto_delete_buckets = false
```

### Bash Script Configuration

Configure deployment by setting environment variables before running scripts:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export FUSION_EDITION="developer"  # or "enterprise"
export STORAGE_CLASS="STANDARD"    # or "NEARLINE", "COLDLINE"
export ENABLE_MONITORING="true"
export MACHINE_TYPE="n1-standard-4"
```

## Post-Deployment Setup

After successful deployment, complete these setup steps:

### 1. Access Colab Enterprise

```bash
# Get the Colab Enterprise URL
echo "Access Colab Enterprise: https://console.cloud.google.com/vertex-ai/colab"

# Upload the sample notebook
gsutil cp notebooks/pipeline_prototype.ipynb gs://your-bucket-name/notebooks/
```

### 2. Configure Data Fusion

```bash
# Get the Data Fusion instance endpoint
FUSION_ENDPOINT=$(gcloud data-fusion instances describe ${INSTANCE_NAME} \
    --location=${REGION} \
    --format="value(apiEndpoint)")

echo "Data Fusion UI: ${FUSION_ENDPOINT}"

# Import the pipeline template
curl -X PUT \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -d @pipelines/pipeline_template.json \
    "${FUSION_ENDPOINT}/v3/namespaces/default/apps/customer-transaction-pipeline"
```

### 3. Verify Setup

```bash
# Check Data Fusion status
gcloud data-fusion instances describe ${INSTANCE_NAME} \
    --location=${REGION} \
    --format="table(name,state,version,type)"

# Verify BigQuery dataset
bq ls ${PROJECT_ID}:${DATASET_NAME}

# Test storage access
gsutil ls gs://${BUCKET_NAME}/
```

## Monitoring and Troubleshooting

### Health Checks

```bash
# Check Data Fusion instance health
gcloud data-fusion instances describe ${INSTANCE_NAME} \
    --location=${REGION} \
    --format="value(state)"

# Verify API endpoints
curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "${FUSION_ENDPOINT}/v3/namespaces/default/apps"

# Check BigQuery connectivity
bq query --use_legacy_sql=false "SELECT 1 as test"
```

### Common Issues

1. **Data Fusion instance stuck in CREATING state**:
   - Check quota limits for the region
   - Verify all required APIs are enabled
   - Review IAM permissions

2. **BigQuery access denied**:
   - Verify service account has BigQuery Data Editor role
   - Check dataset location matches the configured region

3. **Storage bucket access issues**:
   - Confirm service account has Storage Object Admin role
   - Verify bucket names are globally unique

### Logs and Monitoring

```bash
# View Data Fusion logs
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_name~data-fusion" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"

# Monitor BigQuery usage
bq ls -j --max_results=10

# Check storage operations
gsutil ls -L gs://${BUCKET_NAME}/
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/data-pipeline-infrastructure \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify Data Fusion instances are deleted
gcloud data-fusion instances list --location=${REGION}

# Check BigQuery datasets
bq ls

# Verify storage buckets are removed
gsutil ls

# Clean up local files
rm -f *.csv *.json *.ipynb *.yaml
```

## Security Considerations

This deployment implements several security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **Encrypted Storage**: All data is encrypted at rest using Google-managed keys
- **Network Security**: Resources are deployed in default VPC with appropriate firewall rules
- **Audit Logging**: Cloud Audit Logs enabled for all resource operations
- **Data Location**: Resources deployed in specified region for data residency

### Additional Security Hardening

For production environments, consider these enhancements:

```bash
# Enable VPC Service Controls
gcloud access-context-manager perimeters create production-perimeter \
    --title="Production Data Pipeline Perimeter" \
    --resources=projects/${PROJECT_ID}

# Configure customer-managed encryption keys
gcloud kms keyrings create data-pipeline-keys --location=global
gcloud kms keys create pipeline-data-key \
    --location=global \
    --keyring=data-pipeline-keys \
    --purpose=encryption
```

## Cost Optimization

### Resource Costs

- **Cloud Data Fusion Developer**: ~$1.25/hour
- **Cloud Storage**: $0.020/GB/month (standard class)
- **BigQuery**: $5/TB for analysis, $10/TB/month for storage
- **Colab Enterprise**: $0.10/hour for n1-standard-4

### Cost Reduction Strategies

1. **Use Scheduled Start/Stop**:
   ```bash
   # Stop Data Fusion when not in use
   gcloud data-fusion instances stop ${INSTANCE_NAME} --location=${REGION}
   
   # Restart when needed
   gcloud data-fusion instances start ${INSTANCE_NAME} --location=${REGION}
   ```

2. **Implement Lifecycle Policies**:
   ```bash
   # Create lifecycle configuration for storage
   gsutil lifecycle set lifecycle.json gs://${BUCKET_NAME}
   ```

3. **Monitor Usage**:
   ```bash
   # Set up billing alerts
   gcloud alpha billing budgets create \
       --billing-account=${BILLING_ACCOUNT_ID} \
       --display-name="Data Pipeline Budget" \
       --budget-amount=100USD
   ```

## Development Workflow

### Notebook Development Process

1. **Prototype in Colab Enterprise**:
   - Explore data using pandas and BigQuery client
   - Develop transformation logic interactively
   - Validate data quality and performance

2. **Export to Data Fusion**:
   - Convert notebook transformations to Data Fusion pipeline
   - Use Wrangler for complex data transformations
   - Configure scheduling and monitoring

3. **Production Deployment**:
   - Test pipeline with full dataset
   - Configure alerts and monitoring
   - Schedule regular execution

### Pipeline Development Best Practices

```python
# Example notebook cell for pipeline prototyping
import pandas as pd
from google.cloud import bigquery, storage

# Test transformation logic
def clean_customer_data(df):
    """Clean and validate customer data"""
    df['email'] = df['email'].str.lower().str.strip()
    df['signup_date'] = pd.to_datetime(df['signup_date'])
    return df.dropna()

# Validate with sample data
customer_df = pd.read_csv('gs://bucket/raw/customer_data.csv')
cleaned_df = clean_customer_data(customer_df)
print(f"Cleaned {len(cleaned_df)} records from {len(customer_df)}")
```

## Extensions and Integration

### Advanced Analytics Integration

```bash
# Connect to Looker for BI dashboards
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:looker@your-domain.com" \
    --role="roles/bigquery.dataViewer"

# Integrate with Vertex AI for ML workflows
gcloud ai-platform models create customer-analytics \
    --region=${REGION}
```

### Real-time Processing Extension

```bash
# Add Pub/Sub for streaming data
gcloud pubsub topics create customer-events
gcloud pubsub subscriptions create customer-events-sub \
    --topic=customer-events

# Configure Dataflow for stream processing
gcloud dataflow jobs run streaming-pipeline \
    --gcs-location=gs://dataflow-templates/latest/PubSub_to_BigQuery \
    --region=${REGION} \
    --parameters=inputTopic=projects/${PROJECT_ID}/topics/customer-events
```

## Support and Documentation

- [Cloud Data Fusion Documentation](https://cloud.google.com/data-fusion/docs)
- [Colab Enterprise Guide](https://cloud.google.com/colab/docs)
- [BigQuery Best Practices](https://cloud.google.com/bigquery/docs/best-practices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.