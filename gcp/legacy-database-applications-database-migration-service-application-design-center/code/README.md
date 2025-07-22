# Infrastructure as Code for Legacy Database Applications with Database Migration Service and Application Design Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Legacy Database Applications with Database Migration Service and Application Design Center".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Database Migration Service (roles/datamigration.admin)
  - Cloud SQL (roles/cloudsql.admin)
  - Application Design Center (roles/applicationdesigncenter.admin)
  - Compute Engine (roles/compute.admin)
  - Service Networking (roles/servicenetworking.networksAdmin)
- Access to source SQL Server database for migration
- Estimated cost: $50-150 for Cloud SQL instance and migration resources during testing

> **Note**: This recipe requires access to a source SQL Server database. Ensure you have the necessary credentials and network connectivity configured before deployment.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended native IaC solution that provides Git-based workflow integration and Google Cloud Console visualization.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Create Infrastructure Manager deployment
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/legacy-modernization \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --local-source="." \
    --inputs-file=terraform.tfvars.example

# Monitor deployment progress
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/legacy-modernization
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive provider ecosystem for complex infrastructure deployments.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

Bash scripts provide step-by-step deployment with detailed progress tracking and error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export SQLSERVER_HOST="your-sqlserver-host"
export SQLSERVER_USERNAME="migration_user"
export SQLSERVER_PASSWORD="your-password"

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
./scripts/monitor.sh
```

## Configuration

### Required Variables

The following variables must be configured for all deployment methods:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | Yes |
| `zone` | Deployment zone | `us-central1-a` | No |
| `sqlserver_host` | Source SQL Server host | - | Yes |
| `sqlserver_port` | Source SQL Server port | `1433` | No |
| `sqlserver_username` | Migration user | - | Yes |
| `sqlserver_password` | Migration password | - | Yes |
| `cloud_sql_tier` | Cloud SQL machine type | `db-standard-2` | No |
| `storage_size_gb` | Initial storage size | `100` | No |

### Infrastructure Manager Configuration

Create a `terraform.tfvars.example` file:

```hcl
project_id = "your-project-id"
region = "us-central1"
sqlserver_host = "10.0.0.100"
sqlserver_username = "migration_user"
sqlserver_password = "your-secure-password"
cloud_sql_tier = "db-standard-2"
storage_size_gb = 100
```

### Terraform Configuration

The Terraform implementation includes:

- **Provider Configuration**: Google Cloud provider with required APIs
- **Resource Dependencies**: Proper ordering of resource creation
- **Security Best Practices**: IAM roles, VPC configuration, SSL settings
- **Monitoring Integration**: Cloud Logging and Monitoring setup
- **Output Values**: Connection details and resource identifiers

### Security Considerations

- SQL Server credentials are managed securely using Google Secret Manager
- Cloud SQL instances are configured with private IP and authorized networks
- IAM roles follow the principle of least privilege
- All data transfer is encrypted in transit and at rest
- Network security groups restrict access to required ports only

## Deployment Process

### Phase 1: Infrastructure Provisioning

1. **API Enablement**: Activates required Google Cloud APIs
2. **Network Setup**: Configures VPC, subnets, and firewall rules
3. **Cloud SQL Creation**: Provisions PostgreSQL instance with optimal configuration
4. **Service Accounts**: Creates dedicated service accounts with minimal permissions

### Phase 2: Migration Configuration

1. **Connection Profiles**: Sets up secure connections to source and destination databases
2. **Migration Job**: Creates Database Migration Service job with continuous replication
3. **Monitoring Setup**: Configures logging and alerting for migration progress

### Phase 3: Application Modernization

1. **Application Design Center**: Initializes workspace for architecture analysis
2. **Gemini Code Assist**: Configures AI-powered code modernization tools
3. **Source Repository**: Sets up Git repository for tracking modernized code

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Check migration job status
gcloud datamigration migration-jobs describe \
    $(terraform output -raw migration_job_name) \
    --region=$(terraform output -raw region)

# Verify Cloud SQL connectivity
gcloud sql connect $(terraform output -raw cloud_sql_instance_name) \
    --user=migration-user

# Test Application Design Center workspace
gcloud alpha application-design-center workspaces describe \
    $(terraform output -raw workspace_name) \
    --region=$(terraform output -raw region)
```

