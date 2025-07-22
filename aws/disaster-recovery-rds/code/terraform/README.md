# Infrastructure as Code for Implementing RDS Disaster Recovery Solutions

This directory contains Terraform Infrastructure as Code (IaC) for implementing a comprehensive disaster recovery solution for Amazon RDS databases using cross-region read replicas, automated monitoring, and intelligent failover management.

## Solution Overview

This Terraform configuration deploys:

- **Cross-region read replica** for real-time data replication
- **Comprehensive monitoring** with CloudWatch alarms and dashboards
- **Automated notification system** using SNS topics
- **Intelligent automation** with Lambda-based disaster recovery management
- **Security best practices** with IAM roles and encrypted storage

## Architecture Components

- **Primary Region**: Source RDS database with monitoring and alerting
- **Secondary Region**: Read replica with independent monitoring
- **Lambda Function**: Automated disaster recovery logic and notifications
- **CloudWatch**: Alarms, dashboards, and metrics monitoring
- **SNS**: Multi-region notification system
- **IAM**: Least-privilege security roles and policies

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Existing RDS database instance in the primary region
- Appropriate AWS permissions for:
  - RDS instance management
  - Lambda function creation
  - CloudWatch alarm and dashboard management
  - SNS topic management
  - IAM role and policy management

## Quick Start

### 1. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your configuration
vim terraform.tfvars
```

**Required Variables:**
- `source_db_identifier`: Your existing RDS database identifier
- `primary_region`: Region where your database currently exists
- `secondary_region`: Region for disaster recovery replica
- `notification_email`: Email address for DR notifications

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 3. Verify Deployment

```bash
# Check read replica status
aws rds describe-db-instances \
    --db-instance-identifier $(terraform output -raw read_replica_identifier) \
    --region $(terraform output -raw read_replica_region)

# View CloudWatch dashboard
echo "Dashboard URL: $(terraform output -raw cloudwatch_dashboard_url)"
```

## Configuration Options

### Database Configuration

```hcl
# Use different instance class for replica
replica_instance_class = "db.r5.xlarge"

# Configure Multi-AZ deployment
replica_multi_az = true

# Enable storage encryption
replica_storage_encrypted = true
```

### Monitoring Configuration

```hcl
# Adjust alarm thresholds
cpu_alarm_threshold = 75          # CPU percentage
replica_lag_threshold = 180       # Seconds
alarm_evaluation_periods = 3      # Number of periods

# Customize monitoring intervals
lambda_timeout = 600              # Lambda timeout
lambda_memory_size = 512          # Lambda memory MB
```

### Backup and Recovery

```hcl
# Configure backup settings
backup_retention_period = 14                    # Days
backup_window = "02:00-03:00"                   # UTC
maintenance_window = "sat:03:00-sat:04:00"      # UTC

# Security settings
enable_deletion_protection = true
enable_performance_insights = true
```

## Outputs

After deployment, Terraform provides important outputs:

```bash
# Database connection information
terraform output read_replica_endpoint
terraform output read_replica_port

# Monitoring resources
terraform output cloudwatch_dashboard_url
terraform output primary_sns_topic_arn

# Disaster recovery configuration
terraform output disaster_recovery_config
```

## Disaster Recovery Procedures

### Manual Failover Process

1. **Assess the situation**: Verify primary database is truly unavailable
2. **Promote read replica**: Convert replica to standalone database
3. **Update applications**: Point application connections to new primary
4. **Monitor and validate**: Ensure applications are functioning correctly

```bash
# Promote read replica to primary (DESTRUCTIVE - USE WITH CAUTION)
aws rds promote-read-replica \
    --db-instance-identifier $(terraform output -raw read_replica_identifier) \
    --region $(terraform output -raw read_replica_region)
