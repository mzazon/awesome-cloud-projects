# Infrastructure as Code for Cloud Asset Governance with Cloud Asset Inventory and Cloud Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cloud Asset Governance with Cloud Asset Inventory and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) v400.0.0+ installed and configured
- Google Cloud project with billing enabled
- Organization-level access (Organization Admin or Security Admin roles)
- Appropriate permissions for:
  - Creating and managing Cloud Asset Inventory feeds
  - Deploying Cloud Functions, Cloud Workflows, and Pub/Sub resources
  - Creating BigQuery datasets and Cloud Storage buckets
  - Managing IAM policies at organization and project levels
- Estimated cost: $50-150/month for medium-scale deployments

> **Important**: This solution requires organization-level permissions to create asset feeds that monitor resources across multiple projects. Ensure you have the necessary administrative access before proceeding.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set required environment variables
export PROJECT_ID="governance-system-$(date +%s)"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)
export REGION="us-central1"

# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Initialize deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/governance-system \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/governance-iac" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},organization_id=${ORGANIZATION_ID},region=${REGION}"
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="governance-system-$(date +%s)"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)
export REGION="us-central1"

# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
organization_id = "${ORGANIZATION_ID}"
region = "${REGION}"
zone = "${REGION}-a"
governance_suffix = "gov-$(openssl rand -hex 3)"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="governance-system-$(date +%s)"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)
export REGION="us-central1"
export BILLING_ACCOUNT=$(gcloud billing accounts list --format="value(name)" --limit=1)

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the governance system
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID for governance system | - | Yes |
| `organization_id` | Organization ID for asset monitoring | - | Yes |
| `region` | Primary region for resource deployment | `us-central1` | No |
| `governance_suffix` | Unique suffix for resource naming | Auto-generated | No |
| `enable_monitoring` | Enable additional monitoring features | `true` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud project ID | `string` | - | Yes |
| `organization_id` | Organization ID for monitoring | `string` | - | Yes |
| `region` | Primary deployment region | `string` | `us-central1` | No |
| `zone` | Primary deployment zone | `string` | `us-central1-a` | No |
| `governance_suffix` | Unique resource suffix | `string` | Auto-generated | No |
| `asset_types` | List of asset types to monitor | `list(string)` | See variables.tf | No |
| `function_memory` | Memory allocation for Cloud Functions | `number` | `512` | No |
| `workflow_timeout` | Workflow execution timeout | `string` | `540s` | No |

## Architecture Overview

The deployed infrastructure includes:

- **Cloud Asset Inventory Feed**: Organization-wide resource monitoring
- **Pub/Sub Topic & Subscription**: Event streaming for asset changes
- **Cloud Storage Bucket**: Governance policies and compliance reports storage
- **BigQuery Dataset**: Analytics and compliance data warehouse
- **Cloud Functions**: Policy evaluation and workflow triggering
- **Cloud Workflows**: Orchestration of governance processes
- **IAM Service Account**: Secure service-to-service authentication
- **Cloud Monitoring**: Operational visibility and alerting

## Validation & Testing

After deployment, verify the system is working correctly:

```bash
# Check asset feed status
gcloud asset feeds list --organization=${ORGANIZATION_ID}

# Verify Pub/Sub infrastructure
gcloud pubsub topics list --filter="name:asset-changes"
gcloud pubsub subscriptions list --filter="name:workflow-processor"

# Test Cloud Functions
gcloud functions list --region=${REGION}

# Verify BigQuery dataset
bq ls ${PROJECT_ID}:asset_governance_*

# Test end-to-end flow by creating a test resource
gsutil mb gs://test-governance-$(openssl rand -hex 3)
```

## Monitoring & Observability

The governance system includes comprehensive monitoring:

- **Cloud Logging**: All governance activities and violations
- **Cloud Monitoring**: Function performance and workflow execution metrics
- **BigQuery Analytics**: Compliance trends and violation reporting
- **Pub/Sub Metrics**: Message processing and latency monitoring

