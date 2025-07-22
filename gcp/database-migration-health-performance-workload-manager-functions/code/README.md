# Infrastructure as Code for Database Migration Health and Performance with Cloud Workload Manager and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Migration Health and Performance with Cloud Workload Manager and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Workload Manager
  - Database Migration Service
  - Cloud Functions
  - Cloud SQL
  - Cloud Monitoring
  - Cloud Logging
  - Pub/Sub
  - Cloud Storage
- Source database ready for migration (for testing)
- Estimated cost: $50-100 for testing resources over 2 hours

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export DEPLOYMENT_NAME="migration-monitor-$(openssl rand -hex 3)"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/terraform.tfvars"
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
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Follow prompts for configuration
```

## Architecture Overview

This solution deploys a comprehensive monitoring and alerting system for database migrations with the following components:

### Core Infrastructure
- **Cloud SQL Instance**: MySQL 8.0 target database with automated backups
- **Cloud Storage Bucket**: Stores Cloud Functions source code and monitoring artifacts
- **Pub/Sub Topics**: Event-driven messaging for migration events, validation results, and alerts

### Monitoring Functions
- **Migration Monitor**: Tracks Database Migration Service job status and performance
- **Data Validator**: Performs automated data consistency checks between source and target
- **Alert Manager**: Intelligent notification routing based on severity and type

### Observability
- **Cloud Workload Manager**: Rule-based validation and health monitoring
- **Cloud Monitoring**: Custom metrics and dashboards for migration progress
- **Cloud Logging**: Centralized logging for all monitoring components

## Configuration Options

### Environment Variables

The following environment variables can be configured:

```bash
# Core Configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Resource Naming
export MIGRATION_NAME="migration-monitor-$(openssl rand -hex 3)"
export WORKLOAD_NAME="workload-monitor-$(openssl rand -hex 3)"
export BUCKET_NAME="${PROJECT_ID}-migration-monitoring-$(openssl rand -hex 3)"

# Database Configuration
export DB_VERSION="MYSQL_8_0"
export DB_TIER="db-g1-small"
export DB_STORAGE_SIZE="20GB"
export DB_ROOT_PASSWORD="SecurePassword123!"
```

### Terraform Variables

When using Terraform, customize these variables in `terraform.tfvars`:

```hcl
# Project Configuration
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Database Configuration
db_version      = "MYSQL_8_0"
db_tier         = "db-g1-small"
db_storage_size = 20

# Monitoring Configuration
enable_advanced_monitoring = true
alert_email                = "your-email@example.com"
slack_webhook_url         = "https://hooks.slack.com/your-webhook"

# Function Configuration
function_memory    = 256
function_timeout   = 60
validator_memory   = 512
validator_timeout  = 300
```

### Infrastructure Manager Configuration

For Infrastructure Manager deployments, modify `infrastructure-manager/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Custom configuration for your environment
migration_name = "my-migration-monitor"
workload_name  = "my-workload-monitor"
bucket_name    = "my-migration-monitoring-bucket"
```

## Validation & Testing

After deployment, verify the solution is working correctly:

### 1. Verify Cloud Functions

```bash
# List deployed functions
gcloud functions list --filter="name~migration"

# Test migration monitor function
MONITOR_URL=$(gcloud functions describe migration-monitor --format="value(httpsTrigger.url)")
curl -X POST -H "Content-Type: application/json" \
  -d '{"project_id":"'${PROJECT_ID}'","migration_job_id":"test-job","location":"'${REGION}'"}' \
  ${MONITOR_URL}
```

### 2. Test Pub/Sub Event Flow

```bash
# Publish test message
gcloud pubsub topics publish migration-events \
  --message='{"project_id":"'${PROJECT_ID}'","migration_job_id":"test-migration","status":"running"}'

# Verify message delivery
gcloud pubsub subscriptions pull migration-monitor-sub --limit=1 --auto-ack
```

### 3. Check Workload Manager

```bash
# List workload evaluations
gcloud workload-manager evaluations list --location=${REGION}

# Get evaluation details
gcloud workload-manager evaluations describe ${WORKLOAD_NAME} --location=${REGION}
```

### 4. Verify Custom Metrics

```bash
# List custom metrics
gcloud monitoring metrics list \
  --filter="metric.type:custom.googleapis.com/migration" \
  --format="table(type,displayName)"
