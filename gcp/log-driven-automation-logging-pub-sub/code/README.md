# Infrastructure as Code for Log-Driven Automation with Cloud Logging and Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Log-Driven Automation with Cloud Logging and Pub/Sub".

## Overview

This solution implements an intelligent log-driven automation system that monitors application logs in real-time, automatically detects error patterns and anomalies, triggers structured alerts through Pub/Sub messaging, and executes predefined remediation actions to minimize incident response time.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The solution deploys the following components:

- **Pub/Sub Topic and Subscriptions**: Event distribution for alerts and remediation
- **Cloud Logging Sinks**: Forward critical logs to Pub/Sub automatically
- **Log-Based Metrics**: Monitor error rates, exceptions, and latency anomalies
- **Cloud Functions**: Process alerts and execute automated remediation
- **Cloud Monitoring Policies**: Intelligent threshold-based alerting
- **IAM Roles and Bindings**: Secure service-to-service communication

## Prerequisites

- Google Cloud CLI installed and configured (or Google Cloud Shell)
- Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Project Editor or custom role with:
    - Pub/Sub Admin
    - Cloud Functions Admin
    - Logging Admin
    - Monitoring Admin
    - IAM Security Admin
- Node.js 20+ runtime for Cloud Functions
- Basic understanding of Google Cloud Logging, Pub/Sub, and Cloud Functions
- Estimated cost: $5-15 per month depending on log volume and function executions

## Environment Setup

```bash
# Set your Google Cloud project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Set default project and region
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set functions/region ${REGION}

# Enable required APIs
gcloud services enable logging.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
```

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/log-automation \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/log-automation-repo" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/log-automation
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your project ID and region
```

## Configuration

### Variables

The following variables can be customized for your environment:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | us-central1 | No |
| `zone` | Compute zone | us-central1-a | No |
| `topic_name` | Pub/Sub topic name | incident-automation | No |
| `log_sink_name` | Cloud Logging sink name | automation-sink | No |
| `alert_function_name` | Alert processing function name | alert-processor | No |
| `remediation_function_name` | Remediation function name | auto-remediate | No |
| `slack_webhook_url` | Slack webhook for notifications | - | No |

### Customizing Log Filters

Update the log sink filter in your chosen IaC implementation to match your application's log patterns:

```yaml
# Example log filter for custom applications
logFilter: 'severity>=ERROR OR jsonPayload.level="ERROR" OR textPayload:"Exception" OR jsonPayload.app="your-app-name"'
```

### Slack Integration

To enable Slack notifications:

1. Create a Slack webhook URL in your workspace
2. Set the `SLACK_WEBHOOK_URL` environment variable in the alert processing function
3. Update the function configuration with your webhook URL

## Testing the Deployment

After deployment, test the automation system:

```bash
# Generate a test error log
gcloud logging write test-automation \
    '{"severity": "ERROR", "message": "Test error for automation", "service": "test-app"}' \
    --severity=ERROR \
    --payload-type=json

# Check Pub/Sub messages (should see the test log)
gcloud pubsub subscriptions pull alert-subscription --limit=5 --auto-ack

# Generate a critical error to test remediation
gcloud logging write critical-test \
    '{"severity": "CRITICAL", "message": "OutOfMemoryError in application", "service": "web-app", "instance_id": "test-instance"}' \
    --severity=CRITICAL \
    --payload-type=json

# Monitor function logs
gcloud functions logs read alert-processor --limit=10
gcloud functions logs read auto-remediate --limit=10
```

## Monitoring and Observability

### Viewing Logs

```bash
# View Cloud Functions logs
gcloud functions logs read alert-processor --limit=50
gcloud functions logs read auto-remediate --limit=50

# View Pub/Sub subscription status
gcloud pubsub subscriptions describe alert-subscription
gcloud pubsub subscriptions describe remediation-subscription

