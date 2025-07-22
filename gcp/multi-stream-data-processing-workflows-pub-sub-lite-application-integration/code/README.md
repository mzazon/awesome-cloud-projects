# Infrastructure as Code for Multi-Stream Data Processing Workflows with Pub/Sub Lite and Application Integration

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Stream Data Processing Workflows with Pub/Sub Lite and Application Integration".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Pub/Sub Lite Editor
  - Application Integration Admin
  - BigQuery Data Editor
  - Cloud Storage Admin
  - Dataflow Admin
  - Monitoring Admin
  - Service Account Admin
- Python 3.7+ (for testing scripts)
- Terraform 1.0+ (if using Terraform implementation)

## Architecture Overview

This solution deploys:
- **Pub/Sub Lite Topics**: 3 partition-based topics for IoT data, application events, and system logs
- **Pub/Sub Lite Subscriptions**: Multiple subscriptions for real-time analytics and workflow orchestration
- **BigQuery Dataset**: Partitioned and clustered tables for analytical workloads
- **Cloud Storage Bucket**: Data lake storage for raw and processed data
- **Application Integration**: Workflow orchestration and business logic automation
- **Cloud Dataflow**: Stream processing pipelines with automatic scaling
- **Cloud Monitoring**: Dashboards and alerting for pipeline observability

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable required APIs
gcloud services enable clouddeploy.googleapis.com
gcloud services enable config.googleapis.com

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-stream-data-processing \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/inputs.yaml"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts to configure project settings
```

## Configuration Options

### Environment Variables

Set these variables before deployment:

```bash
# Required
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"                    # GCP region
export ZONE="us-central1-a"                    # GCP zone

# Optional - will be generated if not set
export LITE_TOPIC_1="iot-data-stream-abc123"
export LITE_TOPIC_2="app-events-stream-abc123"
export LITE_TOPIC_3="system-logs-stream-abc123"
export DATASET_NAME="streaming_analytics_abc123"
export BUCKET_NAME="data-lake-yourproject-abc123"
```

### Terraform Variables

Key variables in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "pubsub_lite_partitions" {
  description = "Number of partitions for Pub/Sub Lite topics"
  type        = map(number)
  default = {
    iot_data    = 4
    app_events  = 2
    system_logs = 3
  }
}

variable "bigquery_partition_expiration_days" {
  description = "Partition expiration for BigQuery tables"
  type        = number
  default     = 365
}
```

### Infrastructure Manager Inputs

Configure in `infrastructure-manager/inputs.yaml`:

```yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
pubsub_lite_config:
  iot_data:
    partitions: 4
    publish_throughput: 4
    subscribe_throughput: 8
  app_events:
    partitions: 2
    publish_throughput: 2
    subscribe_throughput: 4
  system_logs:
    partitions: 3
    publish_throughput: 3
    subscribe_throughput: 6
```

## Deployment Process

### Phase 1: Core Infrastructure
1. Enable required Google Cloud APIs
2. Create service accounts with appropriate IAM roles
3. Deploy Pub/Sub Lite topics and subscriptions
4. Create BigQuery dataset and tables
5. Set up Cloud Storage bucket

### Phase 2: Processing Pipeline
1. Deploy Application Integration workflows
2. Launch Cloud Dataflow stream processing jobs
3. Configure monitoring dashboards and alerts

### Phase 3: Validation
1. Run data generation scripts
2. Verify end-to-end data flow
3. Test monitoring and alerting

## Cost Estimation

Expected monthly costs (varies by usage):

| Service | Configuration | Estimated Cost |
|---------|---------------|----------------|
| Pub/Sub Lite | 3 topics, 9 partitions total | $50-100 |
| Cloud Dataflow | 2-4 n1-standard-2 workers | $200-400 |
| BigQuery | 1GB-10GB processed daily | $20-200 |
| Cloud Storage | 100GB-1TB data | $2-20 |
| Application Integration | 10K-100K executions | $10-100 |
| **Total** | | **$282-820/month** |

> **Cost Optimization Tips**: 
> - Use Pub/Sub Lite's reserved capacity for predictable pricing
> - Configure BigQuery partition expiration to control storage costs
> - Monitor Dataflow autoscaling to optimize compute usage
> - Use Cloud Storage lifecycle policies for data archival

## Testing the Deployment

### 1. Verify Infrastructure

