# Infrastructure as Code for Resource Governance with Policy Simulator and Resource Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Resource Governance with Policy Simulator and Resource Manager".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Organization-level IAM permissions for policy management and resource governance
- Google Cloud project with billing enabled
- Required APIs enabled:
  - Policy Simulator API
  - Cloud Resource Manager API
  - Cloud Billing API
  - Cloud Functions API
  - Pub/Sub API
  - Cloud Asset API
  - BigQuery API
  - Cloud Scheduler API

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native IaC service that provides GitOps-style infrastructure management with built-in state management and Google Cloud integration.

```bash
# Set required environment variables
export PROJECT_ID="governance-automation-$(date +%s)"
export REGION="us-central1"
export ORGANIZATION_ID=$(gcloud organizations list \
    --filter="displayName:example.com" \
    --format="value(name)" | cut -d'/' -f2)

# Create and configure the deployment
cd infrastructure-manager/

# Create Infrastructure Manager deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/governance-system \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/governance-system

# View deployment outputs
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/governance-system \
    --format="value(serviceAccount,outputs)"
```

### Using Terraform

Terraform provides cross-cloud infrastructure management with extensive provider ecosystem and state management capabilities.

```bash
# Set required environment variables
export PROJECT_ID="governance-automation-$(date +%s)"
export REGION="us-central1"
export ORGANIZATION_ID=$(gcloud organizations list \
    --filter="displayName:example.com" \
    --format="value(name)" | cut -d'/' -f2)

# Navigate to terraform directory and initialize
cd terraform/

# Initialize Terraform with Google Cloud provider
terraform init

# Create terraform.tfvars file with your specific values
cat > terraform.tfvars << EOF
project_id      = "${PROJECT_ID}"
region          = "${REGION}"
organization_id = "${ORGANIZATION_ID}"
EOF

# Review the execution plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs after successful deployment
terraform output
```

### Using Bash Scripts

Bash scripts provide direct CLI-based deployment for maximum control and customization.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="governance-automation-$(date +%s)"
export REGION="us-central1"
export ORGANIZATION_ID=$(gcloud organizations list \
    --filter="displayName:example.com" \
    --format="value(name)" | cut -d'/' -f2)

# Deploy the governance system
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create service accounts with appropriate permissions
# 3. Deploy Cloud Functions for governance automation
# 4. Configure organization policies and constraints
# 5. Set up billing integration and budgets
# 6. Create scheduled governance audits
# 7. Configure resource tagging policies
```

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment can be customized by modifying `inputs.yaml`:

```yaml
project_id: "your-project-id"
region: "us-central1"
organization_id: "your-org-id"
governance_budget_amount: 100
allowed_regions:
  - "us-central1"
  - "us-east1"
  - "us-west1"
required_labels:
  - "environment"
  - "team"
  - "cost-center"
  - "project-code"
```

### Terraform Variables

Customize the deployment by modifying `terraform.tfvars`:

```hcl
project_id                    = "your-project-id"
region                       = "us-central1"
organization_id              = "your-organization-id"
governance_budget_amount     = 100
function_source_bucket_name  = "governance-source-bucket"
governance_function_name     = "governance-automation"
governance_topic_name        = "governance-events"
allowed_compute_regions      = ["us-central1", "us-east1", "us-west1"]
required_resource_labels     = ["environment", "team", "cost-center", "project-code"]
audit_schedule              = "0 9 * * 1"  # Weekly on Monday at 9 AM
cost_monitoring_schedule    = "0 8 * * *"  # Daily at 8 AM
```

### Script Environment Variables

The bash scripts use these environment variables for configuration:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ORGANIZATION_ID="your-organization-id"

# Optional customization variables
export GOVERNANCE_BUDGET_AMOUNT="100"
export FUNCTION_SOURCE_BUCKET="governance-source-bucket"
export GOVERNANCE_FUNCTION_NAME="governance-automation"
export GOVERNANCE_TOPIC_NAME="governance-events"
export AUDIT_SCHEDULE="0 9 * * 1"
export COST_MONITORING_SCHEDULE="0 8 * * *"
```

## Validation & Testing

After deployment, validate the governance system:

```bash
# Test organization policy enforcement
gcloud compute instances create test-compliance-vm \
    --zone=asia-east1-a \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud
# This should fail due to location constraint

# Test resource tagging enforcement
gcloud compute instances create test-tagging-fail \
    --zone=us-central1-a \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud
# This should fail due to missing required labels

# Create resource with proper labels (should succeed)
gcloud compute instances create test-tagging-success \
    --zone=us-central1-a \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --labels=environment=dev,team=engineering,cost-center=rd,project-code=gov-test

# Test governance automation function
gcloud pubsub topics publish governance-events \
    --message='{"audit_type":"full","project_scope":"organization"}'

# Verify scheduled jobs
gcloud scheduler jobs list
```

