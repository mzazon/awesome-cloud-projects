# Infrastructure as Code for Real-Time Streaming Analytics with Cloud Media CDN and Live Stream API

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Streaming Analytics with Cloud Media CDN and Live Stream API".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured (version 450.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for the following services:
  - Live Stream API
  - Cloud Media CDN
  - Cloud Storage
  - Cloud Functions
  - BigQuery
  - Pub/Sub
  - Network Services
- Video encoder software (OBS Studio, FFmpeg, or similar) for testing
- Basic understanding of video streaming protocols (HLS, DASH, RTMP)

## Estimated Costs

- **Testing Environment**: $50-100 for initial testing
- **Production Environment**: Variable based on:
  - Live stream transcoding minutes
  - CDN data egress
  - Cloud Functions invocations
  - BigQuery data processing and storage

> **Warning**: Live streaming and CDN services can incur significant costs based on usage. Monitor your billing dashboard and set up budget alerts.

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/streaming-analytics \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://github.com/your-org/streaming-infrastructure.git" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Confirm deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
```

## Architecture Overview

This infrastructure deploys a complete real-time streaming analytics solution including:

- **Live Stream API**: Input endpoints and transcoding channels
- **Cloud Storage**: Video segment storage with lifecycle policies
- **Media CDN**: Global content delivery network
- **Cloud Functions**: Real-time analytics processing
- **Pub/Sub**: Event streaming and message queuing
- **BigQuery**: Analytics data warehouse with pre-built views

## Configuration Variables

### Infrastructure Manager Variables

```yaml
# infrastructure-manager/main.yaml
inputs:
  project_id:
    description: "Google Cloud Project ID"
    type: string
    required: true
  
  region:
    description: "Primary deployment region"
    type: string
    default: "us-central1"
  
  storage_bucket_name:
    description: "Cloud Storage bucket for video segments"
    type: string
    default: "streaming-content-${random_suffix}"
  
  enable_cdn_logging:
    description: "Enable CDN access logging"
    type: boolean
    default: true
```

### Terraform Variables

```hcl
# terraform/variables.tf
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Primary deployment region"
  type        = string
  default     = "us-central1"
}

variable "storage_bucket_name" {
  description = "Cloud Storage bucket for video segments"
  type        = string
  default     = ""
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "256Mi"
}

variable "bigquery_location" {
  description = "BigQuery dataset location"
  type        = string
  default     = "US"
}
```

## Deployment Steps

### 1. Pre-deployment Setup

```bash
# Enable required APIs
gcloud services enable livestream.googleapis.com \
    storage.googleapis.com \
    networkservices.googleapis.com \
    cloudfunctions.googleapis.com \
    bigquery.googleapis.com \
    pubsub.googleapis.com

# Set default project and region
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
```

### 2. Infrastructure Deployment

Choose one of the deployment methods above based on your preference and organizational standards.

### 3. Post-deployment Configuration

```bash
# Get live stream input endpoint
INPUT_ENDPOINT=$(gcloud livestream inputs describe live-input \
    --location=${REGION} \
    --format="value(uri)")

echo "Stream to: ${INPUT_ENDPOINT}"

# Verify BigQuery dataset
bq ls ${PROJECT_ID}:streaming_analytics

# Test Cloud Function
gcloud functions logs read stream-analytics-processor \
    --region=${REGION} \
    --limit=10
```

## Testing the Deployment

### 1. Validate Infrastructure

```bash
# Check Live Stream API resources
gcloud livestream inputs list --location=${REGION}
gcloud livestream channels list --location=${REGION}

# Verify Cloud Storage bucket
gsutil ls -L gs://your-bucket-name

# Check Media CDN configuration
gcloud network-services edge-cache-services list

# Validate BigQuery setup
bq query --use_legacy_sql=false "SELECT COUNT(*) FROM \`${PROJECT_ID}.streaming_analytics.streaming_events\`"
```

### 2. Test Analytics Pipeline

```bash
# Publish test event to Pub/Sub
gcloud pubsub topics publish stream-events \
    --message='{"eventType":"stream_start","viewerId":"test_123","streamId":"test_stream"}'

# Wait for processing and check BigQuery
sleep 30
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.streaming_analytics.streaming_events\` ORDER BY timestamp DESC LIMIT 5"
```

### 3. Stream Testing

```bash
# Using FFmpeg to test streaming (if available)
ffmpeg -f lavfi -i testsrc=duration=60:size=1280x720:rate=30 \
    -f lavfi -i sine=frequency=1000:duration=60 \
    -c:v libx264 -c:a aac \
    -f flv ${INPUT_ENDPOINT}/live-stream-key
```

## Monitoring and Analytics

### Built-in Analytics Views

The deployment creates several BigQuery views for analytics:

- `viewer_engagement_metrics`: Daily viewer and session statistics
- `cdn_performance_metrics`: CDN cache hit rates and performance
- `stream_quality_metrics`: Video quality and buffering analytics

### Custom Queries

```sql
-- Real-time viewer count
SELECT 
    stream_id,
    COUNT(DISTINCT viewer_id) as current_viewers
FROM `your-project.streaming_analytics.streaming_events`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
    AND event_type = 'stream_start'
GROUP BY stream_id;

-- CDN performance by region
SELECT 
    edge_location,
    AVG(latency_ms) as avg_latency,
    COUNT(*) as request_count,
    COUNT(CASE WHEN cache_status = 'HIT' THEN 1 END) / COUNT(*) * 100 as cache_hit_rate
FROM `your-project.streaming_analytics.cdn_access_logs`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
GROUP BY edge_location
ORDER BY request_count DESC;
```

## Troubleshooting

### Common Issues

1. **Live Stream Channel Not Starting**
   ```bash
   # Check channel status
   gcloud livestream channels describe your-channel-name --location=${REGION}
   
   # Verify input configuration
   gcloud livestream inputs describe your-input-name --location=${REGION}
   ```

2. **Analytics Data Not Flowing**
   ```bash
   # Check Cloud Function logs
   gcloud functions logs read stream-analytics-processor --region=${REGION}
   
   # Verify Pub/Sub subscription
   gcloud pubsub subscriptions pull stream-events-bq-subscription --auto-ack
   ```

3. **CDN Cache Issues**
   ```bash
   # Check CDN service configuration
   gcloud network-services edge-cache-services describe your-cdn-service
   
   # Verify origin configuration
   gcloud network-services edge-cache-origins describe your-origin
   ```

### Log Analysis

```bash
# Cloud Function execution logs
gcloud logging read "resource.type=cloud_function resource.labels.function_name=stream-analytics-processor" \
    --limit=50 --format="table(timestamp,severity,textPayload)"

# Live Stream API logs
gcloud logging read "resource.type=livestream_channel" \
    --limit=50 --format="table(timestamp,severity,textPayload)"

# CDN access logs
gcloud logging read "resource.type=http_load_balancer" \
    --limit=50 --format="table(timestamp,httpRequest.requestUrl,httpRequest.status)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/streaming-analytics
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup Verification

```bash
# Verify resource deletion
gcloud livestream channels list --location=${REGION}
gcloud livestream inputs list --location=${REGION}
gsutil ls gs://your-bucket-name || echo "Bucket deleted"
bq ls ${PROJECT_ID}:streaming_analytics || echo "Dataset deleted"
```

## Security Considerations

### IAM and Access Control

- Service accounts use least privilege principles
- Cloud Functions run with minimal required permissions
- CDN access is configured with appropriate security headers
- BigQuery datasets have proper access controls

### Network Security

- All traffic encrypted in transit (HTTPS/TLS)
- Live Stream API endpoints use secure RTMP over TLS
- CDN configured with security policies
- Private networking where applicable

### Data Protection

- Video segments encrypted at rest in Cloud Storage
- Analytics data encrypted in BigQuery
- Pub/Sub messages encrypted in transit
- Access logging for audit trails

## Performance Optimization

### Scaling Considerations

- Cloud Functions automatically scale with event volume
- Live Stream API channels can be replicated across regions
- CDN automatically scales globally
- BigQuery handles large-scale analytics workloads

### Cost Optimization

- Storage lifecycle policies reduce long-term costs
- CDN caching policies minimize origin requests
- Cloud Functions use efficient resource allocation
- BigQuery slots optimized for query patterns

## Customization

### Adding Custom Analytics

```javascript
// Example Cloud Function modification for custom metrics
exports.processStreamingEvent = (req, res) => {
    const event = req.body;
    
    // Custom business logic
    if (event.eventType === 'buffer_start') {
        // Track buffer events for quality analysis
        customMetrics.bufferEvents.increment();
    }
    
    // Send to BigQuery
    bigquery.dataset('streaming_analytics')
        .table('streaming_events')
        .insert(processedEvent);
};
```

### Multi-Region Deployment

```hcl
# terraform/main.tf - Multi-region example
module "streaming_primary" {
  source = "./modules/streaming-analytics"
  region = "us-central1"
  # ... other variables
}

module "streaming_secondary" {
  source = "./modules/streaming-analytics"
  region = "europe-west1"
  # ... other variables
}
```

## Support and Documentation

- [Google Cloud Live Stream API Documentation](https://cloud.google.com/livestream/docs)
- [Media CDN Documentation](https://cloud.google.com/media-cdn/docs)
- [BigQuery Streaming Documentation](https://cloud.google.com/bigquery/docs/streaming-data-into-bigquery)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update variable descriptions and documentation
3. Verify security configurations
4. Update cost estimates if significant changes are made
5. Test deployment and cleanup procedures