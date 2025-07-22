# Infrastructure as Code for Infrastructure Anomaly Detection with Cloud Monitoring and Gemini

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Anomaly Detection with Cloud Monitoring and Gemini".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate Google Cloud project with billing enabled
- Required IAM permissions for:
  - Cloud Monitoring
  - Vertex AI
  - Cloud Functions
  - Pub/Sub
  - Compute Engine
  - Cloud Build
- Project APIs enabled:
  - `monitoring.googleapis.com`
  - `aiplatform.googleapis.com`
  - `cloudfunctions.googleapis.com`
  - `pubsub.googleapis.com`
  - `cloudbuild.googleapis.com`
  - `compute.googleapis.com`

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code service that supports Terraform configurations with additional Google Cloud integrations.

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="anomaly-detection-deployment"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/inputs.tfvars"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Deploy infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
./scripts/deploy.sh --status
```

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment supports these customizable variables:

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `function_memory`: Cloud Function memory allocation (default: 1Gi)
- `function_timeout`: Cloud Function timeout (default: 540s)
- `max_instances`: Maximum Cloud Function instances (default: 10)
- `instance_type`: Test VM instance type (default: e2-medium)
- `notification_email`: Email for anomaly alerts (required)

### Terraform Variables

Key variables in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone"
  type        = string
  default     = "us-central1-a"
}

variable "notification_email" {
  description = "Email address for anomaly notifications"
  type        = string
}
```

### Environment Variables for Scripts

The bash scripts use these environment variables:

```bash
export PROJECT_ID="your-project-id"           # Required
export REGION="us-central1"                   # Optional, defaults to us-central1
export ZONE="us-central1-a"                   # Optional, defaults to us-central1-a
export NOTIFICATION_EMAIL="admin@example.com" # Required for alerts
```

## Deployment Components

This infrastructure deployment creates:

### Core Infrastructure
- **Pub/Sub Topic**: Event processing backbone for monitoring data
- **Pub/Sub Subscription**: Connects monitoring events to analysis functions
- **Cloud Function**: Serverless AI analysis engine with Vertex AI integration
- **Test VM Instance**: Generates realistic monitoring data with Ops Agent

### Monitoring & Alerting
- **Alert Policies**: Intelligent threshold-based triggers for anomaly detection
- **Notification Channels**: Email and webhook integration for alert delivery
- **Custom Metrics**: AI-generated anomaly scores and analysis results
- **Monitoring Dashboard**: Visual interface for anomaly detection insights

### AI & Analysis
- **Vertex AI Integration**: Gemini 2.0 Flash model for intelligent pattern analysis
- **Service Account**: Secure access to Google Cloud AI Platform and monitoring services
- **IAM Roles**: Least privilege permissions for anomaly detection workflow

## Testing the Deployment

After deployment, test the anomaly detection system:

```bash
# Generate synthetic CPU load to trigger anomaly detection
gcloud compute ssh test-instance --zone=${ZONE} \
    --command="stress --cpu 4 --timeout 300s"

# Monitor Cloud Function execution
gcloud functions logs read anomaly-detector --region=${REGION} --limit=10

# Check Pub/Sub message processing
gcloud pubsub topics list-subscriptions monitoring-events

# View monitoring dashboard
echo "Dashboard URL: https://console.cloud.google.com/monitoring/dashboards"
```

## Validation

Verify the deployment is working correctly:

```bash
# Check Cloud Function status
gcloud functions describe anomaly-detector --region=${REGION}

# Verify Pub/Sub resources
gcloud pubsub topics describe monitoring-events
gcloud pubsub subscriptions describe anomaly-analysis

# Test Vertex AI integration
gcloud ai models list --region=${REGION}

# Check monitoring policies
gcloud alpha monitoring policies list --filter="displayName:'AI-Powered CPU Anomaly Detection'"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify deletion
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify state file is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
./scripts/destroy.sh --verify
```

## Cost Optimization

### Estimated Costs

- **Cloud Functions**: $0.0000004 per invocation + $0.0000025 per GB-second
- **Pub/Sub**: $0.40 per million messages
- **Vertex AI**: $0.000025 per 1K input tokens, $0.000125 per 1K output tokens
- **Compute Engine**: $0.033 per hour (e2-medium instance)
- **Cloud Monitoring**: Free tier covers most monitoring needs

### Cost Reduction Strategies

1. **Function Optimization**: Reduce memory allocation and timeout values
2. **Instance Scheduling**: Use Cloud Scheduler to start/stop test instances
3. **Monitoring Scope**: Limit monitoring to critical resources only
4. **Alert Tuning**: Optimize thresholds to reduce false positive AI analysis calls

## Security Considerations

### IAM Best Practices

- Service accounts follow least privilege principle
- Vertex AI access restricted to specific models and regions
- Cloud Functions execute with minimal required permissions
- Monitoring data access controlled through Cloud IAM

### Data Protection

- All data encrypted in transit and at rest
- Pub/Sub messages use Google Cloud's default encryption
- Vertex AI API calls secured with service account authentication
- No sensitive data stored in function environment variables

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **IAM Permissions**: Verify service account has necessary roles
3. **Function Deployment**: Check Cloud Build logs for deployment issues
4. **Vertex AI Access**: Confirm Vertex AI is available in your chosen region

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# View function logs
gcloud functions logs read anomaly-detector --region=${REGION}

# Test Pub/Sub connectivity
gcloud pubsub topics publish monitoring-events --message="test"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}
```

## Monitoring and Maintenance

### Regular Maintenance Tasks

1. **Function Updates**: Keep Cloud Functions runtime updated
2. **Model Versioning**: Monitor for new Vertex AI model versions
3. **Threshold Tuning**: Adjust anomaly detection thresholds based on false positive rates
4. **Cost Monitoring**: Review monthly costs and optimize resource usage

### Performance Monitoring

- Monitor Cloud Function execution times and memory usage
- Track Pub/Sub message processing latency
- Analyze Vertex AI API response times and token usage
- Review monitoring dashboard for anomaly detection accuracy

## Integration Examples

### Webhook Integration

```bash
# Add webhook notification channel
gcloud alpha monitoring channels create \
    --channel-content='{
        "type": "webhook_tokenauth",
        "displayName": "Slack Integration",
        "labels": {
            "url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
        }
    }'
```

### Custom Metrics Integration

```python
# Example: Send custom metrics to Cloud Monitoring
from google.cloud import monitoring_v3

client = monitoring_v3.MetricServiceClient()
series = monitoring_v3.TimeSeries()
series.metric.type = 'custom.googleapis.com/anomaly_confidence'
series.resource.type = 'global'

# Add your custom metric logic here
```

## Support and Documentation

### Additional Resources

- [Google Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Vertex AI Generative AI Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud support documentation
4. Open an issue in the repository

---

*This infrastructure code implements the complete solution described in the "Infrastructure Anomaly Detection with Cloud Monitoring and Gemini" recipe, providing AI-powered anomaly detection capabilities for Google Cloud infrastructure.*