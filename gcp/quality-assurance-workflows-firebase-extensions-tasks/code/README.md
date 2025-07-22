# Infrastructure as Code for Quality Assurance Workflows with Firebase Extensions and Cloud Tasks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Quality Assurance Workflows with Firebase Extensions and Cloud Tasks".

## Overview

This recipe deploys an automated quality assurance pipeline that leverages Firebase Extensions for event-driven workflow triggers, Cloud Tasks for reliable test orchestration, and Vertex AI for intelligent analysis of test results and quality metrics. The solution provides scalable, automated QA processes with AI-powered insights for faster, more reliable software delivery.

## Architecture Components

- **Firebase Platform**: Firebase Extensions, Cloud Firestore for workflow state management
- **Orchestration Layer**: Cloud Tasks with multiple priority queues for test execution
- **Testing Infrastructure**: Cloud Storage for artifacts and test results
- **AI Analysis**: Vertex AI for intelligent quality analysis and recommendations
- **Monitoring**: Cloud Functions for phase execution and Cloud Run for dashboard
- **Security**: IAM roles and policies following least privilege principles

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Bash Scripts**: Deployment and cleanup automation scripts

## Prerequisites

- Google Cloud account with billing enabled
- Google Cloud CLI (`gcloud`) installed and configured
- Firebase CLI installed (`npm install -g firebase-tools`)
- Appropriate IAM permissions for:
  - Firebase project management
  - Cloud Tasks administration
  - Cloud Storage bucket creation
  - Vertex AI model deployment
  - Cloud Functions and Cloud Run deployment
  - IAM role management
- Basic understanding of:
  - Firebase Extensions and Cloud Functions
  - Quality assurance workflows
  - Task queue patterns
  - Machine learning concepts

### Required APIs

