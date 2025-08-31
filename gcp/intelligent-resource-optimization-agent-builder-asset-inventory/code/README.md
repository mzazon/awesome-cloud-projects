# Infrastructure as Code for Intelligent Resource Optimization with Agent Builder and Asset Inventory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Resource Optimization with Agent Builder and Asset Inventory".

## Overview

This infrastructure deploys an AI-powered resource optimization system that automatically analyzes Google Cloud resource inventory, identifies cost optimization opportunities, and provides actionable recommendations through natural language interactions. The solution combines Vertex AI Agent Builder, Cloud Asset Inventory, BigQuery, and Cloud Scheduler to create a proactive cost optimization workflow.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following components:

- **BigQuery Dataset**: Central repository for asset metadata and analytics
- **Cloud Storage Bucket**: Staging bucket for Vertex AI Agent Engine
- **Cloud Asset Inventory Export**: Automated asset metadata collection
- **Vertex AI Agent Engine**: AI-powered natural language interface
- **Cloud Scheduler Jobs**: Automated daily asset exports
- **Service Accounts**: Secure access management for automation
- **IAM Policies**: Least-privilege access controls
- **Optimization Views**: SQL analytics for cost optimization insights

## Prerequisites

### Required Permissions

- **Organization Level**: `cloudasset.viewer` role for comprehensive asset inventory access
- **Project Level**: `Editor` or equivalent permissions for resource creation
- **Vertex AI**: `aiplatform.user` role for Agent Engine deployment

### Required APIs

The following APIs must be enabled in your project:

- Cloud Asset Inventory API (`cloudasset.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)

### Tools and CLI

- Google Cloud CLI installed and authenticated
- Organization-level permissions for Cloud Asset Inventory
- Python 3.8+ with pip for Agent Engine deployment
- Terraform 1.0+ (for Terraform implementation)

### Cost Considerations

- **Estimated monthly cost**: $25-50 for regular monitoring and analysis
- **BigQuery**: Storage and query costs for asset data
- **Vertex AI Agent Engine**: Compute costs for AI queries
- **Cloud Storage**: Minimal costs for staging bucket
- **Cloud Scheduler**: Minimal costs for automated jobs

## Quick Start

### Using Infrastructure Manager

```bash
# Clone or download the infrastructure code
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ORGANIZATION_ID="your-organization-id"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/resource-optimization \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/resource-optimization" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION},organization_id=${ORGANIZATION_ID}"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" \
               -var="region=us-central1" \
               -var="organization_id=your-organization-id"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" \
                -var="region=us-central1" \
                -var="organization_id=your-organization-id"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ORGANIZATION_ID="your-organization-id"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud Project ID | `my-optimization-project` |
| `region` | Primary deployment region | `us-central1` |
| `organization_id` | Organization ID for asset inventory | `123456789012` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `dataset_name` | BigQuery dataset name | `asset_optimization` |
| `bucket_name` | Storage bucket name | `resource-optimizer-${random}` |
| `job_schedule` | Cron schedule for exports | `0 2 * * *` |
| `asset_types` | Asset types to monitor | See defaults in code |

## Post-Deployment Setup

### 1. Initial Asset Export

After deployment, trigger the first asset export:

```bash
# Trigger initial export manually
gcloud asset export \
    --organization=${ORGANIZATION_ID} \
    --content-type=resource \
    --bigquery-table=projects/${PROJECT_ID}/datasets/asset_optimization/tables/asset_inventory \
    --output-bigquery-force
```

### 2. Test Agent Functionality

```bash
# Test the deployed AI agent
python3 -c "
import vertexai
from vertexai import agent_engines

vertexai.init(project='${PROJECT_ID}', location='${REGION}')
agent = agent_engines.list()[0]  # Get first agent
response = agent.query(input='What are the top optimization opportunities?')
print(response)
"
```

### 3. Verify Data Pipeline

```bash
# Check BigQuery data
bq query --use_legacy_sql=false \
"SELECT COUNT(*) as asset_count FROM \`${PROJECT_ID}.asset_optimization.asset_inventory\`"
```

## Usage Examples

### Query Optimization Opportunities

```bash
# High-priority optimizations
python3 -c "
import vertexai
from vertexai import agent_engines

vertexai.init(project='${PROJECT_ID}', location='${REGION}')
agent = agent_engines.get('projects/${PROJECT_ID}/locations/${REGION}/agents/resource-optimization-agent')

response = agent.query(
    input='Show me resources with optimization scores above 70 and provide cost-saving recommendations'
)
print(response)
"
```

### Analyze Resource Categories

```bash
# Resource category analysis
bq query --use_legacy_sql=false \
"SELECT 
  optimization_category,
  COUNT(*) as resource_count,
  AVG(optimization_score) as avg_score
FROM \`${PROJECT_ID}.asset_optimization.resource_optimization_analysis\`
GROUP BY optimization_category
ORDER BY avg_score DESC"
```

### Monitor Idle Resources

```bash
# Identify idle compute instances
bq query --use_legacy_sql=false \
"SELECT name, location, age_days, optimization_score
FROM \`${PROJECT_ID}.asset_optimization.resource_optimization_analysis\`
WHERE optimization_category = 'Idle Compute'
ORDER BY optimization_score DESC
LIMIT 10"
```

## Monitoring and Maintenance

### Check Scheduler Status

```bash
# Verify scheduled jobs are running
gcloud scheduler jobs list --location=${REGION}
```

### Monitor Data Freshness

```bash
# Check latest asset data timestamp
bq query --use_legacy_sql=false \
"SELECT MAX(update_time) as latest_update
FROM \`${PROJECT_ID}.asset_optimization.asset_inventory\`"
```

### Agent Health Check

```bash
# Test agent responsiveness
python3 -c "
import vertexai
from vertexai import agent_engines

vertexai.init(project='${PROJECT_ID}', location='${REGION}')
agents = agent_engines.list()
print(f'Active agents: {len(agents)}')
for agent in agents:
    print(f'Agent: {agent.display_name}, Status: {agent.state}')
"
```

## Troubleshooting

### Common Issues

1. **Asset Export Failures**
   ```bash
   # Check organization permissions
   gcloud asset export --organization=${ORGANIZATION_ID} --dry-run
   ```

2. **BigQuery Access Errors**
   ```bash
   # Verify dataset permissions
   bq show ${PROJECT_ID}:asset_optimization
   ```

3. **Agent Deployment Issues**
   ```bash
   # Check Vertex AI API status
   gcloud services list --enabled --filter="name:aiplatform.googleapis.com"
   ```

4. **Scheduler Job Failures**
   ```bash
   # Check job execution logs
   gcloud scheduler jobs describe asset-export-job --location=${REGION}
   ```

### Performance Optimization

- **BigQuery Costs**: Use table partitioning and clustering for large datasets
- **Agent Response Time**: Optimize BigQuery queries used by the agent
- **Storage Costs**: Implement lifecycle policies for the staging bucket

## Security Considerations

### IAM Best Practices

- Service accounts use minimal required permissions
- Asset export service account has read-only access
- Agent service account limited to BigQuery data access
- Regular audit of IAM bindings recommended

### Data Protection

- Asset inventory data contains metadata only, not application data
- BigQuery dataset can be encrypted with customer-managed keys
- Agent queries logged for audit purposes
- Automated export schedule limits data exposure window

### Access Control

- Organization-level asset access requires explicit permission
- Agent access controlled through Vertex AI IAM
- BigQuery access follows principle of least privilege
- Scheduler jobs use dedicated service accounts

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/resource-optimization
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" \
                 -var="region=${REGION}" \
                 -var="organization_id=${ORGANIZATION_ID}"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify BigQuery dataset removal
bq ls --project_id=${PROJECT_ID}

# Verify storage bucket removal
gsutil ls -p ${PROJECT_ID}

# Verify agent removal
gcloud ai agents list --location=${REGION}

# Verify scheduler jobs removal
gcloud scheduler jobs list --location=${REGION}
```

## Customization

### Modifying Asset Types

Edit the `asset_types` variable to focus on specific resource types:

```bash
# Example: Focus on compute and storage only
export ASSET_TYPES="compute.googleapis.com/Instance,storage.googleapis.com/Bucket"
```

### Custom Optimization Scoring

Modify the optimization analysis views in BigQuery to implement custom scoring logic:

```sql
-- Example: Custom scoring for your organization
CASE
  WHEN cost_per_month > 1000 AND utilization < 0.3 THEN 95
  WHEN age_days > 90 AND status = 'TERMINATED' THEN 85
  ELSE 20
END as custom_optimization_score
```

### Agent Behavior Customization

Modify the agent implementation to include custom tools and analysis:

```python
# Add custom analysis tools
def custom_cost_analysis():
    # Your custom cost analysis logic
    pass

# Update agent with custom tools
agent = agent_engines.LangchainAgent(
    model="gemini-1.5-pro",
    tools=[query_optimization_data, custom_cost_analysis],
    # ... other configurations
)
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions workflow
name: Deploy Resource Optimization
on:
  push:
    branches: [main]
    paths: ['infrastructure/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: google-github-actions/setup-gcloud@v1
      - name: Deploy Infrastructure
        run: |
          cd infrastructure-manager/
          gcloud infra-manager deployments apply ...
```

### Alerting Integration

```bash
# Example Cloud Monitoring alert policy
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring-policy.yaml
```

### Dashboard Integration

```bash
# Create custom dashboard for optimization metrics
gcloud monitoring dashboards create \
    --config-from-file=optimization-dashboard.json
```

## Support and Documentation

### Related Documentation

- [Vertex AI Agent Engine Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/agent-engine/overview)
- [Cloud Asset Inventory Documentation](https://cloud.google.com/asset-inventory/docs/overview)
- [BigQuery Asset Inventory Integration](https://cloud.google.com/asset-inventory/docs/export-bigquery)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

- For infrastructure issues: Check the deployment logs in Cloud Console
- For agent issues: Review Vertex AI logs and quotas
- For asset export issues: Verify organization-level permissions
- For cost optimization questions: Consult the original recipe documentation

### Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Update documentation as needed
4. Follow Google Cloud IaC best practices

## License

This infrastructure code is provided as part of the cloud recipes project. Refer to the main repository license for terms and conditions.