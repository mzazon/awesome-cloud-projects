# Infrastructure as Code for Intelligent Retail Inventory Optimization

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting Intelligent Retail Inventory Optimization with Fleet Engine and Cloud Optimization AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent retail inventory management system that combines:

- **BigQuery**: Data warehouse for analytics and ML forecasting
- **Vertex AI**: Machine learning for demand forecasting
- **Cloud Optimization AI**: Inventory allocation optimization
- **Fleet Engine**: Delivery route optimization
- **Cloud Run**: Serverless microservices for analytics and coordination
- **Cloud Storage**: Data pipeline storage and model artifacts
- **Cloud Monitoring**: System observability and alerting

## Prerequisites

### General Requirements
- Google Cloud Project with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Appropriate IAM permissions for resource creation:
  - BigQuery Admin
  - Vertex AI User
  - Cloud Optimization Admin
  - Fleet Engine Admin (requires special access approval)
  - Cloud Run Admin
  - Storage Admin
  - Monitoring Admin
  - Service Account Admin

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager API enabled
- `gcloud infra-manager` command available

#### Terraform
- Terraform >= 1.0 installed
- Google Cloud provider >= 4.0

#### Bash Scripts
- bash shell environment
- jq for JSON processing
- curl for API testing

### Special Requirements
- **Fleet Engine Access**: Requires special approval from Google Cloud sales team
- **Estimated Cost**: $200-400 for complete setup and testing

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/retail-inventory \
    --service-account="projects/$PROJECT_ID/serviceAccounts/inventory-optimizer-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/retail-inventory" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" \
               -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" \
                -var="region=us-central1"

# Outputs will display service URLs and resource information
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy complete infrastructure
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create service accounts and IAM bindings
# 3. Deploy BigQuery datasets and ML models
# 4. Set up Cloud Storage buckets
# 5. Build and deploy Cloud Run services
# 6. Configure monitoring and alerting
```

## Deployment Steps

### 1. Pre-deployment Setup

```bash
# Set project configuration
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION

# Enable required APIs (if not using scripts)
gcloud services enable bigquery.googleapis.com \
                       aiplatform.googleapis.com \
                       optimization.googleapis.com \
                       fleetengine.googleapis.com \
                       run.googleapis.com \
                       storage.googleapis.com \
                       monitoring.googleapis.com
```

### 2. Service Account Creation

The infrastructure creates a service account with required permissions:
- `inventory-optimizer-sa@PROJECT_ID.iam.gserviceaccount.com`

### 3. Core Infrastructure

1. **BigQuery Dataset**: `retail_analytics_SUFFIX`
   - Inventory levels table
   - Sales history table
   - Store locations table
   - ML forecasting model

2. **Cloud Storage Bucket**: `retail-inventory-PROJECT_ID-SUFFIX`
   - Raw data storage
   - Processed data storage
   - ML model artifacts
   - Optimization results

3. **Cloud Run Services**:
   - Analytics service (demand forecasting APIs)
   - Optimization coordinator service
   - Auto-scaling and managed infrastructure

### 4. AI/ML Components

- **Vertex AI**: Demand forecasting model training
- **BigQuery ML**: ARIMA_PLUS time series forecasting
- **Cloud Optimization AI**: Inventory allocation algorithms

### 5. Monitoring Setup

- Custom dashboards for system performance
- Alerting policies for optimization failures
- Log aggregation and analysis

## Configuration

### Environment Variables

```bash
# Required variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"                    # GCP region
export ZONE="us-central1-a"                    # GCP zone

# Optional customization
export DATASET_NAME="retail_analytics_custom"  # BigQuery dataset name
export BUCKET_NAME="custom-bucket-name"        # Cloud Storage bucket
export SERVICE_ACCOUNT_NAME="custom-sa"        # Service account name
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
dataset_name = "retail_analytics"
bucket_name  = "retail-inventory-bucket"
```

### Infrastructure Manager Variables

Modify `infrastructure-manager/main.yaml` parameters:

```yaml
parameters:
  project_id: "your-project-id"
  region: "us-central1"
  dataset_name: "retail_analytics"
```

## Validation & Testing

### 1. Verify Infrastructure Deployment

```bash
# Check BigQuery resources
bq ls $PROJECT_ID:retail_analytics_*

# Verify Cloud Run services
gcloud run services list --region=$REGION

# Test Cloud Storage bucket
gsutil ls gs://retail-inventory-*

# Check service accounts
gcloud iam service-accounts list --filter="email:inventory-optimizer*"
```

### 2. Test API Endpoints

```bash
# Get Cloud Run service URLs
ANALYTICS_URL=$(gcloud run services describe analytics-service \
    --region=$REGION --format="value(status.url)")

OPTIMIZER_URL=$(gcloud run services describe optimizer-service \
    --region=$REGION --format="value(status.url)")

# Test health endpoints
curl -X GET "$ANALYTICS_URL/health"
curl -X GET "$OPTIMIZER_URL/health"

# Test demand forecasting
curl -X POST "$ANALYTICS_URL/demand-forecast" \
    -H "Content-Type: application/json" \
    -d '{"store_ids": ["store_001"], "product_ids": ["prod_123"]}'
