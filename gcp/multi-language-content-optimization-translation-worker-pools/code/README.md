# Infrastructure as Code for Multi-Language Content Optimization with Cloud Translation Advanced and Cloud Run Worker Pools

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Language Content Optimization with Cloud Translation Advanced and Cloud Run Worker Pools".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Translation API
  - Cloud Run Worker Pools
  - Cloud Storage
  - Pub/Sub
  - BigQuery
  - Cloud Build
  - IAM Service Account management
- Docker installed (for local development)
- Terraform >= 1.0 (for Terraform deployment)

## Architecture Overview

This solution deploys an intelligent content optimization system using:

- **Cloud Translation Advanced**: High-quality batch translations with custom models
- **Cloud Run Worker Pools**: Serverless background processing for translation jobs
- **Cloud Storage**: Source content, translated output, and custom model storage
- **Pub/Sub**: Event-driven message processing
- **BigQuery**: Analytics and engagement metrics storage
- **IAM Service Accounts**: Secure service-to-service authentication

## Quick Start

### Using Infrastructure Manager

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable required APIs
gcloud services enable config.googleapis.com

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/translation-optimization \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source infrastructure-manager/ \
    --inputs-file infrastructure-manager/inputs.yaml
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
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

# Monitor deployment progress
gcloud run worker-pools list --region=${REGION}
```

## Configuration

### Infrastructure Manager Configuration

The Infrastructure Manager deployment uses these key configuration files:

- `infrastructure-manager/main.yaml`: Main deployment configuration
- `infrastructure-manager/inputs.yaml`: Input parameters for customization

### Terraform Variables

Key variables you can customize in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Storage configuration
source_bucket_name = "content-source-unique-suffix"
translated_bucket_name = "content-translated-unique-suffix"
models_bucket_name = "translation-models-unique-suffix"

# Pub/Sub configuration
topic_name = "content-processing"
subscription_name = "content-processing-sub"

# Worker Pool configuration
worker_pool_name = "translation-workers"
worker_pool_cpu = "2"
worker_pool_memory = "4Gi"
worker_pool_min_instances = 1
worker_pool_max_instances = 10

# BigQuery configuration
dataset_name = "content_analytics"
dataset_location = "US"

# Tags for resource organization
labels = {
  environment = "production"
  application = "content-optimization"
  team = "platform"
}
```

### Script Configuration

The bash scripts use environment variables for configuration. Set these before running:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional: Customize resource names
export SOURCE_BUCKET="content-source-$(date +%s)"
export TRANSLATED_BUCKET="content-translated-$(date +%s)"
export MODELS_BUCKET="translation-models-$(date +%s)"
export TOPIC_NAME="content-processing-$(date +%s)"
export WORKER_POOL_NAME="translation-workers-$(date +%s)"
export DATASET_NAME="content_analytics_$(date +%s)"
```

## Testing the Deployment

After deployment, test the system functionality:

### 1. Verify Worker Pool Status

```bash
gcloud run worker-pools describe ${WORKER_POOL_NAME} \
    --region ${REGION} \
    --format="table(metadata.name,status.url,status.conditions[0].type:label=STATUS)"
```

### 2. Upload Sample Content

```bash
# Create sample content
echo "Welcome to our innovative cloud platform that transforms business operations." > sample-content.txt

# Upload to source bucket
gsutil cp sample-content.txt gs://${SOURCE_BUCKET}/

# Trigger translation job
gcloud pubsub topics publish ${TOPIC_NAME} --message='{
    "content_id": "test-content-001",
    "batch_id": "test-batch-001",
    "source_language": "en",
    "target_languages": ["es", "fr", "de"],
    "source_uri": "gs://'${SOURCE_BUCKET}'/sample-content.txt",
    "output_uri_prefix": "gs://'${TRANSLATED_BUCKET}'/test/",
    "content_type": "marketing",
    "mime_type": "text/plain"
}'
```

### 3. Monitor Translation Progress

```bash
# Check Pub/Sub subscription metrics
gcloud pubsub subscriptions describe ${TOPIC_NAME}-sub

# View worker pool logs
gcloud run worker-pools logs read ${WORKER_POOL_NAME} --region ${REGION}

# Check translated output
gsutil ls -l gs://${TRANSLATED_BUCKET}/
```

### 4. Query Analytics Data

```bash
# Check BigQuery performance metrics
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.translation_performance\` ORDER BY timestamp DESC LIMIT 10"

# Check engagement metrics
bq query --use_legacy_sql=false \
    "SELECT language, AVG(engagement_score) as avg_engagement FROM \`${PROJECT_ID}.${DATASET_NAME}.engagement_metrics\` GROUP BY language"
```

