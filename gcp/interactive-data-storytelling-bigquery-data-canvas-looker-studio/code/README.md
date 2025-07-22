# Infrastructure as Code for Interactive Data Storytelling with BigQuery Data Canvas and Looker Studio

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Interactive Data Storytelling with BigQuery Data Canvas and Looker Studio".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Required APIs enabled:
  - BigQuery API
  - Cloud Functions API
  - Cloud Scheduler API
  - Vertex AI API
  - Cloud Storage API
- Appropriate IAM permissions for:
  - BigQuery dataset and table creation
  - Cloud Functions deployment
  - Cloud Scheduler job creation
  - Vertex AI model access
  - IAM service account management
- Estimated cost: $10-20 for BigQuery queries, Vertex AI usage, and Looker Studio Pro features during testing

## Architecture Overview

This implementation creates an intelligent data storytelling pipeline that:

- Stores retail analytics data in BigQuery
- Uses BigQuery Data Canvas for AI-powered data exploration
- Leverages Vertex AI Gemini for automated insight generation
- Publishes interactive reports to Looker Studio via Cloud Functions
- Automates report generation using Cloud Scheduler

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/data-storytelling \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/recipes" \
    --git-source-directory="gcp/interactive-data-storytelling-bigquery-data-canvas-looker-studio/code/infrastructure-manager" \
    --git-source-ref="main"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/data-storytelling
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud functions list --regions=${REGION}
gcloud scheduler jobs list --location=${REGION}
```

## Configuration Options

### Terraform Variables

You can customize the deployment by setting these variables:

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: "us-central1")
- `dataset_name`: BigQuery dataset name (default: auto-generated with timestamp)
- `function_name`: Cloud Function name (default: "data-storytelling-automation")
- `schedule`: Cron schedule for automated reports (default: "0 9 * * 1-5")
- `function_memory`: Cloud Function memory allocation (default: "512MB")
- `function_timeout`: Cloud Function timeout in seconds (default: 300)

Example terraform.tfvars file:

```hcl
project_id = "my-gcp-project"
region = "us-west1"
schedule = "0 8 * * 1-7"  # Daily at 8 AM
function_memory = "1GB"
```

### Infrastructure Manager Parameters

Similar configuration options are available for Infrastructure Manager deployments through parameter files.

## Post-Deployment Steps

After successful deployment, complete these additional steps:

1. **Load Sample Data**:
   ```bash
   # The sample data is loaded automatically during deployment
   # Verify data loading
   bq query --use_legacy_sql=false "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_data\`"
   ```

2. **Test the Automation**:
   ```bash
   # Get the Cloud Function URL
   FUNCTION_URL=$(gcloud functions describe data-storytelling-automation \
       --region=${REGION} \
       --format="value(httpsTrigger.url)")
   
   # Test manual execution
   curl -X POST ${FUNCTION_URL} -H "Content-Type: application/json" -d '{"test": true}'
   ```

3. **Set Up Looker Studio Connection**:
   - Open [Looker Studio](https://lookerstudio.google.com/)
   - Create a new report
   - Connect to BigQuery
   - Select your project and the `dashboard_data` materialized view
   - Create visualizations based on the automated insights

4. **Configure Additional Security** (Optional):
   ```bash
   # Restrict Cloud Function access
   gcloud functions remove-iam-policy-binding data-storytelling-automation \
       --region=${REGION} \
       --member="allUsers" \
       --role="roles/cloudfunctions.invoker"
   
   # Grant access to specific service accounts only
   gcloud functions add-iam-policy-binding data-storytelling-automation \
       --region=${REGION} \
       --member="serviceAccount:your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
       --role="roles/cloudfunctions.invoker"
   ```

## Monitoring and Troubleshooting

### Check Cloud Function Logs

```bash
# View recent function execution logs
gcloud functions logs read data-storytelling-automation \
    --region=${REGION} \
    --limit=20

# Monitor real-time logs
gcloud functions logs tail data-storytelling-automation \
    --region=${REGION}
```

### Verify Scheduled Jobs

```bash
# Check scheduler job status
gcloud scheduler jobs describe storytelling-job-* \
    --location=${REGION}

