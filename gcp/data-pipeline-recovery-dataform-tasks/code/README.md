# Infrastructure as Code for Data Pipeline Recovery Workflows with Dataform and Cloud Tasks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Pipeline Recovery Workflows with Dataform and Cloud Tasks".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Dataform API
  - Cloud Tasks API
  - Cloud Functions API
  - Cloud Monitoring API
  - Cloud Logging API
  - Pub/Sub API
  - BigQuery API
- Basic understanding of data pipeline concepts and serverless architectures
- Estimated cost: $5-15 per month for small to medium workloads

## Architecture Overview

This solution implements an intelligent data pipeline recovery system that:

- Automatically detects Dataform workflow failures through Cloud Monitoring alerts
- Queues remediation tasks using Cloud Tasks for reliable execution with exponential backoff
- Orchestrates comprehensive retry logic with Cloud Functions
- Sends stakeholder notifications via Pub/Sub and email alerts
- Maintains detailed audit logs for troubleshooting and optimization

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/pipeline-recovery \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/pipeline-recovery" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Confirm deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy complete infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud dataform repositories list --region=${REGION}
gcloud tasks queues list --location=${REGION}
gcloud functions list --filter="name:pipeline-"
```

## Configuration

### Required Environment Variables

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export NOTIFICATION_RECIPIENTS="admin@company.com,ops-team@company.com"
```

### Optional Customization

The infrastructure can be customized by modifying variables in:

- **Infrastructure Manager**: `infrastructure-manager/variables.yaml`
- **Terraform**: `terraform/variables.tf`
- **Bash Scripts**: Environment variables at the top of `scripts/deploy.sh`

Key customizable parameters:

- `dataform_repo_name`: Name for the Dataform repository
- `task_queue_name`: Name for the Cloud Tasks queue
- `dataset_name`: BigQuery dataset name for pipeline data
- `notification_recipients`: Email addresses for alerts
- `memory_allocation`: Memory allocation for Cloud Functions
- `max_retry_attempts`: Maximum retry attempts for failed pipelines

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check all resources are deployed
gcloud dataform repositories list --region=${REGION}
gcloud tasks queues describe pipeline-recovery-queue --location=${REGION}
gcloud functions list --filter="name:pipeline-"
gcloud pubsub topics list --filter="name:pipeline-notifications"
```

### Test Pipeline Recovery

```bash
# Get controller function URL
CONTROLLER_URL=$(gcloud functions describe pipeline-controller \
    --region=${REGION} --gen2 \
    --format="value(serviceConfig.uri)")

# Simulate pipeline failure
curl -X POST ${CONTROLLER_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "incident": {
        "resource": {
          "labels": {
            "pipeline_id": "test-pipeline-001"
          }
        },
        "condition_name": "sql_error",
        "state": "OPEN"
      }
    }'

# Verify recovery task was queued
gcloud tasks list --queue=pipeline-recovery-queue --location=${REGION}
```

### Monitor System Health

```bash
# Check function logs
gcloud functions logs read pipeline-controller --region=${REGION} --limit=50

# Monitor task queue metrics
gcloud monitoring metrics list --filter="metric.type:tasks.googleapis.com"

# View pipeline execution logs
gcloud logging read 'resource.type="dataform_repository"' --limit=20
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/pipeline-recovery
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

### Manual Cleanup (if needed)

```bash
# Remove Cloud Functions
gcloud functions delete pipeline-controller --region=${REGION} --quiet
gcloud functions delete recovery-worker --region=${REGION} --quiet
gcloud functions delete notification-handler --region=${REGION} --quiet

# Remove Cloud Tasks queue
gcloud tasks queues delete pipeline-recovery-queue --location=${REGION} --quiet

# Remove monitoring resources
gcloud alpha monitoring policies list --format="value(name)" | \
    xargs -I {} gcloud alpha monitoring policies delete {} --quiet

# Remove Dataform repository
gcloud dataform repositories delete pipeline-recovery-repo --region=${REGION} --quiet

# Remove BigQuery dataset
bq rm -r -f pipeline_monitoring

# Remove Pub/Sub topic
gcloud pubsub topics delete pipeline-notifications --quiet
```

## Monitoring and Observability

### Key Metrics to Monitor

- **Pipeline Success Rate**: Percentage of successful pipeline executions
- **Recovery Success Rate**: Percentage of successful automated recoveries
- **Time to Recovery**: Average time from failure detection to successful recovery
- **Alert Response Time**: Time from failure to first recovery attempt
- **Cost Per Recovery**: Cloud costs associated with recovery operations

### Dashboards

Access pre-configured dashboards in Cloud Monitoring:

- **Pipeline Health Dashboard**: Overall pipeline status and trends
- **Recovery Performance Dashboard**: Recovery system metrics and effectiveness
- **Cost Analysis Dashboard**: Resource usage and cost optimization insights

