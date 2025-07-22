# Infrastructure as Code for Supply Chain Analytics with Cloud Bigtable and Cloud Dataproc

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Supply Chain Analytics with Cloud Bigtable and Cloud Dataproc".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Project with billing enabled and appropriate IAM permissions:
  - Bigtable Admin
  - Dataproc Admin
  - Pub/Sub Admin
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Storage Admin
  - Monitoring Admin
- Terraform (version >= 1.0) installed for Terraform deployment
- Basic understanding of supply chain analytics and IoT data processing
- Estimated cost: $50-100 for resources created during deployment

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution that provides native integration with Google Cloud services.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="supply-chain-analytics"

# Deploy infrastructure using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with state tracking and plan preview capabilities.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Preview changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct control over resource creation and are ideal for learning and customization.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy all resources
./scripts/deploy.sh

# Generate and publish test data (optional)
./scripts/test_pipeline.sh

# View deployment status
./scripts/status.sh
```

## Architecture Overview

This infrastructure deploys a comprehensive supply chain analytics platform consisting of:

- **Cloud Bigtable**: High-performance NoSQL database for real-time IoT sensor data
- **Cloud Dataproc**: Managed Apache Spark clusters for batch analytics and ML processing
- **Cloud Pub/Sub**: Message queue for ingesting sensor data from IoT devices
- **Cloud Functions**: Serverless data processing for real-time data transformation
- **Cloud Scheduler**: Automated job orchestration for regular analytics workflows
- **Cloud Storage**: Data lake storage for analytics results and job artifacts
- **Cloud Monitoring**: Observability and alerting for the analytics platform

## Configuration Options

### Common Variables

All implementations support these configuration options:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `zone` | Primary zone for compute resources | `us-central1-a` | No |
| `bigtable_node_count` | Number of Bigtable nodes | `3` | No |
| `dataproc_worker_count` | Number of Dataproc workers | `3` | No |
| `enable_preemptible` | Use preemptible instances | `true` | No |
| `scheduler_frequency` | Analytics job frequency (cron) | `0 */6 * * *` | No |

### Infrastructure Manager Variables

Located in `infrastructure-manager/main.yaml`:

```yaml
input:
  project_id:
    type: string
    description: "Google Cloud Project ID"
  region:
    type: string
    default: "us-central1"
    description: "Primary region for resources"
  bigtable_instance_type:
    type: string
    default: "PRODUCTION"
    description: "Bigtable instance type (PRODUCTION or DEVELOPMENT)"
```

### Terraform Variables

Located in `terraform/variables.tf`. Create `terraform.tfvars` to override defaults:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
bigtable_node_count    = 5
dataproc_worker_count  = 4
enable_preemptible     = false
```

### Bash Script Variables

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export BIGTABLE_NODE_COUNT="3"
export DATAPROC_WORKER_COUNT="3"
```

## Post-Deployment Validation

### Verify Infrastructure

Check that all resources are properly deployed:

```bash
# Verify Bigtable instance
gcloud bigtable instances list --project=${PROJECT_ID}

# Check Dataproc cluster status
gcloud dataproc clusters list --region=${REGION}

# Validate Cloud Functions
gcloud functions list --region=${REGION}

# Confirm Pub/Sub topics
gcloud pubsub topics list

# Check scheduled jobs
gcloud scheduler jobs list --location=${REGION}
```

### Test Data Pipeline

```bash
# Generate sample sensor data
cd scripts/
./generate_test_data.sh

# Verify data ingestion
gcloud bigtable instances tables show sensor_data \
    --instance=supply-chain-bt-$(date +%s) \
    --project=${PROJECT_ID}

# Run analytics job manually
gcloud dataproc jobs submit pyspark \
    --cluster=supply-analytics-cluster \
    --region=${REGION} \
    gs://your-bucket/jobs/supply_chain_analytics.py
```

### Monitor System Health

```bash
# View monitoring dashboard
echo "Visit: https://console.cloud.google.com/monitoring/dashboards"

# Check alerting policies
gcloud alpha monitoring policies list

# Review function logs
gcloud functions logs read process-sensor-data --region=${REGION}
```

## Cost Optimization

### Development Environment

For development and testing, use smaller resource configurations:

```bash
# Terraform
bigtable_node_count    = 1
dataproc_worker_count  = 2
enable_preemptible     = true

# Or set environment variables for bash scripts
export BIGTABLE_NODE_COUNT="1"
export DATAPROC_WORKER_COUNT="2"
export ENABLE_PREEMPTIBLE="true"
```

### Production Environment

For production workloads, consider:

- Multi-region Bigtable replication for disaster recovery
- Larger Dataproc clusters with autoscaling
- Enhanced monitoring and alerting configurations
- Network security hardening

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**:
   ```bash
   # Grant required roles to your user account
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/editor"
   ```

2. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable bigtable.googleapis.com dataproc.googleapis.com \
       pubsub.googleapis.com cloudfunctions.googleapis.com \
       cloudscheduler.googleapis.com monitoring.googleapis.com
   ```

3. **Resource Quota Exceeded**:
   - Check quota limits in Google Cloud Console
   - Request quota increases if needed
   - Use smaller resource configurations

4. **Terraform State Issues**:
   ```bash
   # Refresh Terraform state
   terraform refresh
   
   # Import existing resources if needed
   terraform import google_bigtable_instance.main projects/${PROJECT_ID}/instances/instance-id
   ```

### Logs and Debugging

```bash
# View Cloud Function logs
gcloud functions logs read process-sensor-data --region=${REGION} --limit=50

# Check Dataproc job logs
gcloud dataproc jobs list --region=${REGION}
gcloud dataproc jobs describe JOB_ID --region=${REGION}

# Monitor Bigtable metrics
gcloud monitoring timeseries list \
    --filter='resource.type="bigtable_table"' \
    --interval.end-time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --delete-policy=DELETE

# Verify resources are deleted
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Preview what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Clean up local state
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
./scripts/verify_cleanup.sh

# Clean up environment variables
unset PROJECT_ID REGION ZONE BIGTABLE_NODE_COUNT DATAPROC_WORKER_COUNT
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud bigtable instances list --project=${PROJECT_ID}
gcloud dataproc clusters list --region=${REGION}
gcloud functions list --region=${REGION}
gcloud pubsub topics list
gcloud scheduler jobs list --location=${REGION}
gsutil ls gs://supply-chain-data-*
```

## Security Considerations

### IAM Best Practices

- Use service accounts with minimal required permissions
- Enable audit logging for all resource access
- Implement VPC firewall rules for network security
- Use Cloud KMS for encryption key management

### Data Protection

- Enable encryption at rest for all storage services
- Use VPC Service Controls for additional network security
- Implement data classification and access controls
- Regular security assessments and compliance checks

## Performance Tuning

### Bigtable Optimization

- Design row keys for optimal query patterns
- Monitor hotspotting and adjust key design if needed
- Use column family garbage collection policies
- Scale nodes based on throughput requirements

### Dataproc Optimization

- Use appropriate machine types for workloads
- Enable autoscaling for variable workloads
- Optimize Spark configurations for data processing
- Use preemptible instances for cost efficiency

## Support and Documentation

- [Original Recipe Documentation](../supply-chain-analytics-bigtable-dataproc.md)
- [Google Cloud Bigtable Documentation](https://cloud.google.com/bigtable/docs)
- [Cloud Dataproc Documentation](https://cloud.google.com/dataproc/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.