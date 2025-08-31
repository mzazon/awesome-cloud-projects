# Infrastructure as Code for Content Performance Optimization using Gemini and Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Performance Optimization using Gemini and Analytics".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with GCP provider
- **Scripts**: Bash deployment and cleanup scripts

## Solution Overview

This solution creates an intelligent content optimization system that automatically analyzes performance data in BigQuery, uses Gemini 2.5 Flash to identify improvement patterns, and generates data-driven content variations. The infrastructure includes:

- BigQuery dataset and tables for content performance analytics
- Cloud Functions for automated content analysis
- Vertex AI integration with Gemini 2.5 Flash for intelligent insights
- Cloud Storage for content assets and analysis results
- BigQuery views for performance metrics and rankings

## Prerequisites

### General Requirements
- Google Cloud Project with billing enabled
- gcloud CLI installed and configured (or use Cloud Shell)
- Appropriate IAM permissions for:
  - BigQuery Admin
  - Cloud Functions Developer
  - Vertex AI User
  - Storage Admin
  - Service Account Admin

### Required APIs
The following APIs must be enabled in your project:
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

### Cost Estimation
- **Vertex AI**: $10-15/month for moderate usage
- **BigQuery**: $3-7/month for data storage and queries
- **Cloud Functions**: $1-3/month for invocations
- **Cloud Storage**: $1-2/month for content assets
- **Total**: Approximately $15-25/month

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable cloudfunctions.googleapis.com \
    aiplatform.googleapis.com \
    bigquery.googleapis.com \
    storage.googleapis.com \
    cloudbuild.googleapis.com

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/content-optimization \
    --local-source=. \
    --inputs-file=main.yaml

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/content-optimization
```

### Using Terraform

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable cloudfunctions.googleapis.com \
    aiplatform.googleapis.com \
    bigquery.googleapis.com \
    storage.googleapis.com \
    cloudbuild.googleapis.com

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=${PROJECT_ID}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}"

# Note the outputs for testing
terraform output
```

### Using Bash Scripts

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# The script will prompt for confirmation and handle all setup
```

## Testing the Deployment

After successful deployment, test the content analysis system:

```bash
# Get the Cloud Function URL
FUNCTION_URL=$(gcloud functions describe content-analyzer \
    --gen2 \
    --region=us-central1 \
    --format="value(serviceConfig.uri)")

# Trigger content analysis
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"trigger": "manual_analysis"}'

# Check analysis results in Cloud Storage
gsutil ls gs://content-optimization-*/analysis_results/

# Query BigQuery views
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.content_analytics.content_performance_summary\`"
```

## Validation Steps

1. **Verify BigQuery Resources**:
   ```bash
   # Check dataset
   bq ls ${PROJECT_ID}:content_analytics
   
   # Check tables and views
   bq ls ${PROJECT_ID}:content_analytics
   ```

2. **Verify Cloud Function**:
   ```bash
   # Check function status
   gcloud functions describe content-analyzer \
       --gen2 \
       --region=us-central1
   ```

3. **Verify Cloud Storage**:
   ```bash
   # List storage buckets
   gsutil ls | grep content-optimization
   ```

4. **Test Vertex AI Integration**:
   ```bash
   # Trigger analysis and check results
   curl -X POST ${FUNCTION_URL}
   sleep 30
   gsutil ls gs://content-optimization-*/analysis_results/
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/content-optimization

# Confirm deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation and handle all cleanup
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Function
gcloud functions delete content-analyzer \
    --gen2 \
    --region=us-central1 \
    --quiet

# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:content_analytics

# Delete Cloud Storage bucket
gsutil -m rm -r gs://content-optimization-*

# Disable APIs (optional)
gcloud services disable cloudfunctions.googleapis.com \
    aiplatform.googleapis.com \
    bigquery.googleapis.com \
    storage.googleapis.com \
    cloudbuild.googleapis.com
```

## Customization

### Environment Variables

Key variables that can be customized:

- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region (default: us-central1)
- `dataset_name`: BigQuery dataset name
- `function_name`: Cloud Function name
- `bucket_name`: Cloud Storage bucket name

### Terraform Variables

Edit `terraform/variables.tf` to customize:

```hcl
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "dataset_name" {
  description = "BigQuery dataset name"
  type        = string
  default     = "content_analytics"
}
```

### Infrastructure Manager Configuration

Edit `infrastructure-manager/main.yaml` to modify:

- Resource naming conventions
- Function memory and timeout settings
- BigQuery table schemas
- Storage bucket configurations

## Monitoring and Maintenance

### Cloud Monitoring Setup

```bash
# Create alerting policy for function errors
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/function-errors.yaml

# Set up log-based metrics
gcloud logging metrics create content_analysis_errors \
    --description="Content analysis function errors" \
    --log-filter='resource.type="cloud_function" AND severity>=ERROR'
```

### Cost Monitoring

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=YOUR_BILLING_ACCOUNT \
    --display-name="Content Optimization Budget" \
    --budget-amount=50USD \
    --threshold-rules=percent=0.9,percent=1.0
```

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # View specific build logs
   gcloud builds log BUILD_ID
   ```

2. **Vertex AI Permission Errors**:
   ```bash
   # Grant Vertex AI permissions to function service account
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="serviceAccount:${PROJECT_ID}@appspot.gserviceaccount.com" \
       --role="roles/aiplatform.user"
   ```

3. **BigQuery Access Issues**:
   ```bash
   # Grant BigQuery permissions
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="serviceAccount:${PROJECT_ID}@appspot.gserviceaccount.com" \
       --role="roles/bigquery.dataEditor"
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# For Terraform
export TF_LOG=DEBUG
terraform apply

# For gcloud commands
gcloud config set core/verbosity debug
```

## Architecture Details

The deployed infrastructure creates:

1. **BigQuery Dataset**: `content_analytics` with tables and views for performance data
2. **Cloud Function**: `content-analyzer` for automated analysis with Gemini integration
3. **Cloud Storage**: Bucket for content assets and analysis results
4. **IAM Roles**: Appropriate service account permissions
5. **BigQuery Views**: Pre-built analytics views for reporting

## Security Considerations

- Service accounts follow least-privilege principle
- Cloud Storage bucket uses uniform bucket-level access
- BigQuery dataset includes appropriate access controls
- Function environment variables are securely managed
- API access is restricted to required services only

## Performance Optimization

- Cloud Function memory optimized for workload (512MB)
- BigQuery tables use appropriate partitioning
- Storage bucket configured for regional storage class
- Vertex AI requests use efficient batching

## Support and Documentation

- **Original Recipe**: [Content Performance Optimization using Gemini and Analytics](../content-performance-optimization-gemini-analytics.md)
- **Google Cloud Documentation**: [Cloud Functions](https://cloud.google.com/functions/docs), [BigQuery](https://cloud.google.com/bigquery/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs)
- **Terraform GCP Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Infrastructure Manager**: [Documentation](https://cloud.google.com/infrastructure-manager/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the relevant provider documentation above.