# Terraform Infrastructure for Real-Time Streaming Analytics

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive real-time streaming analytics solution on Google Cloud Platform. The infrastructure supports live video streaming with global CDN distribution and real-time analytics processing.

## Architecture Overview

The infrastructure deploys the following components:

- **Cloud Storage**: Video content bucket with lifecycle policies and CDN origin
- **Media CDN**: Global content delivery using Cloud Load Balancer and Backend Buckets
- **BigQuery**: Analytics data warehouse with partitioned tables and views
- **Cloud Functions**: Real-time event processing (2nd generation)
- **Pub/Sub**: Event streaming and message queuing
- **IAM**: Service accounts and least-privilege access controls

## Prerequisites

1. **Google Cloud Project**: Active project with billing enabled
2. **APIs Enabled**: The following APIs will be enabled automatically:
   - Cloud Storage API
   - Cloud Functions API
   - Pub/Sub API
   - BigQuery API
   - Compute Engine API
   - Network Services API
   - Cloud Build API
   - Artifact Registry API
3. **Terraform**: Version 1.5 or later
4. **Google Cloud CLI**: Authenticated and configured
5. **Permissions**: IAM roles for creating resources (typically Project Editor or Owner)

## Quick Start

### 1. Authentication and Project Setup

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project ID
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"
```

### 2. Initialize and Deploy with Terraform

```bash
# Clone the repository and navigate to the terraform directory
cd gcp/real-time-streaming-analytics-media-cdn-live-stream-api/code/terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${TF_VAR_project_id}" -var="region=${TF_VAR_region}"

# Deploy the infrastructure
terraform apply -var="project_id=${TF_VAR_project_id}" -var="region=${TF_VAR_region}"
```

### 3. Configure Live Streaming (Manual Steps)

Since Live Stream API resources are not yet available in the Terraform provider, you'll need to create them manually:

```bash
# Get the suffix from Terraform output
SUFFIX=$(terraform output -raw resource_suffix)
BUCKET_NAME=$(terraform output -raw storage_bucket_name)

# Create Live Stream input endpoint
gcloud livestream inputs create live-input-${SUFFIX} \
    --location=${TF_VAR_region} \
    --type=RTMP_PUSH \
    --tier=HD

# Create channel configuration file
cat > channel-config.yaml << EOF
inputAttachments:
- key: "live-input"
  input: "projects/${TF_VAR_project_id}/locations/${TF_VAR_region}/inputs/live-input-${SUFFIX}"

output:
  uri: "gs://${BUCKET_NAME}/live-stream/"

elementaryStreams:
- key: "video-stream-hd"
  videoStream:
    h264:
      widthPixels: 1280
      heightPixels: 720
      frameRate: 30
      bitrateBps: 3000000
      vbvSizeBits: 6000000
      vbvFullnessBits: 5400000
      gopDuration: "2s"

- key: "audio-stream"
  audioStream:
    codec: "aac"
    bitrateBps: 128000
    channelCount: 2
    channelLayout: ["FL", "FR"]
    sampleRateHertz: 48000

muxStreams:
- key: "hd-stream"
  container: "fmp4"
  elementaryStreams: ["video-stream-hd", "audio-stream"]

manifests:
- fileName: "manifest.m3u8"
  type: "HLS"
  muxStreams: ["hd-stream"]
  maxSegmentCount: 5
  segmentKeepDuration: "10s"
EOF

# Create and start the channel
gcloud livestream channels create live-channel-${SUFFIX} \
    --location=${TF_VAR_region} \
    --config-file=channel-config.yaml

gcloud livestream channels start live-channel-${SUFFIX} \
    --location=${TF_VAR_region}
```

## Configuration Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP project ID | - |
| `region` | GCP region for resources | `us-central1` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name (dev/staging/prod) | `dev` |
| `storage_class` | Cloud Storage default class | `STANDARD` |
| `function_memory` | Cloud Function memory allocation | `512Mi` |
| `function_timeout` | Cloud Function timeout (seconds) | `60` |
| `bigquery_location` | BigQuery dataset location | `US` |
| `cdn_cache_mode` | CDN cache mode | `CACHE_ALL_STATIC` |

### Example terraform.tfvars

```hcl
project_id  = "my-streaming-project"
region      = "us-central1"
environment = "production"

# Storage configuration
storage_class                 = "STANDARD"
bucket_lifecycle_age_nearline = 30
bucket_lifecycle_age_delete   = 90

# Function configuration
function_memory      = "1Gi"
function_timeout     = 120
function_max_instances = 200

# BigQuery configuration
bigquery_location             = "US"
bigquery_table_expiration_days = 365

# CDN configuration
cdn_cache_mode   = "CACHE_ALL_STATIC"
cdn_default_ttl  = 30
cdn_max_ttl      = 300

