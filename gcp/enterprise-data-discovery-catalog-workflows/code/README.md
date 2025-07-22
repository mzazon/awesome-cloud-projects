# Infrastructure as Code for Enterprise Data Discovery with Data Catalog and Cloud Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Data Discovery with Data Catalog and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an automated data discovery and cataloging system that:
- Continuously scans BigQuery datasets and Cloud Storage buckets
- Automatically extracts schema and business metadata using Cloud Functions
- Applies AI-powered classification and tagging through Data Catalog
- Orchestrates discovery workflows using Cloud Workflows
- Schedules regular discovery runs with Cloud Scheduler

## Prerequisites

### Required Tools
- Google Cloud CLI (`gcloud`) installed and configured
- Terraform (for Terraform implementation) - version >= 1.0
- Bash shell (for script-based deployment)

### Required Permissions
Your Google Cloud user or service account needs the following IAM roles:
- `roles/datacatalog.admin` - Manage Data Catalog resources
- `roles/workflows.admin` - Manage Cloud Workflows
- `roles/cloudfunctions.admin` - Deploy and manage Cloud Functions
- `roles/cloudscheduler.admin` - Create and manage scheduled jobs
- `roles/bigquery.admin` - Create test datasets and query metadata
- `roles/storage.admin` - Create and manage Cloud Storage buckets
- `roles/iam.serviceAccountUser` - Use service accounts for automation

