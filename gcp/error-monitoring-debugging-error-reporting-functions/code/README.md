# Infrastructure as Code for Error Monitoring and Debugging with Cloud Error Reporting and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Error Monitoring and Debugging with Cloud Error Reporting and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an intelligent error monitoring system that automatically detects, categorizes, and responds to application errors using:

- Cloud Error Reporting for automatic error aggregation
- Cloud Functions for serverless error processing and automation
- Cloud Monitoring for alerting and dashboards
- Cloud Logging for centralized log management
- Firestore for error tracking and pattern analysis
- Cloud Storage for storing debug reports
- Pub/Sub for event-driven architecture

## Prerequisites

### General Requirements

- Google Cloud project with billing enabled
- Google Cloud CLI installed and configured (or access to Cloud Shell)
- Appropriate IAM permissions for:
  - Cloud Error Reporting
  - Cloud Functions
  - Cloud Monitoring
  - Cloud Logging
  - Pub/Sub
  - Cloud Storage
  - Firestore
- Basic understanding of serverless computing and error handling patterns

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Infrastructure Manager API enabled
- `gcloud` CLI with Infrastructure Manager support

#### Terraform
- Terraform >= 1.0 installed
- Google Cloud provider >= 4.0

#### Bash Scripts
- `gcloud` CLI authenticated and configured
- `gsutil` command-line tool
- `openssl` for generating random values

## Cost Estimates

Estimated monthly cost for small to medium applications:
- Cloud Functions: $2-8 (depends on error volume and function invocations)
- Cloud Storage: $0.50-2 (for debug reports)
- Firestore: $1-3 (for error tracking data)
- Pub/Sub: $0.50-1 (for message passing)
- Cloud Monitoring: $1-2 (for dashboards and alerts)
- **Total: $5-15 per month**

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Set environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export DEPLOYMENT_NAME="error-monitoring-$(date +%s)"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/inputs.yaml"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=$(gcloud config get-value project)" \
               -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=$(gcloud config get-value project)" \
                -var="region=us-central1" \
                -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create Pub/Sub topics
# 3. Deploy Cloud Functions
# 4. Configure log sinks
# 5. Set up monitoring dashboard
# 6. Create sample application for testing
```

## Deployment Details

### Infrastructure Components

The deployment creates the following resources:

1. **Cloud Functions**:
   - Error processor function (processes and classifies errors)
   - Alert router function (routes alerts based on severity)
   - Debug automation function (collects debug context)
   - Sample application function (for testing error generation)

2. **Pub/Sub Topics**:
   - Error notifications topic
   - Alert routing topic
   - Debug automation topic

3. **Storage Resources**:
   - Cloud Storage bucket for debug reports
   - Firestore database for error tracking

4. **Monitoring Resources**:
   - Cloud Monitoring dashboard
   - Log sink for error events
   - Alert policies for critical errors

5. **IAM Configuration**:
   - Service accounts with least privilege access
   - Proper role bindings for function execution

### Configuration Variables

#### Terraform Variables
- `project_id`: GCP project ID
- `region`: Deployment region (default: us-central1)
- `random_suffix`: Unique suffix for resource names
- `enable_monitoring_dashboard`: Enable monitoring dashboard creation
- `slack_webhook_url`: Optional Slack webhook for notifications

#### Infrastructure Manager Inputs
- `project_id`: GCP project ID
- `region`: Deployment region
- `environment`: Environment tag (dev/staging/prod)
- `notification_settings`: Configuration for alert notifications

## Testing the Deployment

### Generate Test Errors

```bash
# Get the sample app URL
SAMPLE_APP_URL=$(gcloud functions describe sample-error-app \
    --region=us-central1 --format="value(httpsTrigger.url)")

# Test critical error
curl -X POST "${SAMPLE_APP_URL}" \
    -H "Content-Type: application/json" \
    -d '{"error_type": "critical"}'

# Test database error
curl -X POST "${SAMPLE_APP_URL}" \
    -H "Content-Type: application/json" \
    -d '{"error_type": "database"}'

# Generate multiple errors for pattern detection
for i in {1..6}; do
    curl -X POST "${SAMPLE_APP_URL}" \
        -H "Content-Type: application/json" \
        -d '{"error_type": "random"}'
    sleep 2
done
```

### Verify Error Processing

```bash
# Check Cloud Error Reporting console
echo "View errors at: https://console.cloud.google.com/errors?project=$(gcloud config get-value project)"

# Check function logs
gcloud functions logs read error-processor --region=us-central1 --limit=10

# Check Firestore for error records
gcloud firestore documents list errors --format="table(name,createTime)" --limit=5

# Check debug reports in Storage
gsutil ls gs://error-debug-data-*/debug_reports/
```

### Monitor System Performance

```bash
# View monitoring dashboard
echo "Dashboard: https://console.cloud.google.com/monitoring/dashboards"

# Check alert policies
gcloud alpha monitoring policies list --format="table(displayName,enabled)"

