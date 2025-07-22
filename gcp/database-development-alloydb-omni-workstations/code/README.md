# Infrastructure as Code for Database Development Workflows with AlloyDB Omni and Cloud Workstations

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Development Workflows with AlloyDB Omni and Cloud Workstations".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete database development workflow environment that includes:

- **Cloud Workstations Cluster**: Managed development environments for database developers
- **Custom Workstation Configuration**: Pre-configured development environment with database tools
- **VPC Network Infrastructure**: Secure networking for workstation communication
- **Cloud Source Repositories**: Git repository for database development projects
- **Cloud Build Integration**: Automated CI/CD pipeline for database testing
- **AlloyDB Omni Configuration**: Containerized PostgreSQL-compatible database for development

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Terraform v1.0+ (for Terraform implementation)
- Docker and Docker Compose (for AlloyDB Omni development)
- Appropriate Google Cloud permissions for:
  - Compute Engine (workstations.admin, compute.admin)
  - Cloud Source Repositories (source.admin)
  - Cloud Build (cloudbuild.editor)
  - Artifact Registry (artifactregistry.admin)
  - Monitoring and Logging (monitoring.editor, logging.admin)
- Estimated cost: $50-75 per month for development resources

## Quick Start

### Using Infrastructure Manager (Recommended for Google Cloud)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/db-dev-workstations \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Navigate to Terraform configuration
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

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `workstation_machine_type`: Machine type for workstations (default: e2-standard-4)
- `persistent_disk_size_gb`: Size of persistent disk for workstations (default: 200)
- `cluster_labels`: Labels for the workstation cluster
- `enable_monitoring`: Enable monitoring and logging (default: true)

### Terraform Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `workstation_machine_type`: Machine type for workstations (default: e2-standard-4)
- `boot_disk_size_gb`: Boot disk size for workstations (default: 100)
- `persistent_disk_size_gb`: Persistent disk size for workstations (default: 200)
- `network_name`: Custom VPC network name (default: db-dev-network)
- `subnet_name`: Custom subnet name (default: db-dev-subnet)
- `subnet_cidr`: CIDR range for subnet (default: 10.0.0.0/24)

## Deployment Details

### Resources Created

1. **Networking Infrastructure**:
   - VPC network (`db-dev-network`)
   - Subnet with private IP range (`db-dev-subnet`)
   - Firewall rules for internal communication

2. **Cloud Workstations**:
   - Workstations cluster for hosting development environments
   - Custom workstation configuration with database development tools
   - Individual workstation instance for development

3. **Source Control and CI/CD**:
   - Cloud Source Repository for database projects
   - Cloud Build trigger for automated testing
   - Build configuration for AlloyDB Omni testing

4. **IAM and Security**:
   - Service accounts for workstations and build processes
   - Appropriate IAM bindings for resource access
   - Network security rules for development environment

### Post-Deployment Setup

After infrastructure deployment, follow these steps:

1. **Access Your Workstation**:
   ```bash
   # List available workstations
   gcloud workstations list --region=${REGION}
   
   # Start and access your workstation
   gcloud workstations start WORKSTATION_NAME --region=${REGION}
   ```

2. **Set Up AlloyDB Omni Development Environment**:
   ```bash
   # Clone the source repository in your workstation
   git clone SOURCE_REPOSITORY_URL
   
   # Navigate to AlloyDB configuration
   cd alloydb-config/
   
   # Start AlloyDB Omni container
   ./setup-dev-db.sh
   ```

3. **Verify Database Connection**:
   ```bash
   # Test connection to AlloyDB Omni
   docker exec alloydb-dev psql -U dev_user -d development_db -c "SELECT version();"
   ```

## Development Workflow

### Making Database Changes

1. **Create Feature Branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Create Migration**:
   ```bash
   cp templates/migrations/migration_template.sql migrations/$(date +%Y%m%d)_your_migration.sql
   ```

3. **Test Locally**:
   ```bash
   # Test against AlloyDB Omni
   PGPASSWORD=dev_password_123 psql -h localhost -U dev_user -d development_db -f migrations/your_migration.sql
   ```

4. **Commit and Push**:
   ```bash
   git add .
   git commit -m "Add: your migration description"
   git push origin feature/your-feature-name
   ```

The automated CI/CD pipeline will run tests when changes are pushed to the main branch.

## Monitoring and Observability