```bash
# Check Pub/Sub Lite topics
gcloud pubsub lite-topics list --location=${REGION}

# Verify BigQuery dataset
bq ls ${PROJECT_ID}:

# Check Cloud Storage bucket
gsutil ls -p ${PROJECT_ID}
```

### 2. Test Data Flow

```bash
# Run the included test script
python3 scripts/test-data-flow.py

# Check BigQuery for data
bq query --use_legacy_sql=false \
"SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET_NAME}.iot_sensor_data\`"
```

### 3. Monitor Performance

```bash
# View Dataflow jobs
gcloud dataflow jobs list --region=${REGION}

# Check monitoring dashboards
gcloud monitoring dashboards list
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable missing APIs
   gcloud services enable pubsublite.googleapis.com
   gcloud services enable integrations.googleapis.com
   ```

2. **Permission Denied**
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Pub/Sub Lite Quota Exceeded**
   ```bash
   # Check quota usage
   gcloud pubsub lite-topics describe ${LITE_TOPIC_1} --location=${REGION}
   ```

4. **Dataflow Job Failures**
   ```bash
   # Check job logs
   gcloud dataflow jobs show ${JOB_ID} --region=${REGION}
   ```

### Debug Mode

Enable debug logging in scripts:

```bash
export DEBUG=true
./scripts/deploy.sh
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-stream-data-processing
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud pubsub lite-topics list --location=${REGION}
bq ls ${PROJECT_ID}:
gsutil ls -p ${PROJECT_ID}
gcloud dataflow jobs list --region=${REGION}
```

## Customization

### Scaling Configuration

Modify partition counts and throughput capacity:

```hcl
# In terraform/variables.tf
variable "pubsub_lite_partitions" {
  default = {
    iot_data    = 8  # Increased for higher throughput
    app_events  = 4
    system_logs = 6
  }
}
```

### Adding New Data Sources

1. Create additional Pub/Sub Lite topics in IaC
2. Add corresponding BigQuery tables
3. Update Dataflow pipeline configuration
4. Modify Application Integration workflows

### Security Enhancements

- Enable Customer-Managed Encryption Keys (CMEK)
- Implement VPC Service Controls
- Add Cloud Armor protection
- Enable audit logging

## Monitoring and Alerting

### Default Dashboards

The deployment creates monitoring dashboards for:
- Pub/Sub Lite message rates and partition utilization
- Dataflow job performance and worker scaling
- BigQuery job execution and slot usage
- Application Integration workflow execution

### Custom Metrics

Add custom metrics by modifying the monitoring configuration:

```yaml
# In infrastructure-manager/monitoring.yaml
custom_metrics:
  - name: "data_quality_score"
    description: "Data quality assessment score"
    type: "GAUGE"
```

### Alert Policies

Configure alerts for:
- High message backlog in Pub/Sub Lite
- Dataflow job failures or high latency
- BigQuery slot usage approaching quota
- Application Integration workflow errors

## Best Practices

1. **Resource Naming**: Use consistent naming conventions with environment prefixes
2. **Tagging**: Apply comprehensive labels for cost tracking and resource management
3. **Security**: Follow principle of least privilege for service accounts
4. **Monitoring**: Set up comprehensive alerting before production deployment
5. **Testing**: Validate data flow and quality before processing production data
6. **Documentation**: Maintain up-to-date documentation for operational procedures

## Support

For issues with this infrastructure code:
1. Check the [original recipe documentation](../multi-stream-data-processing-workflows-pub-sub-lite-application-integration.md)
2. Refer to [Google Cloud Pub/Sub Lite documentation](https://cloud.google.com/pubsub/lite/docs)
3. Review [Application Integration best practices](https://cloud.google.com/application-integration/docs/best-practices)
4. Consult [Cloud Dataflow troubleshooting guide](https://cloud.google.com/dataflow/docs/guides/troubleshooting-your-pipeline)

## Contributing

When modifying this infrastructure:
1. Update variable descriptions and defaults
2. Add new resources to appropriate modules
3. Update this README with new configuration options
4. Test changes in a development environment first
5. Update cost estimates for new resources

## Version History

- **v1.0**: Initial implementation with basic streaming pipeline
- **v1.1**: Added Application Integration workflows
- **v1.2**: Enhanced monitoring and alerting
- **v1.3**: Added security hardening and cost optimization