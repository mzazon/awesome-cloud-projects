# Terraform Infrastructure for GCP Compliance Violation Detection

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive compliance violation detection system on Google Cloud Platform. The system monitors Cloud Audit Logs in real-time using Eventarc and Cloud Functions to detect policy violations and trigger automated response workflows.

## Architecture Overview

The deployed infrastructure includes:

- **Cloud Functions**: Serverless function for analyzing audit logs and detecting compliance violations
- **Eventarc**: Event routing service that triggers the function when audit logs are written
- **Pub/Sub**: Messaging service for distributing compliance alerts to multiple subscribers
- **BigQuery**: Data warehouse for storing and analyzing compliance violation records
- **Cloud Monitoring**: Alerting and dashboards for real-time compliance visibility
- **Cloud Logging**: Log sinks and metrics for comprehensive audit trail management

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: A GCP project with billing enabled
2. **gcloud CLI**: Installed and authenticated with appropriate permissions
3. **Terraform**: Version 1.5.0 or later installed locally
4. **Required Permissions**: The deploying account needs the following IAM roles:
   - Project Editor or Owner
   - Security Admin (for audit log configuration)
   - BigQuery Admin (for dataset creation)
   - Cloud Functions Developer
   - Pub/Sub Admin
   - Monitoring Admin

5. **Enabled APIs**: The following APIs will be automatically enabled during deployment:
   - Cloud Functions API
   - Eventarc API
   - Cloud Logging API
   - Pub/Sub API
   - BigQuery API
   - Cloud Monitoring API
   - Cloud Run API
   - Artifact Registry API
   - Cloud Build API

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/compliance-violation-detection-audit-logs-eventarc/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# Basic Configuration
project_id  = "your-gcp-project-id"
region      = "us-central1"
environment = "production"

# Function Configuration
function_max_instances = 50
function_min_instances = 1
function_memory       = "512Mi"

# BigQuery Configuration
dataset_owner_email = "admin@your-domain.com"
log_retention_days  = 2555  # ~7 years for compliance

# Compliance Rules
enable_iam_monitoring           = true
enable_data_access_monitoring   = false  # Set to true for stricter monitoring
enable_admin_activity_monitoring = true

# Monitoring Configuration
enable_email_notifications = true
alert_notification_channels = [
  "projects/your-project/notificationChannels/CHANNEL_ID_1",
  "projects/your-project/notificationChannels/CHANNEL_ID_2"
]

# Additional Labels
additional_labels = {
  team        = "security"
  cost_center = "compliance"
  environment = "production"
}
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan Deployment

```bash
terraform plan -var-file="terraform.tfvars"
```

### 5. Deploy Infrastructure

```bash
terraform apply -var-file="terraform.tfvars"
```

### 6. Verify Deployment

After deployment, verify the system is working:

```bash
# Check function status
gcloud functions describe $(terraform output -raw compliance_function_name) \
  --region=$(terraform output -raw region)

# Test with a sample IAM change
gcloud projects add-iam-policy-binding $(terraform output -raw project_id) \
  --member="user:test@example.com" \
  --role="roles/viewer"

# Check for violations in BigQuery (wait 2-3 minutes)
bq query --use_legacy_sql=false \
  "SELECT * FROM \`$(terraform output -raw violations_table_id)\` 
   WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE) 
   ORDER BY timestamp DESC LIMIT 5"
```

## Configuration Options

### Environment-Specific Settings

The configuration supports multiple environments with different security postures:

- **Development**: Relaxed monitoring, shorter retention, cost-optimized
- **Staging**: Production-like monitoring for testing compliance rules
- **Production**: Full monitoring, maximum retention, high availability

### Compliance Rule Customization

Modify the Cloud Function code to customize compliance rules:

1. Edit `function_code/index.js`
2. Update the `COMPLIANCE_RULES` object with your specific requirements
3. Redeploy with `terraform apply`

### Monitoring and Alerting

Configure notification channels for compliance alerts:

```bash
# Create email notification channel
gcloud alpha monitoring channels create \
  --display-name="Security Team Email" \
  --type=email \
  --channel-labels=email_address=security@your-domain.com

# Create Slack notification channel
gcloud alpha monitoring channels create \
  --display-name="Security Slack Channel" \
  --type=slack \
  --channel-labels=channel_name=#security-alerts
```

## Accessing Resources

### Cloud Console URLs

After deployment, use these URLs to access your resources:

```bash
# Get all console URLs
terraform output cloud_console_urls

# Access specific resources
echo "Function Logs: $(terraform output -raw cloud_console_urls | jq -r .function_logs)"
echo "BigQuery Dataset: $(terraform output -raw cloud_console_urls | jq -r .bigquery_dataset)"
echo "Monitoring Dashboard: $(terraform output -raw cloud_console_urls | jq -r .monitoring_dashboard)"
```

