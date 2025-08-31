# Terraform Infrastructure for Dynamic Delivery Route Optimization

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive delivery route optimization system on Google Cloud Platform. The solution combines Google Maps Platform Route Optimization API, BigQuery analytics, Cloud Functions automation, and Cloud Scheduler for intelligent logistics management.

## Architecture Overview

The infrastructure deploys the following components:

- **BigQuery Dataset & Tables**: Data warehouse for delivery analytics with partitioning and clustering
- **Cloud Storage Bucket**: Scalable object storage for route data and logs with lifecycle policies
- **Cloud Functions**: Serverless route optimization processing with Maps Platform integration
- **Cloud Scheduler**: Automated route optimization triggering
- **IAM & Security**: Service accounts and least-privilege access controls
- **Monitoring**: Optional Cloud Monitoring dashboard for operational insights

## Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.5
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) configured with appropriate permissions
- [Git](https://git-scm.com/) for version control

### GCP Requirements
- Google Cloud project with billing enabled
- Required IAM permissions:
  - Project Editor or equivalent custom role
  - BigQuery Admin
  - Cloud Functions Developer
  - Storage Admin
  - Service Account Admin
  - Cloud Scheduler Admin

### API Prerequisites
- Enable Google Maps Platform with Route Optimization API access
- Create or verify billing account setup for Maps Platform usage
- Note: Route Optimization API requires paid usage and charges per optimization request

## Quick Start

### 1. Clone and Navigate
```bash
cd gcp/dynamic-delivery-route-optimization-maps-bigquery/code/terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Configure Variables
Create a `terraform.tfvars` file:
```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
environment = "dev"
resource_name_prefix = "route-opt"

# Optional customizations
bigquery_deletion_protection = true
cloud_function_memory = 1024
scheduler_frequency = "0 */2 * * *"
sample_data_load = true
enable_monitoring = true
```

### 4. Plan and Deploy
```bash
# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Verify Deployment
```bash
# Check BigQuery dataset
bq ls --project_id=your-project-id

# Test the Cloud Function
curl -X POST $(terraform output -raw function_url) \
  -H "Content-Type: application/json" \
  -d '$(terraform output -raw test_function_config | jq -r .sample_payload)'

# Verify Cloud Storage bucket
gsutil ls gs://$(terraform output -raw storage_bucket_name)/
```

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `resource_name_prefix` | Prefix for resource names | `route-opt` | No |

### BigQuery Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `bigquery_dataset_location` | BigQuery dataset location | `US` |
| `bigquery_deletion_protection` | Enable deletion protection | `true` |
| `sample_data_load` | Load sample delivery data | `true` |

### Cloud Functions Configuration

| Variable | Description | Default | Valid Values |
|----------|-------------|---------|--------------|
| `cloud_function_timeout` | Function timeout (seconds) | `300` | 60-540 |
| `cloud_function_memory` | Memory allocation (MB) | `1024` | 128,256,512,1024,2048,4096,8192 |
| `depot_latitude` | Default depot latitude | `37.7749` | Valid latitude |
| `depot_longitude` | Default depot longitude | `-122.4194` | Valid longitude |

### Storage & Lifecycle

| Variable | Description | Default |
|----------|-------------|---------|
| `storage_lifecycle_nearline_age` | Days to Nearline storage | `30` |
| `storage_lifecycle_coldline_age` | Days to Coldline storage | `90` |
| `storage_bucket_force_destroy` | Allow bucket destruction with objects | `false` |

### Automation & Monitoring

| Variable | Description | Default |
|----------|-------------|---------|
| `scheduler_frequency` | Cron expression for automation | `"0 */2 * * *"` |
| `enable_monitoring` | Deploy monitoring dashboard | `true` |
| `enable_apis` | Enable required GCP APIs | `true` |

## Testing the Deployment

### 1. Verify BigQuery Tables
```bash
# Check delivery history table
bq query --use_legacy_sql=false \
  "SELECT COUNT(*) as total_records FROM \`$(terraform output -raw delivery_history_table_id)\`"

# Test analytics views
bq query --use_legacy_sql=false \
  "SELECT * FROM \`$(terraform output -raw delivery_performance_view_id)\` LIMIT 5"
```

### 2. Test Route Optimization Function
```bash
# Get function URL
FUNCTION_URL=$(terraform output -raw function_url)

# Test with sample data
curl -X POST $FUNCTION_URL \
  -H "Content-Type: application/json" \
  -d '{
    "deliveries": [
      {"delivery_id": "TEST001", "lat": 37.7749, "lng": -122.4194, "estimated_minutes": 20, "estimated_km": 2.5},
      {"delivery_id": "TEST002", "lat": 37.7849, "lng": -122.4094, "estimated_minutes": 25, "estimated_km": 3.0}
    ],
    "vehicle_id": "TEST_VEH",
    "driver_id": "TEST_DRV", 
    "vehicle_capacity": 5
  }'
```

### 3. Verify Cloud Storage Integration
```bash
# Check bucket contents
gsutil ls gs://$(terraform output -raw storage_bucket_name)/

# View route optimization results
gsutil ls gs://$(terraform output -raw storage_bucket_name)/route-responses/
```

### 4. Check Automated Scheduling
```bash
# View scheduler job details
gcloud scheduler jobs describe $(terraform output -raw scheduler_job_name) \
  --location=$(terraform output -raw region)

# View function logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --limit=10
```

## Monitoring and Operations

### Cloud Monitoring Dashboard
If monitoring is enabled, access the dashboard at:
```
https://console.cloud.google.com/monitoring?project=YOUR_PROJECT_ID
```

### Key Metrics to Monitor
- Cloud Function invocations and errors
- BigQuery query performance
- Storage bucket usage
- Route optimization API quota usage

### Log Analysis
```bash
# Function execution logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=$(terraform output -raw function_name)" --limit=50

# BigQuery job logs
gcloud logging read "resource.type=bigquery_project" --limit=20
```

## Cost Management

### Estimated Monthly Costs (USD)
- **BigQuery**: ~$0.02 per GB storage + $5.00 per TB queries
- **Cloud Functions**: ~$0.40 per 1M invocations + compute time
- **Cloud Storage**: ~$0.020 per GB/month (Standard class)
- **Cloud Scheduler**: ~$0.10 per job/month
- **Maps Platform**: ~$0.005 per route optimization request

**Total Estimated**: $15-25/month for testing workloads

### Cost Optimization Tips
1. **Enable BigQuery deletion protection** in production
2. **Use storage lifecycle policies** to automatically transition old data
3. **Monitor Maps API usage** to avoid unexpected charges
4. **Set up billing alerts** for proactive cost management
5. **Consider regional deployment** to minimize data transfer costs

## Security Considerations

### IAM and Access Control
- Function uses dedicated service account with minimal required permissions
- Storage bucket has uniform bucket-level access enabled
- BigQuery tables use dataset-level access controls
- Function allows public invocation (consider adding authentication for production)

### Data Protection
- Storage bucket versioning enabled for data recovery
- BigQuery tables use time-based partitioning for efficient data management
- All resources tagged with consistent labels for governance

### Production Security Recommendations
1. **Enable VPC networking** for function deployment
2. **Add API authentication** for function endpoints
3. **Use Secret Manager** for sensitive configuration
4. **Implement Cloud KMS** for data encryption keys
5. **Set up Cloud Security Command Center** for threat detection

## Troubleshooting

### Common Issues

#### Function Deployment Failures
```bash
# Check Cloud Build logs
gcloud builds list --limit=5

# View function deployment status
gcloud functions describe $(terraform output -raw function_name) --region=$(terraform output -raw region)
```

#### BigQuery Permission Errors
```bash
# Verify service account permissions
gcloud projects get-iam-policy $(terraform output -raw project_id) \
  --flatten="bindings[].members" \
  --filter="bindings.members:$(terraform output -raw function_service_account_email)"
```

#### API Enablement Issues
```bash
# Check enabled APIs
gcloud services list --enabled

# Enable specific API if needed
gcloud services enable routeoptimization.googleapis.com
```

### Debug Commands
```bash
# Terraform debugging
export TF_LOG=DEBUG
terraform plan

# Function source inspection
unzip -l $(find /tmp -name "*route-optimizer-function*.zip" | head -1)

# BigQuery table schema verification
bq show $(terraform output -raw delivery_history_table_id)
```

## Customization Examples

### Multi-Environment Setup
```hcl
# dev.tfvars
project_id = "route-opt-dev"
environment = "dev"
cloud_function_memory = 512
bigquery_deletion_protection = false

# prod.tfvars  
project_id = "route-opt-prod"
environment = "prod"
cloud_function_memory = 2048
bigquery_deletion_protection = true
```

### Custom Function Configuration
```hcl
# Enhanced function setup
cloud_function_timeout = 540
cloud_function_memory = 2048
max_optimization_requests_per_day = 5000

# Custom depot location (New York)
depot_latitude = 40.7128
depot_longitude = -74.0060
```

### Advanced Storage Lifecycle
```hcl
# Aggressive cost optimization
storage_lifecycle_nearline_age = 7
storage_lifecycle_coldline_age = 30
```

## Cleanup

### Selective Cleanup
```bash
# Remove scheduler job only
terraform destroy -target=google_cloud_scheduler_job.route_optimization_scheduler

# Remove function only  
terraform destroy -target=google_cloudfunctions2_function.route_optimizer
```

### Complete Cleanup
```bash
# Destroy all resources
terraform destroy

# Verify cleanup
gcloud resources list --project=$(terraform output -raw project_id)
```

### Manual Cleanup (if needed)
```bash
# Force delete bucket with contents
gsutil -m rm -r gs://$(terraform output -raw storage_bucket_name)

# Delete BigQuery dataset
bq rm -r -f $(terraform output -raw project_id):$(terraform output -raw bigquery_dataset_id)
```

## Support and Documentation

### Official Documentation Links
- [Google Maps Platform Route Optimization API](https://developers.google.com/maps/documentation/route-optimization)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Additional Resources
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [BigQuery Best Practices](https://cloud.google.com/bigquery/docs/best-practices)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)

For issues specific to this infrastructure code, refer to the original recipe documentation or contact your cloud architecture team.