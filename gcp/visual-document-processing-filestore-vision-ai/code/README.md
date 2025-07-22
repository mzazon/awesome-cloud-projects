# Infrastructure as Code for Visual Document Processing with Cloud Filestore and Vision AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Visual Document Processing with Cloud Filestore and Vision AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate Google Cloud permissions for:
  - Cloud Filestore management
  - Cloud Vision AI access
  - Cloud Pub/Sub topic and subscription management
  - Cloud Functions deployment
  - Cloud Storage bucket management
  - Compute Engine instance management
  - Service account and IAM management
- Project with billing enabled
- Required APIs enabled (handled automatically in deployment scripts)

## Quick Start

### Using Infrastructure Manager

```bash
# Initialize and deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/document-processing \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --git-source-repo="https://source.developers.google.com/p/PROJECT_ID/r/REPO_NAME" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main"
```

### Using Terraform

```bash
# Initialize and deploy using Terraform
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts

```bash
# Deploy using automated scripts
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys an automated document processing pipeline with the following components:

- **Cloud Filestore**: High-performance NFS storage for shared document access
- **Cloud Pub/Sub**: Event-driven messaging for processing pipeline coordination
- **Cloud Functions**: Serverless processing for file monitoring and Vision AI integration
- **Cloud Vision AI**: Intelligent text extraction and document analysis
- **Cloud Storage**: Durable storage for processed results and metadata
- **Compute Engine**: Client instance for Filestore mounting and document uploads

## Configuration Variables

### Infrastructure Manager Variables

Key configuration options available in the Infrastructure Manager deployment:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `filestore_capacity`: Filestore instance capacity in GB (default: 1024)
- `filestore_tier`: Filestore performance tier (STANDARD/PREMIUM)

### Terraform Variables

Key configuration options in `terraform/variables.tf`:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region for resources
- `zone`: Compute zone for zonal resources
- `filestore_instance_name`: Name for the Filestore instance
- `storage_bucket_name`: Name for the processed results bucket
- `pubsub_topic_name`: Name for the document processing topic
- `function_memory`: Memory allocation for Cloud Functions (default: 512MB)
- `function_timeout`: Timeout for Cloud Functions in seconds (default: 300)

Example `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
filestore_instance_name = "docs-filestore"
storage_bucket_name = "processed-documents"
pubsub_topic_name = "document-processing"
```

## Deployment Process

### 1. Environment Setup

Set required environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
```

### 2. API Enablement

The following APIs will be automatically enabled during deployment:

- Compute Engine API
- Cloud Filestore API
- Cloud Vision API
- Cloud Pub/Sub API
- Cloud Functions API
- Cloud Storage API
- Cloud Build API

### 3. Resource Creation

The infrastructure creates these resources in order:

1. Cloud Filestore instance with NFS share
2. Cloud Pub/Sub topics and subscriptions
3. Cloud Storage bucket with lifecycle policies
4. Cloud Functions for file monitoring and processing
5. Compute Engine instance with Filestore mounting
6. IAM service accounts and permissions

### 4. Validation

After deployment, verify the infrastructure:

```bash
# Check Filestore instance
gcloud filestore instances list --filter="zone:${ZONE}"

# Verify Pub/Sub topics
gcloud pubsub topics list

# Check Cloud Functions
gcloud functions list --filter="region:${REGION}"

# Validate storage bucket
gsutil ls -L gs://your-bucket-name
```

## Testing the Pipeline

### Manual Testing

1. **Trigger document processing**:

   ```bash
   # Publish test message to trigger processing
   gcloud pubsub topics publish document-processing \
       --message='{"filename":"test_document.pdf","filepath":"/mnt/filestore/documents/test_document.pdf"}'
   ```

2. **Monitor processing**:

   ```bash
   # Check function logs
   gcloud functions logs read vision-processor --limit=10
   
   # Check processed results
   gsutil ls gs://your-bucket-name/processed/
   ```

3. **Verify Filestore mounting**:

   ```bash
   # SSH to client instance
   gcloud compute ssh filestore-client --zone=${ZONE}
   
   # Check mount point
   df -h /mnt/filestore
   ls -la /mnt/filestore/
   ```

### Performance Testing

Test document processing throughput:

```bash
# Publish multiple documents for processing
for i in {1..10}; do
  gcloud pubsub topics publish document-processing \
      --message='{"filename":"doc_'$i'.pdf","filepath":"/mnt/filestore/documents/doc_'$i'.pdf"}'
