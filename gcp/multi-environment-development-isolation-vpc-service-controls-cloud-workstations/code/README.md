# Infrastructure as Code for Establishing Multi-Environment Development Isolation with VPC Service Controls and Cloud Workstations

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Establishing Multi-Environment Development Isolation with VPC Service Controls and Cloud Workstations".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure creates secure, isolated development environments using:

- **VPC Service Controls**: Security perimeters preventing data exfiltration
- **Cloud Workstations**: Managed development environments with consistent configurations
- **Cloud Filestore**: Shared storage for team collaboration
- **Identity-Aware Proxy**: Secure access controls without VPN requirements
- **Cloud Source Repositories**: Version control within security perimeters

## Prerequisites

### General Requirements
- Google Cloud Organization Admin permissions
- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Billing account configured and linked
- Basic understanding of Google Cloud IAM, VPC networks, and security concepts

### Cost Considerations
- Estimated monthly cost: $50-100 depending on workstation usage and storage requirements
- VPC Service Controls requires Google Cloud Organization (no additional cost)
- Cloud Workstations billing based on usage time and machine type
- Cloud Filestore charges for provisioned storage capacity

### Required APIs
The following APIs will be automatically enabled during deployment:
- Compute Engine API
- Cloud Workstations API
- Cloud Filestore API
- Identity-Aware Proxy API
- Access Context Manager API
- Cloud Source Repositories API

## Environment Setup

Before deploying, set the required environment variables:

```bash
# Set your organization and billing details
export ORGANIZATION_ID="your-org-id"
export BILLING_ACCOUNT_ID="your-billing-account-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique project identifiers
RANDOM_SUFFIX=$(openssl rand -hex 3)
export DEV_PROJECT_ID="secure-dev-environments-dev-${RANDOM_SUFFIX}"
export TEST_PROJECT_ID="secure-dev-environments-test-${RANDOM_SUFFIX}"
export PROD_PROJECT_ID="secure-dev-environments-prod-${RANDOM_SUFFIX}"
```

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that provides GitOps-style deployments with built-in state management.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create a Cloud Storage bucket for Infrastructure Manager state
gsutil mb gs://infrastructure-manager-state-${RANDOM_SUFFIX}

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${DEV_PROJECT_ID}/locations/${REGION}/deployments/dev-environment \
    --service-account=projects/${DEV_PROJECT_ID}/serviceAccounts/infra-manager@${DEV_PROJECT_ID}.iam.gserviceaccount.com \
    --gcs-source=gs://infrastructure-manager-state-${RANDOM_SUFFIX}/main.yaml \
    --input-values=organization_id=${ORGANIZATION_ID},billing_account_id=${BILLING_ACCOUNT_ID}

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${DEV_PROJECT_ID}/locations/${REGION}/deployments/dev-environment
```

### Using Terraform

Terraform provides a mature, multi-cloud infrastructure as code solution with excellent Google Cloud provider support.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="organization_id=${ORGANIZATION_ID}" \
    -var="billing_account_id=${BILLING_ACCOUNT_ID}" \
    -var="region=${REGION}" \
    -var="zone=${ZONE}"

# Apply the infrastructure
terraform apply \
    -var="organization_id=${ORGANIZATION_ID}" \
    -var="billing_account_id=${BILLING_ACCOUNT_ID}" \
    -var="region=${REGION}" \
    -var="zone=${ZONE}"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct control over the deployment process using Google Cloud CLI commands.

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables (if not already set)
export ORGANIZATION_ID="your-org-id"
export BILLING_ACCOUNT_ID="your-billing-account-id"

# Deploy the infrastructure
./deploy.sh

# Follow the script output for deployment progress
```

## Deployment Details

### Infrastructure Manager Implementation

The Infrastructure Manager implementation (`infrastructure-manager/main.yaml`) includes:

- **Project Creation**: Separate projects for dev, test, and production environments
- **VPC Networks**: Isolated networks with private Google access enabled
- **Access Context Manager**: Centralized access policy management
- **VPC Service Controls**: Security perimeters for each environment
- **Cloud Filestore**: High-performance NFS storage for each environment
- **Cloud Workstations**: Managed development environments with custom configurations
- **Identity-Aware Proxy**: Secure access controls

### Terraform Implementation

The Terraform implementation includes:

- **main.tf**: Core infrastructure resources and configurations
- **variables.tf**: Customizable input parameters
- **outputs.tf**: Important values for verification and integration
- **versions.tf**: Provider version constraints and backend configuration

Key Terraform features:
- Uses official Google Cloud provider
- Implements proper resource dependencies
- Includes comprehensive variable validation
- Provides detailed outputs for verification

### Bash Scripts Implementation

The bash scripts provide:

- **deploy.sh**: Complete deployment automation with progress indicators
- **destroy.sh**: Safe cleanup with confirmation prompts
- Error handling and validation at each step
- Support for environment variable configuration
- Detailed logging and status messages

## Validation and Testing

After deployment, verify the infrastructure:

### Check VPC Service Controls
```bash
# List service perimeters
gcloud access-context-manager perimeters list \
    --policy=${POLICY_ID} \
    --format="table(name,title,perimeterType)"

# Verify perimeter configuration
gcloud access-context-manager perimeters describe dev-perimeter \
    --policy=${POLICY_ID}
```

