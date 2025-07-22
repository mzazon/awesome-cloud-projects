# Infrastructure as Code for Multi-Database Migration Workflows with Database Migration Service and Dynamic Workload Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Database Migration Workflows with Database Migration Service and Dynamic Workload Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Compute Engine (instance templates, managed instance groups, future reservations)
  - Cloud SQL (instance creation and management)
  - AlloyDB (cluster and instance creation)
  - Database Migration Service (connection profiles, migration jobs)
  - Cloud Functions (deployment and management)
  - VPC and networking (network creation, subnet management)
  - Cloud Storage (bucket creation and management)
  - Cloud Monitoring and Logging (dashboard and alert configuration)
- Source databases accessible from Google Cloud (VPN, interconnect, or public internet)
- Basic understanding of database migration concepts and Google Cloud networking

## Estimated Costs

The infrastructure deployed by this recipe will incur costs of approximately $200-500 for a 2-hour workshop, varying based on:
- Database sizes and migration duration
- Number of migration worker instances
- Compute resources allocated through Dynamic Workload Scheduler
- Network egress charges for data transfer
- Cloud SQL and AlloyDB instance hours

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses standard Terraform configuration.

```bash
# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Set environment variables
export PROJECT_ID="your-migration-project-id"
export REGION="us-central1"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create multi-db-migration \
    --location=${REGION} \
    --source-blueprint=. \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe multi-db-migration \
    --location=${REGION}
```

### Using Terraform

Terraform provides infrastructure as code with state management and dependency resolution.

```bash
# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide step-by-step deployment following the recipe instructions.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-migration-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and verification commands
```

## Configuration Options

### Infrastructure Manager Variables

Configure the deployment by modifying the input values:

```bash
# Create deployment with custom configuration
gcloud infra-manager deployments create multi-db-migration \
    --location=${REGION} \
    --source-blueprint=. \
    --input-values=project_id=${PROJECT_ID},region=${REGION},zone=${ZONE},instance_machine_type=e2-standard-8,cloudsql_tier=db-n1-standard-8
```

### Terraform Variables

Customize your deployment by editing `terraform.tfvars`:

```hcl
# Project and region configuration
project_id = "your-migration-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Network configuration
network_name    = "migration-network"
subnet_cidr     = "10.0.0.0/24"

# Migration worker configuration
instance_machine_type = "e2-standard-4"
max_worker_instances  = 8
min_worker_instances  = 0

# Database configuration
cloudsql_tier        = "db-n1-standard-4"
cloudsql_storage_gb  = 100
alloydb_cpu_count    = 4
alloydb_memory_gb    = 16

# Source database connection details
source_mysql_host     = "203.0.113.1"
source_mysql_port     = 3306
source_postgres_host  = "203.0.113.2"
source_postgres_port  = 5432

# Migration configuration
enable_binary_logging = true
backup_start_time    = "03:00"
```

### Bash Script Environment Variables

Configure the deployment by setting environment variables before running scripts:

```bash
# Required variables
export PROJECT_ID="your-migration-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization variables
export NETWORK_NAME="migration-network"
export INSTANCE_MACHINE_TYPE="e2-standard-4"
export CLOUDSQL_TIER="db-n1-standard-4"
export ALLOYDB_CPU_COUNT="4"
export ALLOYDB_MEMORY_GB="16"

# Source database configuration
export SOURCE_MYSQL_HOST="203.0.113.1"
export SOURCE_MYSQL_PORT="3306"
export SOURCE_POSTGRES_HOST="203.0.113.2"
export SOURCE_POSTGRES_PORT="5432"
export MIGRATION_USER_PASSWORD="SecureSourcePass123!"
```

## Deployment Architecture

The infrastructure deploys the following components:

### Networking
- VPC network with regional subnet
- Firewall rules for database access
- Private Google Access for secure communication

### Compute Resources
- Instance template for migration workers
- Managed instance group with autoscaling
- Dynamic Workload Scheduler future reservations

### Database Services
- Cloud SQL MySQL instance with high availability
- AlloyDB PostgreSQL cluster with primary instance
- Database users and target databases

### Migration Services
- Database Migration Service connection profiles
- Continuous migration jobs for MySQL and PostgreSQL
- Cloud Functions for migration orchestration

### Monitoring and Storage
- Cloud Storage bucket for migration artifacts
- Cloud Monitoring dashboard and alerting policies
- Cloud Logging configuration for migration visibility

## Validation and Testing

After deployment, validate the infrastructure using these commands:

### Verify Dynamic Workload Scheduler
```bash
# Check future reservation status
gcloud compute future-reservations list --format="table(name,status,specificReservation.count)"

# Monitor instance group scaling
gcloud compute instance-groups managed describe migration-workers \
    --region=${REGION} \
    --format="table(targetSize,currentActions.creating)"
```

