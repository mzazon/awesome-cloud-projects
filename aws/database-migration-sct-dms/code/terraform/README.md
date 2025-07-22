# AWS Database Migration Service - Terraform Infrastructure

This Terraform configuration creates a complete AWS Database Migration Service (DMS) infrastructure for migrating databases with minimal downtime. The infrastructure includes DMS replication instances, RDS target databases, networking components, IAM roles, and comprehensive monitoring.

## Architecture Overview

The infrastructure creates:
- **VPC and Networking**: Custom VPC with public subnets across multiple AZs
- **DMS Components**: Replication instance, endpoints, and migration tasks
- **RDS Database**: Target PostgreSQL database with proper security configuration
- **IAM Roles**: Service-linked roles for DMS operations
- **CloudWatch Monitoring**: Logs, dashboards, and alarms for migration monitoring
- **Security Groups**: Properly configured network access controls

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** version 1.0 or higher installed
3. **AWS Account** with permissions to create VPC, DMS, RDS, IAM, and CloudWatch resources
4. **Source Database** accessible from AWS with proper credentials
5. **Cost Awareness**: Review estimated costs before deployment

### Required AWS Permissions

Your AWS credentials need the following permissions:
- `AmazonDMSFullAccess`
- `AmazonRDSFullAccess`
- `AmazonVPCFullAccess`
- `IAMFullAccess`
- `CloudWatchFullAccess`

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd aws/database-migration-strategies-aws-dms-schema-conversion-tool/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# Basic Configuration
aws_region   = "us-east-1"
project_name = "my-db-migration"
environment  = "production"

# Source Database Configuration (Update with your actual values)
source_db_engine   = "oracle"
source_db_host     = "your-source-database.example.com"
source_db_port     = 1521
source_db_name     = "your_database"
source_db_username = "your_username"
source_db_password = "your_secure_password"

# Target Database Configuration
rds_engine_version = "14.9"
rds_instance_class = "db.t3.medium"
rds_username       = "postgres_admin"
rds_password       = "your_secure_target_password"

# DMS Configuration
dms_replication_instance_class = "dms.t3.medium"
dms_allocated_storage         = 100
migration_type                = "full-load-and-cdc"

# Security Configuration
allowed_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]
enable_deletion_protection = true

# Monitoring Configuration
enable_cloudwatch_logs = true
create_dashboard      = true

# Common Tags
common_tags = {
  Environment = "production"
  Project     = "database-migration"
  Owner       = "data-team"
  CostCenter  = "engineering"
}
```

### 3. Review and Deploy

```bash
# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

After deployment, verify the infrastructure:

```bash
# Check DMS replication instance status
aws dms describe-replication-instances \
    --query 'ReplicationInstances[0].ReplicationInstanceStatus'

# Test endpoint connectivity
aws dms test-connection \
    --replication-instance-arn $(terraform output -raw dms_replication_instance_arn) \
    --endpoint-arn $(terraform output -raw dms_source_endpoint_arn)
```

## Configuration Options

### Source Database Engines

Supported source database engines:
- `oracle` - Oracle Database
- `sqlserver` - Microsoft SQL Server
- `mysql` - MySQL
- `postgres` - PostgreSQL
- `mariadb` - MariaDB

### Migration Types

Available migration types:
- `full-load` - One-time full data migration
- `cdc` - Continuous data capture only
- `full-load-and-cdc` - Full load followed by ongoing replication

### Instance Classes

Recommended instance classes:
- **Development/Testing**: `dms.t3.medium`, `db.t3.medium`
- **Production**: `dms.c5.large`, `db.r5.large`
- **High Performance**: `dms.c5.xlarge`, `db.r5.xlarge`

## Table Mappings and Task Settings

### Custom Table Mappings

To customize which tables to migrate, update the `table_mappings` variable:

```hcl
table_mappings = jsonencode({
  rules = [
    {
      rule-type = "selection"
      rule-id   = "1"
      rule-name = "include-specific-schema"
      object-locator = {
        schema-name = "your_schema"
        table-name  = "%"
      }
      rule-action = "include"
    },
    {
      rule-type = "transformation"
      rule-id   = "2"
      rule-name = "rename-schema"
      rule-target = "schema"
      object-locator = {
        schema-name = "your_schema"
      }
      rule-action = "rename"
      value       = "new_schema_name"
    }
  ]
})
```

