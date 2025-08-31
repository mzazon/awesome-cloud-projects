# Smart Parking Management - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete smart parking management system on Google Cloud Platform. The infrastructure includes Pub/Sub messaging, Cloud Functions for serverless processing, Firestore for real-time data storage, and Google Maps Platform integration.

## Architecture Overview

The deployed infrastructure creates a scalable IoT parking management system with the following components:

- **Pub/Sub**: Message ingestion from MQTT brokers and IoT sensors
- **Cloud Functions**: Serverless data processing and REST API
- **Firestore**: NoSQL database for real-time parking data
- **Maps Platform**: Location services and geocoding APIs
- **IAM**: Service accounts and security policies
- **Monitoring**: Cloud Monitoring alerts and logging
- **Storage**: Function source code and deployment artifacts

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud CLI** installed and configured
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.0)
   ```bash
   terraform version
   ```

3. **Required permissions** in your Google Cloud project:
   - Project Editor or custom role with API enablement permissions
   - Cloud Functions Admin
   - Pub/Sub Admin
   - Firestore Admin
   - Service Account Admin
   - Cloud Storage Admin

4. **Billing enabled** on your Google Cloud project

5. **API quotas** sufficient for your expected usage

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your project details
nano terraform.tfvars
```

### 2. Essential Variables

At minimum, configure these variables in `terraform.tfvars`:

```hcl
# Required: Your Google Cloud Project ID
project_id = "your-gcp-project-id"

# Recommended: Choose your preferred region
region = "us-central1"

# Optional: Environment designation
environment = "dev"

# Optional: Project naming
project_name = "smart-parking"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform (download providers and modules)
terraform init

# Plan the deployment (review changes)
terraform plan

# Deploy the infrastructure
terraform apply
```

The deployment typically takes 5-10 minutes and will create approximately 15-20 Google Cloud resources.

### 4. Verify Deployment

After successful deployment, test the infrastructure:

```bash
# Test the parking API endpoint
curl "$(terraform output -raw parking_api_function_url)/health"

# Publish a test message to Pub/Sub
gcloud pubsub topics publish $(terraform output -raw pubsub_topic_name) \
  --message='{"space_id":"A001","sensor_id":"test-sensor","occupied":false,"confidence":0.95,"zone":"downtown","location":{"lat":37.7749,"lng":-122.4194}}'

# Check function logs
gcloud functions logs read $(terraform output -raw parking_processor_function_name) \
  --region=$(terraform output -raw region) --gen2 --limit=10
```

## Configuration Options

### Environment Variables

The Terraform configuration supports extensive customization through variables:

#### Core Configuration
- `project_id`: Google Cloud Project ID (required)
- `region`: Deployment region (default: "us-central1")
- `environment`: Environment name (default: "dev")
- `project_name`: Project naming prefix (default: "smart-parking")

#### Function Configuration
- `function_runtime`: Node.js runtime version (default: "nodejs20")
- `function_memory`: Memory allocation in MB (default: 256)
- `function_timeout`: Timeout in seconds (default: 60)
- `function_max_instances`: Maximum auto-scaling instances (default: 100)

#### Security Configuration
- `enable_api_authentication`: Require authentication for API (default: false)
- `create_service_account_key`: Create MQTT service account key (default: true)
- `enable_maps_api_restrictions`: Enable Maps API restrictions (default: true)

#### Networking Configuration
- `enable_private_google_access`: Use private VPC (default: false)
- `enable_vpc_flow_logs`: Enable VPC flow logging (default: false)

#### Monitoring Configuration
- `enable_monitoring`: Enable Cloud Monitoring alerts (default: true)
- `enable_cloud_logging`: Enable centralized logging (default: true)
- `log_retention_days`: Log retention period (default: 30)

### Example terraform.tfvars

```hcl
# Project Configuration
project_id   = "my-smart-parking-project"
region       = "us-west2"
environment  = "production"
project_name = "smart-parking"

# Function Configuration
function_memory      = 512
function_max_instances = 50
function_runtime     = "nodejs20"

# Security Configuration
enable_api_authentication = true
enable_maps_api_restrictions = true
maps_allowed_referrers = ["https://myapp.example.com/*"]

# Monitoring Configuration
enable_monitoring = true
log_retention_days = 90

