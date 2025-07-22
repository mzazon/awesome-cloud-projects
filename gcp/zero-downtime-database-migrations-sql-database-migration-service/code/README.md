# Infrastructure as Code for Zero-Downtime Database Migrations with Cloud SQL and Database Migration Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Zero-Downtime Database Migrations with Cloud SQL and Database Migration Service".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) v2.0+ installed and authenticated
- Google Cloud project with appropriate permissions for:
  - Database Migration Service
  - Cloud SQL
  - Cloud Monitoring
  - Cloud Logging
  - Compute Engine (for testing)
- On-premises MySQL database (5.6, 5.7, or 8.0) with binary logging enabled
- Network connectivity between on-premises environment and Google Cloud
- Terraform v1.5+ (for Terraform implementation)
- Appropriate IAM permissions:
  - Cloud SQL Admin
  - Database Migration Admin
  - Monitoring Admin
  - Logging Admin
  - Service Usage Admin

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager provides serverless infrastructure provisioning with native Google Cloud integration.

```bash
# Set up environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export DEPLOYMENT_NAME="mysql-migration-deployment"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/terraform.tfvars"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides declarative infrastructure management with state tracking and dependency resolution.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var-file="terraform.tfvars.example"

# Apply infrastructure
terraform apply -var-file="terraform.tfvars.example"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide step-by-step deployment with comprehensive error handling and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow prompts for configuration
# Script will validate prerequisites and deploy resources
```

## Configuration

### Required Variables

Before deploying, configure these variables in your chosen implementation:

- **project_id**: Your Google Cloud project ID
- **region**: Deployment region (default: us-central1)
- **zone**: Deployment zone (default: us-central1-a)
- **source_mysql_host**: IP address or hostname of source MySQL database
- **source_mysql_port**: Source MySQL port (default: 3306)
- **db_user**: Database user for migration (must have replication privileges)
- **db_password**: Database password (store securely)
- **db_name**: Name of database to migrate

### Optional Variables

- **cloudsql_tier**: Cloud SQL machine type (default: db-n1-standard-2)
- **storage_size**: Initial storage size in GB (default: 100)
- **backup_start_time**: Automated backup time (default: 03:00)
- **maintenance_window_day**: Maintenance day (default: SUN)
- **maintenance_window_hour**: Maintenance hour (default: 04)

## Architecture Components

This implementation creates the following Google Cloud resources:

### Core Migration Resources
- **Database Migration Service Job**: Orchestrates the migration process
- **Connection Profiles**: Secure connection configurations for source and target
- **Cloud SQL Instance**: Target MySQL database with high availability
- **Cloud SQL Users**: Application and migration user accounts

### Monitoring and Observability
- **Cloud Monitoring Dashboards**: Real-time migration metrics
- **Log-based Metrics**: Custom metrics for migration events
- **Alert Policies**: Automated notifications for critical events
- **Cloud Logging Sinks**: Centralized log collection

### Security and Networking
- **IAM Roles**: Least privilege access for migration service
- **Private Service Connect**: Secure database connectivity
- **Cloud SQL Auth Proxy**: Encrypted database connections
- **Service Account**: Dedicated identity for migration operations

## Deployment Phases

### Phase 1: Infrastructure Provisioning
1. Enable required Google Cloud APIs
2. Create Cloud SQL target instance
3. Configure backup and maintenance windows
4. Set up monitoring and alerting infrastructure

### Phase 2: Migration Configuration
1. Create source database connection profile
2. Configure Database Migration Service job
3. Validate connectivity and permissions
4. Initialize continuous replication

### Phase 3: Data Synchronization
1. Perform initial data dump
2. Establish ongoing change data capture
3. Monitor replication lag and performance
4. Validate data consistency

### Phase 4: Production Cutover
1. Stop application writes to source
2. Wait for final replication sync
3. Promote Cloud SQL to primary
4. Update application connection strings

## Monitoring and Validation

### Key Metrics to Monitor

```bash
# Check migration job status
gcloud datamigration migration-jobs describe MIGRATION_JOB_ID \
    --region=REGION \
    --format="table(state,phase,createTime,updateTime)"

# Monitor replication lag
gcloud monitoring metrics list \
    --filter="metric.type:cloudsql.googleapis.com/database/replication/replica_lag"

# View migration logs
gcloud logging read \
    'resource.type="datamigration.googleapis.com/MigrationJob"' \
    --limit=50 \
    --format="table(timestamp,severity,jsonPayload.message)"
```

