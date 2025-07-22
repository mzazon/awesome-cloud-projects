# Video Content Moderation with Video Intelligence API and Cloud Scheduler - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete video content moderation workflow on Google Cloud Platform using Video Intelligence API, Cloud Scheduler, Cloud Functions, and Cloud Storage.

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage Bucket**: Organized folder structure for video processing workflow
- **Pub/Sub Topic & Subscription**: Event-driven messaging for reliable processing
- **Cloud Function (Gen2)**: Serverless compute for video analysis using Video Intelligence API
- **Cloud Scheduler**: Automated batch processing with configurable schedule
- **IAM Service Accounts**: Secure access controls with least privilege principles
- **Monitoring & Logging**: Comprehensive logging for audit trails and troubleshooting

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Platform Account** with appropriate permissions
2. **Google Cloud CLI** installed and authenticated
3. **Terraform** v1.6 or higher installed
4. **Required APIs** will be enabled automatically during deployment
5. **Project Billing** enabled for API usage and resource costs

### Required GCP Permissions

Your account or service account needs the following IAM roles:

- `roles/owner` OR the following individual roles:
  - `roles/serviceusage.serviceUsageAdmin` (to enable APIs)
  - `roles/storage.admin` (for Cloud Storage)
  - `roles/pubsub.admin` (for Pub/Sub)
  - `roles/cloudfunctions.admin` (for Cloud Functions)
  - `roles/cloudscheduler.admin` (for Cloud Scheduler)
  - `roles/iam.serviceAccountAdmin` (for service accounts)
  - `roles/resourcemanager.projectIamAdmin` (for IAM policy bindings)

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd gcp/video-content-moderation-video-intelligence-scheduler/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your values
nano terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init

# Validate the configuration
terraform validate

# Review the execution plan
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Deploy the infrastructure
terraform apply

# Type 'yes' when prompted to confirm deployment
```

### 4. Verify Deployment

```bash
# Check outputs for verification commands
terraform output test_commands

# Upload a test video
gsutil cp test-video.mp4 gs://$(terraform output -raw storage_bucket_name)/processing/

# Manually trigger processing
gcloud scheduler jobs run $(terraform output -raw scheduler_job_name) \
  --location=$(terraform output -raw region)

# Check function logs
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw region) \
  --limit=50
```

## Configuration

### Required Variables

Edit `terraform.tfvars` to set these required values:

```hcl
# GCP Project ID where resources will be created
project_id = "your-project-id"

# GCP region for resources
region = "us-central1"
```

### Optional Configuration

The infrastructure includes many configurable options:

#### Function Performance
```hcl
function_memory = "1Gi"        # Memory allocation
function_timeout = 540         # Timeout in seconds
function_max_instances = 10    # Maximum concurrent instances
function_cpu = "1"             # CPU allocation
```

#### Processing Schedule
```hcl
schedule_expression = "0 */4 * * *"  # Every 4 hours
schedule_timezone = "America/New_York"
```

#### Content Moderation Thresholds
```hcl
explicit_content_threshold = 3          # Sensitivity level (1-5)
explicit_content_ratio_threshold = 0.1  # Ratio of explicit frames (0.0-1.0)
```

#### Storage Configuration
```hcl
storage_class = "STANDARD"      # Storage class for cost optimization
enable_versioning = true        # Enable object versioning
bucket_lifecycle_age = 365      # Auto-delete after N days
```

### Complete Variable Reference

See `variables.tf` for all available configuration options with descriptions and validation rules.

## Usage

### Video Processing Workflow

1. **Upload Videos**: Place videos in the processing folder
   ```bash
   gsutil cp video.mp4 gs://BUCKET_NAME/processing/
   ```

2. **Automated Processing**: Cloud Scheduler triggers analysis every 4 hours (configurable)

3. **Content Analysis**: Video Intelligence API analyzes videos for explicit content

4. **Automatic Sorting**: Videos are moved to appropriate folders:
   - `approved/` - Videos passing moderation checks
   - `flagged/` - Videos requiring manual review

### Manual Operations

```bash
# Manually trigger scheduler job
gcloud scheduler jobs run SCHEDULER_JOB_NAME --location=REGION

# View processing logs
gcloud functions logs read FUNCTION_NAME --region=REGION --limit=50

# List processed videos
gsutil ls -r gs://BUCKET_NAME/

# Check job status
gcloud scheduler jobs describe SCHEDULER_JOB_NAME --location=REGION
```

### Monitoring and Troubleshooting

```bash
# View function metrics
gcloud functions describe FUNCTION_NAME --region=REGION

# Check Pub/Sub message flow
gcloud pubsub topics list-subscriptions TOPIC_NAME

