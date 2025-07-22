# Infrastructure as Code for Workflow Automation with Google Workspace Flows and Service Extensions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Workflow Automation with Google Workspace Flows and Service Extensions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud Project with billing enabled
- Google Workspace Business or Enterprise account with Gemini for Google Workspace license
- Domain administrator access to configure Google Workspace Flows
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Storage Admin
  - Service Extensions Admin
  - Project IAM Admin
- Estimated cost: $50-150/month depending on usage volume

> **Note**: Google Workspace Flows is currently in alpha and requires specific domain eligibility criteria including Gemini for Google Workspace licenses purchased before January 15, 2025.

## Architecture Overview

This solution deploys:
- Cloud Storage bucket with lifecycle policies for document processing
- Pub/Sub topics and subscriptions for event orchestration
- Cloud Functions for document analysis, approval processing, and notifications
- Service Extensions infrastructure for WebAssembly business logic
- Monitoring and analytics collection systems
- Integration points for Google Workspace Flows

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Validate the configuration
gcloud infra-manager deployments create workflow-automation \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/im-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/workflow-automation" \
    --git-source-directory="infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}" \
    --preview

# Deploy the infrastructure
gcloud infra-manager deployments apply workflow-automation \
    --location=${REGION}
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
region     = "${REGION}"
zone       = "${REGION}-a"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Follow the script prompts for configuration
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | Yes |
| `zone` | Primary deployment zone | `us-central1-a` | Yes |
| `bucket_name_suffix` | Suffix for storage bucket | `auto-generated` | No |
| `enable_versioning` | Enable bucket versioning | `true` | No |
| `notification_email` | Admin notification email | - | Yes |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | `string` | - | Yes |
| `region` | Primary deployment region | `string` | `us-central1` | Yes |
| `zone` | Primary deployment zone | `string` | `us-central1-a` | Yes |
| `environment` | Environment name | `string` | `development` | No |
| `labels` | Resource labels | `map(string)` | `{}` | No |
| `function_memory` | Cloud Function memory | `number` | `512` | No |
| `function_timeout` | Cloud Function timeout | `number` | `540` | No |

### Script Configuration

The bash scripts use environment variables and interactive prompts for configuration:

```bash
# Required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export BUCKET_NAME_PREFIX="workflow-docs"
export FUNCTION_MEMORY="512MB"
export FUNCTION_TIMEOUT="540s"
export NOTIFICATION_EMAIL="admin@yourdomain.com"
```

## Post-Deployment Configuration

### Google Workspace Flows Setup

1. **Access Workspace Flows Admin Panel**:
   - Navigate to Google Admin Console
   - Go to Apps > Google Workspace > Flows
   - Enable Flows for your domain

2. **Create Document Processing Flow**:
   - Use the generated configuration template in `workspace-flows/document-approval-flow.json`
   - Configure watched folders in Google Drive
   - Set up Gemini AI analysis prompts
   - Configure approval notification templates

3. **Configure Integration Endpoints**:
   - Update webhook URLs with deployed Cloud Function endpoints
   - Configure authentication for Workspace to Cloud integration
   - Test document upload triggers

### Service Extensions Configuration

1. **Deploy WebAssembly Plugins**:
   ```bash
   # Build WebAssembly module (requires Rust toolchain)
   cd service-extensions/business-rules/
   cargo build --target wasm32-unknown-unknown --release
   
   # Deploy to Service Extensions
   gcloud service-extensions wasm-plugins create business-rules \
       --location=${REGION} \
       --image=path/to/your/wasm/module.wasm
   ```

2. **Configure Business Rules**:
   - Customize approval workflows in the WebAssembly code
   - Update document type classifications
   - Configure department-specific routing rules

### Monitoring Setup

1. **Create Custom Dashboards**:
   ```bash
   # Import monitoring dashboard
   gcloud monitoring dashboards create \
       --config-from-file=monitoring/workflow-dashboard.json
   ```

2. **Set Up Alerting**:
   ```bash
   # Create alerting policies for workflow failures
   gcloud alpha monitoring policies create \
       --policy-from-file=monitoring/alert-policies.yaml
   ```

## Validation & Testing

### Infrastructure Validation