# Labels
labels = {
  project     = "streaming-analytics"
  environment = "production"
  team        = "media-engineering"
  cost_center = "engineering"
}
```

## Testing the Infrastructure

### 1. Verify Deployment

```bash
# Check all resources are created
terraform output

# Validate BigQuery dataset
bq ls $(terraform output -raw bigquery_dataset_id)

# Test Pub/Sub topic
gcloud pubsub topics list --filter="name:$(terraform output -raw pubsub_topic_name)"

# Check Cloud Function status
gcloud functions describe $(terraform output -raw cloud_function_name) --region=${TF_VAR_region} --gen2
```

### 2. Test Event Processing

```bash
# Publish a test event
terraform output -raw pubsub_publish_command | bash

# Check function logs
gcloud functions logs read $(terraform output -raw cloud_function_name) --region=${TF_VAR_region} --limit=10

# Query analytics data
bq query --use_legacy_sql=false "SELECT * FROM \`$(terraform output -raw streaming_events_table)\` ORDER BY timestamp DESC LIMIT 10"
```

### 3. Test CDN Access

```bash
# Get CDN IP address
CDN_IP=$(terraform output -raw cdn_ip_address)

# Test basic connectivity
curl -I http://${CDN_IP}/

# Test with custom host header (if configured)
curl -I -H "Host: streaming-$(terraform output -raw resource_suffix).example.com" http://${CDN_IP}/
```

## Monitoring and Observability

### Cloud Monitoring Dashboards

Access pre-configured monitoring at:
- **Overview**: `terraform output monitoring_dashboard_url`
- **Function Logs**: `terraform output logs_explorer_url`

### Key Metrics to Monitor

1. **Cloud Function Metrics**:
   - Execution count and duration
   - Error rate and success rate
   - Memory and CPU utilization

2. **Pub/Sub Metrics**:
   - Message publish rate
   - Subscription backlog
   - Dead letter queue messages

3. **BigQuery Metrics**:
   - Slot utilization
   - Query performance
   - Storage usage

4. **CDN Metrics**:
   - Request rate and cache hit ratio
   - Origin response time
   - Error rates by region

### Setting Up Alerts

```bash
# Create alerting policy for function errors
gcloud alpha monitoring policies create --config-from-file=alerting-policy.yaml
```

## Cost Optimization

The infrastructure includes several cost optimization features:

1. **Storage Lifecycle**: Automatic transition to cheaper storage classes
2. **BigQuery Partitioning**: Reduced query costs through date partitioning
3. **Function Scaling**: Automatic scaling with configurable limits
4. **CDN Caching**: Reduced origin requests through intelligent caching

### Cost Monitoring

- Monitor costs: `terraform output cost_optimization_notes`
- Set up billing alerts in the GCP Console
- Use BigQuery cost analysis queries for detailed usage patterns

## Security Considerations

The infrastructure implements security best practices:

1. **IAM**: Least privilege service accounts
2. **Network Security**: Private function access and VPC integration options
3. **Data Protection**: Encryption at rest and in transit
4. **Access Control**: Uniform bucket-level access and public access prevention

Review security settings: `terraform output security_notes`

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
2. **Permissions**: Verify IAM roles for the deploying user
3. **Quota Limits**: Check GCP quotas for compute and storage resources
4. **Region Availability**: Ensure chosen region supports all services

### Debug Commands

```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# Check provider versions
terraform version

# View detailed logs
export TF_LOG=DEBUG
terraform apply
```

### Function Debugging

```bash
# Check function source code
gcloud functions describe FUNCTION_NAME --region=REGION --gen2 --format="value(buildConfig.source)"

# View function configuration
gcloud functions describe FUNCTION_NAME --region=REGION --gen2 --format="yaml"

# Test function locally (requires Cloud Functions Emulator)
functions-framework --target=process_streaming_event --debug
```

## Cleanup

To destroy all resources:

```bash
# Stop live streaming resources first (if created)
gcloud livestream channels stop live-channel-${SUFFIX} --location=${TF_VAR_region}
gcloud livestream channels delete live-channel-${SUFFIX} --location=${TF_VAR_region} --quiet
gcloud livestream inputs delete live-input-${SUFFIX} --location=${TF_VAR_region} --quiet

# Destroy Terraform-managed resources
terraform destroy -var="project_id=${TF_VAR_project_id}" -var="region=${TF_VAR_region}"
```

## Support and Contributing

- **Documentation**: [Google Cloud Live Stream API](https://cloud.google.com/livestream/docs)
- **Terraform Provider**: [Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Issues**: Report issues with the infrastructure code in your project repository

## Version History

- **v1.0**: Initial implementation with core streaming analytics features
- Support for Cloud Functions 2nd generation
- BigQuery analytics with partitioning and clustering
- CDN configuration with Cloud Load Balancer
- Comprehensive monitoring and alerting setup