# Infrastructure as Code for Multi-AZ PostgreSQL Cluster

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-AZ PostgreSQL Cluster".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate IAM permissions for RDS, CloudWatch, SNS, IAM, EC2, and Secrets Manager
- Email address for SNS notifications
- Advanced understanding of PostgreSQL administration and high availability concepts
- Estimated cost: $200-500/month for production-grade cluster

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 18+ and npm
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8+ and pip
- AWS CDK CLI (`npm install -g aws-cdk`)

#### Terraform
- Terraform 1.0+ installed
- AWS provider configured

## Quick Start

### Using CloudFormation
```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name postgresql-ha-cluster \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
                ParameterKey=MasterPassword,ParameterValue=SecurePassword123! \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name postgresql-ha-cluster \
    --query 'Stacks[0].StackStatus'

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name postgresql-ha-cluster
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Set required context values
export NOTIFICATION_EMAIL="your-email@example.com"
export MASTER_PASSWORD="SecurePassword123!"

# Deploy the stack
cdk deploy --parameters notificationEmail=$NOTIFICATION_EMAIL

# Confirm email subscription when prompted
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Set required context values
export NOTIFICATION_EMAIL="your-email@example.com"
export MASTER_PASSWORD="SecurePassword123!"

# Deploy the stack
cdk deploy --parameters notificationEmail=$NOTIFICATION_EMAIL
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="notification_email=your-email@example.com" \
    -var="master_password=SecurePassword123!"

# Deploy the infrastructure
terraform apply \
    -var="notification_email=your-email@example.com" \
    -var="master_password=SecurePassword123!"

# Confirm deployment when prompted
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export MASTER_PASSWORD="SecurePassword123!"

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the script prompts and confirm email subscription
```

## Post-Deployment Configuration

### Confirm SNS Email Subscription

After deployment, you'll receive an email subscription confirmation:

1. Check your email for "AWS Notification - Subscription Confirmation"
2. Click the "Confirm subscription" link
3. Verify subscription in AWS Console or CLI:

```bash
aws sns list-subscriptions-by-topic \
    --topic-arn $(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'postgresql-alerts')].TopicArn" \
        --output text)
```

### Test Database Connectivity

```bash
# Get connection endpoints from outputs
aws cloudformation describe-stacks \
    --stack-name postgresql-ha-cluster \
    --query 'Stacks[0].Outputs'

# Test connection to primary endpoint
psql -h <PRIMARY_ENDPOINT> -U dbadmin -d productiondb -c "SELECT version();"

# Test connection to read replica
psql -h <READ_REPLICA_ENDPOINT> -U dbadmin -d productiondb -c "SELECT version();"

# Test connection through RDS Proxy
psql -h <PROXY_ENDPOINT> -U dbadmin -d productiondb -c "SELECT version();"
```

### Verify High Availability Features

```bash
# Check Multi-AZ configuration
aws rds describe-db-instances \
    --db-instance-identifier <PRIMARY_INSTANCE_ID> \
    --query 'DBInstances[0].MultiAZ'

# Check read replica lag
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=<READ_REPLICA_ID> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average

# Test failover (optional - causes brief downtime)
aws rds reboot-db-instance \
    --db-instance-identifier <PRIMARY_INSTANCE_ID> \
    --force-failover
```

## Validation & Testing

### 1. Infrastructure Validation

```bash
# Verify all RDS instances are running
aws rds describe-db-instances \
    --query 'DBInstances[?DBInstanceStatus!=`available`].{ID:DBInstanceIdentifier,Status:DBInstanceStatus}'

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names postgresql-*-cpu-high postgresql-*-connections-high postgresql-*-replica-lag-high

# Verify backup configuration
aws rds describe-db-instances \
    --query 'DBInstances[*].{ID:DBInstanceIdentifier,BackupRetention:BackupRetentionPeriod,DeletionProtection:DeletionProtection}'
```

### 2. Performance Testing

```bash
# Monitor key metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=<PRIMARY_INSTANCE_ID> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum

# Check connection count
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=<PRIMARY_INSTANCE_ID> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum
```

### 3. Disaster Recovery Testing

```bash
# Create test data on primary
psql -h <PRIMARY_ENDPOINT> -U dbadmin -d productiondb -c "
CREATE TABLE dr_test (id SERIAL PRIMARY KEY, data TEXT, created_at TIMESTAMP DEFAULT NOW());
INSERT INTO dr_test (data) VALUES ('Test data for DR validation');
"

# Verify replication to read replica
psql -h <READ_REPLICA_ENDPOINT> -U dbadmin -d productiondb -c "
SELECT * FROM dr_test;
"

# Check cross-region replica (if deployed)
psql -h <CROSS_REGION_REPLICA_ENDPOINT> -U dbadmin -d productiondb -c "
SELECT * FROM dr_test;
"
```

## Monitoring and Maintenance

### CloudWatch Dashboards

Access the following metrics in CloudWatch:

- **Database Performance**: CPU, memory, IOPS, throughput
- **Connection Health**: Active connections, failed connections
- **Replication**: Replica lag, replication errors
- **Storage**: Free storage space, storage throughput