### BigQuery Analysis

Use these sample queries to analyze compliance violations:

```sql
-- Recent violations
SELECT 
  timestamp,
  violation_type,
  severity,
  principal,
  resource,
  details
FROM `PROJECT_ID.DATASET_ID.violations`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY timestamp DESC
LIMIT 100;

-- Violations by type and severity
SELECT 
  violation_type,
  severity,
  COUNT(*) as violation_count,
  COUNT(DISTINCT principal) as unique_principals
FROM `PROJECT_ID.DATASET_ID.violations`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY violation_type, severity
ORDER BY violation_count DESC;
```

### Command Line Management

```bash
# View function logs
gcloud functions logs read $(terraform output -raw compliance_function_name) \
  --region=$(terraform output -raw region) --limit=50

# Pull compliance alerts
gcloud pubsub subscriptions pull \
  $(terraform output -raw compliance_alerts_subscription) \
  --auto-ack --limit=10

# Query violations
bq query --use_legacy_sql=false \
  "$(terraform output -raw sample_bigquery_queries | jq -r .recent_violations)"
```

## Security Considerations

### Data Protection

- All data is encrypted at rest and in transit using Google-managed encryption keys
- BigQuery datasets use project-level access controls
- Cloud Function uses a dedicated service account with minimal permissions
- Pub/Sub messages are automatically encrypted

### Access Control

- Function service account follows principle of least privilege
- BigQuery access is controlled through IAM roles
- Audit logs are immutable and tamper-evident
- All administrative actions are logged

### Network Security

- Cloud Function is configured with `ALLOW_INTERNAL_ONLY` ingress settings
- VPC connector support available for private network access
- No public endpoints exposed except for authenticated Google Cloud APIs

## Cost Optimization

### Estimated Monthly Costs

For a typical enterprise workload:

- **Cloud Functions**: $10-50/month (based on execution volume)
- **BigQuery**: $20-100/month (based on data volume and retention)
- **Pub/Sub**: $5-25/month (based on message volume)
- **Cloud Monitoring**: $10-30/month (custom metrics and dashboards)
- **Cloud Storage**: $1-5/month (function source code)

### Cost Reduction Strategies

```hcl
# Cost-optimized configuration
function_min_instances = 0  # No warm instances
log_retention_days     = 90  # Shorter retention
enable_data_access_monitoring = false  # Reduce log volume
bigquery_location     = "us-central1"  # Single region
```

## Troubleshooting

### Common Issues

1. **Function not receiving events**:
   ```bash
   # Check Eventarc trigger
   gcloud eventarc triggers describe $(terraform output -raw trigger_name) \
     --location=$(terraform output -raw region)
   
   # Verify audit log configuration
   gcloud logging sinks describe $(terraform output -raw log_sink_name)
   ```

2. **BigQuery permissions errors**:
   ```bash
   # Check sink writer permissions
   gcloud projects get-iam-policy $(terraform output -raw project_id) \
     --flatten="bindings[].members" \
     --filter="bindings.members:$(terraform output -raw log_sink_writer_identity)"
   ```

3. **High function execution costs**:
   ```bash
   # Check function metrics
   gcloud monitoring metrics list \
     --filter="metric.type:cloudfunctions.googleapis.com/function/execution_count"
   ```

### Debugging Commands

```bash
# Function execution logs
gcloud functions logs read $(terraform output -raw compliance_function_name) \
  --region=$(terraform output -raw region) \
  --limit=100

# Audit log samples
gcloud logging read 'protoPayload.@type="type.googleapis.com/google.cloud.audit.AuditLog"' \
  --limit=10 --format=json

# Pub/Sub message monitoring
gcloud pubsub topics list
gcloud pubsub subscriptions list
```

## Maintenance

### Regular Tasks

1. **Monitor compliance trends** in BigQuery and dashboards
2. **Review alert policies** and adjust thresholds as needed
3. **Update compliance rules** in the Cloud Function code
4. **Rotate notification channels** and update contact information
5. **Review retention policies** and adjust for regulatory requirements

### Updates and Upgrades

```bash
# Update Terraform providers
terraform init -upgrade

# Plan and apply updates
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

## Cleanup

To remove all deployed resources:

```bash
terraform destroy -var-file="terraform.tfvars"
```

**Warning**: This will permanently delete all compliance data. Ensure you have exported any required records before destruction.

## Support and Documentation

- [Google Cloud Audit Logs Documentation](https://cloud.google.com/logging/docs/audit)
- [Eventarc Documentation](https://cloud.google.com/eventarc/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this Terraform configuration, check the troubleshooting section above or consult the original recipe documentation.