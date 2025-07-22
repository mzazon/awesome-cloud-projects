# Infrastructure as Code for Real-time Clickstream Analytics with Kinesis Data Streams and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Streaming Clickstream Analytics with Kinesis Data Streams".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a real-time clickstream analytics pipeline that includes:

- **Kinesis Data Streams**: High-throughput data ingestion for clickstream events
- **Lambda Functions**: Serverless processing for event handling and anomaly detection
- **DynamoDB Tables**: Real-time storage for metrics and session data
- **S3 Bucket**: Raw data archival and long-term storage
- **CloudWatch**: Monitoring, dashboards, and alerting
- **IAM Roles**: Secure access controls with least privilege principles

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for:
  - Kinesis Data Streams
  - Lambda functions
  - DynamoDB tables
  - S3 buckets
  - CloudWatch dashboards
  - IAM roles and policies
- Node.js 18+ (for CDK TypeScript and testing)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name clickstream-analytics \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name clickstream-analytics

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name clickstream-analytics \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
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

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# Check deployment status
aws kinesis describe-stream --stream-name $(terraform output -raw stream_name)
```

## Testing the Solution

After deployment, you can test the clickstream analytics pipeline:

### Generate Sample Events

```bash
# Install Node.js dependencies for test client
cd test-client/
npm install

# Set environment variables from outputs
export STREAM_NAME=$(aws cloudformation describe-stacks \
    --stack-name clickstream-analytics \
    --query 'Stacks[0].Outputs[?OutputKey==`StreamName`].OutputValue' \
    --output text)

# Generate test events
node generate-events.js
```

### Monitor Processing

```bash
# Check Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/clickstream"

# Query processed data in DynamoDB
TABLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name clickstream-analytics \
    --query 'Stacks[0].Outputs[?OutputKey==`CountersTableName`].OutputValue' \
    --output text)

aws dynamodb scan --table-name $TABLE_NAME --limit 5
```

### View Dashboard

```bash
# Get dashboard URL
DASHBOARD_NAME=$(aws cloudformation describe-stacks \
    --stack-name clickstream-analytics \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardName`].OutputValue' \
    --output text)

echo "Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME"
```

## Customization

### Environment Variables

Each implementation supports customization through parameters:

- **Environment**: Development, staging, or production environment
- **StreamShardCount**: Number of Kinesis shards (default: 2)
- **LambdaMemorySize**: Lambda function memory allocation (default: 256MB)
- **DataRetentionDays**: DynamoDB TTL for automatic cleanup (default: 30 days)

### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name clickstream-analytics \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=StreamShardCount,ParameterValue=4 \
        ParameterKey=LambdaMemorySize,ParameterValue=512
```

### Terraform Variables

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
environment = "production"
stream_shard_count = 4
lambda_memory_size = 512
data_retention_days = 90
EOF

terraform apply -var-file="terraform.tfvars"
```

### CDK Context

```bash
# Set context values for CDK
cdk deploy -c environment=production -c streamShardCount=4
```

## Cost Optimization

### DynamoDB

- Tables use on-demand billing for cost optimization with variable workloads
- TTL attributes automatically expire old data to control storage costs
- Consider switching to provisioned capacity for predictable workloads

### Lambda

- Functions use appropriate memory allocation for performance vs. cost balance
- Event source mapping batching optimizes invocation costs
- Consider provisioned concurrency for consistent low latency

### Kinesis

- Shard count balances throughput with cost
- Data retention period affects storage costs
- Consider Kinesis Data Firehose for scenarios not requiring real-time processing

### S3

- Raw data archival uses standard storage class
- Consider lifecycle policies for long-term cost optimization
- Implement intelligent tiering for mixed access patterns

## Monitoring and Alerting

### CloudWatch Metrics

The solution provides several key metrics:

- **Events Processed**: Count of events by type
- **Lambda Performance**: Duration, errors, and invocations
- **Kinesis Throughput**: Incoming and outgoing record rates
- **DynamoDB Performance**: Read/write capacity and throttling

### Custom Alerts

```bash
# Create custom alarm for high error rate
aws cloudwatch put-metric-alarm \
    --alarm-name "ClickstreamHighErrorRate" \
    --alarm-description "Alert when Lambda error rate exceeds 5%" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold
```

## Security Considerations

### IAM Roles

- Lambda execution roles follow least privilege principle
- Cross-service access uses role-based permissions
- No hard-coded credentials in any configuration

### Data Encryption

- Kinesis streams use server-side encryption
- DynamoDB tables encrypt data at rest
- S3 bucket uses default encryption
- Lambda environment variables are encrypted

### Network Security

- All services use VPC endpoints where applicable
- Security groups restrict access to necessary ports
- Consider VPC deployment for enhanced isolation

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**
   - Increase memory allocation or timeout duration
   - Check CloudWatch logs for specific errors
   - Verify IAM permissions for dependent services

2. **Kinesis Stream Throttling**
   - Increase shard count for higher throughput
   - Implement exponential backoff in producers
   - Monitor shard-level metrics

3. **DynamoDB Throttling**
   - Review partition key distribution
   - Consider switching to provisioned capacity
   - Implement error handling and retries

4. **High Costs**
   - Review data retention policies
   - Optimize Lambda memory allocation
   - Implement lifecycle policies for S3

### Debug Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name clickstream-processor

# Monitor Kinesis stream metrics
aws kinesis describe-stream --stream-name $STREAM_NAME

# Check DynamoDB table status
aws dynamodb describe-table --table-name $TABLE_NAME

# Review CloudWatch logs
aws logs tail /aws/lambda/clickstream-processor --follow
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name clickstream-analytics

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name clickstream-analytics
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
aws kinesis list-streams
aws dynamodb list-tables | grep clickstream
aws s3 ls | grep clickstream
aws lambda list-functions | grep clickstream
```

## Performance Tuning

### Kinesis Optimization

- **Shard Count**: Start with 2 shards, scale based on throughput requirements
- **Batch Size**: Optimize Lambda batch size (50-100) for latency vs. throughput
- **Retention Period**: Balance replay capability with storage costs

### Lambda Optimization

- **Memory Allocation**: 256MB provides good balance for JSON processing
- **Timeout**: 60 seconds accommodates batch processing and retries
- **Concurrency**: Monitor and set reserved concurrency if needed

### DynamoDB Optimization

- **Partition Keys**: Ensure even distribution across partitions
- **Query Patterns**: Design tables for efficient access patterns
- **Indexes**: Add GSIs for additional query patterns if needed

## Integration Patterns

### Real-time Dashboards

```bash
# Connect to Amazon QuickSight
aws quicksight create-data-source \
    --aws-account-id $AWS_ACCOUNT_ID \
    --data-source-id clickstream-source \
    --name "Clickstream Analytics" \
    --type ATHENA
```

### Machine Learning Integration

```bash
# Create SageMaker endpoint for anomaly detection
aws sagemaker create-model \
    --model-name clickstream-anomaly-model \
    --primary-container Image=382416733822.dkr.ecr.us-east-1.amazonaws.com/sagemaker-scikit-learn
```

### Data Lake Integration

```bash
# Set up Glue catalog for S3 data
aws glue create-database --database-input Name=clickstream_db

aws glue create-table \
    --database-name clickstream_db \
    --table-input Name=raw_events
```

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review CloudWatch logs for error details
3. Consult the original recipe documentation
4. Reference AWS service documentation for specific configurations

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new parameters
3. Ensure security best practices are maintained
4. Verify cleanup procedures work correctly