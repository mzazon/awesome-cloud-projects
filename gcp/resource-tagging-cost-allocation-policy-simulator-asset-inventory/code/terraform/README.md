# Resource Tagging and Cost Allocation Infrastructure

This Terraform configuration deploys a comprehensive resource tagging and cost allocation solution for Google Cloud Platform using Policy Simulator, Cloud Asset Inventory, and BigQuery analytics.

## Architecture Overview

The solution creates the following components:

- **Organization Policies**: Enforce mandatory resource tagging across the organization
- **Cloud Asset Inventory**: Monitor resource changes and compliance in real-time
- **BigQuery Analytics**: Store and analyze cost allocation and compliance data
- **Cloud Functions**: Process asset changes and generate automated reports
- **Cloud Storage**: Store billing exports and generated reports
- **Pub/Sub**: Handle asset change notifications

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: With billing enabled and appropriate permissions
2. **Organization Access**: Admin permissions for creating organization policies (optional)
3. **Terraform**: Version 1.5 or higher installed
4. **gcloud CLI**: Configured with appropriate credentials
5. **APIs Enabled**: The Terraform will enable required APIs automatically

### Required IAM Permissions

Your account or service account needs the following roles:

- `roles/resourcemanager.projectIamAdmin`
- `roles/bigquery.admin`
- `roles/storage.admin`
- `roles/cloudfunctions.admin`
- `roles/pubsub.admin`
- `roles/cloudasset.owner`
- `roles/orgpolicy.policyAdmin` (for organization policies)
- `roles/serviceusage.serviceUsageAdmin`

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository and navigate to the terraform directory
cd gcp/resource-tagging-cost-allocation-policy-simulator-asset-inventory/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id      = "your-gcp-project-id"
organization_id = "your-organization-id"  # Leave empty if not using org policies
region         = "us-central1"

# Optional customization
resource_prefix = "my-cost-alloc"
environment     = "prod"
mandatory_labels = ["department", "cost_center", "environment", "project_code"]

# Enable organization policy enforcement (requires org admin permissions)
enforce_org_policy = true

# Enable automated reporting
enable_automated_reporting = true
report_schedule           = "0 9 * * 1"  # Every Monday at 9 AM
```

### 3. Plan and Deploy

```bash
# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Configure Cloud Billing Export

After deployment, configure Cloud Billing export to send data to the created BigQuery dataset:

1. Go to Cloud Billing > Billing export in the Google Cloud Console
2. Enable BigQuery export
3. Select the dataset created by Terraform (shown in outputs)
4. Enable detailed usage cost data export

## Configuration Options

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `organization_id` | Organization ID for policies | "" | No |
| `region` | Deployment region | "us-central1" | No |
| `zone` | Deployment zone | "us-central1-a" | No |

### Resource Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `resource_prefix` | Prefix for resource names | "cost-alloc" |
| `environment` | Environment tag | "dev" |
| `dataset_location` | BigQuery dataset location | "US" |
| `storage_class` | Cloud Storage class | "STANDARD" |

### Policy Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `mandatory_labels` | Required resource labels | ["department", "cost_center", "environment", "project_code"] |
| `enforce_org_policy` | Enable organization policies | false |
| `monitored_asset_types` | Asset types to monitor | ["compute.googleapis.com/Instance", ...] |

### Function Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `function_memory` | Cloud Function memory (MB) | 256 |
| `function_timeout` | Cloud Function timeout (seconds) | 60 |
| `enable_automated_reporting` | Enable scheduled reports | true |
| `report_schedule` | Cron schedule for reports | "0 9 * * 1" |

## Post-Deployment Configuration

### 1. Test Tag Compliance

Create a test resource with proper tags:

```bash
# Create compliant resource
gcloud compute instances create test-compliant \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --labels=department=engineering,cost_center=cc-001,environment=test,project_code=proj-123

# Create non-compliant resource (should be blocked if org policy is enabled)
gcloud compute instances create test-non-compliant \
  --zone=us-central1-a \
  --machine-type=e2-micro
```

### 2. Monitor Asset Changes

Check that the asset feed is working:

```bash
# List asset feeds
gcloud asset feeds list --organization=YOUR_ORG_ID

# Check Pub/Sub messages
gcloud pubsub subscriptions create test-sub --topic=ASSET_TOPIC_NAME
gcloud pubsub subscriptions pull test-sub --limit=5
```

### 3. Verify BigQuery Data

Query the compliance table:

```sql
SELECT 
  resource_type,
  compliant,
  COUNT(*) as count
FROM `PROJECT_ID.DATASET_ID.tag_compliance`
GROUP BY resource_type, compliant
ORDER BY resource_type, compliant;
```

### 4. Access Analytics

Use the provided BigQuery views for analysis:

- `cost_allocation_summary`: Cost data with tag attribution
- `compliance_summary`: Tag compliance metrics and trends

## Monitoring and Alerting

### Cloud Function Monitoring

Monitor function execution and errors:

```bash
# Check function logs
gcloud functions logs read TAG_COMPLIANCE_FUNCTION_NAME --limit=50

# View function metrics
gcloud functions describe TAG_COMPLIANCE_FUNCTION_NAME --region=REGION
```

### BigQuery Monitoring

Set up alerts for:

- Low compliance percentages
- Missing cost allocation data
- Unusual spending patterns

### Cloud Monitoring Integration

Create custom metrics and dashboards:

1. **Compliance Dashboard**: Track tagging compliance trends
2. **Cost Allocation Dashboard**: Visualize spending by department/project
3. **Function Health Dashboard**: Monitor function execution and errors

## Cost Optimization

### Expected Costs

The solution typically costs:

- **BigQuery**: $5-10/month for 1GB of data
- **Cloud Functions**: $1-5/month for typical execution volume
- **Cloud Storage**: $1-3/month for reports and exports
- **Pub/Sub**: $1-2/month for message processing

### Cost Reduction Tips

1. **Adjust BigQuery partitioning**: Use daily partitioning for large datasets
2. **Optimize function memory**: Start with 256MB and adjust based on usage
3. **Set up lifecycle policies**: Archive old reports to cheaper storage classes
4. **Use regional resources**: Deploy in your primary region to reduce costs

## Troubleshooting

### Common Issues

1. **Organization Policy Permission Denied**
   - Ensure you have `roles/orgpolicy.policyAdmin`
   - Set `enforce_org_policy = false` if org policies aren't needed

2. **Asset Feed Creation Failed**
   - Verify Cloud Asset Inventory API is enabled
   - Check that the Pub/Sub topic exists

3. **Function Deployment Failed**
   - Ensure Cloud Build API is enabled
   - Check function source code upload to Cloud Storage

4. **BigQuery Access Denied**
   - Verify service account has BigQuery Data Editor role
   - Check dataset IAM permissions

### Debug Commands

```bash
# Check API status
gcloud services list --enabled --filter="name:cloudasset.googleapis.com"

# Verify IAM permissions
gcloud projects get-iam-policy PROJECT_ID

# Test function manually
gcloud functions call FUNCTION_NAME --data='{}'

# Check Pub/Sub subscription
gcloud pubsub topics list
gcloud pubsub subscriptions list
```

## Security Considerations

### Data Protection

- All data is encrypted at rest and in transit
- Service accounts follow least privilege principle
- BigQuery datasets have appropriate access controls

### Access Management

- Use service accounts for automation
- Implement proper IAM role assignments
- Regular audit of permissions and access

### Compliance

- Organization policies enforce consistent tagging
- Audit logs track all configuration changes
- Billing data export includes detailed attribution

## Extending the Solution

### Custom Labels

Add additional mandatory labels by updating the `mandatory_labels` variable:

```hcl
mandatory_labels = [
  "department",
  "cost_center", 
  "environment",
  "project_code",
  "data_classification",
  "backup_required"
]
```

### Additional Asset Types

Monitor more resource types:

```hcl
monitored_asset_types = [
  "compute.googleapis.com/Instance",
  "storage.googleapis.com/Bucket",
  "container.googleapis.com/Cluster",
  "cloudsql.googleapis.com/DatabaseInstance",
  "redis.googleapis.com/Instance"
]
```

### Advanced Analytics

1. **Machine Learning**: Use Vertex AI to predict cost trends
2. **Anomaly Detection**: Implement cost anomaly detection
3. **Multi-Cloud**: Extend to include AWS and Azure costs
4. **Custom Dashboards**: Build Looker Studio dashboards

## Support and Maintenance

### Regular Tasks

1. **Review compliance reports**: Weekly review of tag compliance
2. **Update organization policies**: Adjust policies as needed
3. **Monitor costs**: Track solution costs and optimize
4. **Update dependencies**: Keep function dependencies current

### Backup and Recovery

- BigQuery datasets are automatically replicated
- Cloud Functions are stateless and easily redeployable
- Organization policies can be backed up as code

For additional support, refer to the original recipe documentation or Google Cloud documentation.