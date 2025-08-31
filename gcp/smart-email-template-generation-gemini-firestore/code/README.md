# Infrastructure as Code for Smart Email Template Generation with Gemini and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Email Template Generation with Gemini and Firestore".

## Overview

This solution deploys an AI-powered email template generation system using Google Cloud services:

- **Vertex AI Gemini** for intelligent content generation
- **Firestore** for storing user preferences and generated templates
- **Cloud Functions** for serverless orchestration and API endpoints
- **Cloud Build** for function deployment automation

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Bash Scripts**: Deployment and cleanup automation scripts

## Architecture

The infrastructure deploys:

1. **Firestore Database** - Native mode database for storing user preferences, campaign types, and generated templates
2. **Cloud Function** - Serverless function that orchestrates AI generation and data storage
3. **IAM Permissions** - Service accounts and roles for secure access to Vertex AI and Firestore
4. **API Enablement** - Required Google Cloud APIs for all services

## Prerequisites

### Required Tools

- **Google Cloud CLI** installed and configured ([Installation Guide](https://cloud.google.com/sdk/docs/install))
- **Terraform** (>= 1.5.0) for Terraform deployments ([Download](https://www.terraform.io/downloads))
- **Infrastructure Manager API** enabled for Infrastructure Manager deployments

### Required Permissions

Your Google Cloud account needs the following IAM roles:

- `roles/owner` or equivalent permissions for:
  - `roles/resourcemanager.projectCreator`
  - `roles/billing.projectManager`
  - `roles/serviceusage.serviceUsageAdmin`
  - `roles/iam.serviceAccountAdmin`
  - `roles/cloudfunctions.admin`
  - `roles/datastore.owner`
  - `roles/aiplatform.admin`

### Cost Estimation

Estimated monthly costs for testing and light usage:

- **Firestore**: ~$1-3 (document operations and storage)
- **Cloud Functions**: ~$1-2 (invocations and compute time)
- **Vertex AI Gemini**: ~$2-8 (API calls based on usage)
- **Total**: ~$4-13 per month for development/testing

> **Note**: Costs may vary based on usage patterns. Use [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for detailed estimates.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy with Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/email-template-generator \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/terraform.tfvars"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Common Variables

All implementations support these configuration variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `email-template-generator` | No |
| `database_name` | Firestore database name | `email-templates` | No |
| `environment` | Environment tag | `development` | No |

### Terraform-Specific Variables

```hcl
# terraform/terraform.tfvars.example
project_id = "your-project-id"
region = "us-central1"
function_name = "email-template-generator"
database_name = "email-templates"
environment = "development"

# Optional: Override default settings
function_memory = "512Mi"
function_timeout = 120
max_instances = 10
```

### Infrastructure Manager Configuration

```yaml
# infrastructure-manager/terraform.tfvars
project_id: "your-project-id"
region: "us-central1"
function_name: "email-template-generator"
database_name: "email-templates"
environment: "development"
```

## Deployment Steps

### 1. Pre-deployment Setup

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set default project
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs (done automatically by IaC)
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable firestore.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable cloudbuild.googleapis.com
```

### 2. Deploy Infrastructure

Choose one of the deployment methods above based on your preference.

### 3. Post-deployment Verification

```bash
# Verify Firestore database
gcloud firestore databases list

# Verify Cloud Function
gcloud functions list --gen2

# Test the function endpoint
FUNCTION_URL=$(gcloud functions describe email-template-generator --gen2 --format="value(serviceConfig.uri)")
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"campaign_type": "newsletter", "subject_theme": "test", "custom_context": "testing deployment"}'
```

## Validation & Testing

### Infrastructure Validation

```bash
# Check Firestore collections
gcloud firestore collections list --database=email-templates

# Verify Cloud Function logs
gcloud functions logs read email-template-generator --gen2 --limit=10

# Test API endpoint functionality
FUNCTION_URL=$(gcloud functions describe email-template-generator --gen2 --format="value(serviceConfig.uri)")

# Test newsletter generation
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "campaign_type": "newsletter",
        "subject_theme": "product updates",
        "custom_context": "announcing new features"
    }' | jq '.'
```

### Expected Response

```json
{
  "success": true,
  "template_id": "abc123def456",
  "template": {
    "subject": "Exciting Product Updates from Your Company",
    "body": "Hello [First Name],\n\nWe're excited to share our latest product updates..."
  },
  "campaign_type": "newsletter"
}
```

## Monitoring and Logging

### View Function Logs

```bash
# Real-time logs
gcloud functions logs tail email-template-generator --gen2

# Historical logs with filtering
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=email-template-generator" \
    --limit=50 --format="table(timestamp,severity,textPayload)"
```

### Monitor Firestore Usage

```bash
# View Firestore metrics in Cloud Console
gcloud logging read "resource.type=gce_instance AND resource.labels.project_id=${PROJECT_ID}" \
    --filter="resource.labels.database_id=email-templates"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/email-template-generator
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --filter="name:email-template-generator"
gcloud firestore databases list --filter="name:email-templates"
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Function
gcloud functions delete email-template-generator --gen2 --region=us-central1 --quiet

# Delete Firestore database
gcloud firestore databases delete email-templates --quiet

# Disable APIs (optional)
gcloud services disable cloudfunctions.googleapis.com
gcloud services disable firestore.googleapis.com
gcloud services disable aiplatform.googleapis.com
```

## Customization

### Modifying the Cloud Function

The generated infrastructure includes placeholder function code. To customize:

1. Update the function source code in the deployment
2. Modify environment variables and runtime settings
3. Adjust memory allocation and timeout values
4. Configure additional triggers or integrations

### Extending the Architecture

Consider these enhancements:

1. **Add Cloud Storage** for template assets and media
2. **Implement Cloud Pub/Sub** for asynchronous processing
3. **Add Cloud Load Balancing** for high availability
4. **Configure Cloud CDN** for static content delivery
5. **Integrate Cloud Monitoring** for advanced observability

### Security Hardening

For production deployments:

1. **Enable VPC Security** - Deploy functions in VPC with private Google access
2. **Implement IAM Conditions** - Add time and IP-based access controls
3. **Configure Cloud Armor** - Add DDoS protection and WAF rules
4. **Enable Audit Logging** - Track all API calls and data access
5. **Use Secret Manager** - Store sensitive configuration securely

## Troubleshooting

### Common Issues

#### Permission Errors

```bash
# Verify current permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Add required roles
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:your-email@domain.com" \
    --role="roles/cloudfunctions.admin"
```

#### Function Deployment Failures

```bash
# Check build logs
gcloud functions logs read email-template-generator --gen2 --limit=50

# Verify source code integrity
gcloud functions describe email-template-generator --gen2 --format="yaml"
```

#### Firestore Connection Issues

```bash
# Verify database status
gcloud firestore databases describe email-templates

# Check IAM permissions for function service account
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:*"
```

#### API Quota Limits

```bash
# Check current quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"

# Monitor API usage
gcloud logging read "protoPayload.serviceName=aiplatform.googleapis.com" \
    --limit=10 --format="table(timestamp,protoPayload.methodName)"
```

### Performance Optimization

#### Function Performance

- **Memory Allocation**: Increase to 1GB for faster AI processing
- **Timeout Settings**: Extend to 540s for complex generation tasks
- **Concurrency**: Adjust max instances based on expected load
- **Cold Start Optimization**: Use minimum instances for production

#### Firestore Performance

- **Index Optimization**: Create composite indexes for complex queries
- **Collection Design**: Structure data for efficient reads
- **Batch Operations**: Use batch writes for bulk data operations
- **Caching Strategy**: Implement application-level caching for frequently accessed data

## Support and Documentation

### Official Documentation

- [Google Cloud Functions](https://cloud.google.com/functions/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)
- [Vertex AI Gemini](https://cloud.google.com/vertex-ai/generative-ai/docs/multimodal/overview)
- [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Community Resources

- [Google Cloud Community](https://cloud.google.com/community)
- [Terraform Google Provider Issues](https://github.com/hashicorp/terraform-provider-google/issues)
- [Stack Overflow - Google Cloud](https://stackoverflow.com/questions/tagged/google-cloud-platform)

### Getting Help

For issues with this infrastructure code:

1. Check the [original recipe documentation](../smart-email-template-generation-gemini-firestore.md)
2. Review Google Cloud service status at [status.cloud.google.com](https://status.cloud.google.com)
3. Consult the troubleshooting section above
4. Search existing issues in the respective tool's repository

## License and Disclaimer

This infrastructure code is provided as-is for educational and development purposes. Review and test thoroughly before using in production environments. Ensure compliance with your organization's security policies and Google Cloud best practices.