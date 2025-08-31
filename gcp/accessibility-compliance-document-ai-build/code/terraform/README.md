# Terraform Infrastructure for Accessibility Compliance with Document AI and Cloud Build

This directory contains Terraform Infrastructure as Code (IaC) for deploying an automated accessibility compliance testing system using Google Cloud Platform services.

## Overview

This infrastructure creates a complete automated accessibility compliance solution that:

- **Analyzes HTML content** using Document AI for intelligent content extraction
- **Validates WCAG 2.1 compliance** through automated testing in Cloud Build pipelines
- **Monitors compliance status** via Security Command Center with centralized findings
- **Sends notifications** through Cloud Functions when violations are detected
- **Stores audit trails** in Cloud Storage for compliance reporting

## Architecture Components

### Core Services

- **Document AI**: OCR processor for intelligent content analysis and extraction
- **Cloud Build**: CI/CD pipeline for automated accessibility testing
- **Security Command Center**: Centralized compliance monitoring and findings management
- **Cloud Functions**: Serverless notification processing for compliance alerts
- **Cloud Storage**: Artifact storage for compliance reports and audit trails
- **Pub/Sub**: Messaging service for decoupled notification processing

### Supporting Infrastructure

- **IAM Roles & Permissions**: Least-privilege access for all service components
- **Build Triggers**: Automated testing on code commits and manual execution
- **Notification Configuration**: Alert routing for compliance violations
- **Lifecycle Policies**: Automated cleanup and cost optimization

## Prerequisites

### Required Tools

- **Terraform** >= 1.0
- **gcloud CLI** installed and authenticated
- **Google Cloud Project** with billing enabled
- **Organization-level access** (optional, for Security Command Center integration)

### Required Permissions

The deploying user needs the following IAM roles:

```bash
# Project-level roles
- Project Owner (or combination of roles below)
- Service Usage Admin
- Project IAM Admin
- Storage Admin
- Cloud Build Editor
- Cloud Functions Admin
- Document AI Admin
- Pub/Sub Admin

# Organization-level roles (if using Security Command Center)
- Security Center Admin
```

### Cost Estimation

Expected monthly costs for moderate usage:

- **Document AI**: $0.015 per page (first 1,000 pages free monthly)
- **Cloud Build**: $0.003 per build minute (first 120 minutes free daily)
- **Cloud Storage**: $0.020 per GB for Standard storage
- **Pub/Sub**: $40 per million messages
- **Cloud Functions**: $0.0000004 per invocation + $0.0000025 per GB-second
- **Security Command Center**: $0.00 for standard tier findings

**Total Estimated**: $15-25 monthly for moderate usage

## Quick Start

### 1. Initialize Terraform

```bash
# Clone or navigate to the terraform directory
cd gcp/accessibility-compliance-document-ai-build/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional: Organization ID for Security Command Center
organization_id = "123456789012"

# Optional: GitHub integration
github_repo_owner = "your-github-username"
github_repo_name  = "your-repository-name"

# Optional: Notification configuration
enable_email_notifications = true
notification_email         = "compliance-team@yourcompany.com"

# Optional: Resource customization
resource_prefix = "accessibility-compliance"
environment     = "prod"

# Optional: Labels for resource management
labels = {
  project     = "accessibility-compliance"
  environment = "production"
  team        = "devops"
  cost-center = "engineering"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Confirm the deployment
# Type 'yes' when prompted
```

### 4. Post-Deployment Setup

After successful deployment, complete these steps:

1. **Configure Repository Connection** (if using GitHub triggers):
   ```bash
   # Connect your GitHub repository to Cloud Build
   gcloud builds connections create github2 \
       --region=us-central1 \
       --name="accessibility-compliance-connection"
   ```

2. **Upload Build Configuration**:
   Create a `cloudbuild.yaml` file in your repository root with the accessibility testing pipeline configuration.

3. **Test the Pipeline**:
   ```bash
   # Get the manual trigger name from Terraform outputs
   terraform output manual_build_trigger_name
   
   # Submit a test build
   gcloud builds triggers run [TRIGGER_NAME] --branch=main
   ```

4. **Verify Security Command Center Integration** (if organization_id provided):
   - Visit the Security Command Center console
   - Look for the "Accessibility Compliance Scanner" source
   - Verify notification configuration is active

## Configuration Options

### Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `organization_id` | GCP organization ID for SCC | `""` | No |
| `github_repo_owner` | GitHub repository owner | `""` | No |
| `github_repo_name` | GitHub repository name | `""` | No |
| `enable_email_notifications` | Enable email alerts | `false` | No |
| `notification_email` | Email for compliance alerts | `""` | No |
| `resource_prefix` | Prefix for resource names | `accessibility-compliance` | No |
| `environment` | Environment name | `dev` | No |

### Advanced Configuration

For advanced use cases, you can customize:

