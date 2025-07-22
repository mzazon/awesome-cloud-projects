# Remote Developer Onboarding with Cloud Workstations and Firebase Studio

This Terraform configuration deploys a comprehensive remote developer onboarding solution using Google Cloud Workstations and Firebase Studio integration.

## Architecture Overview

This solution creates:

- **Cloud Workstations Cluster**: Secure, managed development environments
- **Workstation Configuration**: Pre-configured development environment with tools
- **Cloud Source Repository**: Team templates and shared code repository
- **Firebase Integration**: Firebase Studio for rapid application development
- **IAM & Security**: Custom roles and least-privilege access controls
- **Monitoring & Alerting**: Usage monitoring and cost management
- **Budget Controls**: Automated cost management and alerts

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: A GCP project with billing enabled
2. **Google Cloud CLI**: Latest version installed and authenticated
3. **Terraform**: Version 1.5 or later installed
4. **Required Permissions**: Project owner or equivalent permissions
5. **APIs**: Required APIs will be automatically enabled during deployment

### Required Permissions

Your account needs the following IAM roles:

- `roles/owner` (recommended) or
- `roles/editor` + `roles/resourcemanager.projectIamAdmin` + `roles/billing.admin`

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your configuration
nano terraform.tfvars
```

### 2. Essential Configuration

Edit `terraform.tfvars` and set these required values:

```hcl
# Required: Your GCP project ID
project_id = "your-gcp-project-id"

# Required: Developer and admin email addresses
developer_users = [
  "developer1@yourcompany.com",
  "developer2@yourcompany.com"
]

admin_users = [
  "admin@yourcompany.com"
]

# Optional: Customize other settings
region = "us-central1"
machine_type = "e2-standard-4"
budget_amount = 1000
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

The deployment typically takes 15-20 minutes to complete.

### 4. Access Your Environment

After deployment, access your resources:

```bash
# View deployment outputs
terraform output

# Access Cloud Workstations Console
terraform output -raw quick_access_urls | jq -r '.workstations_console'

# Get workstation creation commands for users
terraform output workstation_creation_commands
```

## Configuration Options

### Machine Types

Choose the appropriate machine type based on your development needs:

```hcl
# Cost-optimized for basic development
machine_type = "e2-standard-2"

# Balanced performance (recommended)
machine_type = "e2-standard-4"

# High-performance for intensive workloads
machine_type = "c2-standard-8"
```

### Container Images

Select from pre-configured development environments:

```hcl
# VS Code (default)
workstation_container_image = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"

# IntelliJ IDEA Ultimate
workstation_container_image = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/intellij-ultimate:latest"

# PyCharm Professional
workstation_container_image = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/pycharm-professional:latest"
```

### Environment Configurations

Customize for different environments:

#### Development Environment
```hcl
environment = "development"
machine_type = "e2-standard-2"
persistent_disk_size_gb = 100
budget_amount = 500
enable_private_endpoint = false
```

#### Production Environment
```hcl
environment = "production"
machine_type = "e2-standard-8"
persistent_disk_size_gb = 500
budget_amount = 5000
enable_private_endpoint = true
```

## Post-Deployment Setup

### 1. Create Workstation Instances

After infrastructure deployment, create workstations for your users:

```bash
# For each developer, create a workstation
gcloud beta workstations create developer1-workstation \
    --cluster=CLUSTER_ID \
    --config=CONFIG_ID \
    --region=us-central1

# Grant user access to their workstation
gcloud beta workstations add-iam-policy-binding developer1-workstation \
    --cluster=CLUSTER_ID \
    --config=CONFIG_ID \
    --region=us-central1 \
    --member='user:developer1@yourcompany.com' \
    --role='roles/workstations.user'
```

Use the output `workstation_creation_commands` for ready-to-run commands.

### 2. Set Up Team Templates Repository

```bash
# Clone the team templates repository
gcloud source repos clone REPO_NAME

# Add initial templates and documentation
cd REPO_NAME/
mkdir -p templates/{web-app,mobile-app,api-service}
mkdir -p docs/{onboarding,best-practices}

# Commit and push
git add .
git commit -m "Initial team development resources"
git push origin main
```

### 3. Configure Firebase Studio

1. Access Firebase Console: `terraform output -raw quick_access_urls | jq -r '.firebase_console'`
2. Set up Firebase Studio projects and templates
3. Configure authentication and project settings

## Monitoring and Cost Management

### View Usage Dashboard

Access the monitoring dashboard:

```bash
# Get dashboard URL
terraform output -raw quick_access_urls | jq -r '.monitoring_console'
```

### Budget Alerts

The deployment automatically sets up:

- Budget monitoring with configurable thresholds
- Email alerts to admin users
- Cost breakdown by service and labels

### Workstation Usage Monitoring

Monitor workstation usage with:

```bash
# View workstation logs
gcloud logging read 'resource.type="workstations.googleapis.com/Workstation"' --limit=20

# List active workstations
gcloud beta workstations list \
    --cluster=CLUSTER_ID \
    --config=CONFIG_ID \
    --region=us-central1
```

## Maintenance and Operations

### Scaling Operations

```bash
# Add new developer
# 1. Add to terraform.tfvars developer_users list
# 2. Apply changes
terraform apply

# Update workstation configuration
# 1. Modify variables in terraform.tfvars
# 2. Apply changes
terraform apply
```

### Backup and Disaster Recovery

The solution includes:

- Persistent disk storage for user data
- Source repository backup via Git
- Infrastructure as Code for rapid rebuilding

### Cost Optimization

Optimize costs by:

1. **Adjusting idle timeouts**: Reduce `idle_timeout_seconds` for automatic shutdown
2. **Right-sizing machines**: Use appropriate `machine_type` for workloads
3. **Monitoring usage**: Review dashboard for underutilized resources
4. **Scheduled cleanup**: Automated cleanup of idle workstations

## Troubleshooting

### Common Issues

#### API Not Enabled Error
```bash
# Check API status
gcloud services list --enabled --filter='name:workstations'

# Enable manually if needed
gcloud services enable workstations.googleapis.com
```

#### Permission Denied Error
```bash
# Check your permissions
gcloud projects get-iam-policy PROJECT_ID \
    --flatten='bindings[].members' \
    --filter='bindings.members:user:YOUR_EMAIL'
```

#### Workstation Creation Fails
```bash
# Check cluster status
gcloud beta workstations clusters describe CLUSTER_ID --region=REGION

# Check configuration
gcloud beta workstations configs describe CONFIG_ID \
    --cluster=CLUSTER_ID --region=REGION
```

### Getting Help

Use the troubleshooting commands provided in outputs:

```bash
# View troubleshooting information
terraform output troubleshooting_info
```

## Security Considerations

This deployment implements security best practices:

- **Private Endpoints**: Workstations accessible only within VPC
- **Custom IAM Roles**: Least-privilege access controls
- **Service Account**: Dedicated service account with minimal permissions
- **Audit Logging**: Comprehensive audit trail for all operations
- **Network Isolation**: Private networking with controlled access

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm the destruction
# Type 'yes' when prompted
```

⚠️ **Warning**: This will permanently delete all workstations, data, and configurations.

## Support

For issues with this Terraform configuration:

1. Check the [troubleshooting section](#troubleshooting)
2. Review Terraform and Google Cloud documentation
3. Check the original recipe documentation
4. Ensure all prerequisites are met

## Contributing

To contribute improvements to this configuration:

1. Test changes in a development environment
2. Update documentation as needed
3. Follow Terraform best practices
4. Include appropriate variable validation

## License

This configuration is provided under the same license as the parent recipe collection.