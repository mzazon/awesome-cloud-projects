# AWS Database Migration Service (DMS) Terraform Infrastructure

This directory contains production-ready Terraform Infrastructure as Code (IaC) for deploying AWS Database Migration Service (DMS) resources based on the **Database Migration Strategies with AWS DMS** recipe.

## Architecture Overview

This Terraform configuration deploys a complete DMS infrastructure including:

- **DMS Replication Instance** - Multi-AZ compute instance for data migration
- **DMS Endpoints** - Source and target database connection configurations  
- **DMS Replication Tasks** - Migration job definitions with table mappings
- **Security Groups** - Network access controls for database connectivity
- **IAM Roles** - Required service roles for DMS operations
- **KMS Encryption** - Data encryption at rest and in transit
- **S3 Bucket** - Storage for migration logs and data (optional)
- **CloudWatch Monitoring** - Metrics, logs, and alarms for operational visibility

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **VPC and Subnets** in at least 2 availability zones
4. **Source and Target Databases** accessible from the VPC
5. **IAM Permissions** for creating DMS, VPC, KMS, S3, and CloudWatch resources

### Required AWS Permissions

Your AWS credentials must have permissions for:
- `dms:*` - Database Migration Service operations
- `iam:*` - IAM role and policy management
- `kms:*` - Key Management Service operations
- `ec2:*` - VPC, Security Group, and Subnet operations
- `s3:*` - S3 bucket operations
- `logs:*` - CloudWatch Logs operations
- `cloudwatch:*` - CloudWatch metrics and alarms

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Configure Variables

Copy the example variables file and customize for your environment:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific configuration:

```hcl
# Required variables
project_name = "my-database-migration"
owner        = "data-engineering-team"
vpc_id       = "vpc-12345678"

# Database configuration
source_engine_name    = "postgres"
source_server_name    = "source-db.example.com"
source_database_name  = "production_db"
source_username       = "dms_user"
source_password       = "secure_password"

target_engine_name    = "postgres"
target_server_name    = "target-db.example.com"
target_database_name  = "migrated_db"
target_username       = "dms_user"
target_password       = "secure_password"
```

### 3. Plan and Apply

Review the execution plan:

```bash
terraform plan
```

Deploy the infrastructure:

```bash
terraform apply
```

## Configuration Options

### Instance Sizing

Choose the appropriate instance class based on your workload:

```hcl
# Development/Testing
replication_instance_class = "dms.t3.medium"

# Production (Small)
replication_instance_class = "dms.r6i.large"

# Production (Large)
replication_instance_class = "dms.r6i.2xlarge"
```

### Migration Types

Configure the migration strategy:

```hcl
# Full load only (one-time migration)
migration_type = "full-load"

# CDC only (ongoing replication)
migration_type = "cdc"

# Full load + CDC (complete migration with ongoing sync)
migration_type = "full-load-and-cdc"
```

### Security Configuration

**Production Security Recommendations:**

```hcl
# Use Secrets Manager for credentials
source_secrets_manager_arn = "arn:aws:secretsmanager:region:account:secret:dms-source"
target_secrets_manager_arn = "arn:aws:secretsmanager:region:account:secret:dms-target"

# Enable encryption
create_kms_key = true

# Private deployment
publicly_accessible = false

# Require SSL
source_ssl_mode = "require"
target_ssl_mode = "require"
```

### Table Mapping Examples

**Migrate All Tables:**
```hcl
table_mappings = jsonencode({
  "rules" = [
    {
      "rule-type"   = "selection"
      "rule-id"     = "1"
      "rule-name"   = "include-all"
      "object-locator" = {
        "schema-name" = "%"
        "table-name"  = "%"
      }
      "rule-action" = "include"
    }
  ]
})
```

**Selective Migration with Transformation:**
```hcl
table_mappings = jsonencode({
  "rules" = [
    {
      "rule-type"   = "selection"
      "rule-id"     = "1"
      "rule-name"   = "include-specific-schema"
      "object-locator" = {
        "schema-name" = "public"
        "table-name"  = "users"
      }
      "rule-action" = "include"
    },
    {
      "rule-type"   = "transformation"
      "rule-id"     = "2"
      "rule-name"   = "rename-table"
      "rule-target" = "table"
      "object-locator" = {
        "schema-name" = "public"
        "table-name"  = "users"
      }
      "rule-action" = "rename"
      "value"       = "migrated_users"
    }
  ]
})
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor key DMS metrics:
- **CPUUtilization** - Replication instance CPU usage
- **FreeableMemory** - Available memory on replication instance
- **CDCLatencySource** - Replication lag for CDC tasks

### CloudWatch Logs

DMS logs are available in CloudWatch Logs group:
```
/aws/dms/{replication-instance-id}
```

### Common Troubleshooting

**Connection Issues:**
```bash
# Test endpoint connections
aws dms test-connection \
  --replication-instance-arn $(terraform output -raw replication_instance_arn) \
  --endpoint-arn $(terraform output -raw source_endpoint_arn)
```

**Task Monitoring:**
```bash
# Check task status
aws dms describe-replication-tasks \
  --replication-task-arn $(terraform output -raw replication_task_arn)

# View table statistics
aws dms describe-table-statistics \
  --replication-task-arn $(terraform output -raw replication_task_arn)
```

## Cost Optimization

### Development Environment

For cost-effective development deployments:

```hcl
# Smaller instance
replication_instance_class = "dms.t3.micro"

# Single AZ
multi_az = false

# Reduced storage
allocated_storage = 20

# Shorter log retention
log_retention_in_days = 7
```

### Production Environment

For production deployments:

```hcl
# Right-sized instance
replication_instance_class = "dms.r6i.large"

# High availability
multi_az = true

# Adequate storage with room for growth
allocated_storage = 500

# Compliance-appropriate log retention
log_retention_in_days = 90
```

## Maintenance and Operations

### Applying Updates

Update the infrastructure:

```bash
# Pull latest configuration
git pull

# Review changes
terraform plan

# Apply updates during maintenance window
terraform apply
```

### Backup and Recovery

**Important Resources to Backup:**
- Task settings and table mappings (version controlled)
- KMS key policies and IAM role configurations
- CloudWatch alarm configurations
- Network security group rules

### Scaling Operations

**Vertical Scaling:**
```hcl
# Increase instance size during maintenance window
replication_instance_class = "dms.r6i.xlarge"
apply_immediately = false  # Apply during maintenance window
```

**Storage Scaling:**
```hcl
# Increase storage (can be done immediately)
allocated_storage = 1000
apply_immediately = true
```

## Security Best Practices

1. **Use Secrets Manager** for database credentials
2. **Enable KMS encryption** for data at rest
3. **Require SSL/TLS** for database connections
4. **Deploy in private subnets** (publicly_accessible = false)
5. **Use least privilege** IAM policies
6. **Enable CloudTrail** logging for API calls
7. **Regular security reviews** of access patterns

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note:** This will permanently delete all DMS resources, S3 data, and KMS keys. Ensure you have appropriate backups before proceeding.

## Support and Documentation

- [AWS DMS User Guide](https://docs.aws.amazon.com/dms/latest/userguide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html)
- [DMS Troubleshooting Guide](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Troubleshooting.html)

## File Structure

```
terraform/
├── main.tf                    # Main infrastructure configuration
├── variables.tf               # Input variable definitions
├── outputs.tf                 # Output value definitions
├── versions.tf                # Provider version requirements
├── terraform.tfvars.example   # Example variable values
└── README.md                  # This documentation file
```

For issues with this infrastructure code, refer to the original recipe documentation or AWS DMS documentation.