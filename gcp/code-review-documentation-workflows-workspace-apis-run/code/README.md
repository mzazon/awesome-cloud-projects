# Infrastructure as Code for Code Review and Documentation Workflows with Google Workspace APIs and Cloud Run

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Code Review and Documentation Workflows with Google Workspace APIs and Cloud Run".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent automation system that integrates Google Workspace APIs with Cloud Run services to automatically generate code review summaries, update project documentation in Google Docs, and send targeted notifications via Gmail. The architecture includes:

- **Cloud Run Services**: Serverless containers for code review analysis, documentation updates, and notifications
- **Pub/Sub**: Event-driven messaging for reliable webhook processing
- **Cloud Scheduler**: Automated maintenance and periodic tasks
- **Secret Manager**: Secure storage for Google Workspace API credentials
- **Cloud Storage**: Artifact storage for review data and logs
- **Cloud Monitoring**: Observability and alerting for the automation workflow

## Prerequisites

### Google Cloud Requirements
- Google Cloud Project with billing enabled
- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate IAM permissions for:
  - Cloud Run
  - Pub/Sub
  - Cloud Scheduler
  - Secret Manager
  - Cloud Storage
  - Cloud Monitoring
  - Infrastructure Manager (for IM deployment)

### Google Workspace Requirements
- Google Workspace account with admin privileges
- Service account configured for domain-wide delegation
- API access enabled for:
  - Gmail API
  - Google Docs API
  - Google Drive API
  - Admin SDK API

### Development Tools
- Terraform >= 1.0 (for Terraform deployment)
- Basic understanding of:
  - REST APIs and OAuth 2.0
  - Serverless architecture patterns
  - Google Workspace administration

### Cost Estimation
- **Expected Monthly Cost**: $15-30 for moderate usage
- **Key Cost Factors**:
  - Cloud Run requests and compute time
  - Pub/Sub message processing
  - Cloud Storage data storage
  - Secret Manager secret access

## Quick Start

### Option 1: Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that provides state management and deployment orchestration.

```bash
# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/code-review-automation \
    --service-account DEPLOY_SERVICE_ACCOUNT@PROJECT_ID.iam.gserviceaccount.com \
    --local-source="."

# Monitor deployment progress
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/code-review-automation
```

### Option 2: Using Terraform

Terraform provides cross-cloud infrastructure management with robust state management and planning capabilities.

```bash
# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View deployment outputs
terraform output
```

### Option 3: Using Bash Scripts

Bash scripts provide direct CLI-based deployment with maximum control over the deployment process.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# The script will prompt for required configuration values
# or set them as environment variables:
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WORKSPACE_ADMIN_EMAIL="admin@yourdomain.com"

./scripts/deploy.sh
```

## Configuration

### Required Variables

All deployment methods require these core configuration values:

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud Project ID | `my-automation-project` |
| `region` | Primary deployment region | `us-central1` |
| `workspace_domain` | Google Workspace domain | `example.com` |
| `notification_recipients` | Email addresses for notifications | `["team@example.com"]` |

### Optional Customization

| Variable | Description | Default | Purpose |
|----------|-------------|---------|---------|
| `service_memory` | Cloud Run memory allocation | `1Gi` | Adjust based on processing needs |
| `max_instances` | Maximum Cloud Run instances | `10` | Control scaling limits |
| `storage_lifecycle_days` | Storage lifecycle (days) | `365` | Cost optimization |
| `monitoring_enabled` | Enable monitoring dashboard | `true` | Observability features |

### Google Workspace Setup

Before deploying, complete these Google Workspace configuration steps:

1. **Enable APIs** in Google Cloud Console:
   - Gmail API
   - Google Docs API
   - Google Drive API
   - Admin SDK API

2. **Create Service Account**:
   ```bash
   gcloud iam service-accounts create workspace-automation \
       --display-name="Workspace Automation" \
       --description="Service account for code review automation"
   ```

3. **Configure Domain-Wide Delegation**:
   - Go to Google Admin Console
   - Navigate to Security → API Controls → Domain-wide Delegation
   - Add the service account with required scopes:
     - `https://www.googleapis.com/auth/documents`
     - `https://www.googleapis.com/auth/drive`
     - `https://www.googleapis.com/auth/gmail.send`

4. **Generate and Store Credentials**:
   ```bash
   # Create service account key
   gcloud iam service-accounts keys create workspace-key.json \
       --iam-account=workspace-automation@PROJECT_ID.iam.gserviceaccount.com
   
   # Store in Secret Manager (done automatically by IaC)
   ```

## Post-Deployment Setup

### 1. Configure Repository Webhooks

After deployment, configure your code repository to send webhook events:

```bash
# Get the webhook URL from deployment outputs
WEBHOOK_URL=$(terraform output -raw webhook_endpoint)

# For GitHub repositories, add webhook in repository settings:
# URL: $WEBHOOK_URL/webhook
# Content Type: application/json
# Events: Push, Pull Request
```

### 2. Test the Automation Workflow

```bash
# Send a test webhook event
curl -X POST "${WEBHOOK_URL}/webhook" \
    -H "Content-Type: application/json" \
    -d '{
        "repository": {"name": "test-project"},
        "commits": [{"added": ["src/main.py"], "removed": []}]
    }'

# Check Cloud Run logs for processing
gcloud logs read "resource.type=cloud_run_revision" --limit=20 --format=json
```

