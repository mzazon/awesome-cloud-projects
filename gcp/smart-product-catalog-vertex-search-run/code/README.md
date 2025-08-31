# Infrastructure as Code for Smart Product Catalog Management with Vertex AI Search and Cloud Run

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Product Catalog Management with Vertex AI Search and Cloud Run".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Compute Admin
  - Storage Admin
  - Firestore Admin
  - Discovery Engine Admin
  - Cloud Run Admin
  - Cloud Build Admin
  - Artifact Registry Admin
- Docker installed locally (for Cloud Run deployments)
- Python 3.11+ (for application code)

## Architecture Overview

This solution deploys:
- Firestore database for product storage
- Cloud Storage bucket for search data
- Vertex AI Search data store and application
- Cloud Run service with REST API
- Required IAM roles and service accounts

## Quick Start

### Using Infrastructure Manager (GCP Native)

```bash
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/smart-catalog \
    --service-account YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/smart-catalog
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_id=YOUR_PROJECT_ID" \
    -var="region=us-central1"

# Apply infrastructure
terraform apply \
    -var="project_id=YOUR_PROJECT_ID" \
    -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml`:

```yaml
project_id: "your-gcp-project-id"
region: "us-central1"
app_name: "product-catalog"
search_app_id: "catalog-search"
datastore_id: "products"
bucket_name: "your-unique-bucket-name"
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or use command-line variables:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"
app_name   = "product-catalog"

# Optional customizations
cloud_run_memory    = "1Gi"
cloud_run_cpu       = 1
cloud_run_timeout   = 300
firestore_location  = "us-central1"
storage_class       = "STANDARD"
```

### Bash Script Variables

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export APP_NAME="product-catalog-$(date +%s)"
export SEARCH_APP_ID="catalog-search-$(date +%s)"
export DATASTORE_ID="products-$(date +%s)"
```

## Deployment Process

### Step 1: Enable APIs
All implementations automatically enable required Google Cloud APIs:
- Cloud Run API
- Cloud Build API
- Firestore API
- Discovery Engine API
- Artifact Registry API

### Step 2: Create Core Infrastructure
- Firestore database in native mode
- Cloud Storage bucket with versioning
- IAM service accounts and roles

### Step 3: Deploy Search Infrastructure
- Vertex AI Search data store
- Sample product data upload
- Search application configuration

### Step 4: Deploy Application
- Cloud Run service with container
- Environment variable configuration
- Public access configuration

### Step 5: Initialize Data
- Add sample products to Firestore
- Import product data into Vertex AI Search
- Verify search indexing

## Validation & Testing

After deployment, test the solution:

```bash
# Get the Cloud Run service URL
SERVICE_URL=$(gcloud run services describe $APP_NAME \
    --region=$REGION \
    --format="value(status.url)")

# Test health endpoint
curl "$SERVICE_URL/health"

# Test product search
curl "$SERVICE_URL/search?q=wireless%20headphones&page_size=3"

# Test recommendations
curl "$SERVICE_URL/recommend?product_id=prod-001&page_size=3"
```

Expected responses:
- Health check: `{"status": "healthy", "service": "product-catalog"}`
- Search: JSON with relevant product matches
- Recommendations: JSON with similar products

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/smart-catalog \
    --delete-policy="DELETE"
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_id=YOUR_PROJECT_ID" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
./scripts/verify-cleanup.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Run service
gcloud run services delete $APP_NAME --region=$REGION --quiet

# Delete Vertex AI Search resources
gcloud alpha discovery-engine engines delete $SEARCH_APP_ID --location=global --quiet
gcloud alpha discovery-engine data-stores delete $DATASTORE_ID --location=global --quiet

# Delete Cloud Storage bucket
gsutil -m rm -r gs://$BUCKET_NAME

# Note: Firestore database deletion requires manual action in Console
echo "Delete Firestore database manually at: https://console.cloud.google.com/firestore/databases"
```

## Customization

### Adding Authentication

To secure the API endpoints, modify the Cloud Run service configuration:

```bash
# Deploy with authentication required
gcloud run deploy $APP_NAME \
    --source . \
    --platform managed \
    --region $REGION \
    --no-allow-unauthenticated  # Remove this flag from public deployment
```

### Scaling Configuration

Adjust Cloud Run scaling in `terraform/main.tf`:

```hcl
resource "google_cloud_run_service" "app" {
  # ... other configuration
  
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = "1"
        "autoscaling.knative.dev/maxScale" = "100"
        "run.googleapis.com/cpu-throttling" = "false"
      }
    }
    # ... other configuration
  }
}
```