# View function metrics
gcloud functions describe error-processor --region=us-central1
```

## Customization

### Environment-Specific Configuration

1. **Development Environment**:
   ```bash
   # Deploy with development settings
   terraform apply -var="environment=dev" \
                  -var="enable_advanced_monitoring=false"
   ```

2. **Production Environment**:
   ```bash
   # Deploy with production settings
   terraform apply -var="environment=prod" \
                  -var="enable_advanced_monitoring=true" \
                  -var="function_memory=512MB"
   ```

### Notification Customization

1. **Slack Integration**:
   ```bash
   # Set Slack webhook URL
   export SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
   
   # Update function environment variables
   gcloud functions deploy error-processor-router \
       --update-env-vars="SLACK_WEBHOOK=${SLACK_WEBHOOK}"
   ```

2. **Email Notifications**:
   - Modify the alert router function to integrate with SendGrid or Gmail API
   - Update notification channels in Cloud Monitoring

### Function Configuration

Customize function behavior by modifying environment variables:

```bash
# Update error classification thresholds
gcloud functions deploy error-processor \
    --update-env-vars="CRITICAL_THRESHOLD=5,HIGH_THRESHOLD=10"

# Configure debug report retention
gcloud functions deploy error-processor-debug \
    --update-env-vars="DEBUG_RETENTION_DAYS=30"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=$(gcloud config get-value project)" \
                 -var="region=us-central1" \
                 -auto-approve

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Functions
# 2. Remove Pub/Sub topics
# 3. Delete Storage bucket and Firestore data
# 4. Remove monitoring resources
# 5. Clean up IAM bindings
```

### Manual Cleanup Verification

```bash
# Verify Cloud Functions are deleted
gcloud functions list --region=us-central1

# Verify Pub/Sub topics are deleted
gcloud pubsub topics list

# Verify Storage buckets are deleted
gsutil ls

# Verify Firestore collections are empty
gcloud firestore documents list errors --limit=1
```

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**:
   ```bash
   # Check function logs for errors
   gcloud functions logs read FUNCTION_NAME --region=us-central1
   
   # Verify required APIs are enabled
   gcloud services list --enabled
   ```

2. **Permission Errors**:
   ```bash
   # Check IAM bindings
   gcloud projects get-iam-policy $(gcloud config get-value project)
   
   # Verify service account permissions
   gcloud iam service-accounts get-iam-policy SERVICE_ACCOUNT_EMAIL
   ```

3. **Pub/Sub Message Delivery Issues**:
   ```bash
   # Check topic subscriptions
   gcloud pubsub topics list-subscriptions TOPIC_NAME
   
   # Monitor message delivery metrics
   gcloud monitoring metrics list --filter="metric.type:pubsub"
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Update function with debug logging
gcloud functions deploy error-processor \
    --update-env-vars="LOG_LEVEL=DEBUG"

# View detailed logs
gcloud functions logs read error-processor \
    --region=us-central1 \
    --start-time="2025-01-01T00:00:00Z"
```

## Security Considerations

### Best Practices Implemented

1. **Least Privilege Access**: Functions use minimal required permissions
2. **Secure Communication**: All inter-service communication uses IAM authentication
3. **Data Encryption**: Storage and Firestore data encrypted at rest
4. **Network Security**: Functions deployed with private networking where possible

### Additional Security Measures

```bash
# Enable VPC connector for functions (optional)
gcloud compute networks vpc-access connectors create error-monitoring-connector \
    --region=us-central1 \
    --subnet=default \
    --min-instances=2 \
    --max-instances=3

# Update functions to use VPC connector
gcloud functions deploy error-processor \
    --vpc-connector=error-monitoring-connector
```

## Monitoring and Alerting

### Key Metrics to Monitor

1. **Function Performance**:
   - Execution time and memory usage
   - Error rates and retry counts
   - Cold start frequency

2. **Error Processing**:
   - Error classification accuracy
   - Alert routing effectiveness
   - Debug report generation success

3. **System Health**:
   - Pub/Sub message processing latency
   - Firestore write operations
   - Storage bucket usage

### Custom Alerts

```bash
# Create custom alert policy for function errors
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/function-error-policy.yaml

# Create alert for high error volumes
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/high-error-volume-policy.yaml
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Deploy Error Monitoring
on:
  push:
    branches: [main]
    paths: ['gcp/error-monitoring-debugging-error-reporting-functions/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: google-github-actions/setup-gcloud@v1
        with:
          service_account_key: ${{ secrets.GCP_SA_KEY }}
          project_id: ${{ secrets.GCP_PROJECT_ID }}
      - name: Deploy with Terraform
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

## Support

### Documentation References

- [Cloud Error Reporting Documentation](https://cloud.google.com/error-reporting/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

1. **Recipe Issues**: Refer to the original recipe documentation
2. **GCP Service Issues**: Check [Google Cloud Status](https://status.cloud.google.com/)
3. **Terraform Issues**: Consult [Terraform Google Provider](https://github.com/hashicorp/terraform-provider-google)
4. **Community Support**: [Google Cloud Community](https://cloud.google.com/community)

### Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description
5. Ensure all security and best practice guidelines are followed