# Infrastructure as Code for Digital Twin Manufacturing Resilience with IoT and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Digital Twin Manufacturing Resilience with IoT and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Pub/Sub Admin
  - BigQuery Admin
  - Storage Admin
  - Cloud Functions Admin
  - Vertex AI Admin
  - Dataflow Admin
  - Monitoring Admin
- For Terraform: Terraform CLI version 1.0+ installed
- For Infrastructure Manager: `gcloud` CLI with Infrastructure Manager APIs enabled

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/digital-twin-manufacturing \
    --service-account=YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --git-source-repo=https://source.developers.google.com/YOUR_PROJECT_ID/YOUR_REPO \
    --git-source-directory=infrastructure-manager/ \
    --git-source-ref=main \
    --input-values=project_id=YOUR_PROJECT_ID,region=us-central1

# Monitor deployment status
gcloud infra-manager deployments describe \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/digital-twin-manufacturing
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and resource URLs
```

## Configuration Variables

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud region for resources | `us-central1` | No |
| `dataset_name` | BigQuery dataset name | `manufacturing_data` | No |
| `bucket_suffix` | Suffix for Cloud Storage bucket | random 6-char string | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud region for resources | `us-central1` | No |
| `zone` | Google Cloud zone for resources | `us-central1-a` | No |
| `dataset_name` | BigQuery dataset name | `manufacturing_data` | No |
| `function_memory` | Cloud Function memory allocation | `256` | No |
| `function_timeout` | Cloud Function timeout in seconds | `60` | No |

### Bash Script Variables

Set these environment variables before running the deployment script:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export DATASET_NAME="manufacturing_data"
```

## Architecture Overview

The infrastructure deploys the following Google Cloud services:

- **Pub/Sub**: Three topics for sensor data, failure simulation events, and recovery commands
- **BigQuery**: Data warehouse with tables for sensor data, simulation results, and equipment metadata
- **Cloud Storage**: Bucket for ML model artifacts, training data, and pipeline storage
- **Cloud Functions**: Serverless digital twin simulation engine
- **Vertex AI**: Machine learning dataset for failure prediction models
- **Cloud Monitoring**: Dashboard for operational visibility

## Cost Estimation

Estimated monthly costs for moderate usage:

- Pub/Sub: $10-20 (for 1M messages/month)
- BigQuery: $20-50 (for 100GB storage + queries)
- Cloud Storage: $5-15 (for 50GB data)
- Cloud Functions: $10-30 (for 100K invocations)
- Vertex AI: $50-100 (for dataset management and model training)
- Cloud Monitoring: $5-10 (for custom dashboards and metrics)

**Total: $100-225/month**

> **Note**: Actual costs depend on data volume, query frequency, and ML model training frequency.

## Validation & Testing

After deployment, validate the infrastructure:

### Test Pub/Sub Message Flow

```bash
# Publish test message
gcloud pubsub topics publish manufacturing-sensor-data \
    --message='{"equipment_id":"test_pump","sensor_type":"temperature","value":75.5,"unit":"celsius","timestamp":"2025-07-23T10:00:00Z"}'

# Verify subscription receives messages
gcloud pubsub subscriptions pull sensor-data-processing \
    --limit=1 --format="value(message.data)" | base64 -d
```

### Test Digital Twin Simulation

```bash
# Get Cloud Function URL
FUNCTION_URL=$(gcloud functions describe digital-twin-simulator \
    --region=us-central1 \
    --format="value(httpsTrigger.url)")

# Trigger simulation
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"equipment_id":"pump_001","failure_type":"temperature_spike","duration_hours":2}'
```

### Verify BigQuery Setup

```bash
# List tables in dataset
bq ls manufacturing_data

# Run test query
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as table_count FROM \`${PROJECT_ID}.manufacturing_data.__TABLES__\`"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/digital-twin-manufacturing

# Verify deletion
gcloud infra-manager deployments list \
    --location=us-central1
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable pubsub.googleapis.com
   gcloud services enable bigquery.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current user permissions
   gcloud auth list
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   ```

3. **Cloud Function Deployment Failures**
   ```bash
   # Check function logs
   gcloud functions logs read digital-twin-simulator --region=us-central1
   ```

4. **BigQuery Access Issues**
   ```bash
   # Verify dataset existence and permissions
   bq show manufacturing_data
   ```

### Resource Naming Conflicts

If you encounter naming conflicts, modify the resource names in the configuration files:

- For Terraform: Update `variables.tf` default values
- For Infrastructure Manager: Update the variable values in your deployment command
- For Bash scripts: Modify the environment variables

## Security Considerations

The infrastructure implements several security best practices:

- **IAM**: Least privilege access for service accounts
- **Network Security**: Private IP addresses where applicable
- **Data Encryption**: Encryption at rest and in transit for all data services
- **Access Logging**: Cloud Audit Logs enabled for compliance tracking
- **Secret Management**: Uses Cloud Functions environment variables for sensitive data

## Monitoring and Observability

The deployment includes:

- **Cloud Monitoring Dashboard**: Pre-configured dashboard for digital twin operations
- **Custom Metrics**: Application-specific metrics for simulation performance
- **Alerting**: Configurable alerts for system health and performance
- **Logging**: Centralized logging for all components

## Extending the Solution

To extend this infrastructure for production use:

1. **Multi-Region Deployment**: Deploy across multiple regions for high availability
2. **Advanced Security**: Implement VPC Service Controls and private endpoints
3. **CI/CD Integration**: Add Cloud Build pipelines for automated deployments
4. **Advanced Monitoring**: Implement SLO-based alerting and incident response
5. **Data Governance**: Add data lineage tracking and compliance monitoring

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for each service
3. Validate IAM permissions and API enablement
4. Review Cloud Logging for detailed error messages

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to Google Cloud pricing and terms of service for production usage.