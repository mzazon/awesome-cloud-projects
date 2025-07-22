# Dynamic Resource Governance - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying the complete Dynamic Resource Governance system using Google Cloud Platform services.

## Architecture Overview

The infrastructure creates a comprehensive governance system that includes:

- **Cloud Asset Inventory Feed**: Monitors all resource changes across your GCP organization
- **Pub/Sub Topic & Subscription**: Handles real-time event processing for governance workflows
- **Cloud Functions**: Three specialized functions for asset analysis, policy validation, and compliance enforcement
- **Service Account**: Dedicated service account with least-privilege IAM roles
- **Cloud Storage**: Buckets for function source code and governance logs
- **Cloud Monitoring**: Alerts and metrics for governance system health
- **Cloud Logging**: Centralized logging for all governance activities

## Prerequisites

1. **Google Cloud Project**: Active GCP project with billing enabled
2. **Terraform**: Version 1.0 or later installed locally
3. **Google Cloud CLI**: Installed and authenticated (`gcloud auth login`)
4. **APIs Enabled**: The Terraform configuration will enable required APIs automatically
5. **IAM Permissions**: Your account needs the following roles:
   - `roles/owner` or `roles/editor` on the project
   - `roles/resourcemanager.projectIamAdmin`
   - `roles/serviceusage.serviceUsageAdmin`

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/dynamic-resource-governance-asset-inventory-policy-simulator/code/terraform/
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your project details
nano terraform.tfvars
```

**Required Variables:**
- `project_id`: Your GCP project ID
- `region`: GCP region (default: us-central1)
- `zone`: GCP zone (default: us-central1-a)

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

## Configuration

### Essential Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `zone` | GCP zone for resources | `us-central1-a` | No |
| `environment` | Environment name | `dev` | No |

### Cloud Functions Configuration

Each Cloud Function can be configured independently:

```hcl
asset_analyzer_config = {
  memory_mb          = 512
  timeout_seconds    = 300
  max_instances      = 100
  min_instances      = 0
  cpu                = "1"
  ingress_settings   = "ALLOW_INTERNAL_ONLY"
  egress_settings    = "PRIVATE_RANGES_ONLY"
}
```

### Compliance Policies

Configure organizational compliance policies:

```hcl
compliance_policies = {
  "public-storage-bucket" = {
    enabled        = true
    risk_level     = "HIGH"
    auto_remediate = false
    alert_channels = []
  }
}
```

### High-Risk Asset Types

Define which asset types require special attention:

```hcl
high_risk_asset_types = [
  "compute.googleapis.com/Instance",
  "storage.googleapis.com/Bucket",
  "iam.googleapis.com/ServiceAccount",
  "container.googleapis.com/Cluster"
]
```

## Post-Deployment

### Validation

After deployment, verify the system is working:

```bash
# Check deployed functions
gcloud functions list --regions=us-central1

# Verify asset feed
gcloud asset feeds list

# Check Pub/Sub topics
gcloud pubsub topics list

# Test with a resource creation
gcloud compute instances create test-governance-vm \
    --zone=us-central1-a \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud
```

### Monitoring

View governance system logs:

```bash
# Asset analyzer logs
gcloud functions logs read governance-asset-analyzer-[suffix] --region=us-central1

# Compliance engine logs
gcloud functions logs read governance-compliance-engine-[suffix] --region=us-central1

# All governance logs
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name=~"governance-.*"' --limit=10
```

### Pub/Sub Message Monitoring

```bash
# Pull messages from compliance subscription
gcloud pubsub subscriptions pull governance-compliance-subscription-[suffix] --auto-ack --limit=5

# Check subscription status
gcloud pubsub subscriptions describe governance-compliance-subscription-[suffix]
```

## Customization

### Adding New Compliance Policies

1. Update the `compliance_policies` variable in `terraform.tfvars`
2. Modify the `check_policy_violation` function in `functions/compliance_engine.py`
3. Redeploy with `terraform apply`

### Modifying Risk Assessment

Update the risk assessment logic in `functions/asset_analyzer.py`:

```python
def assess_risk_level(asset_type: str, asset_data: Dict[str, Any]) -> Dict[str, Any]:
    # Add your custom risk assessment logic here
    pass
