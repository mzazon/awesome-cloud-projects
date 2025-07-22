# Infrastructure as Code for Edge Analytics with Cloud Run WebAssembly and Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Edge Analytics with Cloud Run WebAssembly and Pub/Sub".

## Recipe Overview

This recipe implements a high-performance edge analytics platform using WebAssembly modules deployed on Cloud Run to process streaming IoT data through Pub/Sub. The serverless architecture combines the computational efficiency of WebAssembly with Google Cloud's managed services to deliver real-time analytics, intelligent alerting, and seamless scalability while maintaining low latency for critical edge workloads.

## Architecture Components

- **Cloud Run**: Serverless container platform hosting WebAssembly analytics engine
- **Pub/Sub**: Managed messaging service for IoT data ingestion and event-driven processing
- **Cloud Storage**: Data lake for storing processed analytics results with lifecycle management
- **Firestore**: NoSQL database for storing analytics metadata and results
- **Cloud Monitoring**: Observability platform with custom metrics and alerting
- **Cloud Build**: Container building service for WebAssembly-enabled applications

## Available Implementations

- **Infrastructure Manager**: Google Cloud's current IaC tool (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured, version 400.0.0 or later
- Appropriate IAM permissions for Cloud Run, Pub/Sub, Cloud Storage, Cloud Monitoring, and Cloud Build
- Billing enabled on your Google Cloud project
- Docker installed locally for building container images (for development)
- Rust toolchain installed for compiling WebAssembly modules (rustc 1.70+)
- Basic understanding of WebAssembly, serverless architectures, and IoT data processing
- Estimated cost: $5-15 per day for moderate IoT data volumes (1000 messages/hour)

> **Note**: This recipe uses Cloud Run's container runtime features to support WebAssembly workloads. Ensure your project has the latest Cloud Run APIs enabled.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's current infrastructure-as-code tool that provides plan and apply workflows for managing Google Cloud resources.

```bash
# Clone or navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create a deployment
gcloud infra-manager deployments create edge-analytics-deployment \
    --location=${REGION} \
    --source-input-artifact-url=gs://your-bucket/config.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe edge-analytics-deployment \
    --location=${REGION}

# Apply the deployment
gcloud infra-manager deployments apply edge-analytics-deployment \
    --location=${REGION}
```

### Using Terraform

Terraform provides a consistent workflow for managing infrastructure across multiple cloud providers.

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create a terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide a simple way to deploy the infrastructure using gcloud commands.

```bash
# Navigate to the scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./deploy.sh

# Verify deployment
gcloud run services list --region=${REGION}
gcloud pubsub topics list
gcloud storage buckets list
```

## Deployment Configuration

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | No |
| `zone` | Compute zone for resources | `us-central1-a` | No |
| `service_name` | Cloud Run service name | `edge-analytics` | No |
| `topic_name` | Pub/Sub topic name | `iot-sensor-data` | No |
| `bucket_name` | Cloud Storage bucket name | `edge-analytics-data` | No |
| `enable_monitoring` | Enable Cloud Monitoring alerts | `true` | No |
| `container_memory` | Cloud Run container memory | `1Gi` | No |
| `container_cpu` | Cloud Run container CPU | `2` | No |
| `max_instances` | Maximum Cloud Run instances | `100` | No |

### Environment Variables

When using scripts, set these environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export SERVICE_NAME="edge-analytics"
export TOPIC_NAME="iot-sensor-data"
export BUCKET_NAME="edge-analytics-data"
```

## Testing the Deployment

After deployment, you can test the edge analytics pipeline:

### 1. Verify Cloud Run Service

```bash
# Check service status
gcloud run services describe ${SERVICE_NAME} \
    --region=${REGION} \
    --format="table(status.conditions[].type,status.conditions[].status)"

# Get service URL
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
    --region=${REGION} \
    --format='value(status.url)')

echo "Service URL: ${SERVICE_URL}"
```

### 2. Test with Sample Data

```bash
# Send test message to Pub/Sub
gcloud pubsub topics publish ${TOPIC_NAME} \
    --message='{"sensor_id":"test-001","temperature":85.5,"pressure":3.2,"vibration":6.1,"timestamp":1640995200000}'

# Check Cloud Run logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}" \
    --limit=10 --format="table(timestamp,severity,textPayload)"
```

### 3. Verify Data Storage

```bash
# Check processed data in Cloud Storage
gsutil ls -r gs://${BUCKET_NAME}/analytics/

# Verify Firestore documents
gcloud firestore databases list
```

### 4. Monitor Custom Metrics

```bash
# Check custom metrics in Cloud Monitoring
gcloud monitoring metrics list --filter="metric.type:custom.googleapis.com/iot"

