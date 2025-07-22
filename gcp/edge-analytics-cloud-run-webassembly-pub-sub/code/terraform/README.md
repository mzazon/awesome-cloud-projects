# Edge Analytics with Cloud Run WebAssembly and Pub/Sub - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete edge analytics platform on Google Cloud Platform. The infrastructure supports IoT sensor data processing using WebAssembly modules deployed on Cloud Run with Pub/Sub for event-driven architecture.

## Architecture Overview

The Terraform configuration deploys the following Google Cloud resources:

- **Cloud Run Service**: Serverless container platform hosting WebAssembly analytics modules
- **Pub/Sub Topic & Subscription**: Event-driven messaging for IoT sensor data ingestion
- **Cloud Storage Bucket**: Data lake for storing processed analytics results
- **Firestore Database**: NoSQL database for metadata and operational data
- **Cloud Monitoring**: Dashboards and alert policies for observability
- **IAM Service Accounts**: Secure service-to-service authentication
- **Cloud Logging**: Centralized logging with log sinks

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud CLI** installed and configured
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.8)
   ```bash
   terraform --version
   ```

3. **Required Permissions** in your Google Cloud project:
   - Project Editor or custom roles with permissions for:
     - Compute Engine, Cloud Run, Pub/Sub, Cloud Storage
     - Firestore, Cloud Monitoring, IAM, Cloud Logging
     - Service Usage (for enabling APIs)

4. **Billing enabled** on your Google Cloud project

5. **Estimated Monthly Cost**: $10-50 for development workloads, varies by usage

## Quick Start

### 1. Clone and Navigate
```bash
cd terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Configure Variables
Create a `terraform.tfvars` file:
```hcl
# Required Variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional Customizations
environment        = "dev"
resource_prefix    = "edge-analytics"
use_random_suffix  = true

# Cloud Run Configuration
cloud_run_memory      = "1Gi"
cloud_run_cpu         = "2"
cloud_run_concurrency = 80
cloud_run_max_instances = 100

# Storage Configuration
storage_location = "US"
storage_class    = "STANDARD"

# Monitoring Configuration
enable_monitoring_alerts = true
anomaly_threshold       = 5

# Security Configuration
enable_cloud_run_all_users = true
ingress                    = "INGRESS_TRAFFIC_ALL"
```

### 4. Plan Deployment
```bash
terraform plan
```

### 5. Deploy Infrastructure
```bash
terraform apply
```

### 6. Verify Deployment
```bash
terraform output
```

## Configuration Variables

### Required Variables

| Variable | Description | Type | Example |
|----------|-------------|------|---------|
| `project_id` | Google Cloud Project ID | string | `"my-edge-analytics-project"` |
| `region` | Google Cloud region | string | `"us-central1"` |

### Optional Variables

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `environment` | Environment name | `"dev"` | `dev`, `staging`, `prod` |
| `resource_prefix` | Prefix for resource names | `"edge-analytics"` | Any valid string |
| `use_random_suffix` | Add random suffix to names | `true` | `true`, `false` |
| `cloud_run_memory` | Memory allocation | `"1Gi"` | `512Mi`, `1Gi`, `2Gi`, etc. |
| `cloud_run_cpu` | CPU allocation | `"2"` | `1`, `2`, `4`, `8` |
| `storage_class` | Storage class | `"STANDARD"` | `STANDARD`, `NEARLINE`, `COLDLINE` |
| `enable_monitoring_alerts` | Enable alerts | `true` | `true`, `false` |

For a complete list of variables, see `variables.tf`.

## Outputs

After successful deployment, Terraform provides these outputs:

### Service Endpoints
- `cloud_run_service_url`: Main service URL
- `process_endpoint`: Data processing endpoint
- `health_check_endpoint`: Health check endpoint

### Resource Information
- `storage_bucket_name`: Cloud Storage bucket name
- `pubsub_topic_name`: Pub/Sub topic name
- `firestore_database_name`: Firestore database name

### Connection Information
- `connection_info`: Complete connection details for client applications

## Container Image Deployment

### Option 1: Use Placeholder Image (Default)
The Terraform configuration deploys a placeholder image by default. After infrastructure deployment, build and deploy your WebAssembly-enabled container:

```bash
# Build your container image
gcloud builds submit --tag gcr.io/PROJECT_ID/edge-analytics .

# Update Cloud Run service
gcloud run deploy SERVICE_NAME \
    --image gcr.io/PROJECT_ID/edge-analytics \
    --region REGION
