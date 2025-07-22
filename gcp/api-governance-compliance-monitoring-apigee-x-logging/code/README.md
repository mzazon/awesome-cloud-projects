# Infrastructure as Code for API Governance and Compliance Monitoring with Apigee X and Cloud Logging

This directory contains Infrastructure as Code (IaC) implementations for the recipe "API Governance and Compliance Monitoring with Apigee X and Cloud Logging".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK installed and configured (version 400.0.0 or later)
- Active Google Cloud project with billing enabled
- Apigee X organization provisioned (may take 1-2 hours initially)
- Owner or Editor permissions for resource creation
- Understanding of API management and compliance frameworks

### Required APIs
The following APIs will be automatically enabled during deployment:
- Apigee API (`apigee.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Eventarc API (`eventarc.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Pub/Sub API (`pubsub.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)

## Quick Start

### Environment Setup

First, configure your environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique suffix for resources
RANDOM_SUFFIX=$(openssl rand -hex 3)
export APIGEE_ORG="${PROJECT_ID}"
export ENV_NAME="dev-${RANDOM_SUFFIX}"

# Set default project and region
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}
```

### Using Infrastructure Manager (Recommended)

Google Cloud's Infrastructure Manager provides native support for Terraform configurations with enhanced Google Cloud integration.

```bash
# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/api-governance-deployment \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/api-governance-compliance-monitoring-apigee-x-logging/code/infrastructure-manager" \
    --git-source-ref="main" \
    --inputs-file="terraform.tfvars"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/api-governance-deployment
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="apigee_org=${APIGEE_ORG}" \
    -var="env_name=${ENV_NAME}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="apigee_org=${APIGEE_ORG}" \
    -var="env_name=${ENV_NAME}"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required environment variables if not set
```

## Architecture Overview

This solution deploys:

1. **Apigee X Environment**: Secure API management platform with governance policies
2. **Cloud Logging Configuration**: Centralized logging with structured sinks
3. **BigQuery Dataset**: Data warehouse for compliance analytics and reporting
4. **Pub/Sub Topics**: Real-time event streaming for compliance monitoring
5. **Cloud Functions**: Serverless compliance monitoring and policy enforcement
6. **Eventarc Triggers**: Event-driven automation for violation response
7. **Cloud Monitoring**: Dashboards and alerting for governance metrics
8. **Cloud Storage**: Secure storage for function code and configurations

## Configuration Options

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `apigee_org` | Apigee organization name | `project_id` | No |
| `env_name` | Apigee environment name | `dev-${random_suffix}` | No |
| `enable_apis` | Enable required APIs automatically | `true` | No |
| `create_storage_bucket` | Create Cloud Storage bucket | `true` | No |
| `function_memory` | Memory allocation for Cloud Functions | `256` | No |
| `function_timeout` | Timeout for Cloud Functions (seconds) | `60` | No |
| `log_retention_days` | Log retention period | `30` | No |
| `alert_notification_channels` | Alert notification channels | `[]` | No |

### Infrastructure Manager Configuration

Create a `terraform.tfvars` file with your specific values:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
apigee_org = "your-apigee-org"
env_name = "dev-governance"
enable_apis = true
function_memory = 256
function_timeout = 60
log_retention_days = 30
```

## Validation & Testing

After deployment, validate the solution:

```bash
# Check Apigee environment status
gcloud alpha apigee environments describe ${ENV_NAME} \
    --organization=${APIGEE_ORG} \
    --format="table(name,state,createdAt)"

# Verify Cloud Functions deployment
gcloud functions list --region=${REGION} \
    --format="table(name,status,trigger)"

# Test compliance monitoring function
gcloud pubsub topics publish api-governance-events \
    --message='{"severity":"WARNING","resource":{"type":"apigee_organization"}}'

# Check BigQuery dataset creation
bq ls --project_id=${PROJECT_ID} --format="table"

# Verify log sinks configuration
gcloud logging sinks list \
    --format="table(name,destination,filter)"
```

## Monitoring & Operations

### Dashboard Access

Access the governance dashboard through:
```bash
# Get dashboard URL
gcloud monitoring dashboards list \
    --filter="displayName:'API Governance Dashboard'" \
    --format="value(name)"
```

### Log Analysis

Query compliance logs in BigQuery:
```sql
SELECT
  timestamp,
  severity,
  resource.type,
  protoPayload.methodName,
  protoPayload.authenticationInfo.principalEmail
FROM `${PROJECT_ID}.api_governance.*`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY timestamp DESC;
```

### Alert Configuration

Monitor key compliance metrics:
- Authentication failure rates
- Rate limit violations
- Policy bypass attempts
- Unusual API usage patterns

## Security Considerations

This solution implements several security best practices:

1. **Least Privilege IAM**: All services use minimal required permissions
2. **Encryption**: Data encrypted at rest and in transit
3. **Network Security**: Private service connections where possible
4. **Audit Logging**: Comprehensive audit trails for all actions
5. **Automated Response**: Immediate response to security violations
6. **Policy Enforcement**: Consistent policy application across all APIs

## Cost Optimization

### Estimated Monthly Costs (Development Environment)

- Apigee X: $150-200/month
- Cloud Functions: $10-30/month
- Cloud Logging: $20-50/month
- BigQuery: $10-25/month
- Pub/Sub: $5-15/month
- Cloud Storage: $5-10/month

**Total Estimated Cost: $200-330/month**

### Cost Optimization Tips

1. **Right-size Resources**: Adjust function memory and timeout based on actual usage
2. **Log Retention**: Configure appropriate log retention periods
3. **Data Lifecycle**: Implement BigQuery table partitioning and expiration
4. **Monitoring**: Use Cloud Monitoring to track resource utilization
5. **Development vs Production**: Use separate environments with different resource sizes

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/api-governance-deployment

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="apigee_org=${APIGEE_ORG}" \
    -var="env_name=${ENV_NAME}"

# Clean up Terraform state
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Script will confirm before deleting resources
```

### Manual Cleanup (If Required)

Some resources may require manual cleanup:

```bash
# Remove any remaining Cloud Functions
gcloud functions delete api-compliance-monitor --region=${REGION} --quiet
gcloud functions delete api-policy-enforcer --region=${REGION} --quiet

# Delete Apigee environment (if not handled by automation)
gcloud alpha apigee environments delete ${ENV_NAME} \
    --organization=${APIGEE_ORG} --quiet

# Remove BigQuery dataset
bq rm -r -f ${PROJECT_ID}:api_governance

# Delete Cloud Storage bucket
gsutil -m rm -r gs://governance-functions-*
```

## Troubleshooting

### Common Issues

1. **Apigee Organization Not Found**
   - Verify Apigee X organization is provisioned
   - Check IAM permissions for Apigee API

2. **Function Deployment Failures**
   - Verify Cloud Functions API is enabled
   - Check Cloud Storage bucket permissions
   - Validate function source code syntax

3. **Log Sink Creation Errors**
   - Verify BigQuery dataset exists
   - Check Pub/Sub topic permissions
   - Validate log filter syntax

4. **Eventarc Trigger Issues**
   - Verify Eventarc API is enabled
   - Check service account permissions
   - Validate event filter configuration

### Debug Commands

```bash
# Check API enablement status
gcloud services list --enabled --filter="name:apigee.googleapis.com"

# View function logs
gcloud functions logs read api-compliance-monitor --region=${REGION}

# Test Pub/Sub connectivity
gcloud pubsub topics publish api-governance-events --message="test"

# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify API enablement and IAM permissions
4. Review Cloud Logging for deployment errors
5. Contact your Google Cloud support team for platform-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any configuration changes
4. Validate security and compliance requirements
5. Test both deployment and cleanup procedures

## License

This infrastructure code is provided under the same license as the parent recipe repository.