```

### Integration with External Systems

The functions include placeholder integration points for:

- **ITSM Systems**: ServiceNow, Jira for ticket creation
- **Alerting**: PagerDuty, Slack for notifications
- **SIEM**: Splunk, Chronicle for security event forwarding

## Outputs

After deployment, Terraform provides useful outputs:

- `governance_service_account`: Email of the governance service account
- `pubsub_topic_name`: Name of the asset changes topic
- `asset_feed_name`: Name of the Cloud Asset Inventory feed
- `validation_commands`: Commands to verify the deployment

## Cost Estimation

Estimated monthly costs for moderate enterprise usage:

- **Cloud Functions**: $5-15/month (execution-based)
- **Pub/Sub**: $2-5/month (message volume-based)
- **Cloud Storage**: $1-3/month (function source + logs)
- **Cloud Monitoring**: $2-5/month (alerts + metrics)
- **Cloud Asset Inventory**: Included in API quotas

**Total Estimated Cost**: $10-28/month

## Security Considerations

### Service Account Permissions

The governance service account uses least-privilege principles:

- `roles/cloudasset.viewer`: Read-only access to asset inventory
- `roles/iam.securityReviewer`: Review IAM policies and configurations
- `roles/monitoring.metricWriter`: Write custom metrics
- `roles/logging.logWriter`: Write to Cloud Logging
- `roles/pubsub.publisher`: Publish to Pub/Sub topics
- `roles/pubsub.subscriber`: Subscribe to Pub/Sub topics

### Network Security

- Asset Analyzer and Compliance Engine functions use `ALLOW_INTERNAL_ONLY` ingress
- Policy Validator allows external access for API calls
- All functions use private Google APIs through VPC connector when possible

### Data Privacy

- No sensitive data is stored in function environment variables
- All logs are structured and follow Google Cloud security best practices
- Function source code is stored in private Cloud Storage buckets

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Permission Denied**: Verify your account has sufficient IAM permissions
3. **Function Deployment Fails**: Check Cloud Build logs for detailed error messages
4. **Asset Feed Not Working**: Verify Pub/Sub topic permissions and asset feed configuration

### Debug Commands

```bash
# Check function deployment status
gcloud functions describe governance-asset-analyzer-[suffix] --region=us-central1

# View Cloud Build logs
gcloud builds list --limit=10

# Check service account permissions
gcloud projects get-iam-policy [PROJECT_ID] --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:governance-automation"
```

### Log Analysis

```bash
# Search for errors in governance functions
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name=~"governance-.*" AND severity>=ERROR' --limit=50

# View specific function logs
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name="governance-asset-analyzer-[suffix]"' --limit=20
```

## Cleanup

To remove all resources created by this Terraform configuration:

```bash
# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

**Note**: This will delete all governance infrastructure. Any logs stored in Cloud Storage will also be deleted.

## Advanced Configuration

### Multi-Project Deployment

For organization-wide governance, deploy the system in a dedicated governance project:

```hcl
# Use organization-level asset feeds
resource "google_cloud_asset_organization_feed" "governance_feed" {
  billing_project = var.project_id
  org_id          = var.organization_id
  feed_id         = local.asset_feed_name
  # ... rest of configuration
}
```

### Custom Notification Channels

Add notification channels for alerts:

```bash
# Create notification channel
gcloud alpha monitoring channels create --display-name="Governance Alerts" --type=email --email-address=security@company.com

# Add to terraform.tfvars
alert_notification_channels = ["projects/PROJECT_ID/notificationChannels/CHANNEL_ID"]
```

### Integration with CI/CD

Include governance checks in your CI/CD pipeline:

```yaml
# .github/workflows/governance.yml
name: Governance Check
on: [push, pull_request]
jobs:
  governance:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v1
    - name: Terraform Plan
      run: terraform plan
```

## Support

For issues with this Terraform configuration:

1. Check the [troubleshooting section](#troubleshooting)
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Check Terraform Google Cloud Provider documentation

## Contributing

To contribute improvements to this infrastructure:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This infrastructure code is provided under the same license as the parent repository.