## Monitoring and Observability

The deployment includes comprehensive monitoring capabilities:

### Cloud Monitoring Integration

- Worker Pool performance metrics
- Translation API usage and quotas
- Storage bucket access patterns
- Pub/Sub message processing rates

### BigQuery Analytics

- Translation performance tracking
- Content engagement metrics
- Cost optimization insights
- Quality scoring and trends

### Logging

- Worker Pool execution logs
- Translation API request/response logging
- Error tracking and alerting
- Performance debugging information

## Security Considerations

The infrastructure implements security best practices:

### IAM and Access Control

- Least privilege service account permissions
- Resource-level IAM bindings
- Workload Identity for secure service authentication
- Audit logging for compliance tracking

### Data Protection

- Encryption at rest for all storage
- Encryption in transit for all API communications
- Private network configurations where applicable
- Secure handling of translation models and content

### Network Security

- VPC-native configurations
- Private service access for APIs
- Firewall rules for worker pool communication
- Secure bucket access policies

## Cost Optimization

### Resource Scaling

- Auto-scaling worker pools based on message queue depth
- Intelligent instance sizing based on workload patterns
- Storage lifecycle policies for cost management
- BigQuery slot optimization for analytics workloads

### Translation Cost Management

- Batch processing for optimal API pricing
- Custom model usage based on engagement metrics
- Quality vs. cost optimization algorithms
- Usage monitoring and budget alerts

## Troubleshooting

### Common Issues

1. **Worker Pool Not Processing Messages**
   ```bash
   # Check IAM permissions
   gcloud iam service-accounts get-iam-policy translation-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com
   
   # Verify Pub/Sub subscription
   gcloud pubsub subscriptions describe ${TOPIC_NAME}-sub
   ```

2. **Translation API Quota Exceeded**
   ```bash
   # Check current quotas
   gcloud services list --enabled --filter="name:translate.googleapis.com"
   
   # Monitor API usage
   gcloud logging read 'resource.type="api" AND protoPayload.serviceName="translate.googleapis.com"'
   ```

3. **Storage Access Issues**
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://${SOURCE_BUCKET}
   
   # Test service account access
   gsutil -i translation-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com ls gs://${SOURCE_BUCKET}
   ```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Set debug environment variable
export DEBUG=true

# Redeploy with debug logging
./scripts/deploy.sh

# View detailed logs
gcloud run worker-pools logs read ${WORKER_POOL_NAME} --region ${REGION} --limit 100
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/translation-optimization
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud run worker-pools list --region=${REGION}
gcloud storage buckets list --project=${PROJECT_ID}
gcloud pubsub topics list --project=${PROJECT_ID}
bq ls --project_id=${PROJECT_ID}
```

## Customization

### Extending the Solution

1. **Custom Translation Models**: Integrate AutoML Translation model training
2. **Multi-Modal Content**: Support document translation with Document AI
3. **Real-Time Processing**: Add Cloud Functions for immediate translation
4. **Advanced Analytics**: Create Looker dashboards for business insights
5. **Hybrid Workflows**: Implement human review integration

### Configuration Examples

#### High-Volume Processing

```hcl
# terraform.tfvars
worker_pool_min_instances = 5
worker_pool_max_instances = 50
worker_pool_cpu = "4"
worker_pool_memory = "8Gi"
```

#### Cost-Optimized Setup

```hcl
# terraform.tfvars
worker_pool_min_instances = 0
worker_pool_max_instances = 5
worker_pool_cpu = "1"
worker_pool_memory = "2Gi"
```

#### Multi-Region Deployment

```hcl
# terraform.tfvars
regions = ["us-central1", "europe-west1", "asia-southeast1"]
enable_global_load_balancing = true
```

## Performance Tuning

### Worker Pool Optimization

- CPU and memory allocation based on content complexity
- Concurrency settings for translation API calls
- Message acknowledgment timeout configuration
- Instance scaling policies for cost vs. performance balance

### Translation Quality Settings

- Custom model usage thresholds
- Quality vs. speed optimization parameters
- Batch size optimization for different content types
- Engagement-based quality level selection

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../multi-language-content-optimization-translation-worker-pools.md)
2. Review Google Cloud [Translation API documentation](https://cloud.google.com/translate/docs)
3. Consult [Cloud Run Worker Pools documentation](https://cloud.google.com/run/docs/workerpools)
4. Check [Terraform Google Cloud provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any new variables or resources
3. Validate security configurations
4. Update cost estimates for significant changes
5. Test both deployment and cleanup procedures