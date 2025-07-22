# Infrastructure as Code for Streamlining Smart City Data Processing with Cloud Dataprep and BigQuery DataCanvas

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Streamlining Smart City Data Processing with Cloud Dataprep and BigQuery DataCanvas".

## Solution Overview

This solution implements an automated smart city data processing pipeline using Google Cloud's visual data preparation and AI-enhanced analytics capabilities. The infrastructure handles real-time IoT sensor data from traffic monitoring systems, air quality sensors, and energy consumption meters, providing automated data quality management and intelligent dashboards for urban planning and operational decisions.

## Architecture Components

- **Cloud Storage**: Data lake for storing raw and processed sensor data
- **Pub/Sub**: Real-time messaging for IoT data ingestion
- **Dataflow**: Stream processing for data validation and transformation
- **Cloud Dataprep**: Visual data preparation with ML-powered suggestions
- **BigQuery**: Serverless data warehouse with materialized views
- **BigQuery DataCanvas**: AI-enhanced data exploration and visualization
- **Cloud Monitoring**: Comprehensive monitoring and alerting

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with error handling

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: Active project with billing enabled
2. **Required APIs**: The following APIs must be enabled:
   - Dataprep API (`dataprep.googleapis.com`)
   - BigQuery API (`bigquery.googleapis.com`)
   - Pub/Sub API (`pubsub.googleapis.com`)
   - Cloud Storage API (`storage.googleapis.com`)
   - Dataflow API (`dataflow.googleapis.com`)
   - Cloud Monitoring API (`monitoring.googleapis.com`)
   - Infrastructure Manager API (`config.googleapis.com`)
3. **Google Cloud CLI**: Installed and configured with appropriate permissions
4. **IAM Permissions**: Your account needs the following roles:
   - Project Editor or custom role with storage, pubsub, bigquery, dataflow permissions
   - Service Account Admin (for creating service accounts)
   - Infrastructure Manager Admin (for Infrastructure Manager deployments)
5. **Terraform** (if using Terraform): Version 1.0+ with Google Cloud provider
6. **Python Dependencies** (for sample data generation): `apache-beam[gcp]`

### Estimated Costs

- **Development/Testing**: $50-100 per full implementation cycle
- **Production**: Varies based on data volume and query frequency
- **Storage**: ~$0.02/GB/month for Cloud Storage
- **BigQuery**: $5/TB for queries, $0.02/GB/month for storage
- **Pub/Sub**: $0.60/million messages
- **Dataflow**: $0.056/vCPU/hour for streaming jobs

> **Note**: Costs can be optimized using BigQuery flat-rate pricing and Cloud Storage lifecycle policies included in the infrastructure.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Clone and navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="smart-city-data-processing"

# Create the deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infrastructure-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned infrastructure changes
terraform plan -var="project_id=your-gcp-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-gcp-project-id" -var="region=us-central1"

# View outputs including resource names and endpoints
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"

# Deploy the complete infrastructure
./scripts/deploy.sh

# The script will:
# 1. Validate prerequisites
# 2. Enable required APIs
# 3. Create all infrastructure components
# 4. Set up monitoring and alerting
# 5. Generate sample data for testing
```

## Configuration Options

### Infrastructure Manager

Edit `main.yaml` to customize:

- Project ID and region settings
- Resource naming conventions
- Storage bucket lifecycle policies
- BigQuery dataset configurations
- Monitoring alert thresholds

### Terraform

Edit `terraform.tfvars` or pass variables:

```bash
# Example custom configuration
terraform apply \
    -var="project_id=my-smart-city-project" \
    -var="region=europe-west1" \
    -var="storage_class=NEARLINE" \
    -var="bigquery_location=EU" \
    -var="enable_monitoring=true"