done

# Monitor processing metrics
gcloud functions logs read vision-processor --limit=50
```

## Monitoring and Observability

### Cloud Monitoring

Key metrics to monitor:

- Cloud Functions execution count and duration
- Pub/Sub message throughput and backlog
- Filestore IOPS and throughput
- Vision AI API quotas and usage
- Storage bucket object count and size

### Logging

Access logs for troubleshooting:

```bash
# Cloud Functions logs
gcloud functions logs read file-monitor --limit=20
gcloud functions logs read vision-processor --limit=20

# Pub/Sub message logs
gcloud logging read "resource.type=pubsub_topic" --limit=10

# Compute Engine system logs
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_id=filestore-client" --limit=10
```

### Alerting

Set up alerts for:

- Function execution failures
- Pub/Sub message delivery failures
- Filestore capacity thresholds
- Vision AI quota exhaustion

## Security Considerations

### IAM and Permissions

The infrastructure implements least-privilege access:

- Cloud Functions use dedicated service accounts
- Filestore access is limited to authorized instances
- Storage buckets have appropriate access controls
- Vision AI access is restricted to processing functions

### Network Security

- Filestore uses private IP addresses within VPC
- Cloud Functions operate in secure serverless environment
- Compute instances follow security best practices

### Data Protection

- Filestore data is encrypted at rest
- Pub/Sub messages are encrypted in transit
- Storage buckets use server-side encryption
- Vision AI processing respects data residency requirements

## Cost Optimization

### Resource Sizing

- Filestore: Start with Standard tier, upgrade to Premium if needed
- Cloud Functions: 512MB memory allocation balances performance and cost
- Storage: Lifecycle policies automatically transition to cheaper storage classes

### Cost Monitoring

```bash
# Monitor costs by service
gcloud billing accounts list
gcloud alpha billing budgets list --billing-account=ACCOUNT_ID
```

### Optimization Tips

1. **Filestore**: Use Standard tier for most workloads
2. **Functions**: Optimize memory allocation based on actual usage
3. **Storage**: Implement intelligent lifecycle policies
4. **Vision AI**: Batch process documents when possible

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/document-processing
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup Verification

Verify all resources are removed:

```bash
# Check remaining resources
gcloud filestore instances list
gcloud functions list
gcloud pubsub topics list
gcloud storage ls
gcloud compute instances list
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   gcloud services enable REQUIRED_API.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   gcloud projects add-iam-policy-binding PROJECT_ID \
       --member="user:YOUR_EMAIL" \
       --role="roles/REQUIRED_ROLE"
   ```

3. **Filestore Mount Failures**:
   ```bash
   # Check network connectivity
   gcloud compute firewall-rules list --filter="name~nfs"
   
   # Verify Filestore IP
   gcloud filestore instances describe INSTANCE_NAME --zone=ZONE
   ```

4. **Function Deployment Issues**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # Verify source code packaging
   gcloud functions logs read FUNCTION_NAME --limit=10
   ```

### Debug Commands

```bash
# Enable debug logging
export GOOGLE_CLOUD_CPP_ENABLE_TRACING=true

# Check quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.usage,quotas.limit)"

# Validate service accounts
gcloud iam service-accounts list
```

## Customization

### Adding Document Types

Extend the solution for additional document formats:

1. Update Vision AI processing function to handle new MIME types
2. Add document classification logic for new categories
3. Create additional storage paths for organized results

### Scaling Configuration

For high-volume processing:

1. Increase Filestore capacity and performance tier
2. Configure Cloud Functions concurrency limits
3. Implement Pub/Sub flow control settings
4. Add multiple processing regions

### Integration Points

Connect with existing systems:

1. **Webhook Notifications**: Add HTTP endpoints for processing results
2. **Database Integration**: Store metadata in Cloud SQL or Firestore
3. **Workflow Integration**: Connect with Cloud Workflows for complex processes
4. **API Gateway**: Expose processing APIs through Cloud Endpoints

## Support

### Documentation References

- [Cloud Filestore Documentation](https://cloud.google.com/filestore/docs)
- [Cloud Vision AI Documentation](https://cloud.google.com/vision/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud Status page for service issues
3. Consult the original recipe documentation
4. Submit issues to the recipe repository

### Contributing

To improve this infrastructure code:

1. Test changes in a development project
2. Follow Google Cloud best practices
3. Update documentation for any modifications
4. Validate all IaC implementations work consistently