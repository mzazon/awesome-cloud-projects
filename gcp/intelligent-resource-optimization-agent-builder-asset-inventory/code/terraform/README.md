# Terraform Infrastructure for GCP Intelligent Resource Optimization

This directory contains Terraform Infrastructure as Code (IaC) for deploying an intelligent resource optimization system using Vertex AI Agent Builder, Cloud Asset Inventory, BigQuery, and Cloud Scheduler.

## Architecture Overview

The solution deploys:

- **BigQuery Dataset**: Stores and analyzes asset inventory data
- **Cloud Storage Bucket**: Staging area for Vertex AI Agent Engine
- **Cloud Function**: Triggers automated asset inventory exports
- **Cloud Scheduler**: Automates daily asset exports
- **Service Accounts**: Secure access with least privilege principles
- **BigQuery Views**: Pre-built optimization analysis queries
- **Monitoring**: Alert policies for high-impact optimization opportunities

## Prerequisites

### Required Tools

- Terraform >= 1.8.0
- Google Cloud CLI (gcloud) configured with appropriate permissions
- Access to a GCP organization for Cloud Asset Inventory

### Required Permissions

The deploying user/service account needs:

- `roles/owner` or equivalent permissions on the target project
- `roles/cloudasset.viewer` at the organization level
- `roles/resourcemanager.projectIamAdmin` for service account management
- `roles/bigquery.admin` for BigQuery resource creation
- `roles/storage.admin` for Cloud Storage bucket creation

### Required APIs

The following APIs will be enabled automatically (if `enable_apis = true`):

- Cloud Asset Inventory API (`cloudasset.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)

## Quick Start

### 1. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id       = "your-project-id"
organization_id  = "your-organization-id"
region          = "us-central1"

# Optional customizations
dataset_name         = "asset_optimization_custom"
bucket_name_prefix   = "my-optimizer"
environment         = "production"
export_schedule     = "0 2 * * *"  # Daily at 2 AM
schedule_timezone   = "America/New_York"

# Vertex AI configuration
vertex_ai_model     = "gemini-1.5-pro"
agent_temperature   = 0.2
agent_max_tokens    = 2000

# Custom asset types (optional)
asset_types = [
  "compute.googleapis.com/Instance",
  "compute.googleapis.com/Disk",
  "storage.googleapis.com/Bucket",
  "container.googleapis.com/Cluster",
  "sqladmin.googleapis.com/Instance"
]
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 3. Verify Deployment

```bash
# Check BigQuery dataset
bq ls -d YOUR_PROJECT_ID:asset_optimization_SUFFIX

# Verify Cloud Function
gcloud functions describe asset-export-trigger-SUFFIX --region=us-central1

# Check Cloud Scheduler job
gcloud scheduler jobs list --location=us-central1
```

## Configuration Variables

### Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `project_id` | GCP project ID for deployment | `string` |
| `organization_id` | GCP organization ID for asset inventory | `string` |

### Optional Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `region` | GCP region for resources | `"us-central1"` | `string` |
| `zone` | GCP zone for resources | `"us-central1-a"` | `string` |
| `dataset_name` | BigQuery dataset name prefix | `"asset_optimization"` | `string` |
| `bucket_name_prefix` | Storage bucket name prefix | `"resource-optimizer"` | `string` |
| `export_schedule` | Cron schedule for exports | `"0 2 * * *"` | `string` |
| `schedule_timezone` | Timezone for scheduler | `"America/New_York"` | `string` |
| `vertex_ai_model` | Vertex AI model for agent | `"gemini-1.5-pro"` | `string` |
| `agent_temperature` | AI agent temperature setting | `0.2` | `number` |
| `agent_max_tokens` | Maximum tokens for agent | `2000` | `number` |
| `environment` | Environment tag | `"production"` | `string` |
| `retention_days` | BigQuery data retention | `90` | `number` |
| `enable_apis` | Auto-enable required APIs | `true` | `bool` |

## Post-Deployment Steps

### 1. Deploy Vertex AI Agent

After Terraform deployment, deploy the Vertex AI Agent using the Python SDK:

```bash
# Navigate to the agent directory
cd agent/

# Install dependencies
pip install -r requirements.txt

# Deploy the agent
python3 -c "
import vertexai
from vertexai import agent_engines
from optimization_agent import agent

# Initialize Vertex AI
vertexai.init(
    project='YOUR_PROJECT_ID',
    location='us-central1',
    staging_bucket='gs://YOUR_BUCKET_NAME'
)

# Deploy the agent
remote_agent = agent_engines.create(
    agent,
    requirements=['google-cloud-aiplatform[agent_engines,langchain]', 'google-cloud-bigquery', 'pandas'],
    display_name='resource-optimization-agent'
)

print(f'Agent deployed: {remote_agent.resource_name}')
"
```

### 2. Trigger Initial Asset Export

```bash
# Get the Cloud Function URL from Terraform output
FUNCTION_URL=$(terraform output -raw asset_export_function_url)

# Trigger initial export
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "organization_id": "YOUR_ORG_ID",
    "project_id": "YOUR_PROJECT_ID",
    "dataset_name": "DATASET_NAME"
  }' \
  "$FUNCTION_URL"
```

### 3. Verify Data Population

```bash
# Check asset inventory data
bq query --use_legacy_sql=false \
"SELECT COUNT(*) as total_assets FROM \`YOUR_PROJECT.DATASET.asset_inventory\`"