# Monitor API quotas and usage
gcloud logging read "resource.type=gce_instance" --limit=50
```

## Cost Optimization

### Estimated Costs

The infrastructure costs depend on usage patterns:

- **Cloud Storage**: ~$0.02/GB/month (STANDARD class)
- **Cloud Functions**: ~$0.0000004/invocation + compute time
- **Video Intelligence API**: ~$0.10/minute of video analyzed
- **Pub/Sub**: ~$0.40/million operations
- **Cloud Scheduler**: ~$0.10/job/month

### Cost Optimization Tips

1. **Adjust Storage Class**: Use NEARLINE/COLDLINE for long-term storage
2. **Optimize Function Memory**: Monitor usage and adjust allocation
3. **Schedule Frequency**: Balance processing speed vs. cost
4. **Lifecycle Policies**: Automatically delete old videos
5. **Regional Selection**: Choose regions close to your users

## Security Considerations

The infrastructure implements security best practices:

- **Least Privilege Access**: Service accounts have minimal required permissions
- **Network Security**: Functions use internal-only ingress
- **Data Protection**: Bucket versioning and uniform access controls
- **Audit Logging**: Comprehensive logging for compliance
- **Encryption**: Data encrypted at rest and in transit (GCP default)

### Security Checklist

- [ ] Review IAM permissions in `main.tf`
- [ ] Verify bucket access controls
- [ ] Monitor function logs for suspicious activity
- [ ] Regularly rotate service account keys (if using keys)
- [ ] Enable security command center alerts

## Customization

### Extending Functionality

The infrastructure can be extended with:

1. **Additional Video Intelligence Features**:
   ```hcl
   # Add to function environment variables
   ENABLE_OBJECT_DETECTION = "true"
   ENABLE_TEXT_DETECTION = "true"
   ```

2. **Human Review Workflow**: Add Cloud Tasks for manual review queue

3. **Real-time Processing**: Add Cloud Storage triggers for immediate processing

4. **Multi-region Deployment**: Replicate infrastructure across regions

5. **Integration APIs**: Add Cloud Endpoints for external system integration

### Custom Moderation Logic

Modify the Cloud Function code in `main.tf` to implement custom business rules:

```python
def custom_moderation_logic(result, video_metadata):
    # Implement your custom moderation rules
    # Consider factors like video duration, audio analysis, etc.
    pass
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services list --enabled
   ```

2. **Permission Denied**: Verify IAM roles and service account permissions
   ```bash
   gcloud projects get-iam-policy PROJECT_ID
   ```

3. **Function Timeout**: Adjust timeout for large videos
   ```hcl
   function_timeout = 540  # Maximum for gen2 functions
   ```

4. **Storage Access Issues**: Check bucket permissions and uniform access

5. **Scheduler Not Triggering**: Verify time zone and cron expression

### Debugging Steps

1. **Check Function Logs**:
   ```bash
   gcloud functions logs read FUNCTION_NAME --region=REGION
   ```

2. **Verify Pub/Sub Flow**:
   ```bash
   gcloud pubsub subscriptions pull SUBSCRIPTION_NAME --auto-ack
   ```

3. **Test Video Intelligence API**:
   ```bash
   gcloud ml video-intelligence analyze-explicit-content gs://BUCKET/video.mp4
   ```

## Cleanup

### Destroy Infrastructure

To remove all deployed resources:

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Type 'yes' when prompted to confirm
```

### Manual Cleanup

If Terraform destroy fails, manually delete:

1. Cloud Storage buckets (and all objects)
2. Cloud Functions
3. Pub/Sub topics and subscriptions
4. Cloud Scheduler jobs
5. Service accounts

```bash
# Delete storage bucket
gsutil rm -r gs://BUCKET_NAME

# Delete function
gcloud functions delete FUNCTION_NAME --region=REGION

# Delete scheduler job
gcloud scheduler jobs delete JOB_NAME --location=REGION
```

## Support and Contributing

### Getting Help

- Review the [Video Intelligence API documentation](https://cloud.google.com/video-intelligence/docs)
- Check [Cloud Functions best practices](https://cloud.google.com/functions/docs/bestpractices)
- Consult [Terraform Google Provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Reporting Issues

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Terraform and function logs
3. Verify your GCP permissions and quotas
4. Test with minimal configuration

### Contributing

To contribute improvements:

1. Test changes in a development environment
2. Follow Terraform best practices
3. Update documentation for any new variables or outputs
4. Validate with `terraform validate` and `terraform plan`

## License

This infrastructure code is provided as part of the cloud recipes project. See the main repository for license information.