## Monitoring and Troubleshooting

### Migration Monitoring

Monitor migration progress using these commands:

```bash
# Check migration job logs
gcloud logging read "resource.type=gce_instance AND \
    logName=projects/$(terraform output -raw project_id)/logs/datamigration" \
    --limit=50

# Monitor Cloud SQL performance
gcloud monitoring metrics list \
    --filter="resource.type=cloudsql_database"

# Check Application Design Center activity
gcloud alpha application-design-center projects list \
    --workspace=$(terraform output -raw workspace_name) \
    --region=$(terraform output -raw region)
```

### Common Issues

1. **Migration Job Stuck**: Check source database connectivity and permissions
2. **Schema Conversion Errors**: Review Database Migration Service logs for specific issues
3. **Network Connectivity**: Verify VPC peering and firewall configurations
4. **Application Design Center Access**: Ensure proper API enablement and IAM permissions

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/legacy-modernization

# Verify resource cleanup
gcloud infra-manager deployments list \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are removed
./scripts/verify-cleanup.sh
```

## Customization

### Scaling Configuration

Modify these variables for different environment sizes:

```hcl
# Development environment
cloud_sql_tier = "db-f1-micro"
storage_size_gb = 20
backup_enabled = false

# Production environment
cloud_sql_tier = "db-standard-4"
storage_size_gb = 500
backup_enabled = true
high_availability = true
```

### Network Configuration

Customize network settings for enterprise environments:

```hcl
# Custom VPC configuration
vpc_name = "legacy-modernization-vpc"
subnet_cidr = "10.1.0.0/16"
authorized_networks = ["10.0.0.0/8", "192.168.0.0/16"]

# Private Service Connection
enable_private_ip = true
allocated_ip_range = "google-managed-services-subnet"
```

### Security Hardening

Enhance security for production deployments:

```hcl
# Enhanced security settings
require_ssl = true
deletion_protection = true
backup_retention_days = 30
maintenance_window_day = 7
maintenance_window_hour = 3
```

## Cost Optimization

### Resource Sizing Recommendations

| Environment | Cloud SQL Tier | Storage | Estimated Monthly Cost |
|-------------|---------------|---------|----------------------|
| Development | db-f1-micro | 20GB | $15-25 |
| Staging | db-standard-1 | 100GB | $75-100 |
| Production | db-standard-2+ | 500GB+ | $200-400+ |

### Cost Control Features

- **Automatic Storage Increase**: Prevents storage full errors
- **Maintenance Windows**: Scheduled during low-usage periods
- **Backup Optimization**: Configurable retention policies
- **Regional Placement**: Choose regions based on compliance and cost

## Advanced Features

### High Availability Setup

```hcl
# Regional persistent disk and failover replica
availability_type = "REGIONAL"
backup_configuration {
  enabled = true
  start_time = "02:00"
  point_in_time_recovery_enabled = true
}
```

### Performance Optimization

```hcl
# Performance insights and query optimization
insights_config {
  query_insights_enabled = true
  record_application_tags = true
  record_client_address = true
}
```

### Integration with Other Services

- **Cloud Monitoring**: Automated alerting and dashboards
- **Cloud Logging**: Centralized log aggregation and analysis
- **Cloud IAM**: Role-based access control for database resources
- **Cloud KMS**: Customer-managed encryption keys (CMEK)

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for solution overview
2. **Google Cloud Documentation**: Consult official Google Cloud service documentation
3. **Terraform Google Provider**: Check the official Terraform Google Cloud provider documentation
4. **Database Migration Service**: Review Google Cloud Database Migration Service troubleshooting guides
5. **Community Support**: Engage with Google Cloud community forums for specific technical issues

## Additional Resources

- [Google Cloud Database Migration Service Documentation](https://cloud.google.com/database-migration/docs)
- [Cloud SQL for PostgreSQL Documentation](https://cloud.google.com/sql/docs/postgres)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Application Design Center Documentation](https://cloud.google.com/application-design-center/docs)