# Infrastructure as Code for Domain Health Monitoring with Cloud Domains and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Domain Health Monitoring with Cloud Domains and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Domains
  - Cloud Functions
  - Cloud Monitoring
  - Cloud Storage
  - Pub/Sub
  - Cloud Scheduler
- Basic knowledge of Python programming and DNS concepts
- At least one domain registered or transferred to Cloud Domains for testing

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments create domain-monitoring \
    --location=${REGION} \
    --file=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe domain-monitoring \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" \
               -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" \
                -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and validation steps
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Google Cloud region for resources (default: us-central1)
- `function_name`: Name for the Cloud Function (default: domain-health-monitor)
- `schedule`: Cron schedule for monitoring (default: "0 */6 * * *")
- `monitoring_frequency`: How often to run health checks
- `alert_email`: Email address for notifications

### Terraform Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Google Cloud region for resources (default: us-central1)
- `zone`: Google Cloud zone for resources (default: us-central1-a)
- `function_name`: Name for the Cloud Function
- `bucket_name`: Cloud Storage bucket name (auto-generated if not specified)
- `domains_to_monitor`: List of domains to monitor (customizable)
- `ssl_warning_days`: Days before SSL expiration to alert (default: 30)

### Environment Variables for Scripts

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Optional customization variables
export FUNCTION_NAME="domain-health-monitor"
export MONITORING_SCHEDULE="0 */6 * * *"
export SSL_WARNING_DAYS="30"
export ALERT_EMAIL="admin@yourdomain.com"
```

## Architecture Components

The infrastructure deploys the following resources:

### Core Services
- **Cloud Functions**: Serverless monitoring function with Python 3.9 runtime
- **Cloud Storage**: Bucket for function source code and monitoring data
- **Cloud Scheduler**: Automated trigger for health checks every 6 hours
- **Pub/Sub**: Message queue for alert notifications

### Monitoring & Alerting
- **Cloud Monitoring**: Custom metrics and alerting policies
- **Notification Channels**: Email and integration endpoints for alerts
- **IAM Roles**: Least-privilege service accounts for function execution

### Security Features
- Service account with minimal required permissions
- Encrypted storage for monitoring data
- Secure HTTP triggers with authentication
- VPC integration support for enterprise environments

## Validation & Testing

After deployment, verify the infrastructure:

```bash
# Check Cloud Function status
gcloud functions describe ${FUNCTION_NAME} \
    --region=${REGION} \
    --format="table(name,status,runtime)"

# Verify Cloud Scheduler job
gcloud scheduler jobs list \
    --location=${REGION} \
    --filter="name:domain-monitor"

# Test function execution
gcloud functions call ${FUNCTION_NAME} \
    --region=${REGION}

# Check monitoring data
gsutil ls gs://${BUCKET_NAME}/monitoring-results/

# View function logs
gcloud functions logs read ${FUNCTION_NAME} \
    --region=${REGION} \
    --limit=10
```

## Monitoring and Metrics

The solution creates custom Cloud Monitoring metrics:

- `custom.googleapis.com/domain/ssl_valid`: SSL certificate validity (0 or 1)
- `custom.googleapis.com/domain/dns_resolves`: DNS resolution success (0 or 1)
- `custom.googleapis.com/domain/http_responds`: HTTP response success (0 or 1)
- `custom.googleapis.com/domain/ssl_days_until_expiry`: Days until SSL expiration

## Cost Optimization

Estimated monthly costs (assuming 10 domains, 6-hour monitoring frequency):

- Cloud Functions: $0.10-0.50 (within free tier for most usage)
- Cloud Storage: $0.05-0.15 for monitoring data
- Cloud Scheduler: $0.10 for job execution
- Cloud Monitoring: $0.00-0.20 (within free tier limits)
- **Total**: $0.25-1.00 per month

To optimize costs:
- Adjust monitoring frequency based on criticality
- Use Cloud Storage lifecycle policies for data retention
- Monitor Cloud Functions execution time and memory usage

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete domain-monitoring \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" \
                 -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
# and provide progress updates during cleanup
```

## Customization

### Adding Custom Domains

Edit the domain list in the function source code or pass as variables:

```python
# In main.py
domains_to_check = [
    'yourdomain.com',
    'anotherdomain.net',
    'subdomain.example.org'
]
```

### Modifying Health Checks

Extend the monitoring function to include:

- Custom HTTP headers and authentication
- API endpoint health checks
- Database connectivity testing
- Third-party service integration
- Performance metrics collection

### Advanced Alerting

Configure additional notification channels:

```bash
# Slack integration
gcloud alpha monitoring channels create \
    --display-name="Domain Alerts Slack" \
    --type=slack \
    --channel-labels=url=https://hooks.slack.com/your-webhook

# PagerDuty integration
gcloud alpha monitoring channels create \
    --display-name="Domain Alerts PagerDuty" \
    --type=pagerduty \
    --channel-labels=service_key=your-service-key
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**: Check IAM permissions and API enablement
2. **Monitoring data missing**: Verify Storage bucket permissions
3. **Alerts not triggering**: Check notification channel configuration
4. **DNS resolution fails**: Validate domain configuration and network access

### Debug Commands

```bash
# Check function logs
gcloud functions logs read ${FUNCTION_NAME} --limit=50

# Test function locally (requires Functions Framework)
functions-framework --target=domain_health_check --source=main.py

# Validate Cloud Monitoring metrics
gcloud logging read "resource.type=cloud_function" --limit=10

# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}
```

## Support

For issues with this infrastructure code:

1. Consult the original recipe documentation
2. Review Google Cloud documentation:
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Cloud Domains](https://cloud.google.com/domains/docs)
   - [Cloud Monitoring](https://cloud.google.com/monitoring/docs)
3. Check the [Google Cloud Status Page](https://status.cloud.google.com/) for service issues
4. Use `gcloud feedback` to report bugs or request features

## Security Considerations

- Function uses least-privilege service account
- All data encrypted in transit and at rest
- Network access restricted to required services
- Secrets managed through Secret Manager (if configured)
- Regular security updates through automated deployments

## Extensions and Enhancements

Consider these improvements for production use:

- Multi-region deployment for geographic redundancy
- Integration with Cloud Security Command Center
- Custom dashboards with Cloud Monitoring
- Automated certificate renewal workflows
- Integration with ITSM tools for incident management