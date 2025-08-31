# Infrastructure as Code for Task Queue System with Cloud Tasks and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Task Queue System with Cloud Tasks and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Admin
  - Cloud Tasks Admin
  - Storage Admin
  - Project IAM Admin
  - Service Usage Admin
- For Terraform: Terraform CLI installed (>= 1.0)
- For Infrastructure Manager: Infrastructure Manager API enabled

## Architecture Overview

This infrastructure deploys a complete serverless task processing system including:

- **Cloud Tasks Queue**: Managed queue service with retry logic and rate limiting
- **Cloud Function**: HTTP-triggered function for processing background tasks
- **Cloud Storage Bucket**: Storage for processed task results
- **IAM Configuration**: Service accounts and permissions for secure access
- **Monitoring**: Cloud Logging integration for observability

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

1. **Enable Infrastructure Manager API**:
   ```bash
   gcloud services enable config.googleapis.com
   ```

2. **Deploy Infrastructure**:
   ```bash
   cd infrastructure-manager/
   
   # Create deployment
   gcloud infra-manager deployments apply projects/$(gcloud config get-value project)/locations/us-central1/deployments/task-queue-system \
       --service-account=$(gcloud config get-value project)@$(gcloud config get-value project).iam.gserviceaccount.com \
       --local-source="."
   ```

3. **Monitor Deployment**:
   ```bash
   # Check deployment status
   gcloud infra-manager deployments describe projects/$(gcloud config get-value project)/locations/us-central1/deployments/task-queue-system
   ```

### Using Terraform

1. **Initialize Terraform**:
   ```bash
   cd terraform/
   terraform init
   ```

2. **Review and Customize Variables**:
   ```bash
   # Copy and edit the variables file
   cp terraform.tfvars.example terraform.tfvars
   
   # Edit variables as needed
   nano terraform.tfvars
   ```

3. **Plan and Apply**:
   ```bash
   # Review planned changes
   terraform plan
   
   # Apply infrastructure
   terraform apply
   ```

4. **View Outputs**:
   ```bash
   # Display important resource information
   terraform output
   ```

### Using Bash Scripts

1. **Make Scripts Executable**:
   ```bash
   chmod +x scripts/deploy.sh scripts/destroy.sh
   ```

2. **Configure Environment**:
   ```bash
   # Set required environment variables
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   export QUEUE_NAME="background-tasks"
   export FUNCTION_NAME="task-processor"
   ```

3. **Deploy Infrastructure**:
   ```bash
   ./scripts/deploy.sh
   ```

4. **Test Deployment**:
   ```bash
   # The deploy script includes basic validation
   # Additional testing can be performed using the generated test scripts
   ```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `queue_name`: Cloud Tasks queue name
- `function_name`: Cloud Function name
- `bucket_name`: Cloud Storage bucket name
- `function_memory`: Memory allocation for Cloud Function (default: 256MB)
- `function_timeout`: Function timeout in seconds (default: 60s)

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
project_id      = "your-project-id"
region          = "us-central1"
queue_name      = "background-tasks"
function_name   = "task-processor"
bucket_name     = "your-bucket-name"
function_memory = 256
function_timeout = 60
```

### Bash Script Variables

Edit environment variables in `scripts/deploy.sh`:

- `PROJECT_ID`: Your Google Cloud project ID
- `REGION`: Deployment region
- `QUEUE_NAME`: Cloud Tasks queue name
- `FUNCTION_NAME`: Cloud Function name
- `BUCKET_NAME`: Storage bucket name (will be auto-generated if not set)

## Deployment Details

### Resources Created

1. **Cloud Tasks Queue** (`google_cloud_tasks_queue`):
   - Configured with retry policies (max 3 attempts, 300s retry duration)
   - Rate limiting with exponential backoff
   - Dead letter queue handling

2. **Cloud Function** (`google_cloudfunctions2_function`):
   - Gen2 Cloud Function with HTTP trigger
   - Python 3.11 runtime
   - 256MB memory allocation
   - Environment variables for storage bucket integration

3. **Cloud Storage Bucket** (`google_storage_bucket`):
   - Standard storage class for cost optimization
   - Uniform bucket-level access for security
   - Lifecycle policies for automatic cleanup

4. **IAM Resources**:
   - Service account for Cloud Function execution
   - Storage bucket permissions for processed files
   - Cloud Tasks queue access permissions

5. **API Enablement**:
   - Cloud Functions API
   - Cloud Tasks API
   - Cloud Build API (for function deployment)
   - Cloud Storage API

### Security Features

- **Least Privilege Access**: Service accounts with minimal required permissions
- **Encryption**: All data encrypted at rest and in transit by default
- **Network Security**: Functions deployed with secure defaults
- **Access Control**: Bucket-level IAM for file access control

## Testing the Deployment

### Basic Functionality Test

1. **Create Test Task**:
   ```bash
   # Get function URL from outputs
   FUNCTION_URL=$(terraform output -raw function_url)
   # or for Infrastructure Manager:
   # FUNCTION_URL=$(gcloud infra-manager deployments describe ... --format="value(...")
   
   # Create test task using gcloud
   gcloud tasks create-http-task test-task-$(date +%s) \
       --queue=background-tasks \
       --location=us-central1 \
       --url=$FUNCTION_URL \
       --method=POST \
       --header="Content-Type: application/json" \
       --body-content='{"task_type":"process_file","filename":"test.txt","content":"Hello World"}'
   ```

2. **Check Function Logs**:
   ```bash
   gcloud functions logs read task-processor \
       --gen2 \
       --region=us-central1 \
       --limit=10
   ```

3. **Verify Storage Output**:
   ```bash
   # List processed files
   gsutil ls gs://$(terraform output -raw bucket_name)/processed/
   
   # View processed content
   gsutil cat gs://$(terraform output -raw bucket_name)/processed/test.txt
   ```

### Load Testing

```bash
# Create multiple tasks for load testing
for i in {1..10}; do
  gcloud tasks create-http-task load-test-task-$i \
      --queue=background-tasks \
      --location=us-central1 \
      --url=$FUNCTION_URL \
      --method=POST \
      --header="Content-Type: application/json" \
      --body-content="{\"task_type\":\"process_file\",\"filename\":\"load-test-$i.txt\",\"content\":\"Load test content $i\"}"
