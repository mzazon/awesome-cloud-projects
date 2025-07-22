# Infrastructure as Code for Implementing DynamoDB Global Tables for Multi-Region Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing DynamoDB Global Tables for Multi-Region Apps".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - DynamoDB table creation and global table configuration
  - IAM role creation and policy attachment
  - Lambda function deployment
  - CloudWatch alarms and dashboard management
- Understanding of multi-region AWS deployments
- Estimated cost: $10-50/month for testing (varies by region and usage patterns)

> **Note**: Global Tables incur additional costs for cross-region replication. Review [DynamoDB Global Tables pricing](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html) before deployment.

## Architecture Overview

This implementation creates:
- DynamoDB Global Tables across multiple AWS regions (us-east-1, eu-west-1, ap-northeast-1)
- Lambda functions for testing cross-region operations
- CloudWatch monitoring and alarms for replication metrics
- IAM roles and policies for secure access
- Global Secondary Index for optimized queries

## Quick Start

### Using CloudFormation

```bash
# Deploy the primary stack
aws cloudformation create-stack \
    --stack-name dynamodb-global-tables-primary \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=TableName,ParameterValue=GlobalUserProfiles-$(date +%s) \
                 ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=eu-west-1 \
                 ParameterKey=TertiaryRegion,ParameterValue=ap-northeast-1

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name dynamodb-global-tables-primary

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name dynamodb-global-tables-primary \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
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

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
# Script will create all resources and provide status updates
```

## Configuration Options

### CloudFormation Parameters

- `TableName`: Name for the DynamoDB table (default: GlobalUserProfiles-timestamp)
- `PrimaryRegion`: Primary AWS region (default: us-east-1)
- `SecondaryRegion`: Secondary AWS region (default: eu-west-1)
- `TertiaryRegion`: Tertiary AWS region (default: ap-northeast-1)
- `BillingMode`: DynamoDB billing mode (default: PAY_PER_REQUEST)
- `StreamViewType`: DynamoDB stream view type (default: NEW_AND_OLD_IMAGES)

### CDK Configuration

Both TypeScript and Python CDK implementations support:
- Environment variables for region configuration
- Context values for customizing table names
- Stack parameters for billing modes and capacity settings

### Terraform Variables

- `table_name`: DynamoDB table name
- `primary_region`: Primary AWS region
- `secondary_region`: Secondary AWS region
- `tertiary_region`: Tertiary AWS region
- `billing_mode`: DynamoDB billing mode
- `lambda_runtime`: Lambda function runtime version

## Validation & Testing

After deployment, validate the infrastructure:

### Test Global Table Replication

```bash
# Test writing data from primary region
aws lambda invoke \
    --function-name GlobalTableProcessor-$(date +%s) \
    --payload '{"operation": "put", "userId": "test-user", "name": "Test User"}' \
    --region us-east-1 \
    /tmp/test-response.json

# Verify replication in secondary region
aws lambda invoke \
    --function-name GlobalTableProcessor-$(date +%s) \
    --payload '{"operation": "get", "userId": "test-user"}' \
    --region eu-west-1 \
    /tmp/test-response.json
```

### Monitor Replication Metrics

```bash
# Check replication latency
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ReplicationLatency \
    --dimensions Name=TableName,Value=YourTableName \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --region us-east-1
```

### Verify Global Secondary Index

```bash
# Test GSI query functionality
aws dynamodb query \
    --table-name YourTableName \
    --index-name EmailIndex \
    --key-condition-expression "Email = :email" \
    --expression-attribute-values '{":email":{"S":"test@example.com"}}' \
    --region us-east-1
```

## Monitoring and Observability

The implementation includes:

### CloudWatch Alarms

- **ReplicationLatency**: Monitors cross-region replication latency
- **UserErrors**: Tracks user-generated errors
- **ThrottledRequests**: Monitors capacity-related throttling

### CloudWatch Dashboard

- Real-time metrics for read/write capacity utilization
- Replication latency across all regions
- Error rates and operational metrics

### Accessing Dashboards

```bash
# Get dashboard URL
aws cloudwatch describe-dashboards \
    --dashboard-names GlobalTable-YourTableName \
    --region us-east-1
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name dynamodb-global-tables-primary

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name dynamodb-global-tables-primary
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
# Script will remove all resources in proper order
```

## Customization

### Adding Additional Regions

To add more regions to the Global Table:

1. **CloudFormation**: Add new region parameters and replica resources
2. **CDK**: Extend the regions array in the stack configuration
3. **Terraform**: Add new region variables and replica configurations
4. **Bash**: Update the region arrays in deployment scripts

### Modifying Table Schema

To change the table schema:

1. Update attribute definitions in your chosen IaC tool
2. Modify GSI configurations if needed
3. Update Lambda function code to handle new attributes
4. Test thoroughly with new schema

### Scaling Configuration

For production workloads:

1. Consider switching to provisioned capacity mode
2. Configure auto-scaling for predictable traffic patterns
3. Implement proper backup strategies
4. Set up enhanced monitoring and alerting

## Security Considerations

### IAM Permissions

The implementation follows least privilege principles:
- Lambda functions have minimal required DynamoDB permissions
- CloudWatch access is restricted to necessary metrics
- Cross-region replication uses service-linked roles

### Data Encryption

- DynamoDB encryption at rest is enabled by default
- In-transit encryption is enforced for all communications
- Lambda environment variables are encrypted

### Network Security

- Lambda functions run in AWS managed VPCs
- DynamoDB endpoints use TLS encryption
- CloudWatch logs are encrypted

## Troubleshooting

### Common Issues

1. **Replication Delays**: Check CloudWatch metrics for capacity constraints
2. **Lambda Timeouts**: Increase timeout values or optimize code
3. **Permission Errors**: Verify IAM roles and policies
4. **Region Availability**: Ensure all regions support required services

### Debug Commands

```bash
# Check table status across regions
aws dynamodb describe-table --table-name YourTableName --region us-east-1
aws dynamodb describe-table --table-name YourTableName --region eu-west-1
aws dynamodb describe-table --table-name YourTableName --region ap-northeast-1

# View Lambda function logs
aws logs tail /aws/lambda/GlobalTableProcessor-YourSuffix --region us-east-1

# Check CloudWatch alarms
aws cloudwatch describe-alarms --region us-east-1
```

## Cost Optimization

### Strategies

1. **Billing Mode**: Use PAY_PER_REQUEST for variable workloads
2. **Capacity Planning**: Monitor actual usage and adjust accordingly
3. **Regional Optimization**: Consider data locality and access patterns
4. **Lifecycle Management**: Implement TTL for temporary data

### Cost Monitoring

```bash
# Check DynamoDB costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Performance Optimization

### Best Practices

1. **Partition Key Design**: Use high-cardinality partition keys
2. **Query Patterns**: Optimize GSI for common access patterns
3. **Batch Operations**: Use batch operations for bulk data operations
4. **Connection Pooling**: Implement connection pooling in applications

### Performance Monitoring

Monitor these key metrics:
- ConsumedReadCapacityUnits
- ConsumedWriteCapacityUnits
- ReplicationLatency
- SuccessfulRequestLatency

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS DynamoDB documentation for service-specific issues
3. Consult provider documentation for IaC tool problems
4. Use AWS Support for account-specific issues

## Additional Resources

- [DynamoDB Global Tables Documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [Multi-Region Architecture Patterns](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html)
- [CloudWatch DynamoDB Metrics](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/monitoring-cloudwatch.html)