# Check log-based metrics
gcloud logging metrics list
gcloud logging metrics describe error_rate_metric
```

### Cloud Monitoring

Access the Cloud Monitoring console to:
- View alerting policies and their status
- Monitor log-based metrics in dashboards
- Configure notification channels for alerts
- Review incident history and patterns

## Troubleshooting

### Common Issues

1. **Functions not triggering**:
   - Verify Pub/Sub topic permissions
   - Check log sink configuration
   - Ensure functions have proper IAM roles

2. **Log sink not forwarding logs**:
   - Verify log filter syntax
   - Check sink service account permissions
   - Confirm Pub/Sub topic exists

3. **Remediation actions failing**:
   - Review function logs for errors
   - Verify Compute Engine permissions
   - Check instance targeting logic

### Debug Commands

```bash
# Test Pub/Sub connectivity
gcloud pubsub topics publish incident-automation --message="Test message"

# Verify log sink operation
gcloud logging sinks describe automation-sink

# Check function deployment status
gcloud functions describe alert-processor
gcloud functions describe auto-remediate

# View recent function executions
gcloud functions logs read alert-processor --limit=20
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/log-automation
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup

If needed, manually remove resources:

```bash
# Delete Cloud Functions
gcloud functions delete alert-processor --quiet
gcloud functions delete auto-remediate --quiet

# Delete monitoring policies
gcloud alpha monitoring policies list --format="value(name)" | \
    xargs -I {} gcloud alpha monitoring policies delete {} --quiet

# Delete log-based metrics
gcloud logging metrics delete error_rate_metric --quiet
gcloud logging metrics delete exception_pattern_metric --quiet
gcloud logging metrics delete latency_anomaly_metric --quiet

# Delete log sink
gcloud logging sinks delete automation-sink --quiet

# Delete Pub/Sub resources
gcloud pubsub subscriptions delete alert-subscription --quiet
gcloud pubsub subscriptions delete remediation-subscription --quiet
gcloud pubsub topics delete incident-automation --quiet
```

## Customization

### Adding New Remediation Actions

Extend the remediation function by adding new patterns in the `determineRemediationAction` function:

```javascript
if (message.includes('DatabaseConnectionError')) {
  return {
    type: 'restart_database_connection',
    target: logEntry.resource?.labels?.instance_id,
    reason: 'Database connectivity issues detected'
  };
}
```

### Custom Log Filters

Modify log sinks and alerting policies to match your application patterns:

```bash
# Update log sink filter for custom application logs
gcloud logging sinks update automation-sink \
    --log-filter='severity>=ERROR OR jsonPayload.application="my-app" OR textPayload:"FATAL"'
```

### Integration with External Systems

The alert processing function can be extended to integrate with:
- PagerDuty for incident management
- Jira for ticket creation
- Custom webhooks for additional notifications
- Datadog or other monitoring platforms

## Security Considerations

- All functions use least-privilege IAM roles
- Pub/Sub topics have restricted publisher access
- Log sinks use dedicated service accounts
- Functions run with minimal required permissions
- Sensitive configuration uses environment variables
- Network traffic stays within Google Cloud when possible

## Cost Optimization

- Functions use minimal memory allocations
- Pub/Sub subscriptions have appropriate acknowledgment deadlines
- Log-based metrics are optimized for essential monitoring only
- Alerting policies include auto-close timers to prevent alert fatigue
- Consider log retention policies to manage storage costs

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../log-driven-automation-logging-pub-sub.md)
2. Check [Google Cloud Logging documentation](https://cloud.google.com/logging/docs)
3. Refer to [Pub/Sub best practices](https://cloud.google.com/pubsub/docs/best-practices)
4. Review [Cloud Functions documentation](https://cloud.google.com/functions/docs)
5. Consult [Cloud Monitoring guides](https://cloud.google.com/monitoring/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development project first
2. Update variable descriptions and documentation
3. Validate security implications of changes
4. Test both deployment and cleanup procedures
5. Update this README with any new requirements or procedures