```

### Option 2: Specify Custom Image
Set the `container_image` variable in your `terraform.tfvars`:
```hcl
container_image = "gcr.io/your-project/your-edge-analytics-image:latest"
```

## Testing the Deployment

### 1. Verify Cloud Run Service
```bash
# Get service URL from Terraform output
SERVICE_URL=$(terraform output -raw cloud_run_service_url)

# Test health endpoint
curl "${SERVICE_URL}/health"
```

### 2. Test Pub/Sub Integration
```bash
# Publish test message
gcloud pubsub topics publish $(terraform output -raw pubsub_topic_name) \
    --message='{"sensor_id":"test-001","temperature":75.5,"pressure":2.1,"vibration":3.2,"timestamp":1640995200000}'
```

### 3. Verify Storage and Firestore
```bash
# Check processed data in Cloud Storage
gsutil ls gs://$(terraform output -raw storage_bucket_name)/analytics/

# Verify Firestore collections
gcloud firestore collections list
```

## Monitoring and Observability

### Cloud Monitoring Dashboard
Access the pre-configured dashboard:
```bash
echo $(terraform output -raw monitoring_dashboard_url)
```

### Available Metrics
- Data processing rate (messages/second)
- Anomaly detection rate
- Cloud Run request metrics
- Service error rates

### Alert Policies
If `enable_monitoring_alerts = true`, the following alerts are configured:
- High anomaly detection rate
- Low data processing rate
- High service error rate

## Security Considerations

### IAM Configuration
- **Principle of Least Privilege**: Service accounts have minimal required permissions
- **Service Account Separation**: Separate accounts for Cloud Run and Pub/Sub operations
- **Resource-Level Permissions**: Granular access to specific resources

### Network Security
- **Ingress Control**: Configurable traffic ingress settings
- **Binary Authorization**: Optional container image security (set `enable_binary_authorization = true`)
- **Private Access**: Option for internal-only access (set `ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"`)

### Data Protection
- **Encryption**: All data encrypted at rest and in transit
- **Access Logs**: Comprehensive audit logging
- **Versioning**: Optional storage versioning for data protection

## Cost Optimization

### Automatic Features
- **Storage Lifecycle**: Automatic transition to cheaper storage classes
- **Auto-scaling**: Pay-per-use scaling for Cloud Run
- **Resource Optimization**: Right-sized resource allocations

### Configuration Options
```hcl
# Enable lifecycle management
enable_lifecycle_management = true
lifecycle_age_nearline     = 30
lifecycle_age_coldline     = 90

# Optimize Cloud Run scaling
cloud_run_min_instances = 0
cloud_run_max_instances = 100
```

## Troubleshooting

### Common Issues

#### 1. API Not Enabled
```
Error: Error creating service: googleapi: Error 403: Cloud Run Admin API has not been used
```
**Solution**: Ensure `enable_apis = true` in your variables

#### 2. Insufficient Permissions
```
Error: Error creating bucket: googleapi: Error 403: Insufficient Permission
```
**Solution**: Verify your Google Cloud credentials have required permissions

#### 3. Project Quota Exceeded
```
Error: Quota exceeded for quota metric 'Cloud Run services'
```
**Solution**: Request quota increase or choose different region

### Debug Commands
```bash
# Check Terraform state
terraform state list

# View specific resource
terraform state show google_cloud_run_v2_service.edge_analytics

# Check logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50
```

## Cleanup

### Destroy Infrastructure
```bash
terraform destroy
```

### Manual Cleanup (if needed)
```bash
# Remove any remaining resources
gcloud projects delete PROJECT_ID  # Only if dedicated project
```

## Advanced Configuration

### Multi-Environment Deployment
Deploy to multiple environments using workspaces:
```bash
# Create environment-specific workspaces
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# Deploy to specific environment
terraform workspace select dev
terraform apply -var-file="environments/dev.tfvars"
```

### Custom Container Registry
Use a private registry:
```hcl
container_image = "us-central1-docker.pkg.dev/PROJECT_ID/REPOSITORY/image:tag"
```

### External Monitoring Integration
Configure notification channels:
```hcl
notification_channels = [
  "projects/PROJECT_ID/notificationChannels/CHANNEL_ID"
]
```

## Support and Contributions

### Documentation
- [Google Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Version Information
- **Terraform Version**: >= 1.8
- **Google Provider Version**: ~> 6.0
- **Generated**: 2025-07-12
- **Recipe Version**: 1.0

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.