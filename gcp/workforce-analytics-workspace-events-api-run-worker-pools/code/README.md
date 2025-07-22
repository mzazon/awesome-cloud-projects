# Infrastructure as Code for Workforce Analytics with Workspace Events API and Cloud Run Worker Pools

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Workforce Analytics with Workspace Events API and Cloud Run Worker Pools".

## Overview

This solution builds an intelligent workforce analytics system that captures real-time Google Workspace events through the Workspace Events API and processes them using Cloud Run Worker Pools for scalable event handling. The infrastructure aggregates meeting data, file access patterns, and collaboration metrics into BigQuery for advanced analytics while providing real-time monitoring through Cloud Monitoring dashboards.

## Architecture Components

- **Google Workspace Events API**: Real-time event streaming from Workspace applications
- **Cloud Pub/Sub**: Reliable event messaging and distribution
- **Cloud Run Worker Pools**: Scalable event processing with automatic scaling
- **BigQuery**: Data warehouse for analytics and insights
- **Cloud Monitoring**: Operational dashboards and alerting
- **Cloud Storage**: Application code and temporary data storage

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Required Tools
- Google Cloud CLI (`gcloud`) installed and configured (version 400.0.0 or later)
- Terraform (if using Terraform implementation) version 1.5.0 or later
- Docker (for building container images)
- Git (for code management)

### Required Permissions
- Project Owner or Editor role in Google Cloud Platform
- Google Workspace admin access for Events API configuration
- APIs enabled:
  - Cloud Run API
  - Pub/Sub API
  - BigQuery API
  - Cloud Monitoring API
  - Cloud Build API
  - Workspace Events API

### Prerequisites Setup
```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable run.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable workspaceevents.googleapis.com
```

### Estimated Costs
- **Development/Testing**: $15-25 per month
- **Production (moderate workload)**: $50-100 per month
- **Production (high workload)**: $200-500 per month

Costs depend on event volume, storage requirements, and query frequency. BigQuery and Cloud Run scale with usage, providing cost-effective scaling for varying workloads.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Review and customize configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/workforce-analytics \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/workforce-analytics
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan deployment
terraform plan -var-file="terraform.tfvars"

# Apply infrastructure
terraform apply -var-file="terraform.tfvars"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | No |
| `zone` | Compute zone for resources | `us-central1-a` | No |
| `dataset_name` | BigQuery dataset name | `workforce_analytics` | No |
| `worker_pool_name` | Cloud Run Worker Pool name | `analytics-processor` | No |
| `topic_name` | Pub/Sub topic name | `workspace-events` | No |
| `subscription_name` | Pub/Sub subscription name | `events-processor` | No |
| `min_instances` | Minimum worker pool instances | `1` | No |
| `max_instances` | Maximum worker pool instances | `10` | No |
| `memory` | Worker pool memory allocation | `1Gi` | No |
| `cpu` | Worker pool CPU allocation | `1` | No |

### Workspace Events API Configuration

After infrastructure deployment, manual configuration is required for the Workspace Events API:

1. **Access Google Workspace Admin Console**:
   - Navigate to Security > API Reference > Events API
   - Enable Workspace Events API

2. **Create Event Subscription**:
   ```json
   {
     "name": "projects/{PROJECT_ID}/subscriptions/workforce-analytics",
     "targetResource": "//workspace.googleapis.com/users/*",
     "eventTypes": [
       "google.workspace.calendar.event.v1.created",
       "google.workspace.calendar.event.v1.updated",
       "google.workspace.drive.file.v1.created",
       "google.workspace.drive.file.v1.updated",
       "google.workspace.meet.participant.v1.joined",
       "google.workspace.meet.participant.v1.left"
     ],
     "notificationEndpoint": {
       "pubsubTopic": "projects/{PROJECT_ID}/topics/{TOPIC_NAME}"
     }
   }
   ```

3. **Verify Webhook Configuration**:
   - Ensure proper authentication is configured
   - Test event delivery to Pub/Sub topic
   - Validate IAM permissions for service accounts

## Post-Deployment Validation

### 1. Verify Infrastructure Components

```bash
# Check BigQuery dataset
bq ls ${PROJECT_ID}:workforce_analytics

# Verify Pub/Sub topic and subscription
gcloud pubsub topics list
gcloud pubsub subscriptions list

# Check Cloud Run Worker Pool status
gcloud beta run worker-pools list --region=${REGION}

# Verify Cloud Storage bucket
gsutil ls gs://workforce-data-${PROJECT_ID}-*
```

### 2. Test Event Processing

```bash
# Send test event to Pub/Sub
gcloud pubsub topics publish workspace-events \
    --message='{"eventId":"test-123","eventType":"google.workspace.calendar.event.v1.created","meetingId":"meet-test","organizerEmail":"test@example.com"}'

# Check worker pool logs
gcloud beta run worker-pools logs tail analytics-processor --region=${REGION}

# Verify data in BigQuery
bq query --use_legacy_sql=false "SELECT COUNT(*) FROM \`${PROJECT_ID}.workforce_analytics.meeting_events\`"
```

### 3. Access Analytics Dashboards

```bash
# List created monitoring dashboards
gcloud monitoring dashboards list

# Get dashboard URLs
echo "Access your workforce analytics dashboard at:"
echo "https://console.cloud.google.com/monitoring/dashboards"
```

## Customization Examples

### Scaling Configuration

To adjust worker pool scaling for higher event volumes:

```hcl
# In terraform/variables.tf or terraform.tfvars
min_instances = 3
max_instances = 50
memory = "2Gi"
cpu = 2
```

### Additional Event Types

To capture additional Workspace events, update the subscription configuration:

