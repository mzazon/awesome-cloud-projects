# Database Disaster Recovery with Backup and DR Service and Cloud SQL

This Terraform configuration deploys a comprehensive disaster recovery solution for Google Cloud SQL databases using Google Cloud's Backup and DR Service, cross-region replicas, and automated orchestration.

## Architecture Overview

The solution includes:

- **Cloud SQL Primary Instance**: High-availability PostgreSQL instance in the primary region
- **Cross-Region DR Replica**: Disaster recovery replica in a secondary region with automated failover capability
- **Backup and DR Service**: Immutable backup vaults in both regions with automated backup plans
- **Cloud Functions**: Intelligent orchestration for health monitoring and automated recovery
- **Cloud Scheduler**: Automated health checks and backup validation
- **Pub/Sub**: Real-time alerting and event processing
- **Cloud Monitoring**: Comprehensive monitoring and alerting policies

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud CLI** installed and configured
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** version >= 1.5 installed
   ```bash
   terraform version
   ```

3. **Required Google Cloud APIs** enabled:
   - Cloud SQL Admin API
   - Backup and DR API
   - Cloud Functions API
   - Cloud Scheduler API
   - Cloud Monitoring API
   - Pub/Sub API
   - Cloud Build API
   - Cloud Logging API

4. **IAM Permissions** for deployment:
   - `roles/cloudsql.admin`
   - `roles/backupdr.admin`
   - `roles/cloudfunctions.admin`
   - `roles/cloudscheduler.admin`
   - `roles/pubsub.admin`
   - `roles/monitoring.admin`
   - `roles/iam.serviceAccountAdmin`
   - `roles/storage.admin`

5. **Project Information**:
   - Project ID
   - Project Number (for service account permissions)

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd gcp/database-disaster-recovery-backup-dr-service-sql/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your project details
vim terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init
```

### 3. Plan Deployment

```bash
# Review the planned infrastructure changes
terraform plan
```

### 4. Deploy Infrastructure

```bash
# Deploy the disaster recovery infrastructure
terraform apply
```

**Note**: The initial deployment typically takes 15-20 minutes due to Cloud SQL instance creation and configuration.

### 5. Verify Deployment

```bash
# Check the outputs for connection information
terraform output

# Test primary database connection
gcloud sql connect $(terraform output -raw primary_instance_name) --user=postgres

# Verify DR replica status
gcloud sql instances describe $(terraform output -raw dr_replica_name)
```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud Project ID | `"my-project-123"` |
| `project_number` | Google Cloud Project Number | `"123456789012"` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `primary_region` | `"us-central1"` | Primary region for resources |
| `secondary_region` | `"us-east1"` | Secondary region for DR replica |
| `database_version` | `"POSTGRES_15"` | Cloud SQL database version |
| `db_tier` | `"db-custom-2-8192"` | Cloud SQL machine type |
| `backup_retention_days` | `30` | Backup retention period |
| `environment` | `"prod"` | Environment identifier |

### Advanced Configuration

```hcl
# terraform.tfvars example
project_id     = "my-project-123"
project_number = "123456789012"

# Regions
primary_region   = "us-central1"
secondary_region = "us-east1"

# Database Configuration
database_version = "POSTGRES_15"
db_tier         = "db-custom-4-16384"  # 4 vCPUs, 16GB RAM
storage_size_gb = 200

# Backup Configuration
backup_retention_days = 30
backup_start_time    = "03:00"

# Monitoring
monitoring_schedule = "0 */6 * * *"  # Every 6 hours

# Security
enable_deletion_protection = true
enable_private_ip         = false

# Labels
labels = {
  environment = "production"
  team        = "platform"
  cost-center = "engineering"
}
```

## Usage Examples

### Testing Disaster Recovery

```bash
# 1. Test health check function
curl -X POST "$(terraform output -raw dr_orchestrator_function_url)" \
     -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     -H "Content-Type: application/json" \
     -d '{"action": "health_check"}'

# 2. Validate backups
curl -X POST "$(terraform output -raw backup_validator_function_url)" \
     -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
     -H "Content-Type: application/json" \
     -d '{"action": "validate_backups"}'

# 3. Simulate failover (test environment only)
gcloud sql instances failover $(terraform output -raw primary_instance_name)
```

### Monitoring and Alerting

```bash
# Check Cloud SQL instance status
gcloud sql instances list

# View backup plans
gcloud backup-dr backup-plans list --location=$(terraform output -raw primary_region)

# Monitor Cloud Function logs
gcloud functions logs read disaster-recovery-orchestrator