# View execution history
gcloud logging read "resource.type=cloud_scheduler_job" \
    --limit=10 \
    --format="table(timestamp,severity,textPayload)"
```

### BigQuery Monitoring

```bash
# Check dataset and tables
bq ls ${PROJECT_ID}:${DATASET_NAME}

# View recent query jobs
bq ls -j --max_results=10

# Check materialized view refresh status
bq show --materialized_view ${PROJECT_ID}:${DATASET_NAME}.dashboard_data
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/data-storytelling

# Verify cleanup
gcloud infra-manager deployments list
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Manual verification
gcloud functions list --regions=${REGION}
gcloud scheduler jobs list --location=${REGION}
bq ls ${PROJECT_ID}:
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources:

```bash
# Delete Cloud Function
gcloud functions delete data-storytelling-automation \
    --region=${REGION} \
    --quiet

# Delete Scheduler Job
gcloud scheduler jobs delete storytelling-job-* \
    --location=${REGION} \
    --quiet

# Delete BigQuery Dataset
bq rm -r -f ${PROJECT_ID}:${DATASET_NAME}

# Delete Storage Bucket
gsutil -m rm -r gs://${PROJECT_ID}-storytelling-*

# Delete Service Account
gcloud iam service-accounts delete \
    vertex-ai-storytelling@${PROJECT_ID}.iam.gserviceaccount.com \
    --quiet
```

## Cost Management

### Estimated Costs

- **BigQuery**: $5-10/month for queries and storage
- **Cloud Functions**: $2-5/month for executions
- **Cloud Scheduler**: $0.10/month for job executions
- **Vertex AI**: $3-8/month for Gemini API calls
- **Cloud Storage**: $1-2/month for function source storage

### Cost Optimization Tips

1. **Optimize BigQuery**:
   - Use materialized views for frequently accessed data
   - Set up table expiration for temporary data
   - Monitor query costs in the console

2. **Function Optimization**:
   - Adjust memory allocation based on actual usage
   - Set appropriate timeout values
   - Monitor execution frequency

3. **Scheduling Optimization**:
   - Adjust schedule frequency based on business needs
   - Consider timezone-aware scheduling

## Customization

### Adding Custom Data Sources

Modify the Terraform configuration to include additional data sources:

```hcl
# Add external table for CSV data in Cloud Storage
resource "google_bigquery_table" "external_data" {
  dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
  table_id   = "external_sales_data"
  
  external_data_configuration {
    autodetect    = true
    source_format = "CSV"
    
    source_uris = [
      "gs://your-data-bucket/sales_data/*.csv"
    ]
  }
}
```

### Extending AI Capabilities

Enhance the Cloud Function to use additional Vertex AI models:

```python
# Add to main.py in Cloud Function
from google.cloud import aiplatform

def generate_predictions(df):
    """Add predictive analytics to insights"""
    # Initialize Vertex AI
    aiplatform.init(project=project_id, location=region)
    
    # Use AutoML for predictions
    # Implementation depends on your specific model
    pass
```

### Custom Looker Studio Templates

Create reusable Looker Studio templates:

1. Design your dashboard layout
2. Save as a template
3. Share with your team
4. Automate template application via API

## Support

### Documentation References

- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Looker Studio Documentation](https://support.google.com/looker-studio)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)

### Common Issues

1. **Permission Errors**: Ensure all required APIs are enabled and service accounts have appropriate permissions
2. **Function Timeout**: Increase timeout values for complex analytics queries
3. **BigQuery Quota**: Monitor and request quota increases for high-volume deployments
4. **Looker Studio Connection**: Verify service account permissions for BigQuery access

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's support resources.

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Update documentation as needed
4. Submit changes through your organization's process

## Security Considerations

This implementation follows Google Cloud security best practices:

- Service accounts use least privilege principles
- Network access is restricted where possible
- Data encryption is enabled by default
- IAM roles are granularly assigned
- Function access can be restricted to specific users/services

For production deployments, consider additional security measures:

- VPC Service Controls for data perimeter protection
- Customer-managed encryption keys (CMEK)
- Network security policies
- Advanced threat protection
- Compliance monitoring and reporting