```bash
# Verify Cloud Functions deployment
gcloud functions list --filter="name~doc-processor"

# Check Pub/Sub topics and subscriptions
gcloud pubsub topics list --filter="name~document-events"
gcloud pubsub subscriptions list --filter="name~doc-processing"

# Validate storage bucket configuration
gsutil ls -L gs://your-bucket-name
```

### End-to-End Testing

```bash
# Test document processing function
curl -X POST \
  "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/doc-processor-${SUFFIX}" \
  -H "Content-Type: application/json" \
  -d '{
    "fileName": "test-document.pdf",
    "bucketName": "your-bucket-name",
    "metadata": {
      "document_type": "invoice",
      "department": "finance",
      "priority": "high"
    }
  }'

# Test approval webhook
curl -X POST \
  "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/approval-webhook-${SUFFIX}" \
  -H "Content-Type: application/json" \
  -d '{
    "workflowId": "test-workflow-123",
    "approverEmail": "test@company.com",
    "decision": "approved",
    "comments": "Test approval"
  }'
```

### Workspace Integration Testing

1. **Test Document Upload Trigger**:
   - Upload a test document to the configured Google Drive folder
   - Verify Workspace Flows triggers the workflow
   - Check Cloud Function logs for processing events

2. **Test Approval Notifications**:
   - Verify Gmail notifications are sent to approvers
   - Test Google Chat notification delivery
   - Validate Google Sheets logging functionality

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete workflow-automation \
    --location=${REGION} \
    --force
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining Cloud Functions
gcloud functions delete doc-processor-${SUFFIX} --region=${REGION} --quiet
gcloud functions delete approval-webhook-${SUFFIX} --region=${REGION} --quiet
gcloud functions delete chat-notifications-${SUFFIX} --region=${REGION} --quiet

# Clean up Pub/Sub resources
gcloud pubsub subscriptions delete doc-processing-sub-${SUFFIX} --quiet
gcloud pubsub topics delete document-events-${SUFFIX} --quiet

# Remove storage bucket
gsutil -m rm -r gs://workflow-docs-${SUFFIX}/**
gsutil rb gs://workflow-docs-${SUFFIX}
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Errors**:
   ```bash
   # Enable all required APIs
   gcloud services enable \
       cloudfunctions.googleapis.com \
       pubsub.googleapis.com \
       storage.googleapis.com \
       serviceextensions.googleapis.com \
       admin.googleapis.com
   ```

2. **Permission Errors**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add missing roles if needed
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="serviceAccount:your-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
       --role="roles/cloudfunctions.admin"
   ```

3. **Function Deployment Failures**:
   ```bash
   # Check function logs
   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}
   
   # Verify function source code
   gcloud functions describe ${FUNCTION_NAME} --region=${REGION}
   ```

4. **Workspace Flows Integration Issues**:
   - Verify domain eligibility for Workspace Flows alpha
   - Check Gemini for Google Workspace license status
   - Validate Google Workspace admin permissions
   - Ensure API endpoints are accessible from Workspace

### Debug Mode

Enable debug logging for all components:

```bash
# Set debug environment variables
export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account.json"
export DEBUG_MODE="true"

# Re-run deployment with verbose logging
./scripts/deploy.sh --debug
```

## Security Considerations

### IAM Best Practices

- Use least privilege principle for all service accounts
- Enable audit logging for all API calls
- Implement proper resource-level permissions
- Regular review and rotation of service account keys

### Data Protection

- Enable encryption at rest for all storage resources
- Use HTTPS for all API endpoints
- Implement proper authentication for webhook endpoints
- Configure VPC-native networking where applicable

### Compliance

- Document approval workflows for audit purposes
- Implement retention policies for processed documents
- Configure monitoring for security events
- Maintain access logs for compliance reporting

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: Check official Google Cloud documentation
3. **Terraform Provider**: Reference the Google Cloud Terraform provider documentation
4. **Community Support**: Use Stack Overflow with appropriate tags

## Additional Resources

- [Google Workspace Flows Documentation](https://workspace.google.com/products/flows/)
- [Service Extensions Documentation](https://cloud.google.com/service-extensions/docs)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Pub/Sub Message Flow Design](https://cloud.google.com/pubsub/docs/overview)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your organization's policies for production usage guidelines.