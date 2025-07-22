# Infrastructure as Code for Secure Database Modernization Workflows with Cloud Workstations and Database Migration Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Database Modernization Workflows with Cloud Workstations and Database Migration Service".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Workstations Admin
  - Database Migration Admin
  - Secret Manager Admin
  - Cloud Build Editor
  - Artifact Registry Admin
  - Cloud SQL Admin
  - Service Account Admin
- Docker installed (for custom container image builds)
- Terraform >= 1.0 installed (for Terraform deployment)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native IaC solution that provides managed Terraform execution with built-in state management and enterprise features.

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/db-modernization-deployment \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --local-source=infrastructure-manager/ \
    --input-values=project_id=PROJECT_ID,region=REGION

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/db-modernization-deployment

# View deployment outputs
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/db-modernization-deployment \
    --format="value(latestRevision.outputs)"
```

### Using Terraform

Terraform provides declarative infrastructure management with state tracking and dependency resolution.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct gcloud CLI execution with step-by-step deployment and comprehensive error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Workstations**: Secure, managed development environments
- **Database Migration Service**: Managed database migration capabilities
- **Cloud Build**: CI/CD pipeline for migration automation
- **Secret Manager**: Secure credential storage and access
- **Artifact Registry**: Container image repository
- **Cloud SQL**: Target database instance
- **IAM**: Role-based access control and security policies

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment supports these input values:

- `project_id`: Google Cloud project ID
- `region`: Primary deployment region (default: us-central1)
- `zone`: Compute zone for resources (default: us-central1-a)
- `workstation_cluster_name`: Name for the workstation cluster
- `workstation_config_name`: Name for the workstation configuration
- `enable_private_cluster`: Enable private IP for workstations (default: true)
- `workstation_machine_type`: Machine type for workstations (default: e2-standard-4)
- `source_db_host`: Source database hostname
- `source_db_user`: Source database username
- `target_db_instance_name`: Target Cloud SQL instance name

### Terraform Variables

Key variables in `terraform/variables.tf`:

```hcl
# Required variables
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Primary deployment region"
  type        = string
  default     = "us-central1"
}

# Optional variables with defaults
variable "workstation_machine_type" {
  description = "Machine type for Cloud Workstations"
  type        = string
  default     = "e2-standard-4"
}

variable "enable_private_networking" {
  description = "Enable private IP addresses for workstations"
  type        = bool
  default     = true
}
```

### Bash Script Environment Variables

Required environment variables for script deployment:

```bash
export PROJECT_ID="your-project-id"           # Google Cloud project ID
export REGION="us-central1"                   # Primary deployment region
export ZONE="us-central1-a"                   # Compute zone
export WORKSTATION_CLUSTER_NAME="db-migration-cluster"  # Workstation cluster name
export WORKSTATION_CONFIG_NAME="db-migration-config"    # Workstation configuration name
```

## Deployment Workflow

1. **Prerequisites Setup**: Enable APIs and validate permissions
2. **Artifact Registry**: Create container repository for custom images
3. **Secret Manager**: Store database credentials securely
4. **Cloud Workstations**: Deploy cluster and configuration
5. **Database Services**: Set up Database Migration Service profiles
6. **Cloud Build**: Configure CI/CD pipeline
7. **IAM Configuration**: Apply security policies and roles
8. **Validation**: Verify deployment and connectivity

## Security Features

This deployment implements several security best practices:

- **Network Isolation**: Private IP addresses for workstation instances
- **Credential Management**: Centralized secret storage with IAM controls
- **Audit Logging**: Comprehensive logging for compliance
- **Least Privilege**: Role-based access with minimal permissions
- **Container Security**: Custom hardened container images
- **VPC Controls**: Network-level security boundaries

## Monitoring and Observability

The deployment includes:

- **Cloud Logging**: Centralized log collection and analysis
- **Cloud Monitoring**: Performance metrics and alerting
- **Audit Logs**: Security and compliance monitoring
- **Workstation Usage**: Resource utilization tracking

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
2. **Permission Denied**: Verify IAM roles and permissions
3. **Network Connectivity**: Check VPC and firewall configurations
4. **Resource Quotas**: Verify project quotas for compute resources
5. **Container Image**: Ensure custom images are built and pushed

### Debugging Commands

```bash
# Check API status
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy PROJECT_ID

# Check workstation cluster status
gcloud workstations clusters describe CLUSTER_NAME --location=REGION

# View logs
gcloud logging read "resource.type=gce_instance" --limit=50
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/db-modernization-deployment

# Verify deletion
gcloud infra-manager deployments list --location=REGION
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/verify-cleanup.sh
```

## Cost Optimization

### Resource Sizing

- **Workstation Instances**: Use appropriate machine types for workload
- **Persistent Disks**: Right-size storage based on requirements
- **Cloud SQL**: Choose appropriate tier for target database
- **Artifact Registry**: Implement lifecycle policies for image cleanup

### Auto-Stop Policies

Configure workstation idle timeout to reduce costs:

```bash
# Set idle timeout to 30 minutes
gcloud workstations configs update CONFIG_NAME \
    --location=REGION \
    --cluster=CLUSTER_NAME \
    --idle-timeout=1800s
```

## Compliance and Governance

### Regulatory Compliance

- **Data Residency**: Configure resources in appropriate regions
- **Audit Trails**: Enable comprehensive logging
- **Access Controls**: Implement proper IAM policies
- **Encryption**: Enable encryption at rest and in transit

### Best Practices

- Regular security reviews and updates
- Automated compliance monitoring
- Documentation of migration processes
- Regular backup and disaster recovery testing

## Integration with CI/CD

### Cloud Build Integration

The deployment includes Cloud Build configurations for:

- Custom workstation image building
- Migration script validation
- Infrastructure testing
- Security scanning

### Example Pipeline

```yaml
# cloudbuild.yaml
steps:
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        # Deploy infrastructure
        gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$_REGION/deployments/db-modernization-deployment \
          --service-account=$_SERVICE_ACCOUNT \
          --local-source=infrastructure-manager/
        
        # Run validation tests
        ./scripts/validate-deployment.sh

substitutions:
  _REGION: us-central1
  _SERVICE_ACCOUNT: ${PROJECT_NUMBER}-compute@developer.gserviceaccount.com
```

## Support and Documentation

### Additional Resources

- [Cloud Workstations Documentation](https://cloud.google.com/workstations/docs)
- [Database Migration Service Guide](https://cloud.google.com/database-migration/docs)
- [Secret Manager Best Practices](https://cloud.google.com/secret-manager/docs/best-practices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation for specific services
3. Refer to the original recipe documentation
4. Contact your cloud administrator for permission issues

## Version Information

- **Recipe Version**: 1.0
- **Infrastructure Manager**: Compatible with latest Google Cloud APIs
- **Terraform**: Requires version >= 1.0
- **Google Cloud Provider**: Version >= 4.0
- **Generated**: 2025-07-12

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify security configurations before production use.