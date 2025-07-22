# Infrastructure as Code for Architecting NoSQL Databases with DynamoDB Global Tables

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting NoSQL Databases with DynamoDB Global Tables".

## Overview

This implementation creates a globally distributed NoSQL database architecture using Amazon DynamoDB Global Tables that provides fully managed, multi-region, multi-active database replication. The infrastructure includes:

- **DynamoDB Global Tables** across 3 regions (us-east-1, eu-west-1, ap-southeast-1)
- **IAM Roles and Policies** for secure application access
- **KMS Keys** for encryption at rest in each region
- **CloudWatch Alarms** for monitoring and alerting
- **Lambda Functions** for testing and demonstration
- **AWS Backup** for automated backup and disaster recovery
- **DynamoDB Streams** for change data capture

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for DynamoDB, IAM, CloudWatch, Lambda, KMS, and AWS Backup across multiple regions
- Access to at least three AWS regions (us-east-1, eu-west-1, ap-southeast-1)
- Understanding of NoSQL database concepts and DynamoDB data modeling
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform >= 1.0

## Architecture Components

### Primary Resources
- **DynamoDB Global Tables** with multi-region replication
- **IAM Roles** for application access with least privilege permissions
- **KMS Keys** for encryption at rest (one per region)
- **CloudWatch Alarms** for monitoring read/write throttles and replication lag
- **Lambda Function** for testing cross-region operations
- **AWS Backup** vault and plan for disaster recovery

### Key Features
- **Multi-region replication** across 3 AWS regions
- **Automatic conflict resolution** using last-writer-wins
- **Point-in-time recovery** enabled for all replicas
- **Encryption at rest** using customer-managed KMS keys
- **Comprehensive monitoring** with CloudWatch alarms
- **Automated backups** with 30-day retention

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name dynamodb-global-tables-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=TableNamePrefix,ParameterValue=global-app-data \
                 ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=eu-west-1 \
                 ParameterKey=TertiaryRegion,ParameterValue=ap-southeast-1 \
    --capabilities CAPABILITY_IAM \
    --enable-termination-protection

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name dynamodb-global-tables-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure AWS credentials and region
export AWS_DEFAULT_REGION=us-east-1

# Deploy the infrastructure
npx cdk deploy --all --require-approval never

# View outputs
npx cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Deploy the infrastructure
cdk deploy --all --require-approval never

# View stack outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="table_name_prefix=global-app-data" \
    -var="primary_region=us-east-1" \
    -var="secondary_region=eu-west-1" \
    -var="tertiary_region=ap-southeast-1"

# Apply the configuration
terraform apply \
    -var="table_name_prefix=global-app-data" \
    -var="primary_region=us-east-1" \
    -var="secondary_region=eu-west-1" \
    -var="tertiary_region=ap-southeast-1"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Set up environment variables
# 2. Create IAM roles and policies
# 3. Create KMS keys in each region
# 4. Deploy DynamoDB Global Tables
# 5. Set up monitoring and backup
# 6. Deploy test Lambda function
```

## Configuration Parameters

### Common Parameters
- **table_name_prefix**: Prefix for DynamoDB table names (default: "global-app-data")
- **primary_region**: Primary AWS region for Global Tables (default: "us-east-1")
- **secondary_region**: Secondary AWS region for replication (default: "eu-west-1")
- **tertiary_region**: Tertiary AWS region for replication (default: "ap-southeast-1")
- **read_capacity**: Read capacity units for tables (default: 10)
- **write_capacity**: Write capacity units for tables (default: 10)
- **backup_retention_days**: Backup retention period in days (default: 30)

### Security Parameters
- **deletion_protection**: Enable deletion protection for tables (default: true)
- **point_in_time_recovery**: Enable point-in-time recovery (default: true)
- **encryption_at_rest**: Enable encryption at rest (default: true)

## Validation and Testing

### Verify Global Table Status
```bash
# Check global table configuration
aws dynamodb describe-global-table \
    --region us-east-1 \
    --global-table-name <table-name>

# Verify tables in all regions
for region in us-east-1 eu-west-1 ap-southeast-1; do
    echo "Checking table in $region:"
    aws dynamodb describe-table \
        --region $region \
        --table-name <table-name>
done
```

### Test Data Replication
```bash
# Insert test data in primary region
aws dynamodb put-item \
    --region us-east-1 \
    --table-name <table-name> \
    --item '{
        "PK": {"S": "TEST#123"},
        "SK": {"S": "REPLICATION_TEST"},
        "data": {"S": "Test data for replication"}
    }'