### Data Validation Queries

```sql
-- Compare row counts between source and target
SELECT table_name, table_rows 
FROM information_schema.tables 
WHERE table_schema = 'DATABASE_NAME';

-- Validate checksums for critical tables
CHECKSUM TABLE table_name;

-- Check for replication errors
SHOW SLAVE STATUS\G
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify resource cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Review resources to be destroyed
terraform plan -destroy -var-file="terraform.tfvars.example"

# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars.example"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
# Script will remove resources in proper dependency order
```

## Cost Optimization

### Resource Sizing Guidelines

- **Development/Testing**: Use db-n1-standard-1 (1 vCPU, 3.75 GB RAM)
- **Production**: Use db-n1-standard-2 or higher based on workload
- **Storage**: Start with 100GB SSD, enable auto-increase
- **Backups**: Configure retention based on compliance requirements

### Cost Monitoring

```bash
# Enable billing export to BigQuery
gcloud beta billing accounts get-iam-policy BILLING_ACCOUNT_ID

# Set up budget alerts
gcloud beta billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Database Migration Budget" \
    --budget-amount=1000USD
```

## Security Best Practices

### Database Security
- Use strong passwords and rotate regularly
- Enable SSL/TLS for all database connections
- Configure Cloud SQL Auth Proxy for secure access
- Implement least privilege database user permissions

### Network Security
- Use Private Google Access for secure connectivity
- Configure VPC firewall rules to restrict access
- Enable Cloud SQL Private IP when possible
- Use Cloud VPN or Interconnect for on-premises connectivity

### Identity and Access Management
- Create dedicated service accounts for migration
- Use IAM conditions for time-based access
- Enable audit logging for all administrative actions
- Implement separation of duties for production access

## Troubleshooting

### Common Issues

**Migration Job Fails to Start**
- Verify source database binary logging is enabled
- Check network connectivity between environments
- Validate user permissions on source database
- Ensure Cloud SQL APIs are enabled

**High Replication Lag**
- Monitor source database transaction volume
- Check network bandwidth and latency
- Consider upgrading Cloud SQL instance size
- Optimize source database configuration

**Connection Profile Errors**
- Verify source database credentials
- Check firewall rules and network access
- Validate SSL certificate configuration
- Test connectivity from Cloud Shell

### Debug Commands

```bash
# Test source database connectivity
gcloud datamigration connection-profiles test CONNECTION_PROFILE_ID --region=REGION

# Check migration job logs
gcloud logging read 'resource.type="datamigration.googleapis.com/MigrationJob"' \
    --limit=100 --format="table(timestamp,severity,jsonPayload.message)"

# Validate Cloud SQL instance health
gcloud sql operations list --instance=INSTANCE_ID --limit=10
```

## Performance Optimization

### Cloud SQL Configuration
- Enable query cache for read-heavy workloads
- Configure appropriate innodb_buffer_pool_size
- Use read replicas for read scaling
- Enable automated backups during low-traffic periods

### Migration Optimization
- Schedule migration during low-traffic periods
- Use parallel migration for multiple databases
- Monitor and adjust instance sizing based on performance
- Consider using Cloud SQL Proxy for connection pooling

## Support and Documentation

- [Database Migration Service Documentation](https://cloud.google.com/database-migration/docs)
- [Cloud SQL for MySQL Documentation](https://cloud.google.com/sql/docs/mysql)
- [Migration Best Practices](https://cloud.google.com/architecture/database-migration-concepts-principles-part-1)
- [Troubleshooting Guide](https://cloud.google.com/database-migration/docs/mysql/troubleshooting)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## Next Steps

After successful deployment:

1. **Configure Application Connections**: Update application connection strings to use Cloud SQL
2. **Set Up Monitoring Dashboards**: Create custom dashboards for ongoing database monitoring
3. **Implement Backup Strategy**: Configure automated backups and point-in-time recovery
4. **Plan Disaster Recovery**: Set up cross-region read replicas for disaster recovery
5. **Optimize Performance**: Monitor query performance and optimize based on workload patterns