# View monitoring dashboards
gcloud monitoring dashboards list
```

## Customization

### Modifying Analytics Logic

The WebAssembly analytics module can be customized by modifying the Rust source code:

1. Update the analytics algorithm in `src/lib.rs`
2. Rebuild the WebAssembly module: `wasm-pack build --target nodejs`
3. Rebuild and redeploy the Cloud Run service

### Scaling Configuration

Adjust Cloud Run scaling parameters:

```hcl
# In Terraform
resource "google_cloud_run_service" "edge_analytics" {
  template {
    spec {
      container_concurrency = 80
      timeout_seconds      = 300
    }
    
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "200"
        "autoscaling.knative.dev/minScale" = "0"
        "run.googleapis.com/memory"        = "2Gi"
        "run.googleapis.com/cpu"          = "2"
      }
    }
  }
}
```

### Storage Lifecycle Policies

Customize data retention policies:

```hcl
# In Terraform
resource "google_storage_bucket" "analytics_data" {
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type         = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type         = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
}
```

### Monitoring and Alerting

Add custom alert policies:

```hcl
# In Terraform
resource "google_monitoring_alert_policy" "high_anomaly_rate" {
  display_name = "High Anomaly Detection Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Anomaly rate exceeds threshold"
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/iot/anomaly_detected\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 10
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
}
```

## Security Considerations

### IAM Permissions

The deployment creates service accounts with minimal required permissions:

- Cloud Run service account: Access to Cloud Storage, Firestore, and Cloud Monitoring
- Pub/Sub service account: Permission to invoke Cloud Run service
- Cloud Build service account: Access to Container Registry

### Network Security

- Cloud Run service configured for HTTPS-only traffic
- Pub/Sub push subscription uses authenticated endpoints
- Container registry access restricted to project

### Data Protection

- Cloud Storage buckets configured with versioning enabled
- Firestore security rules can be customized based on requirements
- WebAssembly modules run in isolated container environment

## Troubleshooting

### Common Issues

1. **Cloud Run deployment fails**
   ```bash
   # Check build logs
   gcloud builds list --limit=5
   gcloud builds log [BUILD_ID]
   ```

2. **Pub/Sub messages not reaching Cloud Run**
   ```bash
   # Verify push subscription configuration
   gcloud pubsub subscriptions describe ${SUBSCRIPTION_NAME}
   
   # Check IAM permissions
   gcloud run services get-iam-policy ${SERVICE_NAME} --region=${REGION}
   ```

3. **WebAssembly module compilation errors**
   ```bash
   # Ensure Rust toolchain is installed
   rustc --version
   
   # Install wasm-pack
   curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh
   ```

4. **Storage access denied**
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Verify bucket exists and permissions
   gsutil iam get gs://${BUCKET_NAME}
   ```

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify quota limits
gcloud compute project-info describe --project=${PROJECT_ID}

# Check Cloud Run service logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50

# Monitor Pub/Sub subscription
gcloud pubsub subscriptions describe ${SUBSCRIPTION_NAME}
```

## Performance Optimization

### WebAssembly Optimization

- Use release builds for production: `wasm-pack build --release`
- Enable WebAssembly SIMD for vectorized operations
- Consider using WebAssembly threading for parallel processing

### Cloud Run Optimization

- Set appropriate CPU and memory limits based on workload
- Use Cloud Run concurrency settings to optimize throughput
- Enable CPU throttling for cost optimization during low-traffic periods

### Storage Optimization

- Implement intelligent data partitioning in Cloud Storage
- Use Cloud Storage Transfer Service for large data migrations
- Enable Cloud CDN for frequently accessed analytics results

## Cost Estimation

Estimated monthly costs for moderate usage (10,000 IoT messages/day):

- Cloud Run: $15-30 (includes CPU time and requests)
- Pub/Sub: $5-10 (message throughput and storage)
- Cloud Storage: $5-15 (data storage and operations)
- Cloud Monitoring: $3-8 (custom metrics and alerting)
- Firestore: $1-5 (document reads/writes)

**Total estimated cost: $29-68 per month**

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete edge-analytics-deployment \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform state list
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Verify cleanup
gcloud run services list --region=${REGION}
gcloud pubsub topics list
gcloud storage buckets list
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud run services list --region=${REGION}
gcloud pubsub topics list
gcloud pubsub subscriptions list
gsutil ls
gcloud firestore databases list
gcloud monitoring dashboards list
```

## Support and Documentation

### Official Documentation

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### WebAssembly Resources

- [WebAssembly Official Site](https://webassembly.org/)
- [Rust and WebAssembly Book](https://rustwasm.github.io/book/)
- [wasm-pack Documentation](https://rustwasm.github.io/wasm-pack/)

### Community Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../edge-analytics-cloud-run-webassembly-pub-sub.md)
2. Review Google Cloud documentation for specific services
3. Consult the WebAssembly community resources
4. Check the Terraform Google Cloud Provider documentation for Terraform-specific issues

### Additional Resources

- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [IoT Core Documentation](https://cloud.google.com/iot-core/docs) (for production IoT device management)
- [Dataflow Documentation](https://cloud.google.com/dataflow/docs) (for stream processing extensions)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs) (for analytics data warehouse)