# Check Pub/Sub topic messages
gcloud pubsub topics list
```

### Database Operations

```bash
# Connect to primary database
gcloud sql connect $(terraform output -raw primary_instance_name) --user=postgres

# Connect to DR replica (read-only)
gcloud sql connect $(terraform output -raw dr_replica_name) --user=postgres

# Create a test database
gcloud sql databases create test-app --instance=$(terraform output -raw primary_instance_name)
```

## Security Considerations

### Network Security
- Consider enabling `enable_private_ip = true` for production deployments
- Configure VPC firewall rules to restrict database access
- Use authorized networks to limit IP-based access

### IAM Security
- Service accounts follow principle of least privilege
- Regular audit of IAM permissions recommended
- Function service accounts have minimal required permissions

### Data Security
- All backups are encrypted at rest automatically
- Enable SSL enforcement for database connections
- Consider enabling Cloud SQL audit logging

### Example Security Configuration
```hcl
# Enhanced security configuration
enable_private_ip = true
network_name     = "my-secure-vpc"

authorized_networks = [
  {
    name  = "office-network"
    value = "203.0.113.0/24"
  }
]

# Enable audit logging
enable_binary_logging = true
```

## Cost Optimization

### Estimated Monthly Costs (US regions)

| Component | Estimated Cost |
|-----------|----------------|
| Cloud SQL Primary | $200-400/month |
| Cloud SQL DR Replica | $200-400/month |
| Backup Storage | $50-100/month |
| Cloud Functions | $10-30/month |
| Cloud Scheduler | $1-5/month |
| Pub/Sub | $1-10/month |
| Monitoring | $5-20/month |
| **Total** | **$467-965/month** |

### Cost Optimization Tips

1. **Right-size instances**: Start with smaller tiers and scale up as needed
2. **Optimize backup retention**: Balance compliance needs with storage costs
3. **Monitor function invocations**: Adjust monitoring frequency if needed
4. **Use committed use discounts**: For predictable workloads

```hcl
# Cost-optimized configuration for development
db_tier             = "db-f1-micro"
backup_retention_days = 7
monitoring_schedule = "0 */12 * * *"  # Twice daily
```

## Troubleshooting

### Common Issues

#### 1. API Not Enabled
```bash
# Enable required APIs
gcloud services enable sqladmin.googleapis.com
gcloud services enable backupdr.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
```

#### 2. Insufficient Permissions
```bash
# Check current permissions
gcloud iam service-accounts get-iam-policy YOUR_SERVICE_ACCOUNT

# Add required roles
gcloud projects add-iam-policy-binding YOUR_PROJECT \
    --member="serviceAccount:YOUR_SA@YOUR_PROJECT.iam.gserviceaccount.com" \
    --role="roles/cloudsql.admin"
```

#### 3. Function Deployment Issues
```bash
# Check function logs
gcloud functions logs read disaster-recovery-orchestrator --limit=50

# Redeploy function
terraform apply -target=google_cloudfunctions2_function.dr_orchestrator
```

#### 4. Backup Configuration Issues
```bash
# Verify backup vault status
gcloud backup-dr backup-vaults list --location=us-central1

# Check backup plan associations
gcloud backup-dr backup-plan-associations list --location=us-central1
```

### Debug Commands

```bash
# Terraform debugging
export TF_LOG=DEBUG
terraform apply

# Check resource dependencies
terraform graph | dot -Tpng > graph.png

# Validate configuration
terraform validate
terraform fmt -check
```

## Maintenance

### Regular Tasks

1. **Monitor backup health**: Weekly review of backup validation reports
2. **Test DR procedures**: Monthly failover testing in non-production
3. **Review costs**: Monthly cost analysis and optimization
4. **Update dependencies**: Quarterly updates to Terraform providers
5. **Security audit**: Quarterly review of IAM permissions

### Updating the Infrastructure

```bash
# Update to latest provider versions
terraform init -upgrade

# Plan updates
terraform plan

# Apply updates during maintenance window
terraform apply
```

### Backup and Recovery Testing

```bash
# Schedule regular DR tests
# 1. Create test data in primary
# 2. Trigger backup validation
# 3. Simulate failover
# 4. Verify data integrity in replica
# 5. Document results
```

## Support and Documentation

- [Google Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Backup and DR Service Documentation](https://cloud.google.com/backup-disaster-recovery/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

When making changes to this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any new variables or outputs
3. Follow the existing code style and naming conventions
4. Add appropriate labels to all resources
5. Update cost estimates if adding new resources

## License

This code is provided as-is for educational and operational purposes. Ensure compliance with your organization's policies and Google Cloud's terms of service.