### Test Database Connectivity
```bash
# Verify Cloud SQL instance
gcloud sql instances describe ${CLOUD_SQL_INSTANCE} \
    --format="table(state,ipAddresses[0].ipAddress,settings.tier)"

# Check AlloyDB cluster status
gcloud alloydb clusters describe ${ALLOYDB_CLUSTER} \
    --region=${REGION} \
    --format="table(state,networkConfig.network)"
```

### Monitor Migration Progress
```bash
# Check migration job status
gcloud database-migration migration-jobs list \
    --region=${REGION} \
    --format="table(name,state,phase)"

# Test orchestration function
FUNCTION_URL=$(gcloud functions describe migration-orchestrator \
    --format="value(httpsTrigger.url)")
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"priority": "high", "size_gb": 500}'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete multi-db-migration \
    --location=${REGION} \
    --quiet

# Verify resource cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify state cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
gcloud compute instances list --filter="name~migration-workers"
gcloud sql instances list --filter="name~mysql-target"
gcloud alloydb clusters list --filter="name~postgres-cluster"
```

## Troubleshooting

### Common Issues

**Migration Job Failures:**
- Verify source database connectivity and credentials
- Check network configuration and firewall rules
- Ensure source databases have appropriate permissions

**Dynamic Workload Scheduler Issues:**
- Verify future reservation quotas in your project
- Check instance template configuration
- Ensure proper IAM permissions for compute resources

**Database Connection Problems:**
- Validate VPC network configuration
- Check private Google Access settings
- Verify database user permissions and passwords

**Cost Optimization:**
- Monitor flex-start capacity utilization
- Adjust autoscaling parameters based on workload
- Use preemptible instances for non-critical migrations

### Monitoring and Debugging

```bash
# View migration logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=migration-orchestrator" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"

# Check compute instance health
gcloud compute instance-groups managed list-instances migration-workers \
    --region=${REGION} \
    --format="table(instance,status,instanceHealth[0].healthCheck)"

# Monitor database performance
gcloud sql operations list --instance=${CLOUD_SQL_INSTANCE} \
    --format="table(operationType,status,startTime,endTime)"
```

## Security Considerations

### Database Security
- All database instances use private IP addresses
- Encryption at rest and in transit enabled by default
- Strong passwords required for database users
- Network isolation through VPC configuration

### Access Control
- Least privilege IAM roles for service accounts
- Secure credential management for source databases
- Private Google Access for internal communication
- Firewall rules restrict access to necessary ports only

### Migration Security
- Encrypted data transfer during migration
- Audit logging for all migration activities
- Secure storage of migration artifacts in Cloud Storage
- Network security through private connectivity

## Performance Optimization

### Scaling Configuration
- Adjust `max_worker_instances` based on migration volume
- Configure appropriate machine types for worker instances
- Use SSD storage for optimal migration performance
- Monitor CPU and memory utilization during migrations

### Cost Optimization
- Leverage flex-start mode for non-urgent migrations
- Use calendar mode for time-sensitive migrations
- Monitor and adjust autoscaling thresholds
- Implement migration scheduling based on cost patterns

### Network Optimization
- Use regional persistent disks for better performance
- Configure appropriate subnet sizing for worker instances
- Optimize network routes for migration traffic
- Monitor network utilization and adjust as needed

## Support and Resources

### Documentation Links
- [Google Cloud Database Migration Service](https://cloud.google.com/database-migration/docs)
- [Dynamic Workload Scheduler](https://cloud.google.com/blog/products/compute/introducing-dynamic-workload-scheduler)
- [Cloud SQL Best Practices](https://cloud.google.com/sql/docs/mysql/best-practices)
- [AlloyDB for PostgreSQL](https://cloud.google.com/alloydb/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help
- For infrastructure code issues, check the logs and verify configuration
- For migration-specific problems, consult Database Migration Service documentation
- For cost optimization questions, review Dynamic Workload Scheduler documentation
- For general Google Cloud support, use the Google Cloud Console support options

## Customization Examples

### High-Performance Configuration
For large database migrations requiring maximum performance:

```bash
# Terraform variable overrides
instance_machine_type = "c2-standard-16"
max_worker_instances  = 16
cloudsql_tier        = "db-n1-highmem-8"
alloydb_cpu_count    = 8
alloydb_memory_gb    = 32
```

### Cost-Optimized Configuration
For development or testing environments:

```bash
# Terraform variable overrides
instance_machine_type = "e2-micro"
max_worker_instances  = 2
cloudsql_tier        = "db-f1-micro"
alloydb_cpu_count    = 2
alloydb_memory_gb    = 8
```

### Multi-Region Configuration
For geographically distributed migrations:

```bash
# Deploy in multiple regions
for region in "us-central1" "us-east1" "europe-west1"; do
    gcloud infra-manager deployments create multi-db-migration-${region} \
        --location=${region} \
        --source-blueprint=. \
        --input-values=project_id=${PROJECT_ID},region=${region}
done
```

This Infrastructure as Code implementation provides a complete, production-ready deployment of the multi-database migration platform with Dynamic Workload Scheduler optimization, following Google Cloud best practices for security, performance, and cost efficiency.