```

## Monitoring and Alerting

### Custom Dashboards

The solution creates custom Cloud Monitoring dashboards showing:
- Migration progress and duration
- Data validation scores
- Cloud SQL performance metrics
- Alert status and trends

Access dashboards at: [Cloud Monitoring Console](https://console.cloud.google.com/monitoring/dashboards)

### Alert Configuration

Alerts are configured based on:
- **High/Critical**: Immediate notifications via email and Slack
- **Medium**: Standard email notifications
- **Low**: Logged for batch review

### Health Checks

Cloud Workload Manager continuously evaluates:
- Database connection health
- Replication lag monitoring
- Storage utilization
- Configuration compliance

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

```bash
# Check for remaining functions
gcloud functions list --filter="name~migration"

# Check for remaining Cloud SQL instances
gcloud sql instances list --filter="name~migration"

# Check for remaining Pub/Sub topics
gcloud pubsub topics list --filter="name~migration"

# Check for remaining storage buckets
gsutil ls -b gs://*migration*
```

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**
   - Verify APIs are enabled: `gcloud services list --enabled`
   - Check IAM permissions for Cloud Functions service account
   - Ensure source code is properly formatted

2. **Cloud SQL Connection Issues**
   - Verify firewall rules allow connections
   - Check authorized networks configuration
   - Validate database credentials

3. **Pub/Sub Message Delivery**
   - Confirm subscriptions are properly configured
   - Check function trigger configuration
   - Verify message format and encoding

4. **Custom Metrics Not Appearing**
   - Allow time for metrics to propagate (up to 3 minutes)
   - Verify metric names and labels are correct
   - Check Cloud Monitoring API permissions

### Debugging Commands

```bash
# Check function logs
gcloud functions logs read migration-monitor --limit=50

# View Cloud SQL logs
gcloud logging read "resource.type=cloudsql_database" --limit=10

# Check Pub/Sub message flow
gcloud pubsub subscriptions pull migration-monitor-sub --limit=5

# Verify API enablement
gcloud services list --enabled --filter="name~(workload|function|pubsub|monitoring)"
```

## Security Considerations

### IAM Best Practices

The solution implements least-privilege access:
- Cloud Functions use service accounts with minimal required permissions
- Database access is restricted to specific users and IP ranges
- Pub/Sub topics use IAM conditions for access control

### Data Protection

- All data is encrypted at rest and in transit
- Cloud SQL instances use Google-managed encryption keys
- Function environment variables are encrypted
- Pub/Sub messages are automatically encrypted

### Network Security

- Cloud SQL instances are configured with private IPs where possible
- Function-to-function communication uses internal Google Cloud networking
- External access is restricted to necessary endpoints only

## Performance Optimization

### Function Configuration

- Memory allocation is optimized for each function's workload
- Timeout values are set based on expected execution time
- Concurrency limits prevent resource exhaustion

### Database Performance

- Cloud SQL instances are configured with appropriate machine types
- Storage is provisioned with SSD for better performance
- Connection pooling is recommended for high-throughput scenarios

### Monitoring Efficiency

- Metrics are sampled at appropriate intervals to balance cost and visibility
- Log levels are configured to capture essential information without noise
- Dashboard refresh rates are optimized for real-time monitoring needs

## Cost Optimization

### Resource Sizing

- Cloud SQL instances use cost-effective machine types for testing
- Cloud Functions are configured with minimal memory requirements
- Storage buckets use standard class for cost efficiency

### Monitoring Costs

- Custom metrics are limited to essential KPIs
- Log retention is configured based on compliance requirements
- Alert frequency is balanced to avoid excessive notifications

## Support and Documentation

### Additional Resources

- [Cloud Workload Manager Documentation](https://cloud.google.com/workload-manager/docs)
- [Database Migration Service Best Practices](https://cloud.google.com/database-migration/docs/best-practices)
- [Cloud Functions Monitoring Patterns](https://cloud.google.com/functions/docs/monitoring)
- [Cloud Monitoring Custom Metrics](https://cloud.google.com/monitoring/custom-metrics)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud provider documentation
4. Contact your cloud infrastructure team

---

**Note**: This infrastructure code is generated from the cloud recipe and follows Google Cloud best practices. Modify configurations as needed for your specific environment and requirements.