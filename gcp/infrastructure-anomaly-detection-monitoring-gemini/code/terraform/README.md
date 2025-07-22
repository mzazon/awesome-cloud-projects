# Infrastructure Anomaly Detection with Cloud Monitoring and Gemini

This directory contains Terraform Infrastructure as Code (IaC) for deploying an AI-powered infrastructure anomaly detection system on Google Cloud Platform. The solution combines Cloud Monitoring, Vertex AI (Gemini), Cloud Functions, and Pub/Sub to create an intelligent monitoring system that can detect and analyze infrastructure anomalies in real-time.

## Architecture Overview

The solution deploys the following components:

- **Cloud Monitoring**: Comprehensive metrics collection from infrastructure
- **Vertex AI (Gemini)**: AI-powered anomaly analysis and pattern recognition
- **Cloud Functions**: Serverless compute for processing monitoring events
- **Pub/Sub**: Event-driven messaging for reliable data flow
- **Cloud Storage**: Function source code storage
- **Compute Engine**: Optional test infrastructure for validation
- **Monitoring Dashboard**: Visualization of anomaly detection results

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: A GCP project with billing enabled
2. **gcloud CLI**: Google Cloud CLI installed and configured
3. **Terraform**: Terraform >= 1.0 installed
4. **APIs**: The following APIs will be automatically enabled:
   - Cloud Monitoring API
   - Vertex AI API
   - Cloud Functions API
   - Pub/Sub API
   - Cloud Build API
   - Compute Engine API
   - Cloud Logging API

## Required Permissions

Your Google Cloud account needs the following IAM roles:

- `Project Editor` or equivalent custom roles with:
  - `roles/editor` (for resource management)
  - `roles/iam.serviceAccountCreator` (for service account creation)
  - `roles/serviceusage.serviceUsageAdmin` (for enabling APIs)

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd gcp/infrastructure-anomaly-detection-monitoring-gemini/code/terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
nano terraform.tfvars
```

### 2. Required Variables

Edit `terraform.tfvars` and set these required variables:

```hcl
# Required: Your Google Cloud project ID
project_id = "your-project-id-here"

# Required: Email for notifications
notification_email = "your-email@example.com"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Verify Deployment

After deployment, verify the infrastructure:

```bash
# Check Cloud Function status
gcloud functions describe $(terraform output -raw cloud_function_name) --region=$(terraform output -raw region)

# Test Pub/Sub messaging
gcloud pubsub topics publish $(terraform output -raw pubsub_topic_name) --message='{"metric_name":"test","value":0.95,"resource":"test"}'

# View function logs
gcloud functions logs read $(terraform output -raw cloud_function_name) --region=$(terraform output -raw region)
```

## Configuration Options

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Compute zone | `us-central1-a` | No |
| `notification_email` | Email for alerts | - | Yes |

### Function Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cloud_function_memory` | Function memory (MB) | `1024` | No |
| `cloud_function_timeout` | Function timeout (seconds) | `540` | No |
| `cloud_function_max_instances` | Max function instances | `10` | No |
| `gemini_model` | Gemini model to use | `gemini-2.0-flash-exp` | No |

### Test Infrastructure

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_test_infrastructure` | Create test VM | `true` | No |
| `test_instance_machine_type` | VM machine type | `e2-medium` | No |
| `enable_ops_agent` | Install Ops Agent | `true` | No |

### Monitoring Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cpu_threshold` | CPU alert threshold | `0.8` | No |
| `pubsub_ack_deadline` | Pub/Sub ack deadline (seconds) | `600` | No |
| `pubsub_message_retention_duration` | Message retention | `604800s` | No |

## Testing the Solution

### 1. Generate Test Load

If you enabled test infrastructure, generate CPU load:

```bash
# SSH to test instance
gcloud compute ssh $(terraform output -raw test_instance_name) --zone=$(terraform output -raw zone)

# Generate CPU load
stress --cpu 4 --timeout 300s
```

### 2. Monitor Results

```bash
# View anomaly detection dashboard
echo "Dashboard: $(terraform output -raw cloud_console_dashboard_url)"

# Check function logs for AI analysis
gcloud functions logs read $(terraform output -raw cloud_function_name) --region=$(terraform output -raw region)

# View alert policies
gcloud alpha monitoring policies list --format="table(displayName,enabled)"
```

### 3. Test with Synthetic Data

```bash
# Send test message to trigger analysis
gcloud pubsub topics publish $(terraform output -raw pubsub_topic_name) \
  --message='{"metric_name":"compute.googleapis.com/instance/cpu/utilization","value":0.95,"resource":"test-instance","timestamp":"2024-01-01T12:00:00Z"}'
```

## Monitoring and Observability

### Key Metrics

Monitor these key metrics in the Cloud Console:

1. **Anomaly Detection Scores**: AI-generated anomaly probabilities
2. **Function Execution Count**: Processing volume
3. **CPU/Memory Utilization**: Infrastructure health
4. **Pub/Sub Message Count**: Event flow rates
5. **Function Execution Duration**: Processing latency

### Dashboard Access

The deployment creates a comprehensive monitoring dashboard:

```bash
# Get dashboard URL
terraform output cloud_console_dashboard_url
```

### Log Analysis

View structured logs for anomaly detection:

```bash
# Function execution logs
gcloud functions logs read $(terraform output -raw cloud_function_name) --region=$(terraform output -raw region)

# Filter for anomaly alerts
gcloud functions logs read $(terraform output -raw cloud_function_name) --region=$(terraform output -raw region) --filter="ALERT"
```

## Customization

### Extending the Solution

1. **Add More Metrics**: Modify the function to process additional metric types
2. **Custom Notification Channels**: Integrate with Slack, PagerDuty, or other systems
3. **Advanced AI Models**: Use different Gemini models or custom ML models
4. **Multi-Project Monitoring**: Extend to monitor multiple GCP projects

### Security Considerations

- Service accounts follow least privilege principle
- Function source code is stored in private Cloud Storage
- IAM roles are scoped to specific resources
- Network access is restricted where possible

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Permission Denied**: Verify your account has necessary IAM roles
3. **Function Timeout**: Increase `cloud_function_timeout` if analysis takes longer
4. **Vertex AI Region**: Ensure chosen region supports Vertex AI services

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# Verify service account permissions
gcloud projects get-iam-policy $(terraform output -raw project_id)

# Check function deployment
gcloud functions describe $(terraform output -raw cloud_function_name) --region=$(terraform output -raw region)

# Test Pub/Sub connectivity
gcloud pubsub topics list
gcloud pubsub subscriptions list
```

## Cost Optimization

Estimated monthly costs (varies by usage):
- Cloud Function: $5-10 USD (depends on execution frequency)
- Pub/Sub: $1-3 USD (depends on message volume)
- Vertex AI: $5-15 USD (depends on Gemini API calls)
- Monitoring: $2-5 USD (depends on metric volume)
- Compute Engine: $10-20 USD (if test infrastructure enabled)

### Cost-Saving Tips

1. **Disable Test Infrastructure**: Set `enable_test_infrastructure = false` in production
2. **Optimize Function Memory**: Adjust `cloud_function_memory` based on actual usage
3. **Configure Retention**: Adjust `pubsub_message_retention_duration` based on needs
4. **Use Smaller Models**: Switch to `gemini-1.5-flash` for lower costs

## Cleanup

To remove all deployed resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify cleanup
gcloud functions list
gcloud pubsub topics list
gcloud monitoring dashboards list
```

## Support and Documentation

- [Google Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Vertex AI Generative AI Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the same license as the parent repository.