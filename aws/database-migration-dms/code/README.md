# Infrastructure as Code for Database Migration with AWS DMS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Migration with AWS DMS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for DMS, RDS, VPC, IAM, SNS, and CloudWatch
- Source database accessible from AWS (on-premises or EC2-based)
- Target RDS instance or Aurora cluster
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform CLI 1.5+

## Architecture Overview

This implementation creates:
- DMS replication instance with Multi-AZ deployment
- DMS subnet group for network isolation
- Source and target database endpoints
- Migration task with full load and CDC capabilities
- SNS topic for event notifications
- CloudWatch alarms for monitoring
- Event subscription for automated alerts
- Data validation configuration

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name dms-migration-stack \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=SourceDBEndpoint,ParameterValue=your-source-db.example.com \
        ParameterKey=SourceDBUsername,ParameterValue=migration_user \
        ParameterKey=SourceDBPassword,ParameterValue=your-secure-password \
        ParameterKey=TargetDBEndpoint,ParameterValue=your-rds-instance.region.rds.amazonaws.com \
        ParameterKey=TargetDBUsername,ParameterValue=admin \
        ParameterKey=TargetDBPassword,ParameterValue=your-rds-password \
    --capabilities CAPABILITY_IAM

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name dms-migration-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name dms-migration-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --parameters sourceDBEndpoint=your-source-db.example.com \
           --parameters sourceDBUsername=migration_user \
           --parameters sourceDBPassword=your-secure-password \
           --parameters targetDBEndpoint=your-rds-instance.region.rds.amazonaws.com \
           --parameters targetDBUsername=admin \
           --parameters targetDBPassword=your-rds-password

# View outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --parameters sourceDBEndpoint=your-source-db.example.com \
           --parameters sourceDBUsername=migration_user \
           --parameters sourceDBPassword=your-secure-password \
           --parameters targetDBEndpoint=your-rds-instance.region.rds.amazonaws.com \
           --parameters targetDBUsername=admin \
           --parameters targetDBPassword=your-rds-password

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat > terraform.tfvars << EOF
source_db_endpoint = "your-source-db.example.com"
source_db_username = "migration_user"
source_db_password = "your-secure-password"
target_db_endpoint = "your-rds-instance.region.rds.amazonaws.com"
target_db_username = "admin"
target_db_password = "your-rds-password"
project_name = "dms-migration"
environment = "production"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Set required environment variables
export SOURCE_DB_ENDPOINT="your-source-db.example.com"
export SOURCE_DB_USERNAME="migration_user"
export SOURCE_DB_PASSWORD="your-secure-password"
export TARGET_DB_ENDPOINT="your-rds-instance.region.rds.amazonaws.com"
export TARGET_DB_USERNAME="admin"
export TARGET_DB_PASSWORD="your-rds-password"

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh

# Monitor deployment progress
watch -n 30 'aws dms describe-replication-tasks --query "ReplicationTasks[0].{Status:Status,Progress:ReplicationTaskStats}"'
```

## Configuration Parameters

### Database Connection Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `source_db_endpoint` | Source database hostname or IP | `mysql.example.com` |
| `source_db_username` | Source database username | `migration_user` |
| `source_db_password` | Source database password | `SecurePassword123!` |
| `target_db_endpoint` | Target RDS endpoint | `mydb.us-east-1.rds.amazonaws.com` |
| `target_db_username` | Target database username | `admin` |
| `target_db_password` | Target database password | `RDSPassword456!` |

### Infrastructure Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `replication_instance_class` | DMS instance type | `dms.t3.medium` | `dms.t3.micro`, `dms.t3.small`, `dms.t3.medium`, `dms.t3.large` |
| `allocated_storage` | Storage size in GB | `100` | `20-6144` |
| `multi_az` | Enable Multi-AZ deployment | `true` | `true`, `false` |
| `publicly_accessible` | Public access to replication instance | `true` | `true`, `false` |
| `source_engine` | Source database engine | `mysql` | `mysql`, `postgresql`, `oracle`, `sqlserver` |
| `target_engine` | Target database engine | `mysql` | `mysql`, `postgresql`, `aurora`, `aurora-postgresql` |

## Post-Deployment Steps

### 1. Verify Infrastructure Deployment

```bash
# Check DMS replication instance status
aws dms describe-replication-instances \
    --query 'ReplicationInstances[*].{ID:ReplicationInstanceIdentifier,Status:ReplicationInstanceStatus}'

