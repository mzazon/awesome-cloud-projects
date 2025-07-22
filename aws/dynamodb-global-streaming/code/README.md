# Infrastructure as Code for DynamoDB Global Tables with Streaming

This directory contains Infrastructure as Code (IaC) implementations for the recipe "DynamoDB Global Tables with Streaming".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a sophisticated DynamoDB Global Tables architecture with:

- Multi-region DynamoDB Global Tables (us-east-1, eu-west-1, ap-southeast-1)
- DynamoDB Streams for real-time change capture
- Kinesis Data Streams for extended analytics
- Lambda functions for stream processing and business logic
- EventBridge for event-driven architecture
- CloudWatch dashboards for global monitoring

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- Appropriate AWS permissions for DynamoDB, Kinesis, Lambda, EventBridge, and CloudWatch
- Access to multiple AWS regions (us-east-1, eu-west-1, ap-southeast-1)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- IAM permissions to create roles and policies

#### CDK (TypeScript)
- Node.js 18+ and npm
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript compiler

#### CDK (Python)
- Python 3.8+ and pip
- AWS CDK CLI (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0+ installed
- AWS provider credentials configured

### Required AWS Permissions

Your AWS credentials need permissions for:
- DynamoDB (CreateTable, CreateGlobalTable, EnableKinesisStreamingDestination)
- Kinesis (CreateStream, PutRecord, EnableEnhancedMonitoring)
- Lambda (CreateFunction, CreateEventSourceMapping)
- IAM (CreateRole, AttachRolePolicy)
- EventBridge (PutEvents, CreateRule)
- CloudWatch (PutMetricData, PutDashboard)

## Quick Start

### Using CloudFormation

```bash
# Deploy to primary region (us-east-1)
aws cloudformation create-stack \
    --region us-east-1 \
    --stack-name dynamodb-global-streaming \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=TableName,ParameterValue=ecommerce-global \
                 ParameterKey=StreamName,ParameterValue=ecommerce-events

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --region us-east-1 \
    --stack-name dynamodb-global-streaming

# Deploy to secondary regions
aws cloudformation create-stack \
    --region eu-west-1 \
    --stack-name dynamodb-global-streaming \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=TableName,ParameterValue=ecommerce-global \
                 ParameterKey=StreamName,ParameterValue=ecommerce-events

aws cloudformation create-stack \
    --region ap-southeast-1 \
    --stack-name dynamodb-global-streaming \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=TableName,ParameterValue=ecommerce-global \
                 ParameterKey=StreamName,ParameterValue=ecommerce-events
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK in all regions (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/eu-west-1
cdk bootstrap aws://ACCOUNT-NUMBER/ap-southeast-1

# Deploy to all regions
cdk deploy DynamoDBGlobalStreamingStack-us-east-1
cdk deploy DynamoDBGlobalStreamingStack-eu-west-1
cdk deploy DynamoDBGlobalStreamingStack-ap-southeast-1
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK in all regions (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/eu-west-1
cdk bootstrap aws://ACCOUNT-NUMBER/ap-southeast-1

# Deploy to all regions
cdk deploy DynamoDBGlobalStreamingStack-us-east-1
cdk deploy DynamoDBGlobalStreamingStack-eu-west-1
cdk deploy DynamoDBGlobalStreamingStack-ap-southeast-1
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration to all regions
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# The script will:
# 1. Validate prerequisites
# 2. Create resources in all three regions
# 3. Configure Global Tables
# 4. Set up stream processing
# 5. Create monitoring dashboards
```

## Validation

After deployment, verify the solution is working:

### Test Global Tables Replication

```bash
# Insert test data in primary region
aws dynamodb put-item \
    --region us-east-1 \
    --table-name ecommerce-global \
    --item '{
      "PK": {"S": "PRODUCT#test123"},
      "SK": {"S": "METADATA"},
      "Name": {"S": "Test Product"},
      "Price": {"N": "29.99"},
      "Stock": {"N": "50"}
    }'

# Verify replication in other regions
aws dynamodb get-item \
    --region eu-west-1 \
    --table-name ecommerce-global \
    --key '{"PK": {"S": "PRODUCT#test123"}, "SK": {"S": "METADATA"}}'

aws dynamodb get-item \
    --region ap-southeast-1 \
    --table-name ecommerce-global \
    --key '{"PK": {"S": "PRODUCT#test123"}, "SK": {"S": "METADATA"}}'
```

### Monitor Stream Processing

```bash
# Check Lambda function logs
aws logs describe-log-groups \
    --region us-east-1 \
    --log-group-name-prefix "/aws/lambda/ecommerce"

# View CloudWatch dashboard
aws cloudwatch get-dashboard \
    --region us-east-1 \
    --dashboard-name "ECommerce-Global-Monitoring"
```

### Test Kinesis Data Streams

```bash
# Check Kinesis stream status
aws kinesis describe-stream \
    --region us-east-1 \
    --stream-name ecommerce-events

# View stream metrics
aws cloudwatch get-metric-statistics \
    --region us-east-1 \
    --namespace "AWS/Kinesis" \
    --metric-name "IncomingRecords" \
    --dimensions Name=StreamName,Value=ecommerce-events \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Customization

### Environment Variables

All implementations support customization through variables:

- `TABLE_NAME`: DynamoDB table name (default: ecommerce-global)
- `STREAM_NAME`: Kinesis stream name (default: ecommerce-events)
- `PRIMARY_REGION`: Primary AWS region (default: us-east-1)
- `SECONDARY_REGION`: Secondary AWS region (default: eu-west-1)
- `TERTIARY_REGION`: Tertiary AWS region (default: ap-southeast-1)

### Lambda Function Configuration

You can customize the Lambda functions by modifying:

- Memory allocation (default: 512 MB)
- Timeout values (default: 300 seconds)
- Environment variables
- Batch size for stream processing
- Error handling configuration

### Kinesis Configuration

Adjust Kinesis settings:

- Shard count (default: 3 per region)
- Retention period (default: 24 hours)
- Enhanced monitoring (enabled by default)

### CloudWatch Monitoring

Customize monitoring by modifying:

- Dashboard widgets and metrics
- Alarm thresholds
- Log retention periods
- Custom metric namespaces

## Cost Optimization

### DynamoDB
- Uses PAY_PER_REQUEST billing mode to avoid capacity planning
- Enable auto-scaling if switching to PROVISIONED mode
- Monitor unused Global Secondary Indexes

### Kinesis
- Adjust shard count based on actual throughput requirements
- Consider Kinesis Data Firehose for batch analytics
- Monitor shard utilization metrics

### Lambda
- Optimize memory allocation based on actual usage
- Consider Provisioned Concurrency for predictable workloads
- Monitor duration and error metrics

### Data Transfer
- Global Tables incur cross-region data transfer costs
- Monitor data transfer metrics in CloudWatch
- Consider data locality for read-heavy workloads

## Cleanup

⚠️ **Warning**: These commands will delete all resources and data. Ensure you have backups if needed.

### Using CloudFormation

```bash
# Delete stacks in all regions
aws cloudformation delete-stack \
    --region us-east-1 \
    --stack-name dynamodb-global-streaming

aws cloudformation delete-stack \
    --region eu-west-1 \
    --stack-name dynamodb-global-streaming

aws cloudformation delete-stack \
    --region ap-southeast-1 \
    --stack-name dynamodb-global-streaming

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --region us-east-1 \
    --stack-name dynamodb-global-streaming
```

### Using CDK

```bash
# Destroy all stacks
cdk destroy DynamoDBGlobalStreamingStack-us-east-1
cdk destroy DynamoDBGlobalStreamingStack-eu-west-1
cdk destroy DynamoDBGlobalStreamingStack-ap-southeast-1
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Troubleshooting

### Common Issues

#### Global Tables Setup
- **Issue**: Global table creation fails
- **Solution**: Ensure all regional tables have identical schemas and Stream enabled

#### Lambda Function Errors
- **Issue**: Lambda functions timing out
- **Solution**: Increase timeout values and check VPC configuration

#### Kinesis Stream Processing
- **Issue**: Records not appearing in Kinesis
- **Solution**: Verify Kinesis Data Streams integration is enabled

#### Permission Errors
- **Issue**: Access denied errors during deployment
- **Solution**: Verify IAM permissions for all required services

### Monitoring and Debugging

#### CloudWatch Logs
```bash
# View Lambda function logs
aws logs filter-log-events \
    --region us-east-1 \
    --log-group-name "/aws/lambda/ecommerce-stream-processor" \
    --start-time $(date -u -d '1 hour ago' +%s)000
```

#### DynamoDB Metrics
```bash
# Check table metrics
aws cloudwatch get-metric-statistics \
    --region us-east-1 \
    --namespace "AWS/DynamoDB" \
    --metric-name "ConsumedReadCapacityUnits" \
    --dimensions Name=TableName,Value=ecommerce-global \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Security Considerations

### IAM Roles
- Lambda functions use least privilege IAM roles
- Cross-region access is properly configured
- Service-linked roles are used where appropriate

### Data Encryption
- DynamoDB encryption at rest is enabled
- Kinesis server-side encryption is configured
- CloudWatch Logs encryption is enabled

### Network Security
- Lambda functions can be configured for VPC deployment
- Security groups restrict access to necessary ports
- Consider AWS PrivateLink for service communications

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review CloudWatch logs for error details
3. Refer to the original recipe documentation
4. Consult AWS documentation for specific services:
   - [DynamoDB Global Tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
   - [DynamoDB Streams](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Streams.html)
   - [Kinesis Data Streams](https://docs.aws.amazon.com/kinesis/latest/dev/)
   - [AWS Lambda](https://docs.aws.amazon.com/lambda/)

## Additional Resources

- [AWS Global Tables Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-global-tables.html)
- [DynamoDB Streams and Kinesis Integration](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/kds.html)
- [Event-Driven Architecture with AWS](https://aws.amazon.com/event-driven-architecture/)
- [Multi-Region Application Architecture](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/multi-region-application-architecture.html)