# Infrastructure as Code for Carbon Footprint Monitoring with Cloud Asset Inventory and Vertex AI Agents

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Carbon Footprint Monitoring with Cloud Asset Inventory and Vertex AI Agents".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for manual deployment

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0+)
- Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Cloud Asset Inventory Admin
  - BigQuery Admin
  - Pub/Sub Admin
  - Vertex AI Administrator
  - Cloud Monitoring Editor
  - Storage Admin
  - Project Editor (or custom role with equivalent permissions)
- Terraform 1.5+ (for Terraform implementation)
- Basic understanding of sustainability metrics and carbon footprint monitoring

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/carbon-monitoring \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/carbon-monitoring
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# The script will guide you through the deployment process
```

## Configuration

### Required Variables

The following variables need to be configured for deployment:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `dataset_name` | BigQuery dataset name | `carbon_footprint_analytics` | No |
| `agent_name` | Vertex AI agent name | `sustainability-advisor` | No |
| `bucket_prefix` | Storage bucket name prefix | `carbon-data` | No |
| `topic_prefix` | Pub/Sub topic name prefix | `asset-changes` | No |

### Environment Setup

Before deployment, ensure your environment is properly configured:

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set default project
gcloud config set project $PROJECT_ID

# Verify permissions
gcloud projects get-iam-policy $PROJECT_ID
```

## Architecture Components

This infrastructure creates the following resources:

- **BigQuery Dataset**: Central data warehouse for carbon analytics
- **Cloud Asset Inventory Feed**: Real-time asset change tracking
- **Pub/Sub Topic**: Event streaming for asset changes
- **Cloud Storage Bucket**: Data storage for AI agent and reports
- **Vertex AI Agent**: Intelligent sustainability advisor
- **Cloud Monitoring**: Custom metrics and alerting
- **IAM Roles**: Least-privilege service account permissions

## Post-Deployment Configuration

After successful deployment, complete these steps:

1. **Verify Data Flow**:
   ```bash
   # Check BigQuery dataset creation
   bq ls $PROJECT_ID:carbon_footprint_analytics
   
   # Verify asset inventory feed
   gcloud asset feeds list --project=$PROJECT_ID
   ```

2. **Test AI Agent**:
   ```bash
   # Query the sustainability agent
   gcloud alpha ai agents query sustainability-advisor \
       --region=$REGION \
       --query="What are the current carbon footprint trends?"
   ```

3. **Configure Monitoring**:
   - Access Cloud Monitoring console
   - Review custom carbon emission metrics
   - Configure alert notification channels

## Monitoring and Maintenance

### Health Checks

Monitor the system health using these commands:

```bash
# Check BigQuery data ingestion
bq query --use_legacy_sql=false \
"SELECT COUNT(*) as total_records, 
 MAX(timestamp) as latest_update 
 FROM \`$PROJECT_ID.carbon_footprint_analytics.asset_inventory\`"

# Verify Pub/Sub message flow
gcloud pubsub topics describe $TOPIC_NAME

# Check AI agent status
gcloud alpha ai agents describe sustainability-advisor --region=$REGION
```

### Cost Optimization

Expected monthly costs (approximate):

- BigQuery: $10-30 (depending on data volume)
- Vertex AI Agent: $20-50 (based on query frequency)
- Cloud Storage: $5-15 (lifecycle policies applied)
- Other services: $5-10
- **Total**: $40-105/month

### Security Considerations

This deployment implements several security best practices:

- Least-privilege IAM roles for all service accounts
- Encrypted data at rest in BigQuery and Cloud Storage
- VPC-native networking where applicable
- Audit logging enabled for all critical operations
- Storage bucket lifecycle policies for cost optimization

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**:
   ```bash
   # Enable required APIs
   gcloud services enable cloudasset.googleapis.com \
                         bigquery.googleapis.com \
                         pubsub.googleapis.com \
                         aiplatform.googleapis.com \
                         monitoring.googleapis.com \
                         carbonfootprint.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check current user permissions
   gcloud projects get-iam-policy $PROJECT_ID \
       --flatten="bindings[].members" \
       --format="table(bindings.role)" \
       --filter="bindings.members:$(gcloud config get-value account)"
   ```

3. **Vertex AI Agent Creation Failed**:
   - Ensure Vertex AI API is enabled
   - Verify region support for Vertex AI agents
   - Check quota limits in the console

4. **BigQuery Data Not Appearing**:
   - Verify asset inventory feed is active
   - Check Pub/Sub topic subscription
   - Ensure proper IAM permissions for Cloud Asset service account

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/carbon-monitoring
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Remove BigQuery dataset
bq rm -r -f $PROJECT_ID:carbon_footprint_analytics

# Delete storage bucket
gsutil -m rm -r gs://carbon-data-*

# Remove asset inventory feed
gcloud asset feeds delete carbon-monitoring-feed --project=$PROJECT_ID

# Delete Pub/Sub topic
gcloud pubsub topics delete asset-changes-*

# Remove Vertex AI agent
gcloud alpha ai agents delete sustainability-advisor --region=$REGION
```

## Customization

### Extending the Solution

1. **Multi-Region Deployment**: Modify variables to deploy across multiple regions
2. **Custom Metrics**: Add additional carbon footprint KPIs in monitoring configuration
3. **Enhanced AI Agent**: Extend agent instructions for specific industry requirements
4. **Integration**: Connect with external ESG reporting tools

### Configuration Examples

```bash
# Example terraform.tfvars for production
project_id = "my-production-project"
region = "us-central1"
dataset_name = "prod_carbon_analytics"
agent_name = "prod-sustainability-advisor"
enable_monitoring_alerts = true
bucket_lifecycle_enabled = true
```

## Support and Documentation

- [Original Recipe Documentation](../carbon-footprint-monitoring-asset-inventory-vertex-ai-agents.md)
- [Google Cloud Carbon Footprint](https://cloud.google.com/carbon-footprint)
- [Cloud Asset Inventory](https://cloud.google.com/asset-inventory/docs)
- [Vertex AI Agent Builder](https://cloud.google.com/vertex-ai/docs/agent-builder)
- [BigQuery Analytics](https://cloud.google.com/bigquery/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's official documentation for the respective services.

## Contributing

To improve this infrastructure code:

1. Follow Google Cloud best practices
2. Test all changes in a development environment
3. Update documentation for any new features
4. Ensure backward compatibility when possible
5. Add appropriate error handling and validation