# Labels for cost tracking
labels = {
  project     = "smart-parking"
  environment = "production"
  team        = "iot-team"
  cost-center = "engineering"
}
```

## API Usage

After deployment, the parking management API provides these endpoints:

### Search for Parking Spaces
```bash
curl "https://YOUR_FUNCTION_URL/parking/search?lat=37.7749&lng=-122.4194&radius=1000"
```

### Get Zone Statistics
```bash
curl "https://YOUR_FUNCTION_URL/parking/zones/downtown/stats"
```

### List All Zones
```bash
curl "https://YOUR_FUNCTION_URL/parking/zones"
```

### Health Check
```bash
curl "https://YOUR_FUNCTION_URL/health"
```

### API Documentation
```bash
curl "https://YOUR_FUNCTION_URL/api-info"
```

## MQTT Broker Integration

The infrastructure creates a service account for MQTT broker authentication. Configure your MQTT broker with:

1. **Service Account**: Use the created service account for authentication
2. **Pub/Sub Topic**: Publish to the created topic
3. **Message Format**: Send JSON messages with required fields

### Required Message Schema
```json
{
  "space_id": "A001",
  "sensor_id": "parking-sensor-01", 
  "occupied": false,
  "confidence": 0.98,
  "zone": "downtown",
  "location": {
    "lat": 37.7749,
    "lng": -122.4194
  },
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### MQTT Broker Configuration

```bash
# Get service account email
terraform output mqtt_service_account_email

# Get Pub/Sub topic name
terraform output pubsub_topic_name

# Get service account key (if created)
gcloud secrets versions access latest --secret="$(terraform output mqtt_service_account_key_secret)"
```

## Monitoring and Alerting

The infrastructure includes comprehensive monitoring:

### Cloud Monitoring Dashboards
- Function execution metrics
- Pub/Sub message throughput
- Firestore read/write operations
- API response times and error rates

### Alert Policies
- High Pub/Sub message backlog (>1000 messages)
- Cloud Function error rate >10%
- Firestore connection failures
- API endpoint downtime

### Log Analysis
```bash
# View function logs
gcloud functions logs read FUNCTION_NAME --region=REGION --gen2

# View Pub/Sub logs
gcloud logging read "resource.type=pubsub_topic"

# View API access logs
gcloud logging read "resource.type=cloud_function AND textPayload:\"API Request\""
```

## Security Considerations

### Production Security Checklist

- [ ] Enable API authentication (`enable_api_authentication = true`)
- [ ] Restrict Maps API key to specific domains/IPs
- [ ] Use workload identity instead of service account keys
- [ ] Enable private VPC networking (`enable_private_google_access = true`)
- [ ] Configure audit logging for compliance
- [ ] Set up backup and disaster recovery policies
- [ ] Review and customize IAM permissions
- [ ] Enable VPC flow logs for security monitoring

### IAM Permissions

The Terraform configuration creates minimal IAM permissions:

- **MQTT Service Account**: `roles/pubsub.publisher`
- **Functions Service Account**: `roles/datastore.user`, `roles/logging.logWriter`
- **API Access**: Public or authenticated based on configuration

## Cost Optimization

### Estimated Costs (USD/month)

#### Development Environment
- **Light usage** (1K sensors, 10 updates/hour): $18-53/month
- **Pub/Sub**: $2-5 (240M messages)
- **Cloud Functions**: $5-10 (480K invocations)  
- **Firestore**: $5-15 (depends on document size)
- **Maps Platform**: $5-20 (depends on API usage)
- **Storage & Logging**: $1-3

#### Production Environment  
- **High usage** (10K sensors, 6 updates/hour): $175-500/month
- **Pub/Sub**: $20-40 (1.44B messages)
- **Cloud Functions**: $50-100 (2.88M invocations)
- **Firestore**: $50-150 (higher read/write volume)
- **Maps Platform**: $50-200 (higher API usage)
- **Storage & Logging**: $5-10

### Cost Optimization Strategies

1. **Function Memory**: Adjust based on actual usage patterns
2. **Pub/Sub Retention**: Reduce retention period for non-critical data
3. **Maps API**: Implement caching to reduce API calls
4. **Firestore Reads**: Optimize query patterns and use caching
5. **Logging**: Adjust retention periods and filter unnecessary logs

## Backup and Disaster Recovery

### Firestore Backup Strategy
```bash
# Enable point-in-time recovery (enabled by default)
gcloud firestore databases update --database=DATABASE_ID --point-in-time-recovery-enablement=ENABLED

# Create manual backup
gcloud firestore export gs://YOUR_BACKUP_BUCKET --collection-ids=parking_spaces,parking_zones
```

### Function Source Code Backup
- Source code is automatically versioned in Cloud Storage
- Keep Terraform state in remote backend (e.g., Cloud Storage)
- Version control your Terraform configuration

### Recovery Procedures
1. **Complete Infrastructure Loss**: Re-run `terraform apply`
2. **Function Failure**: Automatic retry and dead letter queue handling
3. **Database Corruption**: Restore from point-in-time recovery
4. **Configuration Drift**: Run `terraform plan` to detect changes

## Troubleshooting

### Common Issues

#### Function Deployment Failures
```bash
# Check Cloud Build logs
gcloud builds list --limit=5

# Check function configuration
gcloud functions describe FUNCTION_NAME --region=REGION --gen2
```

#### Pub/Sub Message Processing Issues
```bash
# Check subscription backlog
gcloud pubsub subscriptions describe SUBSCRIPTION_NAME

# Check dead letter queue
gcloud pubsub topics list-subscriptions DEAD_LETTER_TOPIC
```

#### API Connectivity Issues
```bash
# Test function URL directly
curl -v "https://FUNCTION_URL/health"

# Check IAM permissions
gcloud functions get-iam-policy FUNCTION_NAME --region=REGION
```

#### Firestore Connection Issues
```bash
# Test Firestore connectivity
gcloud firestore databases list

# Check service account permissions
gcloud projects get-iam-policy PROJECT_ID
```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export TF_LOG=DEBUG
terraform apply
```

## Cleanup

### Remove All Resources

```bash
# Destroy all infrastructure
terraform destroy

# Verify cleanup
gcloud functions list --regions=REGION
gcloud pubsub topics list
gcloud firestore databases list
```

### Selective Cleanup

```bash
# Remove specific resources
terraform destroy -target=google_cloudfunctions2_function.parking_api
terraform destroy -target=google_pubsub_topic.parking_events
```

**⚠️ Warning**: Destroying Firestore databases is irreversible and will permanently delete all data.

## Support and Contributing

### Getting Help
- Review the [original recipe documentation](../smart-parking-management-maps-iot.md)
- Check Google Cloud [status page](https://status.cloud.google.com/)
- Review Terraform [Google provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Contributing
- Submit issues and feature requests via GitHub
- Follow Google Cloud and Terraform best practices
- Test changes in development environment before production

### Version History
- **v1.0**: Initial release with basic parking management functionality
- **v1.1**: Added monitoring and alerting capabilities
- **v1.2**: Enhanced security and VPC networking options

---

For more detailed information about the smart parking system architecture and business use cases, refer to the [main recipe documentation](../smart-parking-management-maps-iot.md).