### Required APIs
The following APIs must be enabled in your Google Cloud project:
- Data Catalog API (`datacatalog.googleapis.com`)
- Cloud Workflows API (`workflows.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

### Estimated Cost
- **Monthly Cost**: $50-100 for moderate enterprise usage
- **Cost Variables**: Data volume scanned, discovery frequency, Cloud Functions execution time
- **Cost Optimization**: Adjust scheduler frequency and implement incremental discovery patterns

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Clone the repository and navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Review and customize the configuration
vim main.yaml

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/data-discovery-deployment \
    --service-account=YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --source=main.yaml \
    --input-values=project_id=YOUR_PROJECT_ID,region=us-central1

# Monitor deployment progress
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/data-discovery-deployment
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the solution
./scripts/deploy.sh

# Check deployment status
gcloud workflows list --location=$REGION
gcloud functions list --gen2 --region=$REGION
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
    required: true
  
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  
  discovery_schedule:
    description: "Cron schedule for automated discovery"
    type: string
    default: "0 2 * * *"  # Daily at 2 AM
  
  function_memory:
    description: "Memory allocation for Cloud Functions"
    type: string
    default: "1Gi"
  
  function_timeout:
    description: "Timeout for Cloud Functions in seconds"
    type: integer
    default: 540
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Scheduling options
daily_discovery_schedule = "0 2 * * *"
weekly_discovery_schedule = "0 1 * * 0"

# Function configuration
function_memory = "1Gi"
function_timeout = 540
max_function_instances = 10

# Tag templates
enable_data_classification = true
enable_quality_metrics = true

# Sample data creation
create_sample_data = true
```

### Script Configuration

Set environment variables before running scripts:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Optional customization
export FUNCTION_MEMORY="1Gi"
export FUNCTION_TIMEOUT="540"
export DISCOVERY_SCHEDULE="0 2 * * *"
export CREATE_SAMPLE_DATA="true"
```

## Post-Deployment Validation

### 1. Verify Data Catalog Setup

```bash
# Check tag templates
gcloud data-catalog tag-templates list --location=$REGION

# Verify entry groups
gcloud data-catalog entry-groups list --location=$REGION
```

### 2. Test Cloud Function

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe metadata-extractor-${RANDOM_SUFFIX} \
    --gen2 --region=$REGION --format="value(serviceConfig.uri)")

# Test function execution
curl -X POST $FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d "{\"project_id\": \"$PROJECT_ID\", \"location\": \"$REGION\"}"
```

### 3. Execute Discovery Workflow

```bash
# Trigger manual workflow execution
gcloud workflows run data-discovery-workflow-${RANDOM_SUFFIX} \
    --location=$REGION \
    --data="{\"suffix\": \"${RANDOM_SUFFIX}\"}"

# Check execution status
gcloud workflows executions list \
    --workflow=data-discovery-workflow-${RANDOM_SUFFIX} \
    --location=$REGION
```

### 4. Verify Scheduler Jobs

```bash
# List scheduled jobs
gcloud scheduler jobs list --location=$REGION

# Check job execution history
gcloud scheduler jobs describe discovery-scheduler-${RANDOM_SUFFIX} \
    --location=$REGION
```

## Accessing the Data Catalog

### Using Google Cloud Console

1. Navigate to **Data Catalog** in the Google Cloud Console
2. Use the search interface to discover cataloged assets
3. Browse by data source, sensitivity level, or department tags
4. View detailed metadata, schema information, and quality metrics

### Using Data Catalog API

```bash
# Search for specific assets
gcloud data-catalog entries search \
    --location=$REGION \
    --query="type=table AND system=bigquery"

# List entries with tags
gcloud data-catalog entries search \
    --location=$REGION \
    --query="tag:data_classification.sensitivity=CONFIDENTIAL"
```

### Using Client Libraries

```python
from google.cloud import datacatalog_v1

# Initialize client
client = datacatalog_v1.DataCatalogClient()

# Search for assets
request = datacatalog_v1.SearchCatalogRequest(
    scope=datacatalog_v1.SearchCatalogRequest.Scope(
        include_project_ids=["your-project-id"]
    ),
    query="type=table",
    page_size=10
)

# Execute search
response = client.search_catalog(request=request)
for result in response:
    print(f"Asset: {result.relative_resource_name}")
    print(f"Type: {result.search_result_type}")
```

## Monitoring and Troubleshooting

### Cloud Function Logs

```bash
# View function execution logs
gcloud functions logs read metadata-extractor-${RANDOM_SUFFIX} \
    --gen2 --region=$REGION --limit=50

# Monitor real-time logs
gcloud functions logs tail metadata-extractor-${RANDOM_SUFFIX} \
    --gen2 --region=$REGION
```

### Workflow Execution Monitoring

```bash
# List recent workflow executions
gcloud workflows executions list \
    --workflow=data-discovery-workflow-${RANDOM_SUFFIX} \
    --location=$REGION

# Get detailed execution information
gcloud workflows executions describe EXECUTION_ID \
    --workflow=data-discovery-workflow-${RANDOM_SUFFIX} \
    --location=$REGION
```

### Common Issues

**Issue**: Function timeout during large dataset discovery
**Solution**: Increase function timeout or implement pagination

```bash
gcloud functions deploy metadata-extractor-${RANDOM_SUFFIX} \
    --gen2 --timeout=600s --memory=2Gi
```

**Issue**: Rate limiting from BigQuery API
**Solution**: Implement exponential backoff in function code

**Issue**: Permission denied errors
**Solution**: Verify service account has required IAM roles

```bash
# Grant additional permissions if needed
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/datacatalog.entryGroupCreator"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/data-discovery-deployment

# Verify deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manually verify critical resources are deleted
gcloud workflows list --location=$REGION
gcloud functions list --gen2 --region=$REGION
gcloud scheduler jobs list --location=$REGION
```

### Manual Cleanup (if needed)

```bash
# Remove Data Catalog resources
gcloud data-catalog tag-templates delete data_classification --location=$REGION --quiet
gcloud data-catalog tag-templates delete data_quality --location=$REGION --quiet

# Clean up sample data
bq rm -r -f $PROJECT_ID:customer_analytics
bq rm -r -f $PROJECT_ID:hr_internal
gsutil rm -r gs://$PROJECT_ID-public-datasets
gsutil rm -r gs://$PROJECT_ID-confidential-reports
```

## Customization

### Adding Custom Tag Templates

Create additional tag templates for industry-specific metadata:

```bash
# GDPR compliance template
gcloud data-catalog tag-templates create gdpr_compliance \
    --location=$REGION \
    --display-name="GDPR Compliance" \
    --field=id=contains_pii,display-name="Contains PII",type=bool \
    --field=id=retention_period,display-name="Retention Period (Years)",type=double \
    --field=id=lawful_basis,display-name="Lawful Basis",type=string
```

### Extending Discovery Sources

Modify the Cloud Function to include additional data sources:

- Cloud SQL databases
- Cloud Firestore collections
- External data sources via connectors
- File-based data in Cloud Storage (CSV, JSON, Parquet)

### Custom Workflow Orchestration

Enhance the workflow to support:

- Conditional discovery based on data freshness
- Integration with external metadata systems
- Custom notification channels for discovery results
- Data lineage tracking and relationship mapping

## Integration Examples

### Integration with CI/CD Pipelines

```yaml
# Cloud Build configuration
steps:
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        # Trigger discovery after data pipeline deployment
        gcloud workflows run data-discovery-workflow-${_SUFFIX} \
            --location=${_REGION} \
            --data='{"trigger": "cicd", "source": "data-pipeline"}'
```

### Integration with Data Pipelines

```python
# Trigger discovery after ETL completion
from google.cloud import workflows_v1

def trigger_discovery_after_etl():
    client = workflows_v1.WorkflowsClient()
    workflow_name = f"projects/{project_id}/locations/{region}/workflows/{workflow_name}"
    
    execution = {
        "argument": json.dumps({
            "trigger": "etl_completion",
            "dataset": "processed_data"
        })
    }
    
    response = client.create_execution(
        parent=workflow_name,
        execution=execution
    )
    return response
```

## Advanced Configuration

### High-Frequency Discovery

For environments with rapidly changing data:

```bash
# Create high-frequency discovery schedule (every 4 hours)
gcloud scheduler jobs create http discovery-high-frequency \
    --location=$REGION \
    --schedule="0 */4 * * *" \
    --uri="https://workflowexecutions.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workflows/${WORKFLOW_NAME}/executions" \
    --http-method=POST \
    --headers="Content-Type=application/json" \
    --message-body='{"argument": "{\"mode\": \"incremental\"}"}'
```

### Multi-Project Discovery

Configure cross-project discovery for enterprise environments:

```bash
# Grant cross-project permissions
gcloud projects add-iam-policy-binding $TARGET_PROJECT_ID \
    --member="serviceAccount:discovery-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.metadataViewer"
```

## Security Considerations

### Data Classification Automation

The solution automatically classifies data sensitivity based on:
- Column names and data patterns
- Content sampling and analysis
- Organizational naming conventions
- Integration with external classification systems

### Access Control

- Discovery service account uses least privilege principles
- Data Catalog entries inherit source system permissions
- Tag-based access control for sensitive metadata
- Audit logging for all discovery activities

### Compliance Features

- Automatic PII detection and flagging
- Retention period tracking and enforcement
- Data lineage for compliance reporting
- Integration with governance frameworks

## Performance Optimization

### Scaling Considerations

- Function concurrency limits based on API quotas
- Parallel discovery execution for multiple data sources
- Incremental discovery to reduce processing time
- Caching strategies for frequently accessed metadata

### Cost Optimization

- Intelligent scheduling based on data change frequency
- Serverless architecture with pay-per-use pricing
- Resource optimization based on discovery patterns
- Automated cleanup of stale metadata entries

## Support and Documentation

### Additional Resources

- [Google Cloud Data Catalog Documentation](https://cloud.google.com/data-catalog/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Google Cloud Status page for service issues
3. Consult the original recipe documentation
4. Engage with Google Cloud Support for production issues

### Contributing

To improve this implementation:
1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any modifications
4. Consider security and compliance implications