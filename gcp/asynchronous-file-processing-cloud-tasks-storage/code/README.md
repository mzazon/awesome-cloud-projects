# Infrastructure as Code for Asynchronous File Processing Workflows with Cloud Tasks and Cloud Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Asynchronous File Processing Workflows with Cloud Tasks and Cloud Storage".

## Overview

This solution implements a robust asynchronous file processing system using Google Cloud services. The architecture leverages Cloud Tasks for reliable job scheduling, Cloud Storage for durable file handling, Cloud Run for serverless processing, and Cloud Pub/Sub for event-driven triggers.

## Architecture Components

- **Cloud Storage Buckets**: Separate buckets for file uploads and processed results
- **Cloud Tasks Queue**: Reliable task scheduling with retry mechanisms
- **Cloud Run Services**: Serverless upload and processing services
- **Cloud Pub/Sub**: Event-driven notifications for file uploads
- **IAM Service Accounts**: Secure service-to-service communication

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Docker installed for containerizing Cloud Run services
- Appropriate Google Cloud permissions for:
  - Cloud Storage (create buckets, manage objects)
  - Cloud Tasks (create and manage queues)
  - Cloud Run (deploy and manage services)
  - Cloud Pub/Sub (create topics and subscriptions)
  - Cloud Build (build container images)
  - IAM (create service accounts and manage bindings)
- Billing enabled on your Google Cloud project
- Following APIs enabled:
  - Cloud Tasks API
  - Cloud Storage API
  - Cloud Pub/Sub API
  - Cloud Run API
  - Cloud Build API

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create async-file-processing \
    --location=${REGION} \
    --service-account=your-service-account@${PROJECT_ID}.iam.gserviceaccount.com \
    --gcs-source=gs://your-bucket/infrastructure-manager/ \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe async-file-processing \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Configuration

### Required Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | Yes |
| `zone` | Deployment zone | `us-central1-a` | No |
| `upload_bucket_name` | Name for upload bucket | `file-upload-${random}` | No |
| `results_bucket_name` | Name for results bucket | `file-results-${random}` | No |
| `pubsub_topic_name` | Pub/Sub topic name | `file-processing-${random}` | No |
| `task_queue_name` | Cloud Tasks queue name | `file-processing-queue-${random}` | No |

### Optional Customizations

- **Upload Service Configuration**:
  - Memory: 1Gi (configurable)
  - CPU: 1 (configurable)
  - Max instances: 10 (configurable)
  - Concurrency: 100 (configurable)

- **Processing Service Configuration**:
  - Memory: 2Gi (configurable)
  - CPU: 2 (configurable)
  - Max instances: 20 (configurable)
  - Concurrency: 50 (configurable)

- **Cloud Tasks Queue Configuration**:
  - Max dispatches per second: 10 (configurable)
  - Max concurrent dispatches: 100 (configurable)
  - Max retry attempts: 3 (configurable)

## Testing the Deployment

### Upload a Test File

```bash
# Get the upload service URL
UPLOAD_SERVICE_URL=$(gcloud run services describe upload-service \
    --region=${REGION} \
    --format="value(status.url)")

# Create a test image
python3 -c "
from PIL import Image
img = Image.new('RGB', (800, 600), color='red')
img.save('test-image.jpg', 'JPEG')
print('Test image created')
"

# Upload the test file
curl -X POST \
    -F "file=@test-image.jpg" \
    ${UPLOAD_SERVICE_URL}/upload
```

### Monitor Processing

```bash
# Check Cloud Tasks queue
gcloud tasks queues describe ${TASK_QUEUE_NAME} \
    --location=${REGION}

# Check processed files
gsutil ls gs://${RESULTS_BUCKET_NAME}/

# View Cloud Run logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=processing-service" \
    --limit=50 \
    --format="table(timestamp,textPayload)"
```

## Troubleshooting

### Common Issues

1. **Service Account Permissions**:
   - Ensure service accounts have necessary IAM roles
   - Check Cloud Run services are using correct service accounts