## Monitoring & Operations

### Cloud Function Logs

Monitor governance automation function logs:

```bash
# View recent function execution logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=governance-automation" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"

# Stream logs in real-time
gcloud logging tail "resource.type=cloud_function AND resource.labels.function_name=governance-automation"
```

### Organization Policy Status

Check organization policy status:

```bash
# List all organization policies
gcloud org-policies list --organization=${ORGANIZATION_ID}

# Check specific policy status
gcloud org-policies describe custom.restrictComputeLocations \
    --organization=${ORGANIZATION_ID}

# List custom constraints
gcloud org-policies list-custom-constraints \
    --organization=${ORGANIZATION_ID}
```

### Billing and Budget Monitoring

Monitor billing and budget status:

```bash
# Check billing account association
gcloud billing projects describe ${PROJECT_ID}

# List billing budgets
gcloud billing budgets list \
    --billing-account=$(gcloud billing projects describe ${PROJECT_ID} --format="value(billingAccountName)" | cut -d'/' -f2)

# View budget alerts
gcloud logging read "protoPayload.methodName=google.cloud.billing.budgets.v1.BudgetService.UpdateBudget" \
    --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/governance-system

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# The script will:
# 1. Remove test resources
# 2. Delete scheduled jobs and functions
# 3. Clean up organization policies and constraints
# 4. Remove service accounts and storage
# 5. Verify complete cleanup
```

## Cost Optimization

### Resource Cost Breakdown

Estimated monthly costs for the governance system:

- **Cloud Functions**: $5-15 (based on execution frequency)
- **Cloud Storage**: $1-5 (for function source and reports)
- **Pub/Sub**: $1-3 (for governance events)
- **Cloud Scheduler**: $0.10 per job (minimal cost)
- **Policy Simulator**: No additional charges
- **Organization Policy**: No additional charges
- **Cloud Asset Inventory**: Included in organization management

**Total Estimated Cost**: $20-50/month

### Cost Optimization Tips

1. **Function Memory**: Optimize Cloud Function memory allocation based on actual usage
2. **Storage Lifecycle**: Implement lifecycle policies for governance reports in Cloud Storage
3. **Audit Frequency**: Adjust audit schedules based on organizational needs
4. **Regional Deployment**: Deploy in regions with lower compute costs when possible

## Security Considerations

### IAM Best Practices

The governance system follows least privilege principles:

- Service accounts have minimal required permissions
- Organization-level permissions are scoped to specific governance operations
- Function execution uses dedicated service accounts
- Cross-project access is explicitly controlled

### Data Protection

- All governance reports are stored with encryption at rest
- Pub/Sub messages are encrypted in transit
- Function environment variables are managed securely
- Audit logs are retained according to compliance requirements

### Network Security

- Cloud Functions use private Google networks
- No external network access unless explicitly required
- VPC integration available for enhanced network controls

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**:
   ```bash
   # Verify organization-level permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Check service account permissions
   gcloud iam service-accounts get-iam-policy policy-simulator-sa@${PROJECT_ID}.iam.gserviceaccount.com
   ```

2. **Function Deployment Failures**:
   ```bash
   # Check function logs for deployment errors
   gcloud logging read "resource.type=cloud_function" --limit=20
   
   # Verify required APIs are enabled
   gcloud services list --enabled
   ```

3. **Organization Policy Issues**:
   ```bash
   # Validate policy syntax
   gcloud org-policies set-policy policy-file.yaml --dry-run
   
   # Check policy hierarchy conflicts
   gcloud org-policies describe POLICY_NAME --effective
   ```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Enable debug logging for gcloud commands
export CLOUDSDK_CORE_VERBOSITY=debug

# Set function logging level to DEBUG
gcloud functions deploy governance-automation \
    --set-env-vars="LOG_LEVEL=DEBUG"
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../resource-governance-policy-simulator-resource-manager.md)
2. Review [Google Cloud Organization Policy documentation](https://cloud.google.com/resource-manager/docs/organization-policy/overview)
3. Consult [Policy Intelligence documentation](https://cloud.google.com/policy-intelligence/docs)
4. Refer to [Cloud Functions troubleshooting guide](https://cloud.google.com/functions/docs/troubleshooting)

## Next Steps

After successful deployment:

1. **Customize Policies**: Adapt organization policies to your specific compliance requirements
2. **Extend Automation**: Add custom governance rules and automated remediation
3. **Integration**: Integrate with existing ITSM and monitoring systems
4. **Training**: Train teams on the governance portal and exception processes
5. **Compliance**: Configure additional compliance frameworks as needed

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud infrastructure best practices
3. Update documentation for any configuration changes
4. Validate security implications of modifications