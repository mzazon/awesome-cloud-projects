# Infrastructure as Code for Smart City Infrastructure Monitoring with IoT and AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart City Infrastructure Monitoring with IoT and AI".

## Solution Overview

This solution demonstrates a modern smart city infrastructure monitoring system using Google Cloud Platform services. The architecture leverages Pub/Sub for scalable IoT data ingestion, Vertex AI for machine learning-powered anomaly detection, BigQuery for analytics at scale, and Cloud Monitoring for comprehensive observability. This enables cities to transition from reactive to predictive infrastructure management using current Google Cloud best practices.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following Google Cloud services:

- **Pub/Sub**: Topics and subscriptions for scalable IoT message streaming
- **BigQuery**: Data warehouse with optimized tables for sensor analytics
- **Cloud Functions**: Serverless data processing with validation and enrichment
- **Vertex AI**: Machine learning platform for anomaly detection
- **Cloud Storage**: Object storage for ML artifacts and data lifecycle management
- **Cloud Monitoring**: Dashboards, alerts, and custom metrics
- **IAM**: Service accounts and security policies for IoT device authentication

## Prerequisites

- Google Cloud account with billing enabled and project owner permissions
- Google Cloud CLI installed and configured (or Cloud Shell access)
- Terraform installed (version >= 1.0) - for Terraform deployment
- Appropriate permissions for resource creation:
  - `roles/owner` or equivalent service-level permissions
  - `roles/iam.serviceAccountAdmin`
  - `roles/pubsub.admin`
  - `roles/bigquery.admin`
  - `roles/aiplatform.admin`
  - `roles/storage.admin`
  - `roles/monitoring.admin`
  - `roles/cloudfunctions.admin`

## Cost Considerations

Estimated daily costs for active monitoring:
- Pub/Sub messages: $2-5 per day (based on sensor volume)
- BigQuery storage and queries: $3-8 per day
- Cloud Functions executions: $1-3 per day
- Vertex AI training/inference: $5-10 per day
- Cloud Storage: $1-2 per day
- Total estimated: $15-25 per day

> **Note**: Costs will vary based on sensor data volume, ML training frequency, and query patterns.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native IaC platform that provides state management and deployment orchestration.

```bash
# Set up environment variables
export PROJECT_ID="your-smart-city-project"
export REGION="us-central1"
export DEPLOYMENT_NAME="smart-city-monitoring"

# Authenticate with Google Cloud
gcloud auth login
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/terraform.tfvars"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Set up environment variables
export TF_VAR_project_id="your-smart-city-project"
export TF_VAR_region="us-central1"
export TF_VAR_zone="us-central1-a"

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

The bash scripts provide a step-by-step deployment that closely follows the original recipe instructions.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-smart-city-project"
export REGION="us-central1"

# Run deployment script
./scripts/deploy.sh

# The script will:
# 1. Enable required Google Cloud APIs
# 2. Create service accounts and IAM bindings
# 3. Set up Pub/Sub topics and subscriptions
# 4. Create BigQuery datasets and tables
# 5. Deploy Cloud Functions for data processing
# 6. Configure Cloud Storage with lifecycle policies
# 7. Set up Vertex AI resources
# 8. Create Cloud Monitoring dashboards and alerts
```

## Configuration Options

### Terraform Variables

Key variables you can customize in `terraform/terraform.tfvars`:

```hcl
# Project and region settings
project_id = "your-smart-city-project"
region     = "us-central1"
zone       = "us-central1-a"

# Resource naming
deployment_prefix = "smart-city"
dataset_name     = "smart_city_data"
topic_name       = "sensor-telemetry"

# BigQuery configuration
bq_location                = "us-central1"
bq_partition_expiration_ms = 7776000000  # 90 days
bq_clustering_fields       = ["sensor_type", "location"]

# Cloud Function settings
function_memory_mb    = 512
function_timeout_sec  = 120
function_max_instances = 100

# Storage lifecycle settings
storage_nearline_days = 30
storage_coldline_days = 90
storage_delete_days   = 365

# Monitoring configuration
alert_threshold_value = 0.85
alert_duration_sec    = 300
notification_channels = ["projects/PROJECT_ID/notificationChannels/CHANNEL_ID"]

# Security settings
enable_uniform_bucket_level_access = true
enable_bucket_versioning          = true
pubsub_message_retention_duration = "604800s"  # 7 days
```

### Infrastructure Manager Configuration

Modify `infrastructure-manager/terraform.tfvars` with your specific values:

```hcl
project_id = "your-smart-city-project"
region     = "us-central1"
zone       = "us-central1-a"

# Additional Infrastructure Manager specific settings
deployment_labels = {
  environment = "production"
  team        = "city-operations"
  purpose     = "iot-monitoring"
}
```

## Testing the Deployment

After deployment, verify the infrastructure is working correctly:

### 1. Test Pub/Sub Connectivity

