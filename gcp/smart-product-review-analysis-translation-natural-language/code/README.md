# Infrastructure as Code for Smart Product Review Analysis with Translation and Natural Language AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Product Review Analysis with Translation and Natural Language AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active GCP project with billing enabled
- Appropriate permissions for the following services:
  - Cloud Functions
  - Translation API
  - Natural Language AI API
  - BigQuery
  - Cloud Build
  - Cloud IAM
- For Terraform: Terraform >= 1.0 installed
- For Infrastructure Manager: gcloud CLI >= 400.0.0

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/review-analysis \
    --service-account="projects/PROJECT_ID/serviceAccounts/SERVICE_ACCOUNT" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/review-analysis
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# - Enable required APIs
# - Create BigQuery dataset and table
# - Deploy Cloud Function
# - Configure IAM permissions
# - Provide testing instructions
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `terraform.tfvars` file in the `infrastructure-manager/` directory:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
function_name          = "review-analysis"
dataset_name          = "product_reviews"
function_memory       = "512MB"
function_timeout      = "60s"
function_runtime      = "python312"
```

### Terraform Variables

Use variables in the `terraform/` directory:

```bash
# Using variable file
terraform apply -var-file="custom.tfvars"

# Using command line variables
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="function_memory=1024MB" \
    -var="dataset_location=US"
```

### Bash Script Environment Variables

Set these environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"           # Required
export REGION="us-central1"                   # Required
export ZONE="us-central1-a"                  # Optional
export FUNCTION_MEMORY="512MB"               # Optional
export FUNCTION_TIMEOUT="60s"               # Optional
export DATASET_LOCATION="US"                # Optional
```

## Testing the Deployment

After successful deployment, test the review analysis pipeline:

1. **Get the Cloud Function URL**:
   ```bash
   # Using gcloud
   export FUNCTION_URL=$(gcloud functions describe review-analysis \
       --region=us-central1 \
       --format="value(httpsTrigger.url)")
   
   # Or from Terraform output
   terraform output function_url
   ```

2. **Test with a sample review**:
   ```bash
   curl -X POST \
       -H "Content-Type: application/json" \
       -d '{
         "review_id": "test_001",
         "review_text": "Este producto es excelente. La calidad es muy buena.",
         "dataset_id": "product_reviews"
       }' \
       "${FUNCTION_URL}"
   ```

3. **Query the results in BigQuery**:
   ```bash
   bq query --use_legacy_sql=false \
       "SELECT * FROM \`${PROJECT_ID}.product_reviews.review_analysis\` LIMIT 5"
   ```

## Architecture Components

The infrastructure creates the following resources:

### Core Services
- **Cloud Function**: Serverless function for processing reviews
- **BigQuery Dataset**: Data warehouse for analytics
- **BigQuery Table**: Structured storage for review analysis results

### APIs and Services
- Translation API (automatically enabled)
- Natural Language AI API (automatically enabled)
- Cloud Functions API (automatically enabled)
- BigQuery API (automatically enabled)
- Cloud Build API (automatically enabled)

### IAM and Security
- Service account for Cloud Function execution
- IAM roles for BigQuery access
- IAM roles for Translation and Natural Language APIs
- Least privilege access principles

### Monitoring and Logging
- Cloud Functions logging (automatic)
- BigQuery audit logs (automatic)
- API usage metrics (automatic)

## Cost Considerations

This infrastructure operates on a pay-per-use model:

- **Cloud Functions**: Charged per invocation and compute time
- **Translation API**: $20 per million characters
- **Natural Language API**: $1-2 per 1000 text records
- **BigQuery**: $5 per TB stored, $5 per TB queried
- **Cloud Build**: $0.003 per build minute (for deployments)

**Estimated monthly cost for moderate usage** (1000 reviews/month): $15-25

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/review-analysis

# Confirm deletion
gcloud infra-manager deployments list --location=REGION
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# - Delete Cloud Function
# - Remove BigQuery dataset and tables
# - Clean up IAM bindings
# - Provide confirmation of cleanup
```

### Manual Cleanup Verification

After running cleanup, verify resources are removed:

```bash
# Check Cloud Functions
gcloud functions list --regions=us-central1

# Check BigQuery datasets
bq ls

# Check enabled APIs (optional - these can remain enabled)
gcloud services list --enabled
```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Ensure you have necessary roles
   gcloud projects add-iam-policy-binding PROJECT_ID \
       --member="user:your-email@domain.com" \
       --role="roles/editor"
   ```

2. **API Not Enabled**:
   ```bash
   # Enable required APIs manually
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable translate.googleapis.com
   gcloud services enable language.googleapis.com
   gcloud services enable bigquery.googleapis.com
   ```

3. **Function Deployment Fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   gcloud builds log BUILD_ID
   ```

4. **BigQuery Access Issues**:
   ```bash
   # Verify dataset exists and permissions
   bq ls
   bq show dataset_name
   ```

### Getting Help

- **GCP Documentation**: [Cloud Functions](https://cloud.google.com/functions/docs), [BigQuery](https://cloud.google.com/bigquery/docs)
- **API References**: [Translation API](https://cloud.google.com/translate/docs), [Natural Language API](https://cloud.google.com/natural-language/docs)
- **Infrastructure Manager**: [Documentation](https://cloud.google.com/infrastructure-manager/docs)
- **Terraform Google Provider**: [Registry Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Customization

### Adding New Languages

To support additional languages, modify the Cloud Function code to handle specific language pairs or add language-specific processing logic.

### Scaling for High Volume

For production workloads processing thousands of reviews:

1. **Increase Function Resources**:
   ```hcl
   function_memory = "2048MB"
   function_timeout = "120s"
   ```

2. **Enable BigQuery Streaming Inserts**:
   Modify the function to use streaming inserts for real-time analytics.

3. **Add Error Handling**:
   Implement retry logic and dead letter queues for failed processing.

### Integration Options

- **Pub/Sub Integration**: Add Pub/Sub triggers for event-driven processing
- **Cloud Storage**: Store raw reviews in Cloud Storage before processing
- **Dataflow**: Use Dataflow for batch processing of historical reviews
- **Looker Studio**: Connect BigQuery to Looker Studio for visual analytics

## Security Best Practices

The infrastructure implements several security measures:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **VPC Security**: Functions run in Google-managed VPC with secure defaults
- **Data Encryption**: All data encrypted in transit and at rest
- **API Security**: Functions use Google Cloud authentication
- **Audit Logging**: All API calls and data access logged automatically

For additional security in production:

- Enable VPC Service Controls
- Implement customer-managed encryption keys (CMEK)
- Add API Gateway for rate limiting and authentication
- Enable Security Command Center for monitoring

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Status page for service issues
3. Consult provider documentation links above
4. Review Cloud Console error logs and monitoring dashboards

## Version Information

- **Infrastructure Manager**: Compatible with Google Cloud Infrastructure Manager
- **Terraform**: Requires Terraform >= 1.0, Google Provider >= 4.0
- **GCP APIs**: Uses current stable API versions
- **Function Runtime**: Python 3.12 (latest supported runtime)