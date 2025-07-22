# Infrastructure as Code for Real-Time Behavioral Analytics with Cloud Run Worker Pools and Cloud Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Behavioral Analytics with Cloud Run Worker Pools and Cloud Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with Google Cloud CLI

## Architecture Overview

This solution implements a serverless real-time behavioral analytics system using:

- **Cloud Run Worker Pools** for continuous background event processing
- **Cloud Firestore** for fast analytics queries and real-time aggregation
- **Pub/Sub** for reliable event ingestion and message queuing
- **Cloud Monitoring** for comprehensive system observability
- **Artifact Registry** for secure container image storage

## Prerequisites

- Google Cloud Project with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Docker installed locally for container image building
- Appropriate IAM permissions for:
  - Cloud Run administration
  - Firestore database creation and management
  - Pub/Sub topic and subscription management
  - IAM service account creation
  - Cloud Monitoring configuration
  - Artifact Registry repository management
- Estimated cost: $5-15 for testing (varies by event volume and duration)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code service that provides native integration with Google Cloud services.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/behavioral-analytics \
    --service-account="projects/PROJECT_ID/serviceAccounts/SERVICE_ACCOUNT_EMAIL" \
    --git-source-repo="https://source.developers.google.com/p/PROJECT_ID/r/REPO_NAME" \
    --git-source-directory="gcp/real-time-behavioral-analytics-run-worker-pools-firestore/code/infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=PROJECT_ID,region=REGION"

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/behavioral-analytics
```

### Using Terraform

Terraform provides declarative infrastructure management with excellent Google Cloud provider support.

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

Bash scripts provide step-by-step deployment using Google Cloud CLI commands.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
gcloud run workers list --region=$REGION
gcloud firestore databases list
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `worker_pool_name` | Cloud Run Worker Pool name | `behavioral-processor` | No |
| `firestore_database` | Firestore database name | `behavioral-analytics` | No |
| `max_instances` | Maximum worker pool instances | `10` | No |
| `memory_limit` | Memory limit per instance | `1Gi` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | `string` | - | Yes |
| `region` | Deployment region | `string` | `us-central1` | No |
| `zone` | Deployment zone | `string` | `us-central1-a` | No |
| `worker_pool_name` | Cloud Run Worker Pool name | `string` | `behavioral-processor` | No |
| `firestore_database` | Firestore database name | `string` | `behavioral-analytics` | No |
| `pubsub_topic_name` | Pub/Sub topic name | `string` | `user-events` | No |
| `subscription_name` | Pub/Sub subscription name | `string` | `analytics-processor` | No |
| `max_instances` | Maximum worker pool instances | `number` | `10` | No |
| `min_instances` | Minimum worker pool instances | `number` | `1` | No |
| `memory_limit` | Memory limit per instance | `string` | `1Gi` | No |
| `cpu_limit` | CPU limit per instance | `string` | `1` | No |
| `enable_monitoring` | Enable Cloud Monitoring dashboard | `bool` | `true` | No |

### Script Environment Variables

Set these environment variables before running the bash scripts:

```bash
export PROJECT_ID="your-project-id"           # Required
export REGION="us-central1"                   # Optional (default: us-central1)
export ZONE="us-central1-a"                   # Optional (default: us-central1-a)
export WORKER_POOL_NAME="custom-name"         # Optional
export FIRESTORE_DATABASE="custom-db"         # Optional
export PUBSUB_TOPIC="custom-topic"           # Optional
```

## Post-Deployment Steps

After deploying the infrastructure, you'll need to:

1. **Build and Deploy Application Container**:
   ```bash
   # Clone application code (if not already available)
   # Build container image
   cd behavioral-processor/
   gcloud builds submit . --tag=REGION-docker.pkg.dev/PROJECT_ID/behavioral-analytics/processor:latest
   
   # Update Cloud Run Worker Pool with new image
   gcloud run workers replace-service worker-pool-name --region=REGION
   ```

2. **Configure Firestore Indexes**:
   ```bash
   # Deploy Firestore composite indexes for optimal query performance
   gcloud firestore indexes composite create \
       --collection-group=user_events \
       --field-config=field-path=user_id,order=ascending \
       --field-config=field-path=timestamp,order=descending
   
   gcloud firestore indexes composite create \
       --collection-group=user_events \
       --field-config=field-path=event_type,order=ascending \
       --field-config=field-path=timestamp,order=descending
   ```

3. **Test Event Processing**:
   ```bash
   # Generate sample events using the provided event generator
   python3 generate_events.py
   
   # Monitor processing in Cloud Logging
   gcloud logs read "resource.type=cloud_run_revision" --limit=20
   ```

## Monitoring and Observability

The deployment includes comprehensive monitoring setup:

- **Cloud Monitoring Dashboard**: Real-time metrics for event processing rates and system performance
- **Custom Metrics**: Application-specific metrics for behavioral analytics insights
- **Log Aggregation**: Centralized logging for debugging and performance analysis
- **Alert Policies**: Automated alerts for system health and performance thresholds

Access monitoring:
```bash
# View monitoring dashboards
gcloud monitoring dashboards list