### Custom Search Configuration

Modify Vertex AI Search settings in the data store configuration:

```yaml
# infrastructure-manager/main.yaml
search_config:
  content_config: "CONTENT_REQUIRED"
  solution_types: ["SOLUTION_TYPE_SEARCH", "SOLUTION_TYPE_RECOMMENDATION"]
  industry_vertical: "GENERIC"
```

### Adding Monitoring

Include Cloud Monitoring and logging:

```hcl
# terraform/monitoring.tf
resource "google_monitoring_alert_policy" "cloud_run_errors" {
  display_name = "Cloud Run Error Rate"
  # ... monitoring configuration
}
```

## Cost Optimization

### Resource Sizing
- **Cloud Run**: Starts with minimal resources (1 CPU, 1Gi memory)
- **Firestore**: Pay-per-operation model
- **Vertex AI Search**: Pay-per-query pricing
- **Cloud Storage**: Standard class storage

### Cost Management Tips
1. Set up budget alerts in Google Cloud Console
2. Use Cloud Run's automatic scaling to minimize idle costs
3. Monitor Vertex AI Search query volume
4. Implement request caching for frequently searched products
5. Use Cloud Storage lifecycle policies for old data

### Estimated Costs (USD per month)
- **Development/Testing**: $15-25
- **Low Traffic Production**: $50-100
- **Medium Traffic Production**: $200-500
- **High Traffic Production**: $500+

*Costs vary based on query volume, data size, and traffic patterns.*

## Troubleshooting

### Common Issues

1. **Vertex AI Search indexing delays**
   - Solution: Wait 5-10 minutes for initial indexing
   - Check: `gcloud alpha discovery-engine data-stores describe $DATASTORE_ID`

2. **Cloud Run deployment failures**
   - Check: Container logs in Cloud Console
   - Verify: Required APIs are enabled
   - Solution: Review environment variables

3. **Firestore permission errors**
   - Check: Service account IAM roles
   - Verify: Firestore database is created
   - Solution: Grant Firestore User role

4. **Search queries returning no results**
   - Check: Data import status in Discovery Engine Console
   - Verify: Sample data was uploaded to Cloud Storage
   - Solution: Re-run data import process

### Debugging Commands

```bash
# Check Cloud Run service logs
gcloud logs read "resource.type=cloud_run_revision" --limit=50

# Verify Firestore data
gcloud firestore export gs://$BUCKET_NAME/firestore-export

# Check Vertex AI Search status
gcloud alpha discovery-engine engines describe $SEARCH_APP_ID \
    --location=global \
    --format="table(name,displayName,state)"

# Test connectivity
gcloud run services proxy $APP_NAME --region=$REGION --port=8080
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: 
   - [Cloud Run](https://cloud.google.com/run/docs)
   - [Vertex AI Search](https://cloud.google.com/generative-ai-app-builder/docs)
   - [Firestore](https://cloud.google.com/firestore/docs)
3. **Terraform Google Provider**: [terraform.io/providers/hashicorp/google](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Infrastructure Manager**: [cloud.google.com/infrastructure-manager/docs](https://cloud.google.com/infrastructure-manager/docs)

## Security Considerations

### Data Protection
- All data is encrypted at rest and in transit
- Cloud Storage bucket uses Google-managed encryption
- Firestore uses default encryption
- Cloud Run enforces HTTPS

### Access Control
- Service accounts follow least privilege principle
- API endpoints can be configured for authentication
- IAM roles are scoped to specific resources
- Network access controlled through Cloud Run settings

### Best Practices Implemented
- No hardcoded credentials in code
- Environment variables for configuration
- Proper resource naming and tagging
- Regular security updates through automated deployments

## Performance Optimization

### Response Time Optimization
- Cloud Run automatic scaling based on demand
- Firestore regional deployment for low latency
- Cloud Storage regional bucket for fast data access
- Vertex AI Search global deployment for worldwide access

### Caching Strategies
- Implement application-level caching for frequent searches
- Use Cloud CDN for static content delivery
- Consider Redis/Memorystore for session data
- Cache Firestore queries with appropriate TTL

### Monitoring and Alerting
- Set up Cloud Monitoring for service health
- Configure alerting for error rates and latency
- Monitor Vertex AI Search query performance
- Track Firestore read/write operations

---

*This infrastructure code was generated from the Smart Product Catalog Management recipe and follows Google Cloud best practices for AI-powered applications.*