- **Document AI processor type**: Change `document_ai_processor_type` for different analysis capabilities
- **Storage lifecycle**: Adjust `storage_lifecycle_age` for data retention policies
- **Function runtime**: Modify `function_runtime` for different language runtimes
- **Build triggers**: Customize `build_trigger_branch_pattern` for specific branch workflows

## Usage Examples

### Basic Deployment

```bash
# Minimal configuration for testing
terraform apply -var="project_id=my-test-project"
```

### Production Deployment

```bash
# Full production setup with all features
terraform apply \
  -var="project_id=my-prod-project" \
  -var="organization_id=123456789012" \
  -var="environment=prod" \
  -var="enable_email_notifications=true" \
  -var="notification_email=compliance@company.com" \
  -var="github_repo_owner=mycompany" \
  -var="github_repo_name=web-applications"
```

### Organization-Only Deployment

```bash
# Deploy without GitHub integration for manual testing
terraform apply \
  -var="project_id=my-project" \
  -var="organization_id=123456789012"
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **Build Success Rate**: Monitor Cloud Build execution success/failure rates
2. **Compliance Findings**: Track accessibility violation trends in Security Command Center
3. **Function Execution**: Monitor Cloud Function invocation success and latency
4. **Storage Usage**: Track compliance report storage growth and costs

### Accessing Logs and Metrics

```bash
# Cloud Build logs
gcloud builds log [BUILD_ID]

# Cloud Function logs
gcloud functions logs read [FUNCTION_NAME] --region=[REGION]

# Security Command Center findings
gcloud scc findings list --organization=[ORG_ID] \
  --source=[SOURCE_ID] \
  --filter='category="ACCESSIBILITY_COMPLIANCE"'
```

### Dashboard Creation

Use the Terraform outputs to create monitoring dashboards:

```bash
# Get monitoring resource URLs
terraform output monitoring_resources
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
   ```bash
   gcloud services enable documentai.googleapis.com cloudbuild.googleapis.com
   ```

2. **Insufficient Permissions**: Verify IAM roles for the deploying user
   ```bash
   gcloud projects get-iam-policy [PROJECT_ID]
   ```

3. **Organization Access**: Security Command Center requires organization-level permissions
   ```bash
   gcloud organizations get-iam-policy [ORG_ID]
   ```

4. **Function Deployment**: Check function logs for runtime errors
   ```bash
   gcloud functions logs read compliance-notifier --region=us-central1
   ```

### Validation Commands

```bash
# Test Document AI processor
gcloud documentai processors list --location=us-central1

# Verify storage bucket
gsutil ls gs://[BUCKET_NAME]/

# Test Pub/Sub topic
gcloud pubsub topics publish [TOPIC_NAME] --message="test"

# Check Security Command Center source
gcloud scc sources list --organization=[ORG_ID]
```

## Maintenance

### Updates and Upgrades

1. **Terraform Updates**: Regularly update Terraform and provider versions
2. **Function Dependencies**: Update Python dependencies in `requirements.txt`
3. **Security Patches**: Monitor Google Cloud security advisories
4. **Cost Optimization**: Review storage lifecycle and resource usage

### Backup and Recovery

- **Terraform State**: Store state in Google Cloud Storage backend
- **Configuration Backup**: Version control all Terraform files
- **Compliance Reports**: Implement cross-region storage replication

## Cleanup

To remove all resources:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

**Warning**: This will permanently delete all compliance reports and audit trails. Ensure you have backed up any required data before destroying the infrastructure.

## Security Considerations

### Best Practices Implemented

- **Least Privilege IAM**: All service accounts have minimal required permissions
- **Encryption at Rest**: All storage uses Google-managed encryption
- **Network Security**: Private service communication where possible
- **Audit Logging**: Comprehensive audit trail for all compliance activities
- **Secret Management**: Environment variables for sensitive configuration

### Additional Security Measures

For enhanced security in production:

1. **Enable VPC Service Controls** for additional network security
2. **Implement Customer-Managed Encryption Keys (CMEK)** for sensitive data
3. **Configure Organization Policies** for resource constraints
4. **Enable Cloud Asset Inventory** for comprehensive resource tracking

## Support and Contributing

### Getting Help

- **Google Cloud Documentation**: [Cloud Build](https://cloud.google.com/build/docs), [Document AI](https://cloud.google.com/document-ai/docs)
- **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **WCAG Guidelines**: [WCAG 2.1 Quick Reference](https://www.w3.org/WAI/WCAG21/quickref/)

### Contributing

When contributing to this infrastructure:

1. Follow Terraform best practices and style guidelines
2. Test all changes in a development environment
3. Update documentation for any new variables or resources
4. Ensure all resources include appropriate labels and tags

## License

This infrastructure code is provided as-is for educational and implementation purposes. Please ensure compliance with your organization's security and governance policies before deploying to production environments.