# Infrastructure as Code for Voice-Controlled Task Automation with Speech-to-Text and Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Voice-Controlled Task Automation with Speech-to-Text and Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Speech-to-Text API
  - Cloud Workflows
  - Cloud Functions
  - Cloud Tasks
  - Cloud Storage
  - IAM administration
- For Terraform: Terraform CLI installed (version >= 1.0)
- Estimated cost: $5-15 for testing and development

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy infrastructure
gcloud infra-manager deployments apply \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/voice-automation \
    --service-account=YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --git-source-repo=https://github.com/your-repo.git \
    --git-source-directory=gcp/voice-controlled-task-automation-speech-workflows/code/infrastructure-manager \
    --git-source-ref=main

# Check deployment status
gcloud infra-manager deployments describe \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/voice-automation
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Architecture Overview

This infrastructure deploys a complete voice-controlled task automation system with the following components:

- **Cloud Storage Bucket**: Stores audio files with lifecycle management
- **Cloud Tasks Queue**: Manages asynchronous task processing with rate limiting
- **Speech Processing Cloud Function**: Handles voice recognition and intent analysis
- **Task Automation Workflow**: Orchestrates business processes based on voice commands
- **Task Processing Function**: Executes specific automation tasks
- **IAM Roles and Permissions**: Secure service-to-service communication

## Configuration Variables

### Infrastructure Manager Variables

Customize your deployment by modifying the variables in `infrastructure-manager/main.yaml`:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `environment`: Environment name (dev, staging, prod)
- `bucket_lifecycle_days`: Storage lifecycle in days (default: 7)
- `queue_max_dispatches`: Max tasks per second (default: 10)
- `function_memory`: Cloud Function memory allocation (default: 512MB)

### Terraform Variables

Configure your deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
project_id              = "your-project-id"
region                  = "us-central1"
environment             = "dev"
bucket_lifecycle_days   = 7
queue_max_dispatches    = 10
function_memory         = 512
enable_speech_api       = true
enable_workflows_api    = true
```

### Bash Script Configuration

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ENVIRONMENT="dev"
export BUCKET_LIFECYCLE_DAYS=7
export QUEUE_MAX_DISPATCHES=10
```

## Testing the Deployment

After successful deployment, test the voice automation system:

1. **Get Function URL**:
   ```bash
   # Using gcloud
   gcloud functions describe voice-processor-SUFFIX --region=us-central1 --format="value(httpsTrigger.url)"
   
   # Using Terraform output
   terraform output function_url
   ```

2. **Test Voice Processing**:
   ```bash
   curl -X POST "YOUR_FUNCTION_URL" \
       -H "Content-Type: application/json" \
       -d '{
         "text_command": "create task urgent meeting preparation",
         "test_mode": true
       }'
   ```

3. **Verify Workflow Execution**:
   ```bash
   gcloud workflows executions list \
       --workflow=task-automation-SUFFIX \
       --location=us-central1
   ```

4. **Check Task Queue**:
   ```bash
   gcloud tasks queues describe task-queue-SUFFIX \
       --location=us-central1
   ```

## Monitoring and Logging

- **Function Logs**: View in Cloud Logging under Cloud Functions
- **Workflow Logs**: Monitor in Cloud Workflows console
- **Task Queue Metrics**: Available in Cloud Tasks console
- **Speech API Usage**: Track in Cloud Monitoring

## Security Considerations

The infrastructure implements several security best practices:

- **Least Privilege IAM**: Each service has minimal required permissions
- **Service Account Keys**: Uses default service accounts where possible
- **API Enablement**: Only required APIs are enabled
- **Storage Security**: Bucket configured with appropriate access controls
- **Function Security**: HTTP triggers with authentication options

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/voice-automation

# Verify deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/verify-cleanup.sh
```

## Customization

### Adding New Voice Commands

1. Modify the intent recognition logic in the Cloud Function code
2. Update the workflow definition to handle new intents
3. Extend the task processing function for new actions
4. Redeploy using your preferred IaC method

### Scaling Configuration

Adjust these parameters for production workloads:

- **Cloud Functions**: Increase memory and timeout limits
- **Cloud Tasks**: Modify queue configuration for higher throughput
- **Storage**: Enable multi-regional storage for global access
- **Workflows**: Add parallel execution paths for complex scenarios

### Integration with External Systems

The infrastructure supports integration with:

- **Databases**: Cloud SQL, Firestore, BigQuery
- **Notification Systems**: Pub/Sub, Cloud Messaging
- **External APIs**: Via HTTP connectors in workflows
- **Monitoring**: Cloud Monitoring, Error Reporting

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
2. **Permission Errors**: Verify service account permissions
3. **Function Timeouts**: Increase timeout limits for complex processing
4. **Workflow Failures**: Check workflow execution logs
5. **Storage Access**: Verify bucket permissions and lifecycle policies

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# View function logs
gcloud functions logs read voice-processor-SUFFIX --limit=50

# Check workflow status
gcloud workflows describe task-automation-SUFFIX --location=us-central1

# Verify IAM bindings
gcloud projects get-iam-policy YOUR_PROJECT_ID
```

## Cost Optimization

- **Storage Lifecycle**: Automatic deletion after 7 days (configurable)
- **Function Memory**: Right-sized based on workload requirements
- **Task Queue**: Rate limiting prevents unexpected costs
- **Speech API**: Efficient audio processing to minimize API calls

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../voice-controlled-task-automation-speech-workflows.md)
2. Review [Google Cloud documentation](https://cloud.google.com/docs)
3. Consult provider-specific documentation:
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
   - [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. Review Cloud Functions, Workflows, and Speech-to-Text service documentation

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update variable documentation
3. Verify security configurations
4. Update this README with any new requirements
5. Test all deployment methods (Infrastructure Manager, Terraform, Bash)

---

*Generated for recipe version 1.1 - Last updated: 2025-07-12*