# View custom metrics
gcloud monitoring metrics list --filter="metric.type:custom.googleapis.com/behavioral_analytics"

# Check alert policies
gcloud alpha monitoring policies list
```

## Validation and Testing

### Infrastructure Validation

```bash
# Verify all components are deployed
gcloud run workers describe WORKER_POOL_NAME --region=REGION
gcloud firestore databases describe behavioral-analytics
gcloud pubsub topics describe user-events
gcloud pubsub subscriptions describe analytics-processor

# Check IAM service account
gcloud iam service-accounts describe analytics-processor@PROJECT_ID.iam.gserviceaccount.com
```

### Functional Testing

```bash
# Generate test events
python3 scripts/generate_test_events.py

# Verify event processing
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=WORKER_POOL_NAME" \
    --limit=10 --format="value(timestamp,textPayload)"

# Query analytics data
gcloud firestore documents list --collection-ids=analytics_aggregates --limit=5
```

### Performance Testing

```bash
# Run load test with higher event volume
python3 scripts/load_test.py --events=1000 --rate=10

# Monitor system performance
gcloud monitoring metrics list --filter="metric.type:run.googleapis.com"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/behavioral-analytics

# Verify deletion
gcloud infra-manager deployments list --location=REGION
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud run workers list --region=$REGION
gcloud firestore databases list
gcloud pubsub topics list
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
gcloud run workers list --region=REGION
gcloud firestore databases list
gcloud pubsub topics list | grep user-events
gcloud iam service-accounts list | grep analytics-processor
gcloud artifacts repositories list --location=REGION
```

## Troubleshooting

### Common Issues

1. **Worker Pool Not Processing Messages**:
   ```bash
   # Check worker pool logs
   gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=WORKER_POOL_NAME" --limit=50
   
   # Verify Pub/Sub subscription
   gcloud pubsub subscriptions describe analytics-processor
   ```

2. **Firestore Permission Errors**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy PROJECT_ID --filter="bindings.members:analytics-processor@PROJECT_ID.iam.gserviceaccount.com"
   ```

3. **Container Image Issues**:
   ```bash
   # Check Artifact Registry
   gcloud artifacts repositories list --location=REGION
   gcloud artifacts docker images list REGION-docker.pkg.dev/PROJECT_ID/behavioral-analytics
   ```

4. **High Processing Latency**:
   ```bash
   # Monitor worker pool metrics
   gcloud monitoring metrics list --filter="metric.type:run.googleapis.com/container"
   
   # Check Firestore performance
   gcloud monitoring metrics list --filter="metric.type:firestore.googleapis.com"
   ```

### Performance Optimization

- **Scale Worker Pool**: Adjust `max_instances` based on event volume
- **Optimize Firestore Queries**: Ensure proper composite indexes are created
- **Tune Pub/Sub Settings**: Adjust `ack_deadline` and `max_messages` for optimal throughput
- **Monitor Memory Usage**: Increase memory allocation if processing is memory-bound

## Security Considerations

- **IAM Principle of Least Privilege**: Service accounts have minimal required permissions
- **Network Security**: All communication uses Google Cloud's private network
- **Data Encryption**: Firestore and Pub/Sub provide encryption at rest and in transit
- **Container Security**: Artifact Registry includes vulnerability scanning
- **Audit Logging**: All operations are logged for security monitoring

## Cost Optimization

- **Serverless Scaling**: Automatic scaling based on demand reduces idle costs
- **Firestore Optimization**: Use composite indexes and efficient query patterns
- **Cloud Run Efficiency**: Configure appropriate CPU and memory limits
- **Data Retention**: Implement lifecycle policies for log and data retention
- **Monitoring**: Set up billing alerts and cost monitoring

## Customization

### Extending the Solution

1. **Add Data Lake Integration**: Connect to BigQuery for long-term analytics
2. **Implement Machine Learning**: Integrate Vertex AI for predictive analytics
3. **Add Real-time Dashboards**: Connect to Looker Studio for business intelligence
4. **Enhance Security**: Add VPC Service Controls and customer-managed encryption keys
5. **Multi-region Deployment**: Extend to multiple regions for global coverage

### Custom Event Processing

Modify the application code to:
- Add custom event validation logic
- Implement business-specific aggregation rules
- Integrate with external APIs for data enrichment
- Add custom monitoring metrics and alerts

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Monitor Cloud Logging for detailed error messages
5. Use Cloud Monitoring for performance insights

## Additional Resources

- [Cloud Run Worker Pools Documentation](https://cloud.google.com/run/docs/worker-pools)
- [Cloud Firestore Best Practices](https://cloud.google.com/firestore/docs/best-practices)
- [Pub/Sub Message Ordering](https://cloud.google.com/pubsub/docs/ordering)
- [Cloud Monitoring Custom Metrics](https://cloud.google.com/monitoring/custom-metrics)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)