Access governance dashboards:

```bash
# View recent violations
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.asset_governance_*.asset_violations\` 
     ORDER BY timestamp DESC LIMIT 10"

# Check compliance reports
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.asset_governance_*.compliance_reports\` 
     ORDER BY scan_timestamp DESC LIMIT 5"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/governance-system

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
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

## Security Considerations

This implementation follows Google Cloud security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **Encryption**: All data encrypted at rest and in transit
- **Network Security**: Private service connectivity where possible
- **Audit Logging**: Comprehensive logging for compliance requirements
- **Resource Isolation**: Governance infrastructure isolated in dedicated project

## Customization

### Adding Custom Governance Policies

Modify the Cloud Function code in `governance-function/main.py` to implement organization-specific policies:

```python
# Example: Add custom policy for database encryption
if asset_type == 'sqladmin.googleapis.com/Instance':
    settings = asset.get('resource', {}).get('data', {}).get('settings', {})
    if not settings.get('ipConfiguration', {}).get('requireSsl', False):
        violations.append({
            'policy': 'database_ssl_required',
            'severity': 'HIGH',
            'description': 'Database instance requires SSL connections'
        })
```

### Extending Asset Monitoring

Add additional asset types to monitor by updating the asset feed configuration:

```bash
# Update asset feed to include additional resource types
gcloud asset feeds update ${FEED_NAME} \
    --organization=${ORGANIZATION_ID} \
    --add-asset-types=iam.googleapis.com/ServiceAccount,pubsub.googleapis.com/Topic
```

### Custom Alerting

Integrate with external systems by modifying the workflow YAML:

```yaml
- custom_alert:
    call: http.post
    args:
      url: "https://your-alerting-system.com/api/alerts"
      headers:
        Authorization: "Bearer ${SECRET_TOKEN}"
      body:
        severity: ${violation_severity}
        message: ${violation_details}
```

## Troubleshooting

### Common Issues

1. **Asset Feed Creation Fails**
   - Verify organization-level permissions
   - Ensure Cloud Asset Inventory API is enabled
   - Check that the service account has pubsub.publisher role

2. **Function Deployment Errors**
   - Verify Cloud Functions API is enabled
   - Check that source code dependencies are correctly specified
   - Ensure sufficient IAM permissions for deployment

3. **Workflow Execution Failures**
   - Review Cloud Logging for detailed error messages
   - Verify service account permissions for all integrated services
   - Check that all API dependencies are properly enabled

4. **BigQuery Insert Errors**
   - Verify table schema matches insert data structure
   - Check that service account has BigQuery dataEditor role
   - Ensure BigQuery dataset exists and is accessible

### Debug Commands

```bash
# Check function logs
gcloud logging read "resource.type=cloud_function" --limit=50

# Monitor workflow executions
gcloud workflows executions list governance-orchestrator --location=${REGION}

# Verify Pub/Sub message flow
gcloud pubsub subscriptions pull ${WORKFLOW_SUBSCRIPTION} --auto-ack --limit=5
```

## Performance Optimization

- **Function Scaling**: Adjust max instances based on expected asset change volume
- **BigQuery Partitioning**: Implement table partitioning for large-scale deployments
- **Pub/Sub Optimization**: Configure message retention and acknowledgment deadlines
- **Workflow Parallelization**: Implement parallel processing for high-volume scenarios

## Compliance & Governance

This solution supports various compliance frameworks:

- **SOC 2**: Comprehensive audit logging and access controls
- **PCI DSS**: Data encryption and secure processing requirements
- **GDPR**: Data privacy and retention policy enforcement
- **HIPAA**: Healthcare data security and compliance monitoring

## Support & Documentation

- [Cloud Asset Inventory Documentation](https://cloud.google.com/asset-inventory/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.

## License

This infrastructure code is provided under the same license terms as the parent recipe repository.