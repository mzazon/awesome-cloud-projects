# Infrastructure as Code for Database Disaster Recovery with Read Replicas

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Disaster Recovery with Read Replicas".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive disaster recovery architecture using Amazon RDS cross-region read replicas with automated failover mechanisms. The infrastructure includes:

- Primary RDS MySQL instance in the primary region (us-east-1)
- Cross-region read replica in the disaster recovery region (us-west-2)
- CloudWatch alarms for monitoring database health and replica lag
- SNS topics for alerting and automation triggers
- Lambda functions for disaster recovery coordination and replica promotion
- EventBridge rules for automated event processing
- Route 53 health checks for DNS-level failover
- S3 bucket for configuration storage and disaster recovery runbooks

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon RDS (create instances, read replicas, parameter groups)
  - AWS Lambda (create functions, manage permissions)
  - Amazon CloudWatch (create alarms, custom metrics)
  - Amazon SNS (create topics, manage subscriptions)
  - Amazon EventBridge (create rules, manage targets)
  - Amazon Route 53 (create health checks)
  - Amazon S3 (create buckets, manage objects)
  - AWS Systems Manager Parameter Store
  - IAM (create roles and policies for Lambda execution and RDS monitoring)
- Access to two AWS regions (primary: us-east-1, DR: us-west-2)
- VPC with private subnets in both regions for RDS deployment
- Estimated cost: $200-400/month for RDS instances, storage, and cross-region data transfer

### Tool-Specific Prerequisites

#### CloudFormation
- No additional tools required

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK v2 installed (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK v2 installed (`pip install aws-cdk-lib`)

#### Terraform
- Terraform v1.5 or later
- AWS Provider v5.0 or later

## Quick Start

### Using CloudFormation

```bash
# Deploy the disaster recovery infrastructure
aws cloudformation create-stack \
    --stack-name rds-disaster-recovery \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
        ParameterKey=DRRegion,ParameterValue=us-west-2 \
        ParameterKey=NotificationEmail,ParameterValue=admin@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name rds-disaster-recovery \
    --query 'Stacks[0].StackStatus'

# Wait for deployment completion
aws cloudformation wait stack-create-complete \
    --stack-name rds-disaster-recovery
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Deploy the infrastructure
cdk deploy --all

# View outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Deploy the infrastructure
cdk deploy --all

# View outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters and deploy all resources
```

## Configuration Options

### CloudFormation Parameters

- `PrimaryRegion`: Primary AWS region (default: us-east-1)
- `DRRegion`: Disaster recovery AWS region (default: us-west-2)
- `DBInstanceClass`: RDS instance class (default: db.t3.micro)
- `NotificationEmail`: Email address for alerts
- `BackupRetentionPeriod`: Database backup retention in days (default: 7)
- `ReplicaLagThreshold`: Maximum acceptable replica lag in seconds (default: 300)

### CDK Context Variables

- `primaryRegion`: Primary AWS region
- `drRegion`: Disaster recovery AWS region
- `notificationEmail`: Email address for disaster recovery alerts
- `dbInstanceClass`: RDS instance class for cost optimization

### Terraform Variables

- `primary_region`: Primary AWS region
- `dr_region`: Disaster recovery AWS region
- `db_instance_class`: RDS instance class
- `notification_email`: Email address for alerts
- `backup_retention_period`: Backup retention period in days
- `replica_lag_threshold`: Replica lag threshold for alarms

## Outputs

After deployment, the following outputs are available:

- `PrimaryDatabaseEndpoint`: Connection endpoint for the primary database
- `ReplicaDatabaseEndpoint`: Connection endpoint for the read replica
- `SNSTopicArns`: ARNs of SNS topics for monitoring
- `LambdaFunctionArns`: ARNs of disaster recovery Lambda functions
- `HealthCheckIds`: Route 53 health check identifiers
- `S3BucketName`: Configuration bucket name
- `DisasterRecoveryRunbookUrl`: URL to the disaster recovery runbook

## Disaster Recovery Testing

### Manual Failover Test

```bash
# Test the disaster recovery process (non-destructive)
aws rds describe-db-instances \
    --region us-west-2 \
    --db-instance-identifier $(terraform output -raw replica_db_identifier) \
    --query 'DBInstances[0].{Status:DBInstanceStatus,Lag:StatusInfos[?StatusType==`read replication`].Status}'

# Simulate alarm trigger (testing only)
aws cloudwatch set-alarm-state \
    --region us-east-1 \
    --alarm-name "$(terraform output -raw primary_db_identifier)-database-connection-failure" \
    --state-value ALARM \
    --state-reason "Disaster recovery test"
```

### Validation Commands

```bash
# Check replica lag
aws cloudwatch get-metric-statistics \
    --region us-west-2 \
    --namespace AWS/RDS \
    --metric-name ReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=$(terraform output -raw replica_db_identifier) \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average

# Verify Lambda function deployment
aws lambda get-function \
    --region us-east-1 \
    --function-name $(terraform output -raw dr_coordinator_function_name)

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
    --region us-east-1 \
    --topic-arn $(terraform output -raw primary_sns_topic_arn)
```

## Monitoring and Alerting

The deployed infrastructure includes comprehensive monitoring:

- **Database Connection Monitoring**: Detects primary database failures
- **Replica Lag Monitoring**: Ensures disaster recovery target synchronization
- **CPU Utilization Monitoring**: Tracks database performance
- **Custom Metrics**: Disaster recovery readiness indicators

### Alert Channels

- Email notifications via SNS
- Lambda function triggers for automation
- CloudWatch dashboard integration
- Route 53 health check status

## Security Considerations

- All databases are encrypted at rest using AWS KMS
- Network access restricted to private subnets
- IAM roles follow least privilege principle
- Lambda functions use VPC endpoints for secure API access
- SNS topics encrypted for sensitive notifications
- S3 bucket has versioning and access logging enabled

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name rds-disaster-recovery

# Wait for deletion completion
aws cloudformation wait stack-delete-complete --stack-name rds-disaster-recovery
```

### Using CDK

```bash
# Destroy all CDK stacks
cdk destroy --all

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Cost Optimization

- Use `db.t3.micro` instances for development/testing
- Consider `db.t3.small` or larger for production workloads
- Monitor cross-region data transfer costs
- Implement lifecycle policies for S3 storage
- Use reserved instances for predictable workloads

## Troubleshooting

### Common Issues

1. **Replica Lag High**: Check network connectivity and primary database load
2. **Lambda Timeout**: Increase function timeout for promotion operations
3. **IAM Permissions**: Verify Lambda execution roles have required permissions
4. **SNS Delivery Failures**: Check topic policies and subscription configurations

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Monitor CloudWatch alarm history
aws cloudwatch describe-alarm-history --alarm-name "ALARM_NAME"

# Verify EventBridge rule targets
aws events list-targets-by-rule --rule "rds-promotion-events"
```

## Advanced Configuration

### Custom Parameter Groups

The infrastructure includes optimized parameter groups for replication performance:

- `innodb_flush_log_at_trx_commit = 2`
- `sync_binlog = 0`
- `binlog_format = ROW`

### Multi-Region Considerations

- Ensure consistent VPC configuration across regions
- Configure appropriate security group rules for cross-region access
- Consider network latency impact on replication performance

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for specific configurations
3. Validate IAM permissions and resource limits
4. Monitor CloudWatch logs for detailed error information

## License

This infrastructure code is provided as-is for educational and implementation purposes. Ensure compliance with your organization's policies and AWS best practices before production deployment.