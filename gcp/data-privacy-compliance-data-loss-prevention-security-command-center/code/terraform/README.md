# Data Privacy Compliance Infrastructure - Terraform

This Terraform configuration deploys a comprehensive data privacy compliance system on Google Cloud Platform using Cloud Data Loss Prevention (DLP), Security Command Center, Cloud Functions, and automated monitoring capabilities.

## Architecture Overview

The infrastructure creates:

- **Cloud Data Loss Prevention (DLP)**: Inspection templates for detecting sensitive data types
- **Cloud Functions**: Serverless processing of DLP findings with automated response
- **Pub/Sub**: Reliable messaging for DLP findings and scan triggers
- **Cloud Storage**: Secure data storage with lifecycle management
- **Cloud Scheduler**: Automated periodic DLP scans
- **Cloud Monitoring**: Alerting and metrics for privacy violations
- **Security Command Center**: Centralized security findings management

## Prerequisites

1. **Google Cloud Project**: With billing enabled and appropriate permissions
2. **Required APIs**: Will be automatically enabled by Terraform
3. **Terraform**: Version >= 1.0
4. **Google Cloud CLI**: Installed and authenticated

### Permissions Required

Your service account or user account needs the following roles:

- `roles/owner` OR the following specific roles:
  - `roles/dlp.admin`
  - `roles/cloudfunctions.admin`
  - `roles/pubsub.admin`
  - `roles/storage.admin`
  - `roles/monitoring.admin`
  - `roles/logging.admin`
  - `roles/cloudscheduler.admin`
  - `roles/iam.admin`
  - `roles/serviceusage.serviceUsageAdmin`

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/data-privacy-compliance-data-loss-prevention-security-command-center/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment              = "prod"
resource_prefix         = "privacy-compliance"
notification_email      = "security-team@your-company.com"
dlp_scan_schedule       = "0 2 * * *"  # Daily at 2 AM UTC
dlp_min_likelihood      = "POSSIBLE"
monitoring_alert_threshold = 5

# Labels for resource organization
labels = {
  managed-by   = "terraform"
  purpose      = "data-privacy-compliance"
  team         = "security"
  environment  = "production"
}
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

After successful deployment, run the verification commands from the outputs:

```bash
# Check DLP template
terraform output -raw verification_commands | jq -r .check_dlp_template | bash

# Check Cloud Function
terraform output -raw verification_commands | jq -r .check_function | bash

# Check Pub/Sub topic
terraform output -raw verification_commands | jq -r .check_pubsub_topic | bash
```

## Configuration Options

### DLP Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `dlp_min_likelihood` | Minimum likelihood for findings | `"POSSIBLE"` | VERY_UNLIKELY, UNLIKELY, POSSIBLE, LIKELY, VERY_LIKELY |
| `dlp_max_findings_per_request` | Max findings per scan | `100` | 1-3000 |
| `sensitive_info_types` | Types to detect | See variables.tf | Any DLP info type |

### Function Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `function_memory` | Memory allocation | `"512Mi"` | 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, etc. |
| `function_timeout` | Execution timeout | `540` | 1-3600 seconds |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `notification_email` | Alert email address | `""` |
| `monitoring_alert_threshold` | Alert threshold | `5` |
| `enable_monitoring_alerts` | Enable alerts | `true` |

## Testing the Solution

### 1. Trigger a Manual DLP Scan

```bash
# Create a DLP job configuration
cat > dlp-job.json << EOF
{
  "inspectJob": {
    "inspectTemplate": "$(terraform output -raw dlp_inspect_template_name)",
    "storageConfig": {
      "cloudStorageOptions": {
        "fileSet": {
          "url": "gs://$(terraform output -raw test_data_bucket_name)/*"
        }
      }
    },
    "actions": [
      {
        "pubSub": {
          "topic": "$(terraform output -raw dlp_findings_topic_id)"
        }
      }
    ]
  }
}
EOF

# Run the DLP job
gcloud dlp jobs create --location=$(terraform output -raw region) --job-file=dlp-job.json
```

### 2. Monitor Function Execution

```bash
# View function logs
gcloud functions logs read $(terraform output -raw dlp_processor_function_name) \
  --region=$(terraform output -raw region) \
  --limit=20
```

### 3. Check Pub/Sub Messages

```bash
# Pull messages from the subscription
gcloud pubsub subscriptions pull $(terraform output -raw dlp_findings_subscription_name) \
  --limit=5 --auto-ack
```