```json
{
  "eventTypes": [
    "google.workspace.calendar.event.v1.created",
    "google.workspace.gmail.message.v1.created",
    "google.workspace.chat.message.v1.created",
    "google.workspace.admin.directory.user.v1.created"
  ]
}
```

### Custom Analytics Views

Add custom BigQuery views for specific business metrics:

```sql
-- Team productivity view
CREATE VIEW `PROJECT_ID.workforce_analytics.team_productivity` AS
SELECT 
  EXTRACT(WEEK FROM DATE(start_time)) as week_number,
  organizer_email,
  COUNT(*) as meetings_per_week,
  AVG(duration_minutes) as avg_meeting_duration,
  SUM(participant_count) as total_participants
FROM `PROJECT_ID.workforce_analytics.meeting_events`
GROUP BY week_number, organizer_email
ORDER BY week_number DESC;
```

## Monitoring and Alerts

### Key Metrics to Monitor

1. **Event Processing Rate**: Messages per second through Pub/Sub
2. **Worker Pool Utilization**: Instance count and CPU/memory usage
3. **BigQuery Insertion Rate**: Rows inserted per minute
4. **Error Rate**: Failed event processing percentage
5. **Latency**: End-to-end event processing time

### Setting Up Custom Alerts

```bash
# Create alert for high error rate
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/high-error-rate-policy.yaml

# Create alert for processing delays
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/processing-delay-policy.yaml
```

## Troubleshooting

### Common Issues

1. **Events Not Processing**:
   - Verify Workspace Events API subscription is active
   - Check IAM permissions for service accounts
   - Validate Pub/Sub topic configuration

2. **Worker Pool Scaling Issues**:
   - Review Cloud Run quotas and limits
   - Check regional resource availability
   - Validate scaling configuration

3. **BigQuery Insertion Errors**:
   - Verify table schemas match event data structure
   - Check BigQuery quotas and slot allocation
   - Review IAM permissions for BigQuery access

### Debug Commands

```bash
# Check worker pool status and logs
gcloud beta run worker-pools describe ${WORKER_POOL_NAME} --region=${REGION}
gcloud beta run worker-pools logs tail ${WORKER_POOL_NAME} --region=${REGION}

# Monitor Pub/Sub subscription
gcloud pubsub subscriptions pull ${SUBSCRIPTION_NAME} --limit=5

# Check BigQuery job history
bq ls -j --max_results=10

# View recent Cloud Monitoring metrics
gcloud monitoring metrics list --filter="resource.type=cloud_run_revision"
```

## Security Considerations

### IAM Best Practices

- Use least privilege principle for all service accounts
- Enable audit logging for all critical operations
- Regularly review and rotate service account keys
- Implement conditional access policies where applicable

### Data Protection

- Enable encryption at rest for BigQuery datasets
- Configure VPC Service Controls for additional network security
- Implement data retention policies for compliance
- Use Customer-Managed Encryption Keys (CMEK) for sensitive data

### Network Security

- Deploy worker pools in private VPC subnets
- Configure firewall rules for necessary traffic only
- Use Private Google Access for Cloud APIs
- Enable VPC Flow Logs for network monitoring

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/workforce-analytics
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars"

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
./scripts/verify-cleanup.sh
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud beta run worker-pools delete ${WORKER_POOL_NAME} --region=${REGION} --quiet
bq rm -r -f ${PROJECT_ID}:workforce_analytics
gcloud pubsub subscriptions delete events-processor
gcloud pubsub topics delete workspace-events
gsutil -m rm -r gs://workforce-data-${PROJECT_ID}-*

# Remove IAM bindings
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:workforce-analytics@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor"
```

## Advanced Features

### Machine Learning Integration

Extend the solution with Vertex AI for predictive analytics:

```bash
# Enable Vertex AI API
gcloud services enable aiplatform.googleapis.com

# Create training pipeline for productivity prediction
gcloud ai custom-jobs create \
    --region=${REGION} \
    --display-name="workforce-productivity-model" \
    --config=ml/training-config.yaml
```

### Real-time Streaming Analytics

Implement Cloud Dataflow for advanced real-time processing:

```bash
# Deploy Dataflow pipeline for anomaly detection
gcloud dataflow jobs run workforce-anomaly-detection \
    --gcs-location=gs://dataflow-templates/latest/PubSub_to_BigQuery \
    --region=${REGION} \
    --parameters inputTopic=projects/${PROJECT_ID}/topics/workspace-events
```

### Multi-Organization Support

Configure for multiple Workspace organizations:

```hcl
# In terraform/main.tf
resource "google_pubsub_topic" "workspace_events_org2" {
  name = "workspace-events-org2"
  # Additional organization configuration
}
```

## Performance Optimization

### BigQuery Optimization

- Use partitioned tables for time-series data
- Implement clustering on frequently queried columns
- Configure materialized views for common queries
- Use streaming inserts efficiently

### Cloud Run Optimization

- Optimize container image size and startup time
- Configure appropriate CPU and memory allocations
- Use connection pooling for database connections
- Implement graceful shutdown handling

### Cost Optimization

- Use BigQuery slots for predictable query costs
- Configure Cloud Run minimum instances based on usage patterns
- Implement data lifecycle policies for long-term storage
- Monitor and optimize Pub/Sub message retention

## Support and Documentation

### Additional Resources

- [Google Workspace Events API Documentation](https://developers.google.com/workspace/events)
- [Cloud Run Worker Pools Documentation](https://cloud.google.com/run/docs/worker-pools)
- [BigQuery Analytics Documentation](https://cloud.google.com/bigquery/docs/analytics)
- [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/best-practices)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Status page for service issues
3. Consult provider documentation for specific services
4. Use `gcloud feedback` to report Google Cloud CLI issues
5. Review Cloud Console audit logs for deployment issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any new features
4. Validate changes against the original recipe requirements