### Logs

Key log sources for troubleshooting:

```bash
# Function execution logs
gcloud functions logs read pipeline-controller --region=${REGION}
gcloud functions logs read recovery-worker --region=${REGION}
gcloud functions logs read notification-handler --region=${REGION}

# Dataform workflow logs
gcloud logging read 'resource.type="dataform_repository"'

# Cloud Tasks execution logs
gcloud logging read 'resource.type="cloud_tasks_queue"'
```

## Security Considerations

### IAM and Access Control

- Cloud Functions run with minimal required permissions
- Service accounts follow principle of least privilege
- Webhook endpoints use proper authentication
- Sensitive configuration stored in Secret Manager

### Data Protection

- All data processing occurs within your GCP project boundary
- Network traffic encrypted in transit using TLS
- BigQuery tables use Google-managed encryption at rest
- Cloud Functions isolate execution environments

### Audit Trail

- All recovery actions logged with detailed context
- Monitoring alerts provide comprehensive failure attribution
- Function execution traces available for security review
- Resource access patterns tracked through Cloud Audit Logs

## Troubleshooting

### Common Issues

**Pipeline Recovery Not Triggering**
```bash
# Check monitoring alert policies
gcloud alpha monitoring policies list
# Verify webhook notification channels
gcloud alpha monitoring channels list
# Test webhook endpoint manually
curl -X POST $CONTROLLER_URL -d '{"test": "data"}'
```

**Recovery Tasks Not Executing**
```bash
# Check task queue status
gcloud tasks queues describe pipeline-recovery-queue --location=${REGION}
# Verify worker function deployment
gcloud functions describe recovery-worker --region=${REGION}
# Check function error logs
gcloud functions logs read recovery-worker --region=${REGION} --severity=ERROR
```

**Notifications Not Sent**
```bash
# Verify Pub/Sub topic and subscription
gcloud pubsub topics describe pipeline-notifications
# Check notification function logs
gcloud functions logs read notification-handler --region=${REGION}
# Test notification function manually
gcloud pubsub topics publish pipeline-notifications --message='{"test": "notification"}'
```

### Performance Optimization

- **Adjust retry policies**: Modify Cloud Tasks queue configuration for optimal backoff
- **Scale function memory**: Increase Cloud Functions memory for better performance
- **Optimize monitoring queries**: Fine-tune alert conditions to reduce false positives
- **Batch notifications**: Combine multiple recovery events in single notifications

## Customization Examples

### Adding Custom Recovery Strategies

Modify the recovery worker function to include domain-specific recovery logic:

```javascript
// In functions/worker/index.js
function determineRecoveryAction(failureType, pipelineMetadata) {
  if (pipelineMetadata.priority === 'critical') {
    return 'immediate_retry_with_escalation';
  }
  if (failureType === 'data_quality_issue') {
    return 'validate_and_retry';
  }
  return 'standard_retry';
}
```

### Integrating with External Systems

Extend notification handling to integrate with external monitoring systems:

```javascript
// In functions/notifications/index.js
async function sendToExternalSystem(notification) {
  // Integration with PagerDuty, ServiceNow, etc.
  await fetch('https://api.external-system.com/alerts', {
    method: 'POST',
    body: JSON.stringify(notification)
  });
}
```

### Custom Monitoring Metrics

Add business-specific metrics to Cloud Monitoring:

```bash
# Create custom metric for pipeline SLA tracking
gcloud logging metrics create pipeline_sla_violation \
    --description="Tracks pipeline SLA violations" \
    --log-filter='resource.type="dataform_repository" AND jsonPayload.duration > 3600'
```

## Cost Optimization

### Resource Sizing Recommendations

- **Cloud Functions**: Start with 256MB memory, scale based on execution time
- **Cloud Tasks**: Use default queue settings, adjust based on failure frequency
- **BigQuery**: Enable table expiration for monitoring data (30-90 days)
- **Cloud Monitoring**: Set appropriate metric retention periods

### Cost Monitoring

```bash
# Enable billing export to BigQuery for detailed cost analysis
gcloud billing accounts list
gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT_ID}

# Monitor Cloud Functions costs
gcloud billing budgets list --billing-account=${BILLING_ACCOUNT_ID}
```

## Support and Documentation

- **Recipe Documentation**: Refer to the original recipe markdown for detailed implementation guidance
- **Google Cloud Documentation**: [Dataform](https://cloud.google.com/dataform/docs), [Cloud Tasks](https://cloud.google.com/tasks/docs), [Cloud Functions](https://cloud.google.com/functions/docs)
- **Terraform Provider**: [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Infrastructure Manager**: [Google Cloud Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate with `terraform plan` or Infrastructure Manager preview
3. Update documentation for any new variables or outputs
4. Ensure all security best practices are maintained

## License

This infrastructure code is provided under the same license as the original recipe documentation.