```

### Automated Monitoring

The Lambda function automatically:
- Monitors database health and performance
- Sends intelligent notifications based on alarm types
- Provides detailed recovery guidance in notifications
- Tracks replica lag and connection health

## Monitoring and Alerting

### CloudWatch Alarms

- **Primary CPU**: Monitors primary database CPU utilization
- **Replica Lag**: Tracks replication delay between regions
- **Database Connections**: Detects connectivity issues
- **Replica CPU**: Monitors read replica performance

### SNS Notifications

- **Email alerts**: Immediate notification of issues
- **Lambda integration**: Automated intelligent response
- **Multi-region**: Independent notification in each region

### CloudWatch Dashboard

- Real-time metrics visualization
- Historical trend analysis
- Cross-region performance comparison
- Replica lag monitoring

## Security Considerations

### IAM Roles and Policies

- **Lambda execution role**: Minimal permissions for RDS and SNS operations
- **RDS monitoring role**: Enhanced monitoring capabilities
- **Cross-region permissions**: Appropriate access for disaster recovery

### Encryption

- **Storage encryption**: Enabled for read replica by default
- **In-transit encryption**: Automatic with RDS
- **Performance Insights**: Encrypted metrics storage

### Network Security

- **VPC integration**: Inherits security groups from source database
- **Cross-region replication**: Secure AWS backbone network
- **Access controls**: Database-level authentication required

## Cost Optimization

### Estimated Monthly Costs

- **Read Replica**: ~Equal to primary database instance cost
- **Data Transfer**: $0.02/GB between regions
- **SNS**: $0.50 per million notifications
- **Lambda**: Minimal cost for monitoring functions
- **CloudWatch**: Standard metrics and dashboard costs

### Cost Reduction Strategies

- Use smaller instance class for replica during development
- Implement automated scaling for non-production environments
- Monitor data transfer costs and optimize replication frequency
- Use reserved instances for predictable workloads

## Maintenance

### Regular Tasks

- **Monitor replica lag**: Ensure replication is current
- **Test failover procedures**: Regular DR testing
- **Review alarm thresholds**: Adjust based on performance patterns
- **Update Lambda function**: Keep automation logic current

### Scaling Considerations

- **Instance class**: Upgrade replica independently of primary
- **Storage**: Auto-scaling available for gp2 and gp3 storage
- **Performance**: Monitor and adjust based on workload

## Troubleshooting

### Common Issues

**High Replica Lag**
```bash
# Check primary database load
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=<primary-db-id>
```

**Connection Failures**
```bash
# Verify database status
aws rds describe-db-instances \
    --db-instance-identifier <db-identifier>
```

**Lambda Function Errors**
```bash
# Check Lambda logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/<function-name>
```

### Getting Help

- Check CloudWatch Logs for detailed error messages
- Review SNS topic subscriptions for notification delivery
- Validate IAM permissions for cross-region operations
- Consult AWS RDS documentation for engine-specific considerations

## Cleanup

To remove all disaster recovery infrastructure:

```bash
# Remove all resources (THIS IS DESTRUCTIVE)
terraform destroy

# Confirm deletion
terraform show
```

**Warning**: This will delete the read replica and all monitoring infrastructure. Ensure you have proper backups before cleanup.

## Advanced Configuration

### Custom Lambda Logic

Modify `dr_manager.py.tpl` to add:
- Custom failover automation
- Integration with external monitoring systems
- Advanced notification logic
- Automated application configuration updates

### Multi-Database Support

Extend the configuration for multiple databases:
```hcl
variable "databases" {
  description = "List of databases for disaster recovery"
  type = list(object({
    identifier = string
    region     = string
  }))
}
```

### Integration with CI/CD

Add Terraform automation to your deployment pipeline:
```yaml
# Example GitHub Actions workflow
- name: Deploy DR Infrastructure
  run: |
    terraform init
    terraform plan
    terraform apply -auto-approve
```

## Support

For issues with this infrastructure code:
1. Check the [original recipe documentation](../disaster-recovery-amazon-rds-databases.md)
2. Review AWS RDS documentation for your database engine
3. Consult CloudWatch Logs for detailed error information
4. Validate IAM permissions and resource limits

## Contributing

When modifying this infrastructure:
1. Update variable descriptions and validation rules
2. Add appropriate outputs for new resources
3. Update this README with configuration changes
4. Test thoroughly in non-production environments