## Security Best Practices

This infrastructure implements several security best practices:

### 1. **Least Privilege Access**
- Service accounts have minimal required permissions
- Function uses dedicated service account
- Workload Identity eliminates service account keys

### 2. **Data Protection**
- Cloud Storage buckets have uniform bucket-level access
- Public access prevention is enforced
- Versioning enabled for audit trails
- Lifecycle policies for automatic cleanup

### 3. **Network Security**
- Cloud Function ingress restricted to internal traffic
- VPC connector configuration available

### 4. **Monitoring and Alerting**
- Comprehensive logging with structured data
- Custom metrics for DLP findings
- Alert policies for high-severity violations
- Dead letter queues for message processing failures

## Monitoring and Observability

### Key Metrics

1. **DLP Findings Count**: Custom metric tracking findings by type and severity
2. **Function Execution**: Duration, errors, and invocation count
3. **Pub/Sub Messages**: Message processing rates and dead letter queue usage

### Dashboards

Create custom dashboards in Cloud Monitoring using these metrics:

```bash
# Example query for DLP findings
custom.googleapis.com/dlp/findings_count
| filter resource.type="global"
| group_by [metric.label.severity]
```

### Logs

Structured logs are available in Cloud Logging:

```bash
# Query for DLP findings
resource.type="cloud_function"
jsonPayload.message="DLP finding processed"
```

## Troubleshooting

### Common Issues

1. **Function Not Triggering**
   - Check Pub/Sub IAM permissions
   - Verify function trigger configuration
   - Review function logs for errors

2. **DLP Scans Failing**
   - Verify DLP API is enabled
   - Check service account permissions
   - Validate inspection template configuration

3. **No Monitoring Alerts**
   - Confirm notification channels are configured
   - Check alert policy conditions
   - Verify custom metrics are being created

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:dlp.googleapis.com"

# Verify service account permissions
gcloud projects get-iam-policy $(terraform output -raw project_id) \
  --flatten="bindings[].members" \
  --filter="bindings.members:$(terraform output -raw function_service_account_email)"

# Check function configuration
gcloud functions describe $(terraform output -raw dlp_processor_function_name) \
  --region=$(terraform output -raw region) --gen2
```

## Customization

### Adding Custom Info Types

Add custom information types to the DLP template:

```hcl
# In main.tf, add to the inspect_config block
custom_info_types {
  info_type {
    name = "EMPLOYEE_ID"
  }
  likelihood = "LIKELY"
  regex {
    pattern = "EMP-[0-9]{6}"
  }
}
```

### Integrating with External Systems

Modify the Cloud Function to integrate with:

- **SIEM Systems**: Send findings to external security platforms
- **Ticketing Systems**: Create tickets for high-severity findings
- **Communication Tools**: Send alerts to Slack, Teams, etc.

### Multi-Environment Setup

Use Terraform workspaces for multiple environments:

```bash
# Create workspace
terraform workspace new staging

# Deploy to staging
terraform apply -var-file=staging.tfvars
```

## Cost Optimization

### Resource Costs

- **Cloud DLP**: $1.00 per 1000 API calls
- **Cloud Functions**: $0.40 per 1M invocations + compute time
- **Pub/Sub**: $40 per TiB + operations
- **Cloud Storage**: $0.020 per GB/month (Standard class)
- **Cloud Monitoring**: Included in free tier for basic usage

### Optimization Tips

1. **Adjust scan frequency** based on data change rates
2. **Use lifecycle policies** to automatically delete old data
3. **Configure DLP sampling** for large datasets
4. **Set function memory** appropriately for workload

## Compliance Considerations

This solution helps with various compliance requirements:

- **GDPR**: Automated detection of personal data
- **CCPA**: California Consumer Privacy Act compliance
- **HIPAA**: Healthcare data protection
- **PCI-DSS**: Credit card data security

### Audit Trail

All activities are logged for compliance auditing:

- DLP scan results
- Function executions
- Security findings
- Remediation actions

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources and data. Make sure to backup any important data before running destroy.

## Support

For issues and questions:

1. Review the troubleshooting section
2. Check Google Cloud documentation for DLP and Security Command Center
3. Consult Terraform Google Provider documentation
4. Open an issue in the repository

## License

This infrastructure code is provided under the Apache 2.0 License. See LICENSE file for details.