2. **Container Build Failures**:
   - Verify Docker is installed and running
   - Check Cloud Build API is enabled
   - Ensure sufficient permissions for Cloud Build

3. **File Upload Failures**:
   - Check Cloud Storage bucket permissions
   - Verify upload service is publicly accessible
   - Check Cloud Tasks queue configuration

4. **Processing Failures**:
   - Review Cloud Run service logs
   - Check processing service has access to storage buckets
   - Verify Cloud Tasks queue is properly configured

### Debugging Commands

```bash
# Check service status
gcloud run services list --region=${REGION}

# View service logs
gcloud logs read "resource.type=cloud_run_revision" --limit=50

# Check Cloud Tasks queue
gcloud tasks queues describe ${TASK_QUEUE_NAME} --location=${REGION}

# List recent tasks
gcloud tasks list --queue=${TASK_QUEUE_NAME} --location=${REGION}

# Check Pub/Sub subscriptions
gcloud pubsub subscriptions list
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete async-file-processing \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/verify-cleanup.sh
```

## Cost Optimization

### Cost Factors

- **Cloud Storage**: $0.020 per GB per month for Standard storage
- **Cloud Tasks**: $0.40 per million operations
- **Cloud Run**: Pay-per-use pricing (CPU, memory, requests)
- **Cloud Pub/Sub**: $0.40 per million operations
- **Cloud Build**: $0.003 per build-minute

### Cost Optimization Tips

1. **Use appropriate Cloud Storage classes**: Consider Nearline or Coldline for results that don't require immediate access
2. **Configure Cloud Run auto-scaling**: Set appropriate min/max instances to control costs
3. **Implement lifecycle policies**: Automatically delete old files from storage buckets
4. **Monitor usage**: Use Cloud Monitoring to track resource utilization
5. **Set up billing alerts**: Get notified when costs exceed thresholds

## Security Best Practices

### Implemented Security Features

- **Service Account Isolation**: Separate service accounts for each service
- **Least Privilege IAM**: Minimal required permissions for each component
- **Private Service Communication**: Processing service not publicly accessible
- **Encrypted Storage**: All data encrypted at rest and in transit
- **VPC Security**: Services deployed in secure network configuration

### Additional Security Recommendations

1. **Enable audit logging**: Track all API calls and resource access
2. **Use Cloud KMS**: Encrypt sensitive data with customer-managed keys
3. **Implement network security**: Use VPC firewall rules and private Google access
4. **Regular security reviews**: Audit IAM policies and service configurations
5. **Vulnerability scanning**: Enable container analysis for Cloud Run images

## Monitoring and Observability

### Available Metrics

- **Cloud Run**: Request latency, error rates, instance utilization
- **Cloud Tasks**: Queue depth, task execution rates, retry counts
- **Cloud Storage**: Request rates, data transfer, storage usage
- **Cloud Pub/Sub**: Message throughput, subscription backlog

### Monitoring Setup

```bash
# Create alerting policy for high queue depth
gcloud alpha monitoring policies create --policy-from-file=monitoring/queue-depth-alert.yaml

# Set up dashboard
gcloud alpha monitoring dashboards create --config-from-file=monitoring/dashboard.yaml
```

## Performance Optimization

### Tuning Recommendations

1. **Cloud Run Configuration**:
   - Adjust memory/CPU based on workload requirements
   - Configure appropriate concurrency limits
   - Set optimal timeout values

2. **Cloud Tasks Configuration**:
   - Tune dispatch rates based on processing capacity
   - Adjust retry policies for your use case
   - Consider using named tasks for deduplication

3. **Storage Optimization**:
   - Use appropriate storage classes
   - Implement caching strategies
   - Consider CDN for frequently accessed results

## Support and Documentation

### Additional Resources

- [Google Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)

### Getting Help

- For infrastructure issues: Check Google Cloud Status page
- For deployment issues: Review logs and troubleshooting section
- For custom modifications: Refer to the original recipe documentation

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements and policies.