```bash
# Publish a test sensor message
gcloud pubsub topics publish sensor-telemetry \
    --message='{
      "device_id": "test-sensor-001",
      "sensor_type": "temperature",
      "location": "City Hall",
      "value": 22.5,
      "unit": "celsius",
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"
    }' \
    --attribute="device_type=temperature_sensor,priority=normal"
```

### 2. Verify BigQuery Data Ingestion

```bash
# Query recent sensor data
bq query \
    --use_legacy_sql=false \
    --max_rows=10 \
    "SELECT 
       device_id, 
       sensor_type, 
       location, 
       timestamp, 
       value 
     FROM \`${PROJECT_ID}.smart_city_data.sensor_readings\` 
     ORDER BY timestamp DESC"
```

### 3. Check Cloud Function Logs

```bash
# View Cloud Function execution logs
gcloud functions logs read process-sensor-data \
    --limit=10 \
    --format="table(timestamp,textPayload)"
```

### 4. Validate Cloud Monitoring

```bash
# List created dashboards
gcloud monitoring dashboards list \
    --format="table(displayName,createTime)"

# Check alert policies
gcloud alpha monitoring policies list \
    --format="table(displayName,enabled)"
```

## Monitoring and Observability

The deployed infrastructure includes comprehensive monitoring:

### Dashboards

- **Smart City Infrastructure Monitoring**: Real-time sensor metrics and system health
- **Data Quality Dashboard**: Data validation metrics and processing statistics
- **ML Model Performance**: Anomaly detection accuracy and model drift metrics

### Alerts

- **High Anomaly Detection**: Triggers when anomaly scores exceed 0.85
- **Pub/Sub Message Backlog**: Alerts on message processing delays
- **Cloud Function Errors**: Notifications for data processing failures
- **BigQuery Query Performance**: Alerts for slow or expensive queries

### Custom Metrics

- `custom.googleapis.com/iot/sensor_messages_processed`: Message processing rate
- `custom.googleapis.com/iot/data_quality_score`: Data validation metrics
- `custom.googleapis.com/ml/anomaly_detection_latency`: ML inference performance

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will safely remove resources in the correct order:
# 1. Vertex AI resources and models
# 2. Cloud Functions and monitoring
# 3. Storage and BigQuery resources
# 4. Pub/Sub topics and subscriptions
# 5. IAM service accounts and bindings
```

## Security Best Practices

The infrastructure implements several security measures:

### IAM and Authentication

- **Service Account**: Dedicated service account for IoT devices with minimal permissions
- **Least Privilege**: Each component has only required permissions
- **Workload Identity**: Secure authentication for Cloud Functions and Vertex AI

### Data Protection

- **Encryption**: All data encrypted in transit and at rest
- **VPC Security**: Resources deployed in secure network configuration
- **Audit Logging**: Complete audit trail of all resource access

### Monitoring and Compliance

- **Security Monitoring**: Automated alerts for suspicious activities
- **Access Controls**: Regular review of IAM permissions
- **Data Retention**: Configurable data lifecycle policies

## Troubleshooting

### Common Issues

1. **Pub/Sub Permission Errors**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:*city-sensors*"
   ```

2. **BigQuery Data Not Appearing**
   ```bash
   # Check Cloud Function logs for errors
   gcloud functions logs read process-sensor-data \
       --filter="severity>=ERROR" \
       --limit=20
   ```

3. **Vertex AI Training Failures**
   ```bash
   # List recent AI Platform jobs
   gcloud ai custom-jobs list --region=${REGION} \
       --filter="state:FAILED" \
       --format="table(name,state,createTime)"
   ```

### Performance Optimization

- **Pub/Sub Scaling**: Adjust subscription settings for message volume
- **BigQuery Optimization**: Use partitioning and clustering for large datasets
- **Cloud Function Tuning**: Optimize memory and timeout settings
- **Storage Lifecycle**: Configure appropriate data tiering policies

## Extension Ideas

This infrastructure provides a foundation for additional smart city capabilities:

1. **Real-time Analytics**: Add Dataflow for stream processing
2. **Edge Computing**: Integrate IoT Edge devices for local processing
3. **Mobile Applications**: Add Firebase for citizen-facing apps
4. **External Integration**: Connect weather and traffic APIs
5. **Advanced ML**: Implement time-series forecasting for predictive maintenance

## Support and Documentation

- **Recipe Documentation**: See the parent directory for the complete recipe guide
- **Google Cloud Documentation**: [IoT Platform Product Architecture](https://cloud.google.com/architecture/connected-devices/iot-platform-product-architecture)
- **Terraform Google Provider**: [Registry Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Infrastructure Manager**: [Google Cloud Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

To modify or extend this infrastructure:

1. Update the appropriate IaC files (Terraform, Infrastructure Manager)
2. Test changes in a development environment
3. Update variable documentation
4. Verify security configurations
5. Update this README with any new features or requirements

---

**Note**: This infrastructure code deploys a production-ready smart city monitoring solution following Google Cloud best practices. Customize the configuration variables to match your specific requirements and scale the solution based on your city's sensor deployment size.