The following APIs will be automatically enabled during deployment:
- Firebase API (`firebase.googleapis.com`)
- Cloud Tasks API (`cloudtasks.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Firestore API (`firestore.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/qa-workflows \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/qa-workflows
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and verification commands
```

## Configuration Options

### Terraform Variables

Key variables you can customize in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# QA Infrastructure Settings
qa_bucket_name = "qa-artifacts-custom"
task_queue_name = "qa-orchestration-custom"
firestore_collection = "qa-workflows"

# Task Queue Configuration
max_concurrent_dispatches = 10
max_retry_duration = "3600s"
min_backoff = "1s"
max_backoff = "300s"

# Cloud Function Settings
function_runtime = "python311"
function_memory = "512MB"
function_timeout = "540s"

# Cloud Run Settings
dashboard_cpu = "1000m"
dashboard_memory = "2Gi"
dashboard_max_instances = 10

# Vertex AI Configuration
vertex_ai_region = "us-central1"
enable_vertex_ai_logging = true

# Security Settings
enable_audit_logs = true
require_ssl = true

# Cost Management
enable_lifecycle_policy = true
storage_class_transition_days = 30
coldline_transition_days = 90
deletion_days = 365
```

### Infrastructure Manager Configuration

Customize the deployment in `main.yaml`:

```yaml
imports:
- path: templates/firebase.yaml
  name: firebase
- path: templates/storage.yaml
  name: storage
- path: templates/tasks.yaml
  name: tasks
- path: templates/vertex-ai.yaml
  name: vertex-ai

resources:
- name: qa-workflows-deployment
  type: deployment.yaml
  properties:
    projectId: "your-project-id"
    region: "us-central1"
    qaBucketName: "qa-artifacts-custom"
    taskQueueName: "qa-orchestration-custom"
```

## Post-Deployment Setup

### 1. Configure Firebase Extensions

```bash
# Install required Firebase Extensions
firebase ext:install firebase/firestore-bigquery-export \
    --project=${PROJECT_ID}

firebase ext:install firebase/storage-resize-images \
    --project=${PROJECT_ID}
```

### 2. Initialize QA Dashboard

```bash
# Get the dashboard URL
DASHBOARD_URL=$(gcloud run services describe qa-dashboard \
    --region=${REGION} \
    --format="value(status.url)")

echo "QA Dashboard URL: ${DASHBOARD_URL}"

# Test dashboard connectivity
curl -s "${DASHBOARD_URL}/api/metrics"
```

### 3. Create Sample QA Trigger

```bash
# Create a test workflow trigger
cat > test-trigger.json << 'EOF'
{
  "repository": "sample-app",
  "branch": "main",
  "commit_hash": "abc123",
  "trigger_type": "pull_request",
  "config": {
    "test_suites": ["unit", "integration"],
    "analysis_enabled": true
  }
}
EOF

# Upload to Firestore to trigger workflow
gcloud firestore import test-trigger.json \
    --collection-ids=qa-triggers
```

## Monitoring and Validation

### Check Deployment Status

```bash
# Verify Firebase project
firebase projects:list

# Check Cloud Tasks queues
gcloud tasks queues list --location=${REGION}

# Verify Cloud Storage bucket
gsutil ls -la gs://your-qa-bucket-name/

# Check Cloud Functions
gcloud functions list --regions=${REGION}

# Verify Cloud Run services
gcloud run services list --region=${REGION}

# Test Vertex AI setup
gcloud ai-platform models list --region=${REGION}
```

### Monitor QA Workflows

```bash
# View recent workflows
gcloud firestore export gs://your-qa-bucket-name/export/ \
    --collection-ids=qa-workflows

# Monitor task queue metrics
gcloud tasks queues describe your-task-queue-name \
    --location=${REGION} \
    --format="yaml(name,state,rateLimits)"

# Check Cloud Function logs
gcloud functions logs read qa-phase-executor \
    --region=${REGION} \
    --limit=50
```

## Troubleshooting

### Common Issues

1. **Firebase Project Not Found**
   ```bash
   # Ensure Firebase is properly initialized
   firebase login
   firebase projects:list
   firebase use your-project-id
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current user permissions
   gcloud auth list
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **API Not Enabled**
   ```bash
   # Enable required APIs manually
   gcloud services enable firebase.googleapis.com
   gcloud services enable cloudtasks.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   ```

4. **Cloud Tasks Queue Creation Failed**
   ```bash
   # Check quota limits
   gcloud compute project-info describe \
       --format="yaml(quotas)"
   ```

5. **Vertex AI Model Deployment Issues**
   ```bash
   # Check Vertex AI status
   gcloud ai-platform operations list --region=${REGION}
   ```

### Debug Commands

```bash
# Enable debug logging for Terraform
export TF_LOG=DEBUG
terraform plan

# Check Infrastructure Manager deployment logs
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/qa-workflows \
    --format="yaml(state,errorLogs)"

# Validate Cloud Function deployment
gcloud functions describe qa-phase-executor \
    --region=${REGION} \
    --format="yaml(status,sourceArchiveUrl)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/us-central1/deployments/qa-workflows

# Verify deletion
gcloud infra-manager deployments list \
    --location=us-central1
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
# Run the cleanup script
./scripts/destroy.sh

# Manual cleanup verification
gcloud projects delete ${PROJECT_ID} --quiet
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Run services
gcloud run services delete qa-dashboard --region=${REGION} --quiet

# Delete Cloud Functions
gcloud functions delete qa-phase-executor --region=${REGION} --quiet

# Delete Cloud Tasks queues
gcloud tasks queues delete your-queue-name --location=${REGION} --quiet

# Delete Cloud Storage bucket
gsutil -m rm -r gs://your-qa-bucket-name

# Delete Vertex AI resources
gcloud ai-platform models delete qa-analysis-model --region=${REGION} --quiet

# Disable APIs (optional)
gcloud services disable cloudtasks.googleapis.com
gcloud services disable aiplatform.googleapis.com
```

## Cost Estimation

Estimated monthly costs for moderate usage:

- **Cloud Functions**: $10-30 (based on execution frequency)
- **Cloud Tasks**: $5-15 (based on task volume)
- **Cloud Storage**: $10-25 (based on artifact storage)
- **Vertex AI**: $20-100 (based on analysis frequency)
- **Cloud Run**: $5-20 (based on dashboard usage)
- **Firebase/Firestore**: $5-15 (based on document operations)

**Total estimated cost**: $55-205/month

Use the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for more precise estimates based on your expected usage patterns.

## Security Considerations

- All services use IAM roles with least privilege access
- Cloud Storage buckets have private access by default
- Cloud Functions run with dedicated service accounts
- Firestore security rules restrict access to authenticated users
- HTTPS is enforced for all web services
- Audit logging is enabled for administrative operations

## Support and Resources

- [Firebase Documentation](https://firebase.google.com/docs)
- [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and adapt according to your organization's requirements before production use.