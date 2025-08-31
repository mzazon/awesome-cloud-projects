# Digital Twin Manufacturing Resilience - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive digital twin system for manufacturing resilience on Google Cloud Platform. The infrastructure enables real-time IoT data ingestion, failure scenario simulation, and recovery testing without disrupting production operations.

## Architecture Overview

The infrastructure deploys the following Google Cloud Platform services:

- **Pub/Sub**: Message queuing for IoT sensor data, failure simulation events, and recovery commands
- **BigQuery**: Data warehouse for manufacturing telemetry, simulation results, and equipment metadata
- **Cloud Storage**: Object storage for ML model artifacts, training data, and pipeline assets
- **Vertex AI**: Machine learning platform for failure prediction models and datasets
- **Cloud Functions**: Serverless compute for digital twin simulation engine
- **Cloud Monitoring**: Observability and alerting for system health and performance
- **IAM**: Security and access control with custom roles and service accounts

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Platform Account**:
   - Active GCP project with billing enabled
   - Owner or Editor permissions on the project

2. **Local Development Environment**:
   - [Terraform](https://www.terraform.io/downloads.html) >= 1.0 installed
   - [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated
   - Git for version control

3. **Authentication Setup**:
   ```bash
   # Authenticate with Google Cloud
   gcloud auth login
   gcloud auth application-default login
   
   # Set your default project
   gcloud config set project YOUR_PROJECT_ID
   ```

4. **Required APIs** (automatically enabled by Terraform):
   - Pub/Sub API
   - BigQuery API
   - Cloud Storage API
   - Vertex AI API
   - Cloud Functions API
   - Cloud Monitoring API
   - Cloud Build API
   - Eventarc API

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the terraform directory
cd gcp/digital-twin-manufacturing-resilience-iot-vertex/code/terraform
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customization
environment     = "dev"
dataset_name    = "manufacturing_data"

# Resource configuration
cloud_function_memory  = 256
cloud_function_timeout = 60

# Storage configuration
storage_bucket_class = "STANDARD"
bigquery_location   = "US"

# Labels for resource organization
labels = {
  project     = "digital-twin-manufacturing"
  environment = "dev"
  team        = "your-team-name"
  managed-by  = "terraform"
}
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

After deployment, verify the infrastructure using the testing commands from outputs:

```bash
# Test Pub/Sub message publishing
terraform output -raw testing_commands | jq -r .test_pubsub | bash

# Test Cloud Function
terraform output -raw testing_commands | jq -r .test_function | bash

# Test BigQuery
terraform output -raw testing_commands | jq -r .test_bigquery | bash

# Test Vertex AI
terraform output -raw testing_commands | jq -r .test_vertex_ai | bash
```

## Configuration Options

### Variable Reference

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | GCP project ID | `string` | - | ✅ |
| `region` | GCP region for resources | `string` | `us-central1` | ❌ |
| `environment` | Environment name | `string` | `dev` | ❌ |
| `dataset_name` | BigQuery dataset name | `string` | `manufacturing_data` | ❌ |
| `cloud_function_memory` | Function memory (MB) | `number` | `256` | ❌ |
| `cloud_function_timeout` | Function timeout (seconds) | `number` | `60` | ❌ |
| `enable_apis` | Enable required APIs | `bool` | `true` | ❌ |
| `monitoring_dashboard_enabled` | Create monitoring dashboard | `bool` | `true` | ❌ |

### Environment-Specific Configurations

#### Development Environment
```hcl
environment = "dev"
cloud_function_memory = 256
bigquery_table_expiration_ms = 7776000000  # 90 days
storage_lifecycle_rules = {
  enabled = true
  action = {
    type = "SetStorageClass"
    storage_class = "NEARLINE"
  }
  condition = {
    age = 30
  }
}
```

#### Production Environment
```hcl
environment = "prod"
cloud_function_memory = 512
bigquery_table_expiration_ms = null  # No expiration
storage_lifecycle_rules = {
  enabled = true
  action = {
    type = "SetStorageClass"
    storage_class = "COLDLINE"
  }
  condition = {
    age = 90
  }
}
```

## Testing and Validation

### Integration Testing

The infrastructure includes comprehensive testing commands accessible via Terraform outputs:

```bash
# Get all testing commands
terraform output testing_commands

# Test individual components
terraform output -raw testing_commands | jq -r .test_pubsub
terraform output -raw testing_commands | jq -r .test_function
terraform output -raw testing_commands | jq -r .test_bigquery
terraform output -raw testing_commands | jq -r .test_vertex_ai
```

### Manual Testing Scenarios

1. **Sensor Data Simulation**:
   ```bash
   # Publish sample sensor data
   gcloud pubsub topics publish manufacturing-sensor-data \
     --message='{"equipment_id":"pump_001","sensor_type":"temperature","value":85.4,"unit":"celsius","timestamp":"2025-01-25T10:00:00Z"}'
   ```

2. **Failure Scenario Testing**:
   ```bash
   # Trigger failure simulation
   FUNCTION_URL=$(terraform output -raw cloud_function | jq -r .url)
   curl -X POST $FUNCTION_URL \
     -H "Content-Type: application/json" \
     -d '{"equipment_id":"pump_001","failure_type":"temperature_spike","duration_hours":4}'
   ```

3. **Data Analytics Validation**:
   ```bash
   # Query aggregated sensor data
   bq query --use_legacy_sql=false \
     "SELECT equipment_id, sensor_type, AVG(value) as avg_value 
      FROM \`$(terraform output -raw project_id).manufacturing_data.sensor_data\` 
      WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      GROUP BY equipment_id, sensor_type"
   ```

## Monitoring and Observability

### Cloud Monitoring Dashboard

The deployment creates a comprehensive monitoring dashboard tracking:

- Sensor data ingestion rates
- Cloud Function execution metrics
- BigQuery data processing performance
- System error rates and latency

Access the dashboard:
```bash
# Get dashboard information
terraform output monitoring_dashboard

# Open in browser
echo "https://console.cloud.google.com/monitoring/dashboards/custom/$(terraform output -raw monitoring_dashboard | jq -r .dashboard_id)"
```

### Alert Policies

The infrastructure includes pre-configured alert policies for:

- High error rates in Cloud Functions
- Pub/Sub message processing delays
- BigQuery job failures
- Storage access anomalies

### Log Analysis

Monitor system logs using Cloud Logging:

```bash
# View Cloud Function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=digital-twin-simulator" --limit=50

# View Pub/Sub logs
gcloud logging read "resource.type=pubsub_topic" --limit=50

# View BigQuery logs
gcloud logging read "resource.type=bigquery_dataset" --limit=50
```

## Security Considerations

### IAM and Access Control

The infrastructure implements security best practices:

1. **Service Accounts**: Dedicated service accounts with minimal required permissions
2. **Custom IAM Roles**: Purpose-built roles for digital twin operations
3. **Least Privilege**: Fine-grained permissions for each service component
4. **Uniform Bucket Access**: Consistent access control for Cloud Storage

### Data Protection

- **Encryption**: All data encrypted at rest and in transit
- **Network Security**: Private networking where possible
- **Access Logging**: Comprehensive audit trails for all data access
- **Data Retention**: Configurable retention policies for compliance

### Production Security Enhancements

For production deployments, consider:

1. **VPC Security**: Deploy within a custom VPC with firewall rules
2. **Private Endpoints**: Use private Google Access for services
3. **Secret Management**: Integrate with Secret Manager for sensitive data
4. **Certificate Management**: Use Cloud KMS for encryption key management

## Cost Optimization

### Resource Sizing

The infrastructure is optimized for cost efficiency:

- **Serverless Services**: Pay-per-use model for Cloud Functions and BigQuery
- **Storage Lifecycle**: Automated data archiving for long-term cost reduction
- **Right-sizing**: Conservative resource allocation with scaling options

### Cost Monitoring

Monitor costs using the provided outputs:

```bash
# View cost estimation
terraform output cost_estimation

# Set up budget alerts
gcloud billing budgets create \
  --billing-account=YOUR_BILLING_ACCOUNT \
  --display-name="Digital Twin Budget" \
  --budget-amount=100 \
  --threshold-rule=percent-90
```

### Optimization Recommendations

1. **Data Lifecycle**: Configure automatic data archiving after 30-90 days
2. **Function Optimization**: Right-size memory allocation based on actual usage
3. **Storage Classes**: Use appropriate storage classes for different data types
4. **Query Optimization**: Partition and cluster BigQuery tables for performance

## Troubleshooting

### Common Issues

1. **API Enablement Errors**:
   ```bash
   # Manually enable required APIs
   gcloud services enable pubsub.googleapis.com bigquery.googleapis.com
   ```

2. **Permission Errors**:
   ```bash
   # Verify current permissions
   gcloud projects get-iam-policy $(terraform output -raw project_id)
   ```

3. **Resource Conflicts**:
   ```bash
   # Check existing resources
   gcloud pubsub topics list
   gcloud storage buckets list
   ```

4. **Function Deployment Issues**:
   ```bash
   # Check function logs
   gcloud functions logs read digital-twin-simulator --region=$(terraform output -raw region)
   ```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Set Terraform debug mode
export TF_LOG=DEBUG

# Enable GCP API debugging
export GOOGLE_CLOUD_CPP_ENABLE_TRACING=1
```

## Maintenance and Updates

### Regular Maintenance Tasks

1. **Update Dependencies**: Keep Terraform providers and modules current
2. **Security Patches**: Apply security updates to Cloud Function dependencies
3. **Performance Review**: Monitor and optimize resource utilization
4. **Backup Verification**: Test data backup and recovery procedures

### Upgrade Process

1. **Plan Changes**: Always run `terraform plan` before applying updates
2. **Test in Development**: Validate changes in a development environment first
3. **Gradual Rollout**: Apply changes incrementally for production systems
4. **Rollback Plan**: Maintain the ability to revert changes if issues occur

## Cleanup and Destruction

To remove all deployed resources:

```bash
# Destroy all infrastructure
terraform destroy

# Verify cleanup
gcloud pubsub topics list
gcloud storage buckets list
bq ls
```

**Warning**: This will permanently delete all data and resources. Ensure you have backups if needed.

## Support and Documentation

### Additional Resources

- [Google Cloud Digital Twin Solutions](https://cloud.google.com/solutions/digital-twins)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/best-practices)
- [BigQuery Optimization Guide](https://cloud.google.com/bigquery/docs/best-practices-performance-overview)

### Getting Help

1. **Terraform Issues**: Check provider documentation and GitHub issues
2. **GCP Issues**: Use Google Cloud Support or Stack Overflow
3. **Integration Problems**: Review logs and monitoring data for insights
4. **Performance Issues**: Analyze metrics and consider resource scaling

For questions specific to this implementation, review the original recipe documentation and consider the architectural decisions documented in the code comments.