# Verify endpoint connectivity
aws dms describe-connections \
    --query 'Connections[*].{Endpoint:EndpointIdentifier,Status:Status}'
```

### 2. Start Migration Task

```bash
# Get migration task ARN
TASK_ARN=$(aws dms describe-replication-tasks \
    --query 'ReplicationTasks[0].ReplicationTaskArn' --output text)

# Start the migration
aws dms start-replication-task \
    --replication-task-arn "$TASK_ARN" \
    --start-replication-task-type start-replication
```

### 3. Monitor Migration Progress

```bash
# Monitor task progress
aws dms describe-replication-tasks \
    --query 'ReplicationTasks[0].{Status:Status,Progress:ReplicationTaskStats}'

# Check table-level statistics
aws dms describe-table-statistics \
    --replication-task-arn "$TASK_ARN" \
    --query 'TableStatistics[*].{Table:TableName,Status:TableState,Records:FullLoadRows}'
```

## Monitoring and Alerting

### CloudWatch Metrics

The implementation creates CloudWatch alarms for:
- DMS task failures
- High replication latency (>5 minutes)
- Memory utilization
- Network connectivity issues

### SNS Notifications

Configure email notifications for the SNS topic:

```bash
# Subscribe to SNS topic for email alerts
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name dms-migration-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' --output text)

aws sns subscribe \
    --topic-arn "$SNS_TOPIC_ARN" \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Troubleshooting

### Common Issues

1. **Connection Test Failures**
   - Verify security group rules allow DMS traffic
   - Check database credentials and permissions
   - Ensure network connectivity between VPCs

2. **Migration Task Errors**
   - Review CloudWatch logs for detailed error messages
   - Verify table mappings configuration
   - Check source database transaction log settings

3. **Performance Issues**
   - Monitor replication instance CPU and memory usage
   - Consider upgrading instance class for better performance
   - Optimize table mappings to reduce unnecessary data transfer

### Log Analysis

```bash
# View DMS logs in CloudWatch
aws logs describe-log-groups --log-group-name-prefix "/aws/dms/"

# Get recent log events
aws logs get-log-events \
    --log-group-name "/aws/dms/task" \
    --log-stream-name "your-task-log-stream"
```

## Cleanup

### Using CloudFormation

```bash
# Stop migration task first
TASK_ARN=$(aws cloudformation describe-stacks \
    --stack-name dms-migration-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`MigrationTaskArn`].OutputValue' --output text)

aws dms stop-replication-task --replication-task-arn "$TASK_ARN"

# Wait for task to stop, then delete stack
aws cloudformation delete-stack --stack-name dms-migration-stack
aws cloudformation wait stack-delete-complete --stack-name dms-migration-stack
```

### Using CDK

```bash
# For TypeScript
cd cdk-typescript/
cdk destroy

# For Python
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
cd scripts/
./destroy.sh
```

## Security Considerations

- **Database Credentials**: Store sensitive credentials in AWS Secrets Manager or SSM Parameter Store
- **Network Security**: Use VPC endpoints for secure communication
- **Encryption**: Enable encryption in transit and at rest for all database connections
- **IAM Policies**: Follow least privilege principle for DMS service roles
- **Monitoring**: Enable CloudTrail logging for audit trails

## Cost Optimization

- **Instance Sizing**: Start with smaller instances and scale up based on performance needs
- **Multi-AZ**: Disable Multi-AZ for development/testing environments
- **Storage**: Monitor and adjust allocated storage based on actual usage
- **Cleanup**: Remember to stop/delete resources after migration completion

## Best Practices

1. **Pre-Migration Testing**: Always test migration with a subset of data first
2. **Backup Strategy**: Ensure both source and target databases are backed up
3. **Validation**: Enable data validation to ensure migration accuracy
4. **Monitoring**: Set up comprehensive monitoring and alerting
5. **Documentation**: Document any custom transformations or mappings

## Support and Resources

- [AWS DMS User Guide](https://docs.aws.amazon.com/dms/latest/userguide/)
- [AWS DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html)
- [AWS DMS Troubleshooting](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Troubleshooting.html)
- [AWS DMS API Reference](https://docs.aws.amazon.com/dms/latest/APIReference/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.