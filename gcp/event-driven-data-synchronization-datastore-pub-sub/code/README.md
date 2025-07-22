# Infrastructure as Code for Event-Driven Data Synchronization with Cloud Datastore and Cloud Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven Data Synchronization with Cloud Datastore and Cloud Pub/Sub".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Datastore Admin
  - Pub/Sub Admin
  - Cloud Functions Admin
  - Cloud Logging Admin
  - Service Account Admin
  - Project IAM Admin
- Python 3.9+ for Cloud Functions development
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses Terraform configurations with Google Cloud integration.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/datastore-sync-deployment \
    --service-account=YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --local-source=. \
    --input-values=project_id=YOUR_PROJECT_ID,region=us-central1

# Check deployment status
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/datastore-sync-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts to set project ID and region
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Datastore**: NoSQL database for storing synchronized entities
- **Cloud Pub/Sub**: Message queuing service with topics and subscriptions
- **Cloud Functions**: Serverless functions for data processing and audit logging
- **Cloud Logging**: Centralized logging for audit trails and monitoring
- **Dead Letter Queues**: Error handling for failed message processing
- **IAM Roles**: Least privilege access controls for all components

## Configuration Options

### Infrastructure Manager Variables

Edit the `terraform.tfvars` file in the `infrastructure-manager/` directory:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
topic_name_suffix          = "custom"
function_memory_mb         = 256
function_timeout_seconds   = 60
max_delivery_attempts      = 5
message_retention_days     = 7
```

### Terraform Variables

Create a `terraform.tfvars` file in the `terraform/` directory:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
environment               = "dev"
sync_function_memory     = 256
audit_function_memory    = 128
dead_letter_retention    = "30d"
```

### Bash Script Configuration

The deployment script will prompt for required values:

- Google Cloud Project ID
- Deployment region
- Deployment zone
- Custom resource name suffix (optional)

## Deployment Details

### Resources Created

1. **Pub/Sub Resources**:
   - Main topic for data synchronization events
   - Subscription for sync processing
   - Subscription for audit logging  
   - Dead letter topic and subscription

2. **Cloud Functions**:
   - Data synchronization processor function
   - Audit logging function
   - Conflict resolution logic

3. **IAM Configuration**:
   - Service accounts for Cloud Functions
   - Least privilege IAM bindings
   - Cross-service permissions

4. **Monitoring**:
   - Cloud Logging configuration
   - Structured logging setup
   - Error tracking and alerting

### Security Features

- **Least Privilege IAM**: Each component has minimal required permissions
- **Service Account Isolation**: Separate service accounts for different functions
- **Audit Logging**: Comprehensive logging for all data operations
- **Dead Letter Queues**: Secure handling of failed messages
- **Data Encryption**: Encryption at rest and in transit by default

## Testing the Deployment

After deployment, test the system using the provided data publisher script:

```bash
# Install Python dependencies
pip3 install google-cloud-pubsub google-cloud-datastore

# Test create operation
python3 scripts/test_publisher.py \
    --project YOUR_PROJECT_ID \
    --topic data-sync-events-SUFFIX \
    --entity-id test-001 \
    --operation create \
    --name "Test Entity"

# Test update operation
python3 scripts/test_publisher.py \
    --project YOUR_PROJECT_ID \
    --topic data-sync-events-SUFFIX \
    --entity-id test-001 \
    --operation update \
    --description "Updated description"

# Verify in Cloud Console
gcloud datastore entities query --kind="SyncEntity" --limit=10
```

## Monitoring and Observability

### Cloud Logging

View logs for different components:

```bash
# Sync function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=data-sync-processor-*" --limit=50

# Audit function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=audit-logger-*" --limit=50

# Pub/Sub logs
gcloud logging read "resource.type=pubsub_topic" --limit=50
```

### Cloud Monitoring

Access the automatically created dashboard:

1. Go to Cloud Monitoring in Google Cloud Console
2. Look for "Datastore Sync Monitoring" dashboard
3. Monitor message rates, function executions, and error rates

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   
   # Verify service account permissions
   gcloud iam service-accounts get-iam-policy SERVICE_ACCOUNT_EMAIL
   ```

2. **Function Deployment Failures**:
   ```bash
   # Check function logs
   gcloud functions logs read FUNCTION_NAME --limit=20
   
   # Verify function configuration
   gcloud functions describe FUNCTION_NAME
   ```

3. **Message Processing Issues**:
   ```bash
   # Check subscription backlog
   gcloud pubsub subscriptions describe SUBSCRIPTION_NAME
   
   # View dead letter queue
   gcloud pubsub subscriptions pull DLQ_SUBSCRIPTION_NAME --limit=10
   ```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export GOOGLE_CLOUD_PROJECT=your-project-id
export DEBUG=true
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/datastore-sync-deployment

# Confirm deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

**Warning**: The destroy script will permanently delete all resources including stored data. Make sure to backup any important data before cleanup.

## Customization

### Extending the Solution

1. **Add Custom Processing Logic**:
   - Modify Cloud Functions in `functions/` directory
   - Update function configurations in IaC templates
   - Redeploy using your chosen method

2. **Integrate External Systems**:
   - Add new Pub/Sub topics for external integration
   - Create additional Cloud Functions for system adapters
   - Configure appropriate IAM permissions

3. **Enhance Monitoring**:
   - Add custom metrics using Cloud Monitoring API
   - Create additional dashboards
   - Set up alerting policies

### Performance Tuning

1. **Function Configuration**:
   - Adjust memory allocation based on workload
   - Modify timeout settings for long-running operations
   - Configure concurrent execution limits

2. **Pub/Sub Settings**:
   - Tune acknowledgment deadlines
   - Adjust message retention periods
   - Configure subscription filters

3. **Datastore Optimization**:
   - Create composite indexes for complex queries
   - Implement query cursors for large datasets
   - Use entity groups for strong consistency

## Cost Optimization

- **Cloud Functions**: Pay-per-invocation pricing with generous free tier
- **Pub/Sub**: Message-based pricing with first 10GB free per month
- **Datastore**: Storage and operation-based pricing with daily free quotas
- **Cloud Logging**: Log volume-based pricing with 50GB free per month

Estimated monthly cost for development workloads: $5-15 USD

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for architectural guidance
2. Review Google Cloud documentation for service-specific issues
3. Use `gcloud` CLI help commands for troubleshooting
4. Monitor Cloud Logging for detailed error information

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Terraform Version**: >= 1.0
- **Google Cloud Provider**: >= 4.0
- **Python Runtime**: 3.9

## Related Documentation

- [Google Cloud Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Google Cloud Datastore Documentation](https://cloud.google.com/datastore/docs)
- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)