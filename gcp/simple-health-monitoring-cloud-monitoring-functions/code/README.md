# Infrastructure as Code for Simple Application Health Monitoring with Cloud Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Application Health Monitoring with Cloud Monitoring".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured (version 400.0.0 or later)
- Google Cloud Platform account with Billing enabled
- Required APIs enabled:
  - Cloud Monitoring API (`monitoring.googleapis.com`)
  - Cloud Functions API (`cloudfunctions.googleapis.com`)
  - Pub/Sub API (`pubsub.googleapis.com`)
  - Cloud Build API (`cloudbuild.googleapis.com`)
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Developer
  - Monitoring Admin
  - Pub/Sub Admin
  - Project Editor (or custom role with required permissions)

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply \
    --location=${REGION} \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --local-source=infrastructure-manager/ \
    monitoring-stack

# Check deployment status
gcloud infra-manager deployments describe monitoring-stack \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" \
               -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" \
                -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud functions list --regions=${REGION}
gcloud pubsub topics list
gcloud alpha monitoring uptime list
```

## Architecture Overview

This infrastructure creates:

- **Pub/Sub Topic**: Message queue for monitoring alerts
- **Cloud Function**: Serverless notification processor (Python 3.12 runtime)
- **Uptime Check**: HTTP health monitoring from global locations
- **Alert Policy**: Monitoring policy that triggers on uptime failures
- **Notification Channel**: Pub/Sub integration for custom alerting

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `monitored_url`: Target URL to monitor (default: https://www.google.com)
- `check_interval`: Uptime check frequency (default: 60s)
- `alert_threshold_duration`: Alert trigger duration (default: 120s)

### Terraform Variables

Available in `terraform/variables.tf`:

- `project_id`: Your Google Cloud project ID (required)
- `region`: Deployment region (default: "us-central1")
- `monitored_url`: Target URL to monitor (default: "https://www.google.com")
- `uptime_check_interval`: Check frequency in seconds (default: 60)
- `alert_duration`: Duration before triggering alert (default: "120s")
- `function_memory`: Cloud Function memory allocation (default: "256Mi")
- `function_timeout`: Function execution timeout (default: 60)

Example terraform.tfvars:

```hcl
project_id = "my-monitoring-project"
region = "us-west2"
monitored_url = "https://myapp.example.com"
uptime_check_interval = 30
alert_duration = "180s"
```

### Bash Script Configuration

Edit environment variables in `scripts/deploy.sh`:

- `MONITORED_URL`: URL to monitor
- `CHECK_INTERVAL`: Frequency of health checks
- `ALERT_DURATION`: Time before alert triggers
- `FUNCTION_MEMORY`: Memory allocation for Cloud Function

## Validation

After deployment, verify the infrastructure:

```bash
# Check uptime monitoring status
gcloud alpha monitoring uptime list \
    --format="table(displayName,httpCheck.path,period)"

# Verify Cloud Function deployment
gcloud functions describe alert-notifier \
    --region=${REGION} \
    --format="table(name,status,runtime)"

# Test notification flow
echo '{"incident":{"policy_name":"Test Alert","state":"OPEN","started_at":"2025-01-15T10:00:00Z"}}' | \
gcloud pubsub messages publish monitoring-alerts --message=-

# Check function logs
gcloud functions logs read alert-notifier \
    --region=${REGION} \
    --limit=5
```

## Monitoring and Alerting

The infrastructure includes:

1. **Uptime Checks**: Monitor HTTP endpoint availability every 60 seconds
2. **Alert Policies**: Trigger when uptime check fails for 2+ minutes
3. **Custom Notifications**: Cloud Function processes alerts and logs details
4. **Global Coverage**: Monitoring from multiple Google Cloud regions

## Security Considerations

- Cloud Function uses least-privilege service account
- Pub/Sub topic permissions limited to monitoring service
- SSL/TLS validation enabled for uptime checks
- Function includes input validation and error handling
- All resources created with appropriate IAM bindings

## Cost Optimization

This solution is designed to stay within Google Cloud free tier limits:

- **Uptime Checks**: 50 checks/month included in free tier
- **Cloud Functions**: 2M invocations/month free
- **Pub/Sub**: 10GB message throughput/month free
- **Cloud Monitoring**: Basic monitoring included

Estimated monthly cost: $0.05-$0.10 for typical small-scale usage.

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete monitoring-stack \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" \
                  -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completed
gcloud functions list --regions=${REGION}
gcloud pubsub topics list
gcloud alpha monitoring uptime list
```

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**:
   - Verify Cloud Build API is enabled
   - Check service account permissions
   - Ensure Python runtime version is supported

2. **Uptime Check Creation Fails**:
   - Verify target URL is accessible
   - Check Cloud Monitoring API is enabled
   - Ensure proper SSL configuration for HTTPS URLs

3. **Alert Policy Not Triggering**:
   - Verify uptime check is running and reporting data
   - Check alert policy conditions and thresholds
   - Ensure notification channel is properly configured

4. **Pub/Sub Messages Not Processing**:
   - Check Cloud Function trigger configuration
   - Verify Pub/Sub topic permissions
   - Review function logs for errors

### Debug Commands

```bash
# Check API status
gcloud services list --enabled --filter="name:(monitoring.googleapis.com OR cloudfunctions.googleapis.com OR pubsub.googleapis.com)"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check function logs with detailed output
gcloud functions logs read alert-notifier \
    --region=${REGION} \
    --format="table(timestamp,severity,textPayload)" \
    --limit=20

# Monitor uptime check results
gcloud alpha monitoring time-series list \
    --filter='metric.type="monitoring.googleapis.com/uptime_check/check_passed"' \
    --interval-start-time="$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --interval-end-time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

## Extending the Solution

This infrastructure provides a foundation for more advanced monitoring:

1. **Multi-Endpoint Monitoring**: Add additional uptime checks for different services
2. **Custom Metrics**: Integrate application-specific metrics via Cloud Monitoring API
3. **Enhanced Notifications**: Add email/Slack integration to the Cloud Function
4. **Dashboard Creation**: Build Cloud Monitoring dashboards for visualization
5. **SLO Integration**: Implement Service Level Objectives based on uptime data

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for context
2. Check Google Cloud documentation for service-specific guidance
3. Verify all prerequisites and permissions are properly configured
4. Use the troubleshooting section for common issues

## Version Information

- **Infrastructure Manager**: Uses latest Google Cloud resource types
- **Terraform**: Compatible with Google Cloud Provider v5.0+
- **Cloud Functions**: Python 3.12 runtime
- **APIs**: Current stable versions as of 2025-01-15

Last Updated: 2025-01-15