### Accessing Logs

```bash
# View workstation logs
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_name:workstation"

# View build logs
gcloud builds log BUILD_ID
```

### Monitoring Workstation Usage

```bash
# Check workstation status
gcloud workstations describe WORKSTATION_NAME --region=${REGION}

# View workstation metrics in Cloud Console
echo "Navigate to Cloud Monitoring > Dashboards > Workstations"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/db-dev-workstations
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

After running automated cleanup, verify these resources are removed:

```bash
# Check for remaining workstations
gcloud workstations list --region=${REGION}

# Check for VPC networks
gcloud compute networks list --filter="name:db-dev*"

# Check for source repositories
gcloud source repos list --filter="name:database-development*"

# Check for build triggers
gcloud builds triggers list
```

## Troubleshooting

### Common Issues

1. **Workstation Creation Fails**:
   - Verify compute quotas in your project
   - Check IAM permissions for Workstations API
   - Ensure the specified region supports Cloud Workstations

2. **AlloyDB Omni Container Won't Start**:
   - Verify Docker is installed in the workstation
   - Check port availability (5432)
   - Review container logs: `docker logs alloydb-dev`

3. **Build Triggers Not Working**:
   - Verify Cloud Build API is enabled
   - Check service account permissions
   - Review build trigger configuration

4. **Network Connectivity Issues**:
   - Verify firewall rules allow internal communication
   - Check subnet CIDR range doesn't conflict
   - Ensure VPC network is properly configured

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:workstations.googleapis.com OR name:compute.googleapis.com OR name:sourcerepo.googleapis.com"

# Verify quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.usage,quotas.limit)"

# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}
```

## Customization

### Workstation Configuration

To customize the workstation environment, modify the workstation configuration in the IaC templates:

- Change machine type for different performance requirements
- Adjust persistent disk size for storage needs
- Modify the container image for different development tools
- Add environment variables for specific development workflows

### Network Configuration

To integrate with existing networks:

- Modify VPC network settings in the templates
- Adjust subnet CIDR ranges to avoid conflicts
- Update firewall rules for additional security requirements
- Configure VPC peering if needed for external resources

### AlloyDB Omni Configuration

To customize the database environment:

- Modify Docker Compose configuration for different PostgreSQL settings
- Add additional PostgreSQL extensions in initialization scripts
- Configure different authentication methods
- Adjust memory and CPU allocation for the container

## Security Considerations

### Best Practices Implemented

- **Network Isolation**: Workstations operate in a dedicated VPC with controlled access
- **IAM Least Privilege**: Service accounts have minimal required permissions
- **Encryption**: All persistent disks are encrypted by default
- **Audit Logging**: All administrative actions are logged for compliance
- **Container Security**: AlloyDB Omni runs with security best practices

### Additional Security Recommendations

1. **Enable VPC Flow Logs** for network monitoring
2. **Implement Cloud Asset Inventory** for resource tracking
3. **Configure Security Command Center** for threat detection
4. **Set up Cloud KMS** for additional encryption key management
5. **Enable Binary Authorization** for container image security

## Performance Optimization

### Workstation Performance

- Use higher-performance machine types (e2-highmem or e2-highcpu) for demanding workloads
- Consider SSD persistent disks for better I/O performance
- Adjust workstation resource allocation based on team usage patterns

### AlloyDB Omni Optimization

- Configure appropriate memory allocation for PostgreSQL
- Use AlloyDB's columnar engine for analytical workloads
- Implement connection pooling for multi-user environments
- Monitor query performance and optimize based on usage patterns

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for detailed implementation guidance
2. **Google Cloud Documentation**: 
   - [Cloud Workstations Documentation](https://cloud.google.com/workstations/docs)
   - [AlloyDB Omni Documentation](https://cloud.google.com/alloydb/omni/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. **Community Support**: Google Cloud Community forums and Stack Overflow
4. **Professional Support**: Google Cloud Support for production deployments

## Version Information

- **Infrastructure Manager**: Uses latest Google Cloud resource schemas
- **Terraform**: Compatible with Google Cloud Provider v5.0+
- **AlloyDB Omni**: Uses latest stable container image
- **Cloud Workstations**: Uses predefined Code-OSS image with development tools

## License

This infrastructure code is provided as-is for educational and development purposes. Refer to Google Cloud's terms of service for usage in production environments.