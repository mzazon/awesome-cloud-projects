# Real-Time Event Processing with Cloud Memorystore and Pub/Sub

This Terraform configuration deploys a complete real-time event processing solution on Google Cloud Platform using Cloud Memorystore for Redis, Pub/Sub for messaging, Cloud Functions for serverless processing, and BigQuery for analytics.

## Architecture Overview

The solution provides:
- **Sub-millisecond data access** through Cloud Memorystore for Redis
- **Scalable event ingestion** via Pub/Sub topics and subscriptions
- **Serverless event processing** using Cloud Functions
- **Long-term analytics** with BigQuery data warehouse
- **Comprehensive monitoring** through Cloud Monitoring and Logging

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: A GCP project with billing enabled
2. **Terraform**: Version 1.3.0 or later installed
3. **Google Cloud CLI**: Latest version installed and authenticated
4. **Required APIs**: The following APIs will be enabled automatically:
   - Cloud Memorystore API
   - Pub/Sub API
   - Cloud Functions API
   - Cloud Build API
   - BigQuery API
   - Cloud Storage API
   - VPC Access API
   - Secret Manager API

5. **Permissions**: Your account needs the following IAM roles:
   - Project Editor or custom roles with equivalent permissions
   - Cloud Memorystore Admin
   - Pub/Sub Admin
   - Cloud Functions Admin
   - BigQuery Admin
   - Storage Admin
   - Network Admin

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/real-time-event-processing-memorystore-pub-sub/code/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
prefix = "event-processing"
redis_node_type = "SHARED_CORE_NANO"  # For development
# redis_node_type = "HIGHMEM_MEDIUM"  # For production

# Network configuration
main_subnet_cidr      = "10.0.0.0/24"
connector_subnet_cidr = "10.0.1.0/28"

# Performance tuning
function_memory = "512Mi"
function_max_instances = 100
redis_cache_ttl_seconds = 3600

# Security settings
redis_auth_enabled = false        # Enable for production
redis_encryption_enabled = false  # Enable for production
deletion_protection = true

# Monitoring
monitoring_enabled = true
error_rate_threshold = 5.0

# Labels for organization
labels = {
  project     = "event-processing"
  environment = "production"
  team        = "data-engineering"
  managed-by  = "terraform"
}
```

### 4. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 5. Verify Deployment

After successful deployment, test the system:

```bash
# Get the Pub/Sub topic name from outputs
TOPIC_NAME=$(terraform output -raw pubsub_topic_name)

# Publish a test event
gcloud pubsub topics publish $TOPIC_NAME \
  --message='{"id":"test-001","userId":"user123","type":"login","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","source":"web","metadata":{"ip":"192.168.1.1"}}'

# Check function logs
FUNCTION_NAME=$(terraform output -raw function_name)
gcloud functions logs read $FUNCTION_NAME --region=$(terraform output -raw region) --limit=10

# Query BigQuery for processed events
BQ_TABLE=$(terraform output -raw bigquery_table_full_name)
bq query --use_legacy_sql=false "SELECT COUNT(*) as event_count FROM \`$BQ_TABLE\` WHERE DATE(timestamp) = CURRENT_DATE()"
```

## Configuration Options

### Redis Configuration

```hcl
# Development setup
redis_node_type = "SHARED_CORE_NANO"
redis_shard_count = 1
redis_replica_count = 0
redis_multi_zone = false

# Production setup
redis_node_type = "HIGHMEM_MEDIUM"
redis_shard_count = 3
redis_replica_count = 1
redis_multi_zone = true
redis_auth_enabled = true
redis_encryption_enabled = true
```

### Cloud Functions Scaling

```hcl
# Cost-optimized setup
function_min_instances = 0
function_max_instances = 10
function_memory = "256Mi"

# High-performance setup
function_min_instances = 5
function_max_instances = 1000
function_memory = "1Gi"
function_concurrency = 100
```

### BigQuery Configuration

```hcl
# Multi-region for global access
bigquery_location = "US"

# Single region for data residency
bigquery_location = "us-central1"