done
```

## Monitoring and Observability

### Cloud Logging

View function execution logs:
```bash
# Real-time log streaming
gcloud functions logs tail task-processor --gen2 --region=us-central1

# Query specific log entries
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=task-processor" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"
```

### Cloud Monitoring

Monitor queue metrics:
```bash
# View queue depth and processing rates in Cloud Console
open "https://console.cloud.google.com/cloudtasks/queue/background-tasks?project=$(gcloud config get-value project)"
```

### Performance Metrics

Key metrics to monitor:
- Queue depth and processing rate
- Function execution time and error rate
- Storage bucket usage and access patterns
- Task retry frequency and failure patterns

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/$(gcloud config get-value project)/locations/us-central1/deployments/task-queue-system \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list
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
gcloud tasks queues list --location=us-central1
gcloud functions list --gen2 --region=us-central1
gsutil ls -b gs://
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs manually
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable cloudtasks.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check current permissions
   gcloud auth list
   gcloud projects get-iam-policy $(gcloud config get-value project)
   ```

3. **Function Deployment Fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   gcloud builds log [BUILD_ID]
   ```

4. **Tasks Not Processing**:
   ```bash
   # Check queue configuration
   gcloud tasks queues describe background-tasks --location=us-central1
   
   # Verify function trigger URL
   gcloud functions describe task-processor --gen2 --region=us-central1
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# For bash scripts
export DEBUG=true
./scripts/deploy.sh

# For Terraform
export TF_LOG=DEBUG
terraform apply
```

## Customization

### Adding New Task Types

1. **Modify Function Code**: Edit the Cloud Function source to handle new task types
2. **Update Infrastructure**: Redeploy with updated function code
3. **Test New Functionality**: Create tasks with new task types

### Scaling Configuration

Adjust these parameters for higher throughput:

- **Queue Rate Limits**: Increase `maxDispatchesPerSecond` in queue configuration
- **Function Concurrency**: Adjust concurrent execution limits
- **Function Resources**: Increase memory and timeout for complex tasks
- **Retry Policies**: Customize retry attempts and backoff strategies

### Multi-Region Deployment

For global task processing:

1. Deploy queues and functions in multiple regions
2. Use Cloud Load Balancer for task distribution
3. Implement cross-region storage replication
4. Configure monitoring across all regions

## Cost Optimization

### Free Tier Usage

- Cloud Tasks: 1M operations/month free
- Cloud Functions: 2M invocations/month free
- Cloud Storage: 5GB storage free
- Cloud Build: 120 build-minutes/day free

### Production Cost Estimation

Typical monthly costs for moderate usage:
- Cloud Tasks: $0.40/million operations
- Cloud Functions: $0.40/million invocations + $0.0000025/GB-second
- Cloud Storage: $0.020/GB/month
- Cloud Build: $0.003/build-minute

### Cost Monitoring

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=[BILLING_ACCOUNT_ID] \
    --display-name="Task Queue System Budget" \
    --budget-amount=10 \
    --threshold-rule=percent=50 \
    --threshold-rule=percent=90
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for architecture details
2. **Google Cloud Documentation**: 
   - [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)
   - [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Provider**: [Google Cloud Terraform Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: [Google Cloud Community](https://cloud.google.com/community)

## Contributing

To improve this infrastructure code:

1. Test changes in a development project
2. Follow Google Cloud best practices
3. Update documentation for any configuration changes
4. Validate security implications of modifications