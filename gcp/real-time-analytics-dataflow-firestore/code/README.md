# Infrastructure as Code for Real-Time Analytics with Cloud Dataflow and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Analytics with Cloud Dataflow and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive real-time analytics platform using:

- **Cloud Pub/Sub**: Event ingestion and messaging
- **Cloud Dataflow**: Streaming data processing with Apache Beam
- **Cloud Firestore**: Real-time NoSQL database for analytics queries
- **Cloud Storage**: Data archival and lifecycle management
- **IAM Service Accounts**: Secure access management

## Prerequisites

- Google Cloud Project with billing enabled
- Google Cloud SDK (gcloud CLI) installed and authenticated
- Appropriate permissions for:
  - Compute Engine Admin
  - Dataflow Admin
  - Pub/Sub Admin
  - Cloud Datastore User
  - Storage Admin
  - Service Account Admin
  - App Engine Admin
- Terraform >= 1.5.0 (for Terraform deployment)
- Python 3.8+ and pip (for pipeline deployment)

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/analytics-deployment \
    --service-account projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/real-time-analytics-dataflow-firestore/code/infrastructure-manager" \
    --git-source-ref="main" \
    --input-values project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project-specific values

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"                    # GCP region for deployment
export ZONE="us-central1-a"                    # GCP zone for compute resources
export RANDOM_SUFFIX=$(openssl rand -hex 3)    # Unique suffix for resources
```

### Terraform Variables

Key variables that can be customized in `terraform.tfvars`:

- `project_id`: Your Google Cloud Project ID
- `region`: GCP region for resource deployment
- `zone`: GCP zone for compute resources
- `max_workers`: Maximum number of Dataflow workers (default: 10)
- `machine_type`: Machine type for Dataflow workers (default: n1-standard-2)
- `storage_location`: Storage bucket location (default: US)
- `firestore_location`: Firestore database location (default: us-central)

### Infrastructure Manager Variables

Customize deployment by modifying input values:

- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region
- `environment`: Environment name (dev, staging, prod)
- `labels`: Resource labels for organization and billing

## Deployment Details

### Resources Created

The infrastructure deployment creates:

1. **Pub/Sub Resources**:
   - Topic for event ingestion with 7-day retention
   - Subscription with exactly-once delivery
   - Dead letter topic for failed messages

2. **Cloud Storage**:
   - Multi-regional bucket for data archival
   - Lifecycle policies for automatic cost optimization
   - Versioning enabled for data protection

3. **Firestore Database**:
   - Native mode database for real-time queries
   - Composite indexes for analytics performance
   - Regional deployment for data locality

4. **IAM Configuration**:
   - Service account with least-privilege permissions
   - Custom roles for Dataflow pipeline operations
   - Security best practices implementation

5. **App Engine Application**:
   - Required foundation for Firestore Native mode
   - Regional deployment matching other resources

### Security Features

- Service accounts follow principle of least privilege
- Private IP addressing for Dataflow workers where possible
- Encryption at rest for all storage services
- VPC firewall rules for secure network access
- Cloud KMS integration for additional encryption (optional)

### Cost Optimization

- Pub/Sub message retention policies to control storage costs
- Cloud Storage lifecycle rules for automatic tier transitions
- Dataflow autoscaling to minimize compute costs during low traffic
- Preemptible instances option for cost-sensitive workloads

## Post-Deployment Steps

After infrastructure deployment, complete the solution setup:

### 1. Deploy the Dataflow Pipeline

```bash
# Install required Python packages
pip install apache-beam[gcp]==2.52.0 google-cloud-firestore google-cloud-storage

# Deploy streaming pipeline
python pipeline/streaming_analytics.py \
    --runner=DataflowRunner \
    --project=${PROJECT_ID} \
    --region=${REGION} \
    --temp_location=gs://analytics-archive-${RANDOM_SUFFIX}/temp \
    --staging_location=gs://analytics-archive-${RANDOM_SUFFIX}/staging \
    --job_name=streaming-analytics-${RANDOM_SUFFIX} \
    --subscription=projects/${PROJECT_ID}/subscriptions/events-subscription-${RANDOM_SUFFIX} \
    --bucket=analytics-archive-${RANDOM_SUFFIX} \
    --service_account_email=dataflow-analytics@${PROJECT_ID}.iam.gserviceaccount.com \
    --streaming
