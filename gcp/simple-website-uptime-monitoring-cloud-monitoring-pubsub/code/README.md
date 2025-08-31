# Infrastructure as Code for Simple Website Uptime Monitoring with Cloud Monitoring and Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Website Uptime Monitoring with Cloud Monitoring and Pub/Sub".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Owner or Editor permissions on the target project
- Basic understanding of website monitoring concepts
- Email address for receiving uptime notifications

### Required APIs

The following APIs will be enabled automatically during deployment:
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Pub/Sub API (`pubsub.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/uptime-monitoring \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/uptime-monitoring
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id"

# Apply the configuration
terraform apply -var="project_id=your-project-id"

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
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit `inputs.yaml` to customize the deployment:

```yaml
project_id: "your-project-id"
region: "us-central1"
notification_email: "your-email@example.com"
monitored_websites:
  - "https://www.google.com"
  - "https://www.github.com"
  - "https://www.stackoverflow.com"
function_memory: "256Mi"
function_timeout: "60s"
check_period: "60s"
alert_threshold: 1
```

### Terraform Variables

Set variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
notification_email = "your-email@example.com"
monitored_websites = [
  "https://www.google.com",
  "https://www.github.com",
  "https://www.stackoverflow.com"
]
function_memory = 256
function_timeout = 60
check_period = 60
alert_threshold = 1
checker_regions = ["us-central1", "europe-west1", "asia-east1"]
```

### Bash Script Variables

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export NOTIFICATION_EMAIL="your-email@example.com"
export MONITORED_WEBSITES="https://www.google.com,https://www.github.com,https://www.stackoverflow.com"
export FUNCTION_MEMORY="256Mi"
export FUNCTION_TIMEOUT="60s"
export CHECK_PERIOD="60"
export ALERT_THRESHOLD="1"
```

## Architecture Overview

The infrastructure creates:

1. **Pub/Sub Topic**: Receives uptime alert messages from Cloud Monitoring
2. **Cloud Function**: Processes alerts and formats notifications (Python 3.12 runtime)
3. **Uptime Checks**: Monitors websites from multiple global regions
4. **Notification Channel**: Connects Cloud Monitoring to Pub/Sub
5. **Alerting Policy**: Defines when to trigger alerts based on uptime failures
6. **IAM Roles**: Proper permissions for function execution and service integration

## Monitoring and Validation

### Check Uptime Monitoring Status

```bash
# List active uptime checks
gcloud monitoring uptime list --format="table(displayName,httpCheck.path,period)"

# View recent check results
gcloud logging read "resource.type=uptime_url" --limit=10

# Check alerting policies
gcloud alpha monitoring policies list --filter="displayName:Website*"
```

### Test Alert Processing

```bash
# Send test alert to Pub/Sub topic
gcloud pubsub topics publish uptime-alerts-topic \
    --message='{"incident":{"policy_name":"Test Policy","state":"OPEN","url":"https://test.example.com"}}'

# Check function logs
gcloud functions logs read uptime-processor-function --region=us-central1 --limit=5
```

### Monitor Costs

```bash
# View current month's costs for monitoring services
gcloud billing budgets list --billing-account=YOUR_BILLING_ACCOUNT_ID

# Check Pub/Sub usage
gcloud monitoring metrics list --filter="metric.type:pubsub"
```

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/uptime-monitoring

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/verify-cleanup.sh
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your account has Owner or Editor role
3. **Function Deployment Fails**: Check Cloud Build API is enabled and has proper IAM roles
4. **Uptime Checks Not Running**: Verify websites are accessible and URLs are correct
5. **No Alerts Received**: Check notification channel configuration and Pub/Sub topic permissions

### Debug Commands

```bash
# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Verify API enablement
gcloud services list --enabled --filter="name:(monitoring|pubsub|cloudfunctions|cloudbuild)"

# Check function deployment status
gcloud functions describe uptime-processor-function --region=${REGION}

# View detailed error logs
gcloud logging read "severity>=ERROR" --limit=20
```

### Getting Help

- Review the [Cloud Monitoring documentation](https://cloud.google.com/monitoring/docs)
- Check [Pub/Sub troubleshooting guide](https://cloud.google.com/pubsub/docs/troubleshooting)
- Consult [Cloud Functions debugging guide](https://cloud.google.com/functions/docs/troubleshooting)

## Cost Estimation

### Expected Monthly Costs (5-10 websites)

- **Cloud Monitoring Uptime Checks**: $0.30 per check per month
- **Pub/Sub**: $0.40 per million messages
- **Cloud Functions**: $0.40 per million invocations + $0.0000025 per GB-second
- **Cloud Build**: $0.003 per build minute (deployment only)

**Total estimated monthly cost**: $2-5 USD for typical usage

### Cost Optimization

- Adjust check frequency for non-critical websites
- Use regional uptime checks instead of global for cost savings
- Implement intelligent alerting to reduce false positives
- Set up budget alerts to monitor spending

## Security Considerations

The infrastructure implements several security best practices:

- **Least Privilege IAM**: Functions and services have minimal required permissions
- **Encrypted Transit**: All communications use HTTPS/TLS
- **Secure Secrets**: Email addresses and sensitive data stored securely
- **Network Security**: Functions deployed with appropriate VPC settings
- **Audit Logging**: All actions logged for security monitoring

## Customization Examples

### Adding New Websites

To monitor additional websites, update the configuration:

**Terraform**: Add URLs to `monitored_websites` variable
**Infrastructure Manager**: Update `monitored_websites` in `inputs.yaml`
**Bash Scripts**: Add URLs to `MONITORED_WEBSITES` environment variable

### Integrating with External Systems

Modify the Cloud Function code to integrate with:
- Slack webhooks for team notifications
- PagerDuty for incident management
- Webhook endpoints for custom integrations
- Email services for rich HTML notifications

### Advanced Monitoring

Enhance the solution with:
- Custom HTTP headers for authenticated endpoints
- Response time threshold alerting
- SSL certificate expiration monitoring
- Content validation checks

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud status page for service issues
3. Consult the provider's documentation links above
4. Review troubleshooting section for common issues

## Version Information

- **Infrastructure Manager**: Uses latest Google Cloud resource types
- **Terraform**: Compatible with Terraform 1.0+ and Google Cloud Provider 4.0+
- **Cloud Functions**: Python 3.12 runtime
- **API Versions**: Uses current stable versions of all Google Cloud APIs