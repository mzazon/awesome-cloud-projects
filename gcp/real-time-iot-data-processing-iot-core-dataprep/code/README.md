# Infrastructure as Code for Real-Time IoT Data Processing with Cloud IoT Core and Cloud Dataprep

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time IoT Data Processing with Cloud IoT Core and Cloud Dataprep".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud IoT Core Admin
  - Pub/Sub Admin
  - BigQuery Admin
  - Dataprep Admin
  - Storage Admin
  - Monitoring Admin
- Python 3.7+ for device simulation scripts
- OpenSSL for certificate generation

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/iot-pipeline \
    --service-account="your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo.git" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/iot-pipeline
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required variables:
# - PROJECT_ID
# - REGION
# - BILLING_ACCOUNT_ID (optional)
```

## Architecture Overview

The infrastructure deploys a complete IoT data processing pipeline including:

- **Cloud IoT Core**: Device registry and authentication
- **Cloud Pub/Sub**: Message queue for telemetry data
- **Cloud Dataprep**: Automated data cleansing and transformation
- **BigQuery**: Data warehouse for analytics
- **Cloud Storage**: Staging area for Dataprep operations
- **Cloud Monitoring**: Pipeline observability and alerting

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  iot_registry_name:
    description: "IoT Core registry name"
    type: string
    default: "sensor-registry"
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
iot_registry_name = "sensor-registry"
pubsub_topic_name = "iot-telemetry"
bigquery_dataset  = "iot_analytics"
```

### Bash Script Variables

The deployment script will prompt for required variables or you can set them as environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export BILLING_ACCOUNT_ID="your-billing-account-id"
```

## Post-Deployment Steps

1. **Configure Cloud Dataprep Flow**:
   - Open Cloud Dataprep console
   - Create new flow using the sample data uploaded to Cloud Storage
   - Configure transformations for data quality issues
   - Set output destination to the created BigQuery table

2. **Set Up IoT Device Simulation**:
   - Generate device certificates using the provided scripts
   - Run the Python IoT simulator to start sending telemetry data
   - Monitor data flow through the pipeline

3. **Configure Monitoring Dashboards**:
   - Access the created Cloud Monitoring dashboard
   - Set up additional alerting policies as needed
   - Monitor pipeline performance and data quality metrics

## Validation

After deployment, verify the infrastructure:

```bash
# Check IoT Core registry
gcloud iot registries list --region=${REGION}

# Verify Pub/Sub topic
gcloud pubsub topics list --filter="name:iot-telemetry"

# Check BigQuery dataset
bq ls ${PROJECT_ID}:

# Test data flow
gcloud pubsub subscriptions pull iot-data-subscription --limit=5
```

## Cost Estimation

Expected monthly costs for moderate usage (approximate):

- **Cloud IoT Core**: $0.50 per million messages
- **Cloud Pub/Sub**: $0.40 per million messages
- **BigQuery**: $5.00 per TB stored, $5.00 per TB processed
- **Cloud Dataprep**: $2.50 per processing hour
- **Cloud Storage**: $0.02 per GB stored

Total estimated cost: $20-50 per month for development/testing workloads.

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for all service accounts
- **Device Authentication**: Certificate-based device authentication
- **Data Encryption**: Automatic encryption at rest and in transit
- **Network Security**: VPC-native networking where applicable
- **Access Controls**: BigQuery dataset-level access controls

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Permission Denied**: Verify your account has the necessary IAM roles
3. **Quota Exceeded**: Check project quotas for Pub/Sub and BigQuery
4. **Device Authentication**: Ensure device certificates are properly generated

### Debug Commands

```bash
# Check enabled APIs
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check resource quotas
gcloud compute project-info describe --project=${PROJECT_ID}

# Monitor logs
gcloud logging read "resource.type=pubsub_topic" --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/iot-pipeline

# Confirm deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup (if needed)

```bash
# Delete IoT Core resources
gcloud iot devices delete DEVICE_ID --region=${REGION} --registry=REGISTRY_ID
gcloud iot registries delete REGISTRY_ID --region=${REGION}

# Delete Pub/Sub resources
gcloud pubsub subscriptions delete SUBSCRIPTION_NAME
gcloud pubsub topics delete TOPIC_NAME

# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:DATASET_NAME

# Delete Cloud Storage bucket
gsutil rm -r gs://BUCKET_NAME
```

## Monitoring and Observability

The deployment includes:

- **Cloud Monitoring Dashboard**: Real-time pipeline metrics
- **Log-based Metrics**: Custom metrics for data quality tracking
- **Alerting Policies**: Proactive notifications for pipeline issues
- **Error Reporting**: Automatic error detection and reporting

Access the monitoring dashboard:
```bash
# Open monitoring console
gcloud monitoring dashboards list
```

## Development and Testing

### Local Development

1. **Set up Python environment**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

2. **Generate test certificates**:
   ```bash
   ./scripts/generate_device_certs.sh
   ```

3. **Run IoT simulator**:
   ```bash
   python3 iot_simulator.py
   ```

### Data Pipeline Testing

```bash
# Test data flow
./scripts/test_pipeline.sh

# Validate data quality
./scripts/validate_data_quality.sh

# Performance testing
./scripts/performance_test.sh
```

## Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy IoT Pipeline
on:
  push:
    branches: [main]
    paths: ['gcp/real-time-iot-data-processing-iot-core-dataprep/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: google-github-actions/setup-gcloud@v1
      - name: Deploy Infrastructure
        run: |
          cd gcp/real-time-iot-data-processing-iot-core-dataprep/code
          ./scripts/deploy.sh
```

## Support and Documentation

- **Original Recipe**: [Real-Time IoT Data Processing Recipe](../real-time-iot-data-processing-iot-core-dataprep.md)
- **Google Cloud IoT Core**: [Documentation](https://cloud.google.com/iot-core/docs)
- **Cloud Dataprep**: [Documentation](https://cloud.google.com/dataprep/docs)
- **BigQuery**: [Documentation](https://cloud.google.com/bigquery/docs)
- **Cloud Pub/Sub**: [Documentation](https://cloud.google.com/pubsub/docs)

## Contributing

When modifying the infrastructure code:

1. Test changes in a development environment
2. Update documentation accordingly
3. Validate all IaC implementations work correctly
4. Follow Google Cloud security best practices
5. Update cost estimates if resource usage changes

## License

This infrastructure code is provided under the same license as the parent recipe repository.