```

Available variables:
- `project_id`: Google Cloud project ID
- `region`: Primary deployment region
- `storage_class`: Default storage class for buckets
- `bigquery_location`: BigQuery dataset location
- `enable_monitoring`: Enable/disable monitoring resources
- `retention_days`: Data retention period for Pub/Sub topics

### Bash Scripts

Environment variables for customization:

```bash
export PROJECT_ID="your-project-id"          # Required
export REGION="us-central1"                  # Optional, defaults to us-central1
export STORAGE_CLASS="STANDARD"              # Optional, defaults to STANDARD  
export BIGQUERY_LOCATION="US"                # Optional, defaults to US
export MONITORING_ENABLED="true"             # Optional, defaults to true
export DATA_RETENTION_DAYS="7"               # Optional, defaults to 7 days
```

## Post-Deployment Setup

After infrastructure deployment, complete these additional configuration steps:

### 1. Configure Cloud Dataprep Flows

```bash
# Access Dataprep UI to create transformation flows
echo "Navigate to Cloud Dataprep UI: https://clouddataprep.com"
echo "Use the sample transformation specifications in the generated files"
```

### 2. Set Up BigQuery DataCanvas

```bash
# Enable DataCanvas features in BigQuery
echo "Navigate to BigQuery UI: https://console.cloud.google.com/bigquery"
echo "Access DataCanvas from the navigation menu"
```

### 3. Generate Sample Data (Optional)

```bash
# Run the sample data generator
cd scripts/
python3 generate_sample_data.py --project-id=${PROJECT_ID} --topic-prefix="smart-city"
```

### 4. Configure Monitoring Dashboards

```bash
# Import pre-configured monitoring dashboard
gcloud monitoring dashboards create --config-from-file=monitoring/dashboard-config.json
```

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check Cloud Storage buckets
gsutil ls -p ${PROJECT_ID}

# Verify Pub/Sub topics
gcloud pubsub topics list

# Check BigQuery datasets
bq ls --project_id=${PROJECT_ID}

# Test data flow
gcloud pubsub topics publish traffic-sensor-data \
    --message='{"sensor_id":"TEST001","timestamp":"2025-07-12T10:00:00Z","vehicle_count":125}'
```

### Run Integration Tests

```bash
# Execute comprehensive test suite
cd scripts/
./run_integration_tests.sh
```

Expected test results:
- ✅ All Pub/Sub topics accessible
- ✅ BigQuery tables created with correct schema
- ✅ Cloud Storage buckets configured with lifecycle policies
- ✅ Monitoring alerts responsive
- ✅ Sample data processing successful

## Monitoring & Operations

### Access Monitoring Dashboards

- **Cloud Monitoring**: https://console.cloud.google.com/monitoring
- **BigQuery Job History**: https://console.cloud.google.com/bigquery/jobs
- **Dataflow Jobs**: https://console.cloud.google.com/dataflow/jobs
- **Pub/Sub Metrics**: https://console.cloud.google.com/cloudpubsub

### Key Metrics to Monitor

- Data ingestion rate (messages/second)
- BigQuery query performance
- Storage costs and usage
- Data quality error rates
- Pipeline processing latency

### Troubleshooting Common Issues

1. **Pub/Sub Authentication Errors**:
   ```bash
   gcloud auth application-default login
   gcloud config set project ${PROJECT_ID}
   ```

2. **BigQuery Permission Issues**:
   ```bash
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:$(gcloud config get-value account)" \
       --role="roles/bigquery.admin"
   ```

3. **Dataflow Job Failures**:
   ```bash
   # Check Dataflow logs
   gcloud dataflow jobs list --region=${REGION}
   gcloud dataflow jobs show <JOB_ID> --region=${REGION}
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy -var="project_id=your-gcp-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Stop all running Dataflow jobs
# 2. Delete BigQuery datasets
# 3. Remove Pub/Sub topics and subscriptions  
# 4. Delete Cloud Storage buckets
# 5. Clean up monitoring resources
# 6. Remove service accounts
```

### Manual Cleanup Verification

```bash
# Verify complete cleanup
gsutil ls -p ${PROJECT_ID}                    # Should show no buckets
gcloud pubsub topics list                     # Should show no custom topics
bq ls --project_id=${PROJECT_ID}              # Should show no custom datasets
gcloud dataflow jobs list --region=${REGION}  # Should show no running jobs
```

## Security Considerations

This infrastructure implements several security best practices:

- **IAM Least Privilege**: Service accounts with minimal required permissions
- **Data Encryption**: Encryption at rest and in transit for all data
- **Network Security**: Private IP addresses where possible
- **Audit Logging**: Comprehensive logging for all operations
- **Access Controls**: Proper BigQuery dataset and Cloud Storage bucket permissions

### Additional Security Hardening

For production deployments, consider:

1. **VPC Service Controls**: Isolate resources within security perimeters
2. **Private Google Access**: Use private IP addresses for Compute Engine resources
3. **Customer-Managed Encryption**: Use your own encryption keys (CMEK)
4. **Binary Authorization**: Validate container images in deployment pipelines
5. **IAM Conditions**: Implement time-based and IP-based access restrictions

## Scaling and Performance

### Horizontal Scaling

- **Pub/Sub**: Automatically scales based on message volume
- **Dataflow**: Configure autoscaling parameters for variable workloads
- **BigQuery**: Serverless scaling handles query concurrency automatically
- **Cloud Storage**: Unlimited capacity with automatic load balancing

### Performance Optimization

```bash
# Configure BigQuery for optimal performance
bq update --max_rows_per_request=10000 ${PROJECT_ID}:${DATASET_NAME}

# Optimize Dataflow worker configuration
gcloud dataflow jobs run smart-city-processor \
    --gcs-location=gs://dataflow-templates/streaming/pubsub-to-bigquery \
    --max-workers=100 \
    --num-workers=10 \
    --worker-machine-type=n1-standard-4
```

## Cost Optimization

### Implemented Cost Controls

- **Storage Lifecycle Policies**: Automatic transition to cheaper storage classes
- **BigQuery Partitioning**: Date-partitioned tables for query efficiency
- **Pub/Sub Message Retention**: Configurable retention periods
- **Monitoring Alerts**: Cost threshold alerts to prevent unexpected charges

### Additional Cost Savings

```bash
# Set up BigQuery cost controls
bq mk --table --time_partitioning_field=timestamp \
    --time_partitioning_expiration=7776000 \
    ${PROJECT_ID}:${DATASET_NAME}.cost_optimized_table

# Configure committed use discounts for predictable workloads
gcloud compute commitments create smart-city-commitment \
    --region=${REGION} \
    --plan=12-month \
    --type=memory-optimized
```

## Integration with External Systems

### IoT Device Integration

```bash
# Configure IoT Core for device authentication
gcloud iot registries create smart-city-registry \
    --region=${REGION} \
    --pubsub-topic=projects/${PROJECT_ID}/topics/iot-telemetry

# Register device certificates
gcloud iot devices create traffic-sensor-001 \
    --registry=smart-city-registry \
    --region=${REGION}
```

### External Data Sources

The infrastructure supports integration with:

- Weather APIs for environmental correlation
- Traffic management systems via REST APIs
- Energy grid data through secure file transfers
- Social media feeds for event detection
- Emergency services for incident response

## Support and Documentation

### Resource Documentation

- [Google Cloud Dataprep Documentation](https://cloud.google.com/dataprep/docs)
- [BigQuery DataCanvas Guide](https://cloud.google.com/bigquery/docs/datacanvas)
- [Pub/Sub Best Practices](https://cloud.google.com/pubsub/docs/building-pubsub-messaging-system)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Smart Cities on Google Cloud](https://cloud.google.com/architecture/smart-cities)

### Getting Help

For issues with this infrastructure:

1. **Check the logs**: Use Cloud Logging to investigate errors
2. **Review the original recipe**: Refer to the step-by-step recipe documentation
3. **Google Cloud Support**: Use your support plan for Google Cloud issues
4. **Community Forums**: [Google Cloud Community](https://cloud.google.com/community)

### Contributing

To improve this infrastructure code:

1. Test changes in a development project
2. Update documentation for any modifications
3. Follow Google Cloud security and performance best practices
4. Validate all IaC syntax before submitting changes

---

> **Note**: This infrastructure code is generated from the original recipe and follows Google Cloud best practices. For the most current service features and pricing, always refer to the official Google Cloud documentation.