### Key Metrics to Monitor

1. **CPUUtilization** - Should stay below 80% under normal load
2. **DatabaseConnections** - Monitor against max_connections parameter
3. **ReplicaLag** - Should stay below 30 seconds for read replicas
4. **FreeStorageSpace** - Monitor for storage capacity planning
5. **ReadLatency/WriteLatency** - Monitor for performance issues

### Automated Alerts

The deployment includes CloudWatch alarms for:

- High CPU utilization (>80% for 10 minutes)
- High connection count (>150 for 10 minutes)
- High replica lag (>30 seconds for 10 minutes)

## Cleanup

⚠️ **Warning**: Cleanup will permanently delete all database instances and data. Ensure you have appropriate backups before proceeding.

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name postgresql-ha-cluster

# Monitor deletion progress
aws cloudformation wait stack-delete-complete \
    --stack-name postgresql-ha-cluster
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="notification_email=your-email@example.com" \
    -var="master_password=SecurePassword123!"

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm deletion of resources
```

### Manual Cleanup Verification

After automated cleanup, verify removal of resources:

```bash
# Check for remaining RDS instances
aws rds describe-db-instances \
    --query 'DBInstances[?contains(DBInstanceIdentifier, `postgresql-ha`)].DBInstanceIdentifier'

# Check for remaining CloudWatch alarms
aws cloudwatch describe-alarms \
    --query 'MetricAlarms[?contains(AlarmName, `postgresql`)].AlarmName'

# Check for remaining SNS topics
aws sns list-topics \
    --query 'Topics[?contains(TopicArn, `postgresql-alerts`)]'

# Check for remaining manual snapshots
aws rds describe-db-snapshots \
    --snapshot-type manual \
    --query 'DBSnapshots[?contains(DBSnapshotIdentifier, `postgresql-ha`)].DBSnapshotIdentifier'
```

## Customization

### Key Configuration Parameters

#### CloudFormation Parameters
- `MasterUsername`: Database administrator username
- `MasterPassword`: Database administrator password
- `NotificationEmail`: Email for SNS alerts
- `DBInstanceClass`: RDS instance type
- `AllocatedStorage`: Initial storage size
- `BackupRetentionPeriod`: Backup retention in days
- `Environment`: Environment tag for resources

#### Terraform Variables
```hcl
variable "master_username" {
  description = "Master username for the PostgreSQL database"
  default     = "dbadmin"
}

variable "master_password" {
  description = "Master password for the PostgreSQL database"
  sensitive   = true
}

variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  default     = "db.r6g.large"
}

variable "allocated_storage" {
  description = "Initial storage allocation in GB"
  default     = 200
}
```

### Common Customizations

1. **Instance Sizing**: Modify `db_instance_class` based on performance requirements
2. **Storage Configuration**: Adjust `allocated_storage` and `storage_type`
3. **Backup Settings**: Customize `backup_retention_period` and backup windows
4. **Monitoring**: Add additional CloudWatch alarms for specific metrics
5. **Security**: Implement additional security groups or IAM policies
6. **Performance**: Tune PostgreSQL parameters in the parameter group

### Advanced Configuration

For production deployments, consider:

1. **Enhanced Monitoring**: Enable Enhanced Monitoring with 1-second granularity
2. **Performance Insights**: Configure longer retention periods
3. **Encryption**: Use customer-managed KMS keys
4. **Network Security**: Implement VPC endpoints and private subnets only
5. **Compliance**: Add additional logging and audit trails

## Troubleshooting

### Common Issues

1. **Stack Creation Fails**
   - Verify IAM permissions
   - Check parameter values
   - Review CloudFormation events

2. **Database Connection Fails**
   - Verify security group rules
   - Check database status
   - Validate credentials

3. **Read Replica Lag High**
   - Check primary instance performance
   - Verify network connectivity
   - Monitor replication metrics

4. **Failover Takes Too Long**
   - Review Multi-AZ configuration
   - Check CloudWatch logs
   - Verify application connection handling

### Getting Help

- AWS RDS Documentation: https://docs.aws.amazon.com/rds/
- PostgreSQL Documentation: https://www.postgresql.org/docs/
- AWS Support (if you have a support plan)
- Community forums and Stack Overflow

## Security Considerations

- All databases are encrypted at rest using AWS KMS
- Network access is restricted through security groups
- IAM roles follow least privilege principle
- Database credentials are managed through AWS Secrets Manager (when using RDS Proxy)
- Deletion protection is enabled by default
- CloudWatch logs capture database activity for auditing

## Cost Optimization

- Use Reserved Instances for long-term deployments
- Monitor storage growth and implement automated scaling
- Consider graviton2-based instances (db.r6g family) for better price/performance
- Implement lifecycle policies for automated backups
- Use read replicas strategically to avoid over-provisioning

## Support

For issues with this infrastructure code, refer to:
- The original recipe documentation
- AWS RDS documentation
- Provider-specific documentation (CloudFormation, CDK, Terraform)
- AWS Support (if available)