# Data retention (90 days)
bigquery_partition_expiration_ms = 7776000000
```

## Monitoring and Alerting

The deployment includes comprehensive monitoring:

### Built-in Metrics
- Redis operations per second
- Pub/Sub message rates
- Cloud Function execution metrics
- BigQuery query performance
- Error rates and latencies

### Alerting Policies
- High error rate alerts (>5% by default)
- Redis memory usage alerts
- Function timeout alerts
- Dead letter queue monitoring

### Log-based Metrics
- Event processing rate
- Cache hit/miss ratios
- User activity patterns

### Console URLs

Access monitoring dashboards:

```bash
# Get console URLs
terraform output console_urls
```

## Performance Tuning

### Redis Optimization

1. **Memory Management**:
   ```hcl
   redis_node_type = "HIGHMEM_XLARGE"  # More memory
   ```

2. **High Availability**:
   ```hcl
   redis_multi_zone = true
   redis_replica_count = 1
   ```

3. **Persistence**:
   ```hcl
   redis_persistence_enabled = true  # RDB snapshots
   ```

### Function Optimization

1. **Warm Instances**:
   ```hcl
   function_min_instances = 5  # Keep instances warm
   ```

2. **Memory Allocation**:
   ```hcl
   function_memory = "1Gi"  # More memory for better performance
   function_cpu = "2"       # More CPU cores
   ```

3. **Concurrency**:
   ```hcl
   function_concurrency = 100  # Higher concurrency
   ```

### Pub/Sub Optimization

1. **Message Retention**:
   ```hcl
   pubsub_message_retention = "604800s"  # 7 days
   ```

2. **Acknowledgment Timeout**:
   ```hcl
   pubsub_ack_deadline_seconds = 300  # 5 minutes for complex processing
   ```

## Security Best Practices

### Network Security
- Private VPC with controlled access
- VPC Access Connector for function connectivity
- Firewall rules for internal communication only

### Authentication & Authorization
- Service accounts with minimal required permissions
- IAM roles scoped to specific resources
- Optional Redis AUTH and TLS encryption

### Data Protection
- Encryption at rest for BigQuery
- Optional transit encryption for Redis
- Secure credential management via Secret Manager

### Compliance
- Data residency controls via region selection
- Audit logging enabled by default
- Resource labeling for governance

## Cost Optimization

### Development Environment
```hcl
# Minimal resources for development
redis_node_type = "SHARED_CORE_NANO"
function_min_instances = 0
function_memory = "256Mi"
bigquery_partition_expiration_ms = 2592000000  # 30 days
```

### Production Environment
```hcl
# Balanced performance and cost
redis_node_type = "HIGHMEM_MEDIUM"
function_min_instances = 2
function_memory = "512Mi"
bigquery_partition_expiration_ms = 7776000000  # 90 days
```

### Cost Monitoring
- Use BigQuery partition expiration
- Configure function scaling policies
- Monitor Redis memory usage
- Set up billing alerts

## Troubleshooting

### Common Issues

1. **Function Connection Errors**:
   ```bash
   # Check VPC connector status
   gcloud compute networks vpc-access connectors list --region=$REGION
   
   # Verify Redis connectivity
   gcloud redis instances describe $REDIS_INSTANCE --region=$REGION
   ```

2. **BigQuery Permission Errors**:
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy $PROJECT_ID
   ```

3. **High Error Rates**:
   ```bash
   # Check function logs
   gcloud functions logs read $FUNCTION_NAME --region=$REGION --limit=50
   
   # Monitor Redis performance
   gcloud redis instances describe $REDIS_INSTANCE --region=$REGION
   ```

### Debug Commands

```bash
# Check all resources
terraform state list

# Get specific resource details
terraform state show google_memorystore_instance.redis_cache

# Refresh state
terraform refresh

# Plan with detailed logging
TF_LOG=DEBUG terraform plan
```

## Disaster Recovery

### Backup Strategy
- Redis: RDB snapshots (if enabled)
- BigQuery: Point-in-time recovery (7 days)
- Function code: Versioned in Cloud Storage

### Multi-Region Setup
```hcl
# Deploy to multiple regions
variable "regions" {
  default = ["us-central1", "us-east1"]
}

# Use global BigQuery location
bigquery_location = "US"
```

### Recovery Procedures
1. Deploy to secondary region
2. Update DNS/load balancer
3. Restore data from backups
4. Validate functionality

## Maintenance

### Regular Tasks
- Monitor resource utilization
- Review and rotate service account keys
- Update function dependencies
- Analyze BigQuery costs and optimize queries

### Terraform State Management
```bash
# Backup state file
cp terraform.tfstate terraform.tfstate.backup

# Import existing resources
terraform import google_redis_instance.main projects/$PROJECT_ID/locations/$REGION/instances/$INSTANCE_ID
```

### Updates and Upgrades
```bash
# Update providers
terraform init -upgrade

# Plan with new provider versions
terraform plan

# Apply updates
terraform apply
```

## Cleanup

To destroy all resources:

```bash
# Remove deletion protection first
terraform apply -var="deletion_protection=false"

# Destroy all resources
terraform destroy
```

## Support and Documentation

- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Memorystore Documentation](https://cloud.google.com/memorystore/docs)
- [Cloud Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)

## License

This Terraform configuration is provided as-is for educational and development purposes.