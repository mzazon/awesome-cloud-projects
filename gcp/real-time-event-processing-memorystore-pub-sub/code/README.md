# Infrastructure as Code for Real-Time Event Processing with Cloud Memorystore and Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Event Processing with Cloud Memorystore and Pub/Sub".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Appropriate Google Cloud project with billing enabled
- Required APIs enabled: Memorystore (Redis), Pub/Sub, Cloud Functions, Cloud Build, Cloud Monitoring
- Permissions for creating and managing:
  - Cloud Memorystore instances
  - Pub/Sub topics and subscriptions
  - Cloud Functions
  - VPC Access Connectors
  - BigQuery datasets and tables
  - IAM roles and service accounts

### Tool-Specific Prerequisites

#### Infrastructure Manager
- `gcloud infra-manager` command available
- Infrastructure Manager API enabled in your project

#### Terraform
- Terraform >= 1.0 installed
- Google Cloud provider >= 4.0

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/event-processing \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --local-source="." \
    --inputs-file="main.yaml" \
    --labels="environment=dev,recipe=event-processing"

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/event-processing
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager

Edit the `main.yaml` file to customize:

- **Redis Configuration**: Memory size, version, network settings
- **Pub/Sub Settings**: Message retention, acknowledgment deadlines
- **Function Settings**: Runtime version, memory allocation, timeout
- **Monitoring**: Custom dashboards and alerting policies

### Terraform

Customize deployment by modifying `terraform.tfvars`:

```hcl
# Project and location settings
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Redis instance configuration
redis_memory_size_gb    = 1
redis_version          = "REDIS_6_X"
redis_tier             = "BASIC"

# Pub/Sub configuration
message_retention_duration = "604800s"  # 7 days
ack_deadline_seconds      = 60

# Cloud Function configuration
function_memory_mb     = 512
function_timeout_s     = 540
function_max_instances = 100

# VPC Access Connector configuration
connector_min_instances = 2
connector_max_instances = 10
connector_machine_type  = "e2-micro"
```

### Bash Scripts

Modify environment variables in `scripts/deploy.sh`:

```bash
# Deployment configuration
export REDIS_MEMORY_SIZE="1"
export REDIS_VERSION="redis_6_x"
export FUNCTION_MEMORY="512MB"
export FUNCTION_TIMEOUT="540s"
export CONNECTOR_MIN_INSTANCES="2"
export CONNECTOR_MAX_INSTANCES="10"
```

## Deployment Architecture

This IaC deploys the following components:

1. **Cloud Memorystore Redis Instance**
   - Basic tier with configurable memory
   - Private IP connectivity within VPC
   - LRU eviction policy for optimal caching

2. **Pub/Sub Infrastructure**
   - Main event topic for message ingestion
   - Subscription with dead letter queue configuration
   - Message retention and acknowledgment policies

3. **Cloud Functions**
   - Event processing function with Pub/Sub trigger
   - VPC Access Connector for Redis connectivity
   - Environment variables for configuration

4. **BigQuery Analytics**
   - Dataset for storing processed events
   - Partitioned tables for query optimization
   - Time-based partitioning and clustering

5. **Monitoring and Observability**
   - Custom dashboards for system metrics
   - Alerting policies for critical thresholds
   - Integration with Cloud Logging

## Post-Deployment Verification

After deployment, verify the infrastructure:

### Check Redis Connectivity
```bash
# Create temporary VM for testing
gcloud compute instances create redis-test \
    --zone=${ZONE} \
    --machine-type=e2-micro \
    --image-family=ubuntu-2004-lts \
    --image-project=ubuntu-os-cloud

# Install Redis tools and test connection
gcloud compute ssh redis-test --zone=${ZONE} --command="
    sudo apt-get update && sudo apt-get install -y redis-tools
    redis-cli -h REDIS_HOST -p REDIS_PORT ping
"
```

### Test Event Processing
```bash
# Publish test message
gcloud pubsub topics publish events-topic-SUFFIX \
    --message='{"id":"test-001","userId":"user123","type":"login","timestamp":"2025-01-14T10:00:00Z"}'

# Check function logs
gcloud functions logs read event-processor-SUFFIX --limit=10

# Verify BigQuery data
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) FROM \`PROJECT_ID.event_analytics.processed_events\`"
```

## Cleanup

### Using Infrastructure Manager
```bash
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/event-processing
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

## Cost Optimization

### Development Environment
- Use Redis Basic tier (no high availability)
- Set lower Cloud Function memory allocation (256MB)
- Reduce VPC Access Connector instance count
- Use shorter message retention periods

### Production Environment
- Consider Redis Standard tier for high availability
- Implement Redis clustering for horizontal scaling
- Use Cloud Function concurrency controls
- Enable BigQuery slot reservations for predictable costs

## Security Considerations

### Network Security
- Redis instances use private IP addresses only
- VPC Access Connector provides secure function connectivity
- No public internet access to Redis instances

### Access Control
- Service accounts with minimal required permissions
- IAM roles follow principle of least privilege
- Function source code excludes hardcoded credentials

### Data Protection
- Pub/Sub messages encrypted in transit and at rest
- BigQuery datasets support customer-managed encryption keys
- Redis AUTH can be enabled for additional security

## Monitoring and Alerting

### Key Metrics to Monitor
- Redis memory utilization and operations per second
- Pub/Sub message rates and subscription lag
- Cloud Function execution duration and error rates
- BigQuery query performance and slot utilization

### Recommended Alerts
- Redis memory usage > 80%
- Pub/Sub subscription lag > 1 minute
- Function error rate > 5%
- VPC connector utilization > 90%

## Troubleshooting

### Common Issues

**Redis Connection Timeouts**
- Verify VPC Access Connector configuration
- Check firewall rules for Redis port access
- Confirm function VPC connector assignment

**Function Deployment Failures**
- Validate Node.js dependencies in package.json
- Check Cloud Build API enablement
- Verify service account permissions

**Pub/Sub Message Processing Delays**
- Monitor subscription acknowledgment deadlines
- Check function concurrency limits
- Verify dead letter queue configuration

### Debug Commands
```bash
# Check Redis instance status
gcloud redis instances describe INSTANCE_NAME --region=REGION

# Monitor function invocations
gcloud functions logs read FUNCTION_NAME --limit=50

# Check VPC connector health
gcloud compute networks vpc-access connectors describe CONNECTOR_NAME --region=REGION
```

## Performance Tuning

### Redis Optimization
- Adjust maxmemory-policy based on use case
- Monitor key expiration patterns
- Consider Redis pipelining for bulk operations

### Function Optimization
- Optimize memory allocation based on workload
- Implement connection pooling for Redis clients
- Use async/await patterns for better concurrency

### Pub/Sub Optimization
- Tune acknowledgment deadlines for processing time
- Configure flow control settings for high throughput
- Use ordering keys when message sequence matters

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check Google Cloud provider documentation
3. Review Terraform Google Cloud provider docs
4. Consult Infrastructure Manager service documentation

## Related Documentation

- [Cloud Memorystore for Redis Documentation](https://cloud.google.com/memorystore/docs/redis)
- [Cloud Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)