### 3. Verify Google Workspace Integration

```bash
# Test document creation (should appear in Google Drive)
# Test email notifications (check configured recipient inboxes)
# Verify monitoring dashboard shows activity
```

## Monitoring and Observability

### Cloud Monitoring Dashboard

The deployment creates a monitoring dashboard accessible at:
- Google Cloud Console → Monitoring → Dashboards → "Code Review Automation Dashboard"

### Key Metrics to Monitor

- **Request Success Rate**: Percentage of successful webhook processing
- **Document Creation Rate**: Google Docs creation frequency
- **Email Delivery Success**: Notification delivery metrics
- **Error Rate**: Service error frequency and types
- **Resource Utilization**: Cloud Run CPU and memory usage

### Logging

```bash
# View Cloud Run service logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=code-review-service" --limit=50

# View Pub/Sub message processing
gcloud logs read "resource.type=pubsub_topic" --limit=20

# View Secret Manager access logs
gcloud logs read "protoPayload.serviceName=secretmanager.googleapis.com" --limit=10
```

### Alerting

The deployment configures basic alerting for:
- Service error rates exceeding 10%
- Failed webhook processing
- Google Workspace API quota limits

## Troubleshooting

### Common Issues

1. **Google Workspace API Access Denied**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy PROJECT_ID --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:workspace-automation@PROJECT_ID.iam.gserviceaccount.com"
   
   # Check domain-wide delegation in Google Admin Console
   ```

2. **Webhook Processing Failures**
   ```bash
   # Check Cloud Run service logs
   gcloud logs read "resource.type=cloud_run_revision" --filter="severity>=ERROR" --limit=10
   
   # Verify Pub/Sub topic configuration
   gcloud pubsub topics describe code-events-topic
   ```

3. **Document Creation Issues**
   ```bash
   # Test Google Docs API access
   gcloud auth application-default login
   # Verify API quota limits in Cloud Console
   ```

### Performance Optimization

1. **Scaling Configuration**:
   ```bash
   # Adjust Cloud Run concurrency
   gcloud run services update code-review-service \
       --concurrency=100 \
       --region=us-central1
   ```

2. **Memory Optimization**:
   ```bash
   # Increase memory for heavy document processing
   gcloud run services update code-review-service \
       --memory=2Gi \
       --region=us-central1
   ```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/code-review-automation

# Verify cleanup completion
gcloud infra-manager deployments list
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify state file is clean
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
# or run with --force flag to skip prompts:
./scripts/destroy.sh --force
```

### Manual Cleanup (if needed)
```bash
# Remove any remaining resources
gcloud run services list --filter="metadata.name:code-review"
gcloud pubsub topics list --filter="name:code-events"
gcloud storage buckets list --filter="name:code-artifacts"

# Clean up Google Workspace configurations
# - Remove service account from domain-wide delegation
# - Revoke API access if no longer needed
```

## Security Considerations

### Best Practices Implemented

1. **Least Privilege Access**: Service accounts have minimal required permissions
2. **Secret Management**: Credentials stored securely in Secret Manager
3. **Network Security**: Cloud Run services use secure HTTPS endpoints
4. **Audit Logging**: All API access logged for compliance tracking
5. **Resource Isolation**: Separate service accounts for different functions

### Additional Security Measures

```bash
# Enable VPC Service Controls (enterprise environments)
gcloud access-context-manager perimeters create code-review-perimeter \
    --policy=POLICY_ID \
    --title="Code Review Automation Perimeter"

# Configure Cloud Armor for DDoS protection
gcloud compute security-policies create code-review-policy \
    --description="Security policy for code review automation"
```

## Extensions and Customization

### Adding New Notification Channels

1. **Slack Integration**:
   - Add Slack API credentials to Secret Manager
   - Modify notification service to support Slack webhooks
   - Update Terraform configuration for additional secrets

2. **Microsoft Teams Integration**:
   - Configure Teams webhook connector
   - Add Teams notification logic to Cloud Run service
   - Update IAM permissions for additional API access

3. **Custom Document Templates**:
   - Store templates in Cloud Storage
   - Modify documentation service to use custom templates
   - Add template management endpoints

### Scaling for Enterprise Use

1. **Multi-Region Deployment**:
   ```bash
   # Deploy to additional regions
   terraform apply -var="regions=[\"us-central1\",\"europe-west1\"]"
   ```

2. **Enhanced Monitoring**:
   - Add custom metrics for business KPIs
   - Configure advanced alerting policies
   - Integrate with external monitoring systems

3. **Compliance Features**:
   - Add audit trail logging
   - Implement data retention policies
   - Configure compliance monitoring

## Support and Contributing

### Getting Help

1. **Documentation**: Refer to the original recipe for detailed implementation guidance
2. **Google Cloud Support**: Use Cloud Console support for infrastructure issues
3. **Community**: Engage with Google Cloud community forums for best practices

### Reporting Issues

When reporting issues, include:
- Deployment method used (Infrastructure Manager/Terraform/Bash)
- Error messages and log outputs
- Configuration parameters (sanitized)
- Steps to reproduce the issue

### Contributing

Contributions to improve the IaC implementations are welcome:
1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any new features
4. Ensure backward compatibility where possible

---

**Note**: This infrastructure code is generated from the recipe "Code Review and Documentation Workflows with Google Workspace APIs and Cloud Run". For detailed implementation guidance and architecture explanations, refer to the original recipe documentation.