### Custom Task Settings

To customize migration behavior, update the `task_settings` variable:

```hcl
task_settings = jsonencode({
  FullLoadSettings = {
    TargetTablePrepMode = "DROP_AND_CREATE"
    CommitRate         = 10000
    MaxFullLoadSubTasks = 8
  }
  ErrorBehavior = {
    DataErrorPolicy = "LOG_ERROR"
    TableErrorPolicy = "SUSPEND_TABLE"
  }
})
```

## Monitoring and Troubleshooting

### CloudWatch Dashboard

Access the monitoring dashboard:
```bash
# Get dashboard URL
terraform output monitoring_urls
```

### Log Analysis

View DMS logs:
```bash
# List log streams
aws logs describe-log-streams \
    --log-group-name $(terraform output -raw cloudwatch_log_group_name)

# View recent logs
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

### Common Issues

1. **Endpoint Connectivity Issues**
   - Check security group rules
   - Verify database credentials
   - Ensure database is accessible from VPC

2. **Migration Task Failures**
   - Review CloudWatch logs
   - Check table mappings configuration
   - Verify source database permissions

3. **Performance Issues**
   - Scale up replication instance
   - Optimize table mappings
   - Review task settings

## Security Considerations

### Network Security

- Use private subnets for production deployments
- Implement VPC endpoints for AWS services
- Enable VPC Flow Logs for network monitoring

### Database Security

- Enable encryption at rest for RDS
- Use SSL/TLS for database connections
- Implement least privilege access policies

### Credentials Management

For production environments, use AWS Secrets Manager:

```hcl
# Store database credentials in Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project_name}-db-credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.source_db_username
    password = var.source_db_password
  })
}
```

## Cost Optimization

### Resource Sizing

- Start with smaller instance classes and scale up as needed
- Use Multi-AZ only for production workloads
- Monitor resource utilization via CloudWatch

### Storage Optimization

- Use GP2 storage for cost-effective performance
- Enable storage encryption for compliance
- Set appropriate backup retention periods

### Cleanup

To avoid ongoing costs after migration:

```bash
# Destroy the infrastructure
terraform destroy
```

## Migration Workflow

### Pre-Migration Steps

1. **Schema Conversion**: Use AWS Schema Conversion Tool (SCT)
2. **Network Setup**: Configure VPC and security groups
3. **Endpoint Testing**: Verify connectivity to source and target databases

### Migration Execution

1. **Full Load**: Initial data migration
2. **CDC Setup**: Enable ongoing replication
3. **Data Validation**: Verify data integrity
4. **Application Testing**: Test applications with target database

### Post-Migration Steps

1. **Performance Tuning**: Optimize target database
2. **Monitoring Setup**: Configure ongoing monitoring
3. **Cleanup**: Remove migration infrastructure

## Support and Troubleshooting

### AWS Documentation

- [AWS DMS User Guide](https://docs.aws.amazon.com/dms/latest/userguide/)
- [AWS DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html)
- [Schema Conversion Tool](https://docs.aws.amazon.com/SchemaConversionTool/)

### Common Commands

```bash
# Check migration task status
aws dms describe-replication-tasks \
    --replication-task-identifier $(terraform output -raw dms_replication_task_id)

# Monitor migration progress
aws dms describe-table-statistics \
    --replication-task-identifier $(terraform output -raw dms_replication_task_id)

# Start migration task
aws dms start-replication-task \
    --replication-task-arn $(terraform output -raw dms_replication_task_arn) \
    --start-replication-task-type start-replication

# Stop migration task
aws dms stop-replication-task \
    --replication-task-arn $(terraform output -raw dms_replication_task_arn)
```

## Contributing

To contribute improvements to this infrastructure:

1. Test changes in a development environment
2. Validate with `terraform plan`
3. Update documentation as needed
4. Follow security best practices

## License

This infrastructure code is provided as-is under the MIT License. Review and modify according to your organization's requirements.