### Verify Cloud Workstations
```bash
# Check workstation status
gcloud workstations list \
    --location=${REGION} \
    --cluster=dev-cluster \
    --project=${DEV_PROJECT_ID}

# Test SSH access
gcloud workstations ssh dev-workstation-1 \
    --location=${REGION} \
    --cluster=dev-cluster \
    --config=dev-workstation-config \
    --project=${DEV_PROJECT_ID}
```

### Test Environment Isolation
```bash
# Verify VPC Service Controls prevent cross-environment access
# This command should fail with access denied
gcloud workstations ssh dev-workstation-1 \
    --location=${REGION} \
    --cluster=dev-cluster \
    --config=dev-workstation-config \
    --project=${DEV_PROJECT_ID} \
    --command="gcloud storage ls gs://test-bucket-${TEST_PROJECT_ID}"
```

## Customization

### Infrastructure Manager Customization

Modify `infrastructure-manager/main.yaml` to customize:
- Machine types for Cloud Workstations
- Filestore capacity and performance tier
- VPC network IP ranges
- Access level conditions

### Terraform Customization

Use `terraform/variables.tf` to customize:
- `workstation_machine_type`: Change workstation compute resources
- `filestore_capacity_gb`: Adjust storage capacity
- `enable_private_endpoint`: Control private endpoint usage
- `allowed_users`: Define authorized users for access levels

Example customization:
```bash
terraform apply \
    -var="workstation_machine_type=e2-standard-8" \
    -var="filestore_capacity_gb=2048" \
    -var="allowed_users=[\"user1@example.com\",\"user2@example.com\"]"
```

### Bash Scripts Customization

Edit environment variables in `scripts/deploy.sh`:
```bash
# Customize workstation configuration
WORKSTATION_MACHINE_TYPE="e2-standard-8"
FILESTORE_TIER="BASIC_SSD"
FILESTORE_CAPACITY="2TB"

# Customize network configuration
DEV_SUBNET_RANGE="10.1.0.0/24"
TEST_SUBNET_RANGE="10.2.0.0/24"
PROD_SUBNET_RANGE="10.3.0.0/24"
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${DEV_PROJECT_ID}/locations/${REGION}/deployments/dev-environment

# Clean up state bucket
gsutil rm -r gs://infrastructure-manager-state-${RANDOM_SUFFIX}
```

### Using Terraform
```bash
cd terraform/
terraform destroy \
    -var="organization_id=${ORGANIZATION_ID}" \
    -var="billing_account_id=${BILLING_ACCOUNT_ID}"
```

### Using Bash Scripts
```bash
cd scripts/
./destroy.sh
```

**Warning**: The cleanup process will permanently delete all created resources including projects, data, and configurations. Ensure you have backed up any important data before proceeding.

## Security Considerations

### VPC Service Controls
- Data exfiltration protection prevents unauthorized data movement
- Access levels enforce user and device-based access controls
- Service perimeters create network-based security boundaries

### Identity-Aware Proxy
- Provides zero-trust access to Cloud Workstations
- Eliminates need for traditional VPN connections
- Integrates with Google Cloud Identity for user management

### Network Security
- Private Google Access enables secure communication without external IPs
- Separate VPC networks provide network-level isolation
- Firewall rules follow least privilege principle

### Best Practices Implemented
- Separate projects for complete resource isolation
- Least privilege IAM roles and permissions
- Encryption at rest and in transit by default
- Regular access reviews through Access Context Manager

## Troubleshooting

### Common Issues

1. **Organization Requirements**
   - VPC Service Controls requires a Google Cloud Organization
   - Ensure you have Organization Admin permissions

2. **Project Creation Failures**
   - Verify billing account is active and linked
   - Check project quota limits in your organization

3. **Workstation Connection Issues**
   - Ensure Identity-Aware Proxy is properly configured
   - Verify user has appropriate IAM roles

4. **Filestore Mount Failures**
   - Check network connectivity between workstation and Filestore
   - Verify NFS client is installed in workstation image

### Support Resources

- [VPC Service Controls Documentation](https://cloud.google.com/vpc-service-controls/docs/overview)
- [Cloud Workstations Security Best Practices](https://cloud.google.com/workstations/docs/security-best-practices)
- [Identity-Aware Proxy Overview](https://cloud.google.com/iap/docs/concepts-overview)
- [Google Cloud Support](https://cloud.google.com/support)

## Next Steps

After successful deployment, consider implementing these enhancements:

1. **Automated Workstation Provisioning**: Use Cloud Build to create environment-specific workstations
2. **Data Loss Prevention**: Implement DLP scanning for sensitive data protection
3. **Compliance Reporting**: Set up automated compliance monitoring and reporting
4. **Cross-Environment Pipelines**: Create controlled deployment workflows between environments
5. **Advanced Threat Detection**: Integrate with Security Command Center for enhanced monitoring

## Support

For issues with this infrastructure code, refer to:
- The original recipe documentation
- Google Cloud provider documentation
- Infrastructure Manager/Terraform documentation
- Google Cloud Support channels

This infrastructure implements enterprise-grade security controls for multi-environment development workflows. Regular security reviews and access audits are recommended to maintain the security posture of your development environments.