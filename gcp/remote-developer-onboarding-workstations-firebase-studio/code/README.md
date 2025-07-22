# Infrastructure as Code for Remote Developer Onboarding with Cloud Workstations and Firebase Studio

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Remote Developer Onboarding with Cloud Workstations and Firebase Studio".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Workstations Admin (`roles/workstations.admin`)
  - Source Repository Admin (`roles/source.admin`)
  - Firebase Admin (`roles/firebase.admin`)
  - IAM Admin (`roles/iam.admin`)
  - Service Usage Admin (`roles/serviceusage.serviceUsageAdmin`)
- Terraform installed (version 1.0+ for Terraform implementation)
- Basic understanding of cloud development environments and Git workflows

## Cost Considerations

Estimated monthly costs for 5-10 active workstations:
- Cloud Workstations: $50-100 (based on e2-standard-4 instances with 200GB storage)
- Cloud Source Repositories: $1-5 (based on storage and network usage)
- Firebase services: $0-20 (depending on usage patterns)

> **Note**: Costs can be optimized by configuring auto-shutdown policies and using spot instances where appropriate.

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create developer-onboarding \
    --location=${REGION} \
    --source=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe developer-onboarding \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy example variables file and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the interactive prompts for configuration
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

- `PROJECT_ID`: Google Cloud Project ID (required)
- `REGION`: Google Cloud region for resources (default: us-central1)
- `CLUSTER_NAME`: Name for the workstation cluster (default: developer-workstations)
- `CONFIG_NAME`: Name for the workstation configuration (default: fullstack-dev-{random})
- `REPO_NAME`: Name for the source repository (default: team-templates-{random})

### Terraform Variables

Key Terraform variables (see `variables.tf` for complete list):

```hcl
project_id = "your-project-id"
region = "us-central1"
cluster_name = "developer-workstations"
workstation_machine_type = "e2-standard-4"
workstation_disk_size = 200
idle_timeout_seconds = 7200
enable_audit_agent = true
```

### Infrastructure Manager Parameters

Key Infrastructure Manager parameters (see `main.yaml` for complete list):

```yaml
inputValues:
  project_id: "your-project-id"
  region: "us-central1"
  cluster_name: "developer-workstations"
  machine_type: "e2-standard-4"
  disk_size_gb: 200
  idle_timeout: "7200s"
```

## Post-Deployment Steps

After successful deployment, complete these manual steps:

1. **Configure Cloud Identity Groups** (if using organizational accounts):
   ```bash
   # Create developer group in Cloud Identity Admin Console
   # Add developers to the group
   # Grant group access to workstation resources
   ```

2. **Set up Firebase Studio**:
   ```bash
   # Access Firebase Console
   # Enable required Firebase services
   # Configure project templates in Firebase Studio
   ```

3. **Onboard first developer**:
   ```bash
   # Use the generated onboarding script
   ./scripts/onboard-developer.sh developer@example.com
   ```

4. **Customize development environment**:
   ```bash
   # Clone the team repository
   # Add project templates and team documentation
   # Configure IDE settings and extensions
   ```

## Validation

Verify the deployment was successful:

```bash
# Check workstation cluster status
gcloud beta workstations clusters describe ${CLUSTER_NAME} \
    --region=${REGION}

# Verify workstation configuration
gcloud beta workstations configs describe ${CONFIG_NAME} \
    --cluster=${CLUSTER_NAME} \
    --region=${REGION}

# List enabled APIs
gcloud services list --enabled \
    --filter="name:workstations OR name:firebase OR name:sourcerepo"

# Test source repository access
gcloud source repos list
```

## Monitoring and Management

### Access Workstation Metrics

```bash
# View workstation usage
gcloud beta workstations list \
    --cluster=${CLUSTER_NAME} \
    --config=${CONFIG_NAME} \
    --region=${REGION}

# Check workstation logs
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_name:workstation" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"
```

### Cost Management

```bash
# Check current billing for workstations
gcloud billing budgets list \
    --billing-account=$(gcloud beta billing accounts list --format="value(name)" | head -1)

# View resource usage
gcloud compute instances list --filter="name:workstation"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete developer-onboarding \
    --location=${REGION} \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
# Verify cleanup in Google Cloud Console
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow interactive prompts to confirm resource deletion
# Script will clean up in reverse order of creation
```

### Manual Cleanup Verification

After running automated cleanup, verify these resources are removed:

```bash
# Check for remaining workstation resources
gcloud beta workstations clusters list --region=${REGION}
gcloud beta workstations configs list --cluster=${CLUSTER_NAME} --region=${REGION}

# Verify source repositories are deleted
gcloud source repos list

# Check IAM roles and policies
gcloud iam roles list --project=${PROJECT_ID} --filter="name:workstationDeveloper"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs manually
   gcloud services enable workstations.googleapis.com \
       sourcerepo.googleapis.com \
       firebase.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check current user permissions
   gcloud auth list
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Workstation Cluster Creation Fails**:
   ```bash
   # Check quota limits
   gcloud compute project-info describe --project=${PROJECT_ID}
   
   # Verify network configuration
   gcloud compute networks list
   gcloud compute networks subnets list --filter="region:${REGION}"
   ```

4. **Source Repository Access Issues**:
   ```bash
   # Verify repository exists and permissions
   gcloud source repos describe ${REPO_NAME}
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" \
       --format="table(bindings.role)" --filter="bindings.members:user:YOUR_EMAIL"
   ```

### Getting Help

- Check the [Cloud Workstations documentation](https://cloud.google.com/workstations/docs)
- Review [Firebase Studio documentation](https://firebase.google.com/docs/studio)
- Consult [Cloud Source Repositories documentation](https://cloud.google.com/source-repositories/docs)
- For Terraform issues, see [Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Customization

### Adding Custom Development Tools

Modify the workstation configuration to include additional development tools:

```yaml
# In Infrastructure Manager main.yaml or Terraform main.tf
container:
  image: "custom-image-with-tools:latest"
  env:
    CUSTOM_TOOL_VERSION: "1.0.0"
    TEAM_SPECIFIC_CONFIG: "enabled"
```

### Multi-Region Deployment

Extend the configuration for global teams:

```bash
# Deploy clusters in multiple regions
REGIONS=("us-central1" "europe-west1" "asia-southeast1")
for region in "${REGIONS[@]}"; do
    # Deploy workstation cluster in each region
done
```

### Integration with External Systems

Connect with existing enterprise systems:

```bash
# Example: LDAP integration for user management
# Example: Slack/Teams integration for notifications
# Example: JIRA integration for project tracking
```

## Security Considerations

- All workstations use private endpoints by default
- IAM roles follow least privilege principle
- Audit logging is enabled for all workstation activities
- Network traffic is encrypted in transit
- Persistent disks are encrypted at rest

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Submit issues through your organization's support channels

## Version Information

- Infrastructure Manager: Uses latest Google Cloud resource schemas
- Terraform: Compatible with Google Cloud Provider 4.0+
- Google Cloud SDK: Requires gcloud CLI version 400.0.0+
- Firebase CLI: Requires firebase-tools 11.0.0+

## Contributing

To modify or extend this infrastructure:
1. Test changes in a development environment
2. Validate with `terraform plan` or Infrastructure Manager preview
3. Update documentation to reflect changes
4. Follow your organization's change management process