```

### 3. Validate ML Model

```bash
# Check ML model training status
bq query --use_legacy_sql=false \
    "SELECT * FROM ML.TRAINING_INFO(MODEL \`$PROJECT_ID.retail_analytics_*.demand_forecast_model\`) LIMIT 5"

# Test forecasting
bq query --use_legacy_sql=false \
    "SELECT * FROM ML.FORECAST(MODEL \`$PROJECT_ID.retail_analytics_*.demand_forecast_model\`, STRUCT(7 as horizon)) LIMIT 10"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/retail-inventory
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" \
                  -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Run services
# 2. Remove BigQuery datasets
# 3. Delete Cloud Storage buckets
# 4. Clean up IAM bindings
# 5. Delete service accounts
# 6. Remove container images
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Run services
gcloud run services delete analytics-service --region=$REGION --quiet
gcloud run services delete optimizer-service --region=$REGION --quiet

# Delete BigQuery dataset
bq rm -r -f $PROJECT_ID:retail_analytics_*

# Delete Cloud Storage bucket
gsutil -m rm -r gs://retail-inventory-*

# Remove service account
gcloud iam service-accounts delete inventory-optimizer-sa@$PROJECT_ID.iam.gserviceaccount.com --quiet
```

## Customization

### Scaling Configuration

Modify Cloud Run service scaling in terraform variables:

```hcl
analytics_service_config = {
  cpu_limit      = "2"
  memory_limit   = "2Gi"
  max_instances  = 10
  min_instances  = 1
}

optimizer_service_config = {
  cpu_limit      = "4"
  memory_limit   = "4Gi"
  max_instances  = 5
  min_instances  = 0
  timeout        = "900s"
}
```

### Data Pipeline Configuration

Customize BigQuery dataset and storage lifecycle:

```hcl
dataset_location = "US"
dataset_description = "Custom retail analytics dataset"

storage_lifecycle_rules = {
  nearline_age_days = 30
  coldline_age_days = 90
  archive_age_days  = 365
}
```

### Monitoring Configuration

Configure custom alerting thresholds:

```hcl
monitoring_config = {
  error_rate_threshold    = 0.05
  latency_threshold_ms   = 5000
  cpu_utilization_threshold = 0.8
}
```

## Troubleshooting

### Common Issues

1. **Fleet Engine Access Required**
   ```
   Error: Fleet Engine API requires special access
   Solution: Contact Google Cloud sales for Fleet Engine enablement
   ```

2. **Insufficient Permissions**
   ```
   Error: User lacks required IAM permissions
   Solution: Grant necessary roles or use service account with admin permissions
   ```

3. **API Not Enabled**
   ```
   Error: API not enabled for project
   Solution: Enable required APIs using gcloud services enable
   ```

4. **Cloud Run Build Failures**
   ```
   Error: Cloud Build failed
   Solution: Check build logs and ensure proper Dockerfile configuration
   ```

### Debugging Commands

```bash
# Check API status
gcloud services list --enabled --filter="name:optimization OR name:aiplatform OR name:fleetengine"

# View Cloud Run logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50

# Check BigQuery job history
bq ls -j --max_results=10

# Monitor Cloud Build status
gcloud builds list --limit=10
```

### Performance Optimization

1. **Increase Cloud Run Resources**: Adjust CPU and memory limits for better performance
2. **Optimize BigQuery Queries**: Use partitioning and clustering for large datasets
3. **Enable Cloud CDN**: Cache API responses for improved latency
4. **Use Regional Persistent Disks**: Improve I/O performance for data processing

## Security Considerations

- **IAM Best Practices**: Service accounts follow least privilege principle
- **Network Security**: Cloud Run services use private Google access
- **Data Encryption**: All data encrypted at rest and in transit
- **API Security**: Authentication required for all service endpoints
- **Audit Logging**: Cloud Audit Logs enabled for all services

## Cost Optimization

- **Cloud Run**: Pay-per-use pricing with automatic scaling to zero
- **BigQuery**: On-demand pricing with query optimization
- **Cloud Storage**: Lifecycle management for automatic cost reduction
- **Monitoring**: Basic tier monitoring included

Estimated monthly costs (moderate usage):
- BigQuery: $50-100
- Cloud Run: $30-60
- Cloud Storage: $20-40
- Vertex AI: $50-150
- Other services: $50-100

**Total**: $200-450/month

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe in `../intelligent-retail-inventory-optimization.md`
2. **Google Cloud Documentation**: 
   - [BigQuery ML](https://cloud.google.com/bigquery-ml/docs)
   - [Vertex AI](https://cloud.google.com/vertex-ai/docs)
   - [Cloud Optimization AI](https://cloud.google.com/optimization/docs)
   - [Cloud Run](https://cloud.google.com/run/docs)
3. **Community Support**: Google Cloud Community forums and Stack Overflow

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate syntax and best practices
3. Update documentation accordingly
4. Submit pull requests with detailed descriptions

## License

This infrastructure code is provided as-is under the same license as the parent recipe repository.