# Verify replication to other regions (wait ~10 seconds)
aws dynamodb get-item \
    --region eu-west-1 \
    --table-name <table-name> \
    --key '{"PK": {"S": "TEST#123"}, "SK": {"S": "REPLICATION_TEST"}}'
```

### Monitor Performance
```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedReadCapacityUnits \
    --dimensions Name=TableName,Value=<table-name> \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T01:00:00Z \
    --period 300 \
    --statistics Sum
```

## Cost Optimization

### Estimated Monthly Costs
- **DynamoDB Tables**: $50-200 (depends on capacity and usage)
- **Global Tables replication**: $20-100 (cross-region data transfer)
- **KMS Keys**: $3 per key per month (3 regions = $9)
- **Lambda Function**: <$1 (minimal usage)
- **CloudWatch Alarms**: $0.50 per alarm (9 alarms = $4.50)
- **AWS Backup**: $5-50 (depends on data volume)

### Cost Optimization Tips
1. **Use Auto Scaling**: Enable DynamoDB auto scaling for capacity management
2. **Monitor Usage**: Use CloudWatch to track actual vs. provisioned capacity
3. **Optimize Queries**: Use proper partition keys to avoid hot partitions
4. **Backup Strategy**: Adjust backup retention based on compliance requirements
5. **Region Selection**: Choose regions closer to your users to reduce transfer costs

## Cleanup

### Using CloudFormation
```bash
# Disable termination protection first
aws cloudformation update-termination-protection \
    --no-enable-termination-protection \
    --stack-name dynamodb-global-tables-stack

# Delete the stack
aws cloudformation delete-stack \
    --stack-name dynamodb-global-tables-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name dynamodb-global-tables-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy all stacks
npx cdk destroy --all --force

# Or for Python
cdk destroy --all --force
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="table_name_prefix=global-app-data" \
    -var="primary_region=us-east-1" \
    -var="secondary_region=eu-west-1" \
    -var="tertiary_region=ap-southeast-1"

# Confirm destruction
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Remove Global Table replicas
# 2. Delete primary table
# 3. Clean up Lambda function
# 4. Remove CloudWatch alarms
# 5. Delete backup configuration
# 6. Remove IAM roles and policies
# 7. Schedule KMS key deletion
```

## Security Considerations

### IAM Permissions
- Uses least privilege principle for all IAM roles
- Separate roles for applications vs. administrative access
- Resource-specific permissions for DynamoDB operations

### Encryption
- Customer-managed KMS keys for encryption at rest
- Separate KMS keys per region for compliance
- Encryption in transit using TLS

### Network Security
- All resources deployed in AWS backbone network
- VPC endpoints can be configured for additional security
- CloudTrail integration for audit logging

## Monitoring and Alerting

### CloudWatch Alarms
- **Read Throttles**: Alerts when read capacity is exceeded
- **Write Throttles**: Alerts when write capacity is exceeded
- **Replication Lag**: Monitors cross-region replication delays

### Metrics Dashboard
- Table-level metrics for all regions
- Global Table replication metrics
- Lambda function execution metrics
- Backup job status and duration

## Troubleshooting

### Common Issues

1. **Global Table Creation Fails**
   - Ensure DynamoDB Streams are enabled
   - Verify IAM permissions for cross-region access
   - Check that table schemas match exactly

2. **High Replication Lag**
   - Monitor write capacity utilization
   - Check for hot partitions
   - Verify network connectivity between regions

3. **Backup Failures**
   - Ensure AWSBackupDefaultServiceRole exists
   - Check IAM permissions for backup service
   - Verify backup vault encryption settings

4. **Lambda Function Errors**
   - Check CloudWatch Logs for detailed error messages
   - Verify IAM role permissions
   - Ensure boto3 is up to date

### Support Resources
- [AWS DynamoDB Global Tables Documentation](https://docs.aws.amazon.com/dynamodb/latest/developerguide/GlobalTables.html)
- [AWS CLI DynamoDB Reference](https://docs.aws.amazon.com/cli/latest/reference/dynamodb/)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/dynamodb/latest/developerguide/best-practices.html)

## Contributing

When modifying this infrastructure:

1. **Test in Development**: Always test changes in a development environment first
2. **Follow AWS Best Practices**: Adhere to AWS Well-Architected Framework principles
3. **Update Documentation**: Keep README and comments up to date
4. **Security Review**: Ensure all changes maintain security best practices
5. **Cost Analysis**: Evaluate cost implications of infrastructure changes

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies and AWS best practices when deploying to production environments.