# Test optimization analysis
bq query --use_legacy_sql=false \
"SELECT optimization_category, COUNT(*) FROM \`YOUR_PROJECT.DATASET.resource_optimization_analysis\` GROUP BY optimization_category"
```

## Monitoring and Alerting

### Built-in Monitoring

The deployment includes:

- **Alert Policy**: Monitors for high optimization scores (>10 high-priority resources)
- **Function Monitoring**: Cloud Function execution logs and metrics
- **Scheduler Monitoring**: Cloud Scheduler job success/failure tracking

### Custom Monitoring

Add notification channels to the monitoring alert policy:

```hcl
# In terraform.tfvars
monitoring_notification_channels = [
  "projects/YOUR_PROJECT/notificationChannels/CHANNEL_ID"
]
```

### Viewing Logs

```bash
# Cloud Function logs
gcloud functions logs read asset-export-trigger-SUFFIX --region=us-central1

# Cloud Scheduler logs
gcloud logging read "resource.type=gce_instance AND logName=projects/YOUR_PROJECT/logs/cloudscheduler.googleapis.com%2Fexecutions"

# BigQuery job logs
gcloud logging read "resource.type=bigquery_resource"
```

## BigQuery Analysis Queries

### Top Optimization Opportunities

```sql
SELECT 
  optimization_category,
  resource_count,
  avg_optimization_score,
  total_impact_score,
  category_recommendation
FROM `YOUR_PROJECT.DATASET.cost_impact_summary`
ORDER BY total_impact_score DESC
LIMIT 10;
```

### High Priority Resources

```sql
SELECT 
  name,
  asset_type,
  optimization_category,
  optimization_score,
  optimization_recommendation
FROM `YOUR_PROJECT.DATASET.resource_optimization_analysis`
WHERE optimization_score >= 70
ORDER BY optimization_score DESC
LIMIT 20;
```

### Cost Savings Analysis

```sql
SELECT 
  optimization_category,
  COUNT(*) as resource_count,
  AVG(optimization_score) as avg_score,
  CASE optimization_category
    WHEN 'Idle Compute' THEN COUNT(*) * 50
    WHEN 'Unattached Storage' THEN COUNT(*) * 20
    WHEN 'Idle Cluster' THEN COUNT(*) * 200
    ELSE COUNT(*) * 10
  END as estimated_monthly_savings_usd
FROM `YOUR_PROJECT.DATASET.resource_optimization_analysis`
GROUP BY optimization_category
ORDER BY estimated_monthly_savings_usd DESC;
```

## Troubleshooting

### Common Issues

1. **Permission Denied for Organization Assets**
   - Ensure the service account has `roles/cloudasset.viewer` at organization level
   - Verify organization ID is correct

2. **BigQuery Export Failures**
   - Check Cloud Function logs for detailed error messages
   - Verify BigQuery dataset exists and service account has write permissions

3. **Cloud Scheduler Not Triggering**
   - Verify scheduler job is enabled: `gcloud scheduler jobs describe JOB_NAME --location=REGION`
   - Check timezone configuration

4. **Vertex AI Agent Deployment Issues**
   - Ensure staging bucket exists and is accessible
   - Verify Vertex AI API is enabled
   - Check agent requirements.txt for compatibility

### Debug Commands

```bash
# Check service account permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID

# Test Cloud Function locally
functions-framework --target=trigger_asset_export --debug

# Validate BigQuery schema
bq show --schema --format=prettyjson YOUR_PROJECT:DATASET.TABLE

# Test asset export API directly
gcloud asset export --organization=ORG_ID --content-type=resource --output-bigquery-force --bigquery-table=projects/PROJECT/datasets/DATASET/tables/TABLE
```

## Cleanup

To remove all deployed resources:

```bash
# Destroy Terraform-managed resources
terraform destroy

# Manual cleanup (if needed)
# - Delete Vertex AI Agent through console or API
# - Remove any remaining Cloud Storage objects
# - Clean up Cloud Logging sinks (if created)
```

## Security Considerations

### Least Privilege Access

- Service accounts have minimal required permissions
- IAM roles are scoped to specific resources
- BigQuery dataset access is limited to service accounts

### Data Protection

- BigQuery dataset has retention policies
- Cloud Storage bucket uses uniform bucket-level access
- Asset inventory data is encrypted at rest

### Network Security

- Cloud Function uses HTTPS endpoints
- BigQuery queries use secure connections
- Service-to-service communication is encrypted

## Cost Optimization

### Resource Sizing

- Cloud Function: 256MB memory (adjust based on usage)
- BigQuery: Pay-per-query pricing
- Cloud Storage: Standard class with lifecycle policies

### Cost Monitoring

- Set up billing alerts for the project
- Monitor BigQuery query costs
- Review Cloud Function invocation patterns

### Optimization Tips

- Adjust export schedule based on data freshness needs
- Use BigQuery clustering and partitioning
- Implement data lifecycle policies

## Support

For issues with this infrastructure:

1. Review Terraform state and outputs
2. Check Google Cloud Console for resource status
3. Examine service logs for error details
4. Consult the original recipe documentation
5. Review Google Cloud documentation for individual services

## Version History

- **v1.0**: Initial Terraform implementation
- Support for all core recipe functionality
- Production-ready configuration with monitoring
- Comprehensive documentation and examples