```

### 2. Generate Test Data

```bash
# Install Pub/Sub client library
pip install google-cloud-pubsub

# Generate sample events
python test/generate_events.py ${PROJECT_ID} events-topic-${RANDOM_SUFFIX} 100
```

### 3. Validate the Solution

```bash
# Check Dataflow job status
gcloud dataflow jobs list --filter="name:streaming-analytics" --format="table(name,state,createTime)"

# Query Firestore for processed data
python test/dashboard_queries.py ${PROJECT_ID}

# Verify Cloud Storage archives
gsutil ls -la gs://analytics-archive-${RANDOM_SUFFIX}/raw-events/
```

## Monitoring and Observability

### Cloud Monitoring Integration

The deployment includes monitoring configuration for:

- Dataflow pipeline metrics (throughput, latency, errors)
- Pub/Sub subscription metrics (backlog, delivery rate)
- Firestore operation metrics (reads, writes, storage)
- Cloud Storage access patterns and costs

### Logging Configuration

- Dataflow worker logs automatically sent to Cloud Logging
- Pub/Sub delivery logs for debugging message flow
- Firestore audit logs for security compliance
- Custom application logs from the streaming pipeline

### Alerting Policies

Consider setting up alerts for:

- Dataflow pipeline failures or high error rates
- Pub/Sub message backlog accumulation
- Firestore quota limit approaching
- Unusual cost increases in any service

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/analytics-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Steps

If automated cleanup doesn't complete successfully:

1. **Stop Dataflow Jobs**:
   ```bash
   gcloud dataflow jobs cancel streaming-analytics-${RANDOM_SUFFIX} --region=${REGION}
   ```

2. **Delete Firestore Data**:
   ```bash
   # Use Firestore console or batch delete operations
   # Note: Firestore database deletion requires manual action
   ```

3. **Remove App Engine Application**:
   ```bash
   # App Engine applications cannot be deleted, only disabled
   gcloud app versions stop --service=default --version=1
   ```

## Troubleshooting

### Common Issues

1. **Dataflow Pipeline Fails to Start**:
   - Verify service account permissions
   - Check that required APIs are enabled
   - Ensure temp/staging bucket accessibility

2. **Firestore Connection Errors**:
   - Verify App Engine application exists
   - Check Firestore database mode (Native vs Datastore)
   - Validate composite index creation

3. **High Costs**:
   - Review Dataflow worker allocation
   - Check Pub/Sub message retention settings
   - Verify Cloud Storage lifecycle policies

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Monitor resource usage
gcloud monitoring dashboards list

# View recent logs
gcloud logging read "resource.type=dataflow_job" --limit=50
```

## Customization

### Scaling Configuration

Modify these parameters for different workloads:

- **High Volume**: Increase `max_num_workers` and use `n1-highmem-2` instances
- **Cost Sensitive**: Enable preemptible instances and reduce worker counts
- **Low Latency**: Use faster machine types and shorter windowing intervals
- **Global Deployment**: Configure multi-region Pub/Sub and Firestore replication

### Security Enhancements

For production deployments, consider:

- VPC-native networking for Dataflow
- Customer-managed encryption keys (CMEK)
- Private Google Access configuration
- Network security perimeter with VPC Service Controls
- Workload Identity for enhanced service account security

## Performance Optimization

### Dataflow Optimization

- Use appropriate worker machine types for your data volume
- Configure autoscaling parameters based on traffic patterns
- Optimize Apache Beam pipeline code for efficiency
- Use side inputs for reference data joining

### Firestore Optimization

- Design document structure for query patterns
- Use composite indexes for complex queries
- Implement proper document sharding for high write volumes
- Monitor and optimize read/write operations

### Cost Management

- Implement Cloud Billing budgets and alerts
- Use committed use discounts for predictable workloads
- Monitor and optimize storage class transitions
- Regular review of resource utilization metrics

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Consult the troubleshooting section above
4. Contact your cloud administrator or Google Cloud support

## Additional Resources

- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)
- [Dataflow Best Practices](https://cloud.google.com/dataflow/docs/guides/best-practices)
- [Firestore Best Practices](https://cloud.google.com/firestore/docs/best-practices)
- [Pub/Sub Best Practices](https://cloud.google.com/pubsub/docs/best-practices)
- [Cloud Storage Best Practices](https://cloud.google.com/storage/docs/best-practices)