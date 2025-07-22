# Infrastructure as Code for Implementing Real-Time Analytics with Amazon Kinesis Data Streams

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Real-Time Analytics with Amazon Kinesis Data Streams".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a complete real-time analytics pipeline including:

- Amazon Kinesis Data Streams with configurable shard count
- AWS Lambda function for stream processing
- S3 bucket for analytics data storage
- IAM roles and policies with least privilege access
- CloudWatch monitoring and alerting
- Event source mapping for automatic Lambda triggers

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Kinesis Data Streams
  - Lambda functions
  - S3 buckets
  - IAM roles and policies
  - CloudWatch metrics and alarms
- For CDK: Node.js 16+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+
- Estimated cost: $50-100/month for moderate traffic volumes

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name kinesis-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=StreamShardCount,ParameterValue=3 \
                ParameterKey=RetentionHours,ParameterValue=168

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name kinesis-analytics-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name kinesis-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
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
# Navigate to CDK Python directory
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
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
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

# The script will output important resource names and ARNs
```

## Testing the Deployment

After deployment, test your real-time analytics pipeline:

### 1. Send Test Data

```bash
# Get stream name from stack outputs
STREAM_NAME=$(aws cloudformation describe-stacks \
    --stack-name kinesis-analytics-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`StreamName`].OutputValue' \
    --output text)

# Send sample records
aws kinesis put-record \
    --stream-name $STREAM_NAME \
    --data '{"timestamp":"2024-01-01T12:00:00Z","user_id":"user_1234","event_type":"purchase","amount":99.99}' \
    --partition-key "user_1234"
```

### 2. Monitor Processing

```bash
# Check Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/stream-processor" \
    --query 'logGroups[0].logGroupName'

# View recent log events
aws logs filter-log-events \
    --log-group-name "/aws/lambda/stream-processor-[suffix]" \
    --start-time $(date -d '10 minutes ago' +%s)000
```

### 3. Verify S3 Storage

```bash
# Get S3 bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name kinesis-analytics-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

# List processed data
aws s3 ls s3://$BUCKET_NAME/analytics-data/ --recursive
```

### 4. Check CloudWatch Metrics

```bash
# View stream metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Kinesis \
    --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value=$STREAM_NAME \
    --statistics Sum \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300
```

## Configuration Options

### CloudFormation Parameters

- `StreamShardCount`: Number of shards for the Kinesis stream (default: 3)
- `RetentionHours`: Data retention period in hours (default: 168)
- `LambdaBatchSize`: Records per Lambda invocation (default: 10)
- `Environment`: Deployment environment tag (default: dev)

### CDK Configuration

Edit the configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
const config = {
  shardCount: 3,
  retentionHours: 168,
  lambdaBatchSize: 10,
  environment: 'dev'
};
```

### Terraform Variables

Customize deployment by editing `terraform.tfvars`:

```hcl
stream_shard_count = 3
retention_hours    = 168
lambda_batch_size  = 10
environment       = "dev"
```

## Monitoring and Alerting

The infrastructure includes comprehensive monitoring:

### CloudWatch Alarms

- **High Incoming Records**: Alerts when record volume exceeds threshold
- **Lambda Processing Errors**: Alerts on function execution failures
- **Stream Throttling**: Monitors for write/read throttling events

### Custom Metrics

- **ProcessedRecords**: Number of records processed by Lambda
- **TotalAmount**: Sum of transaction amounts (business metric example)

### Dashboard

Access the CloudWatch dashboard through the AWS Console or get the URL from stack outputs.

## Scaling Considerations

### Shard Scaling

```bash
# Increase shard count for higher throughput
aws kinesis update-shard-count \
    --stream-name $STREAM_NAME \
    --scaling-type UNIFORM_SCALING \
    --target-shard-count 5
```

### Lambda Scaling

- **Concurrent Executions**: Lambda automatically scales based on shard count
- **Batch Size**: Adjust for latency vs. throughput optimization
- **Memory**: Increase for complex processing logic

### Cost Optimization

- **Retention Period**: Reduce for lower storage costs
- **Shard Count**: Monitor utilization and scale down during low traffic
- **S3 Storage Class**: Use Intelligent Tiering for cost optimization

## Security Features

### IAM Roles

- **Least Privilege**: Lambda role has minimal required permissions
- **Service-Specific**: Separate roles for different components
- **No Hardcoded Credentials**: Uses IAM roles for all AWS service access

### Encryption

- **In Transit**: All data encrypted during transmission
- **At Rest**: Kinesis and S3 use AWS managed encryption
- **Optional KMS**: Can be configured for additional encryption control

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name kinesis-analytics-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name kinesis-analytics-stack
```

### Using CDK

```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Lambda Function Timeout**
   - Increase timeout in function configuration
   - Optimize processing logic
   - Reduce batch size

2. **Kinesis Throttling**
   - Increase shard count
   - Optimize partition key distribution
   - Implement exponential backoff in producers

3. **High Costs**
   - Monitor shard utilization
   - Adjust retention period
   - Use S3 lifecycle policies

### Debugging Commands

```bash
# Check Lambda function configuration
aws lambda get-function \
    --function-name stream-processor-[suffix]

# View Kinesis stream details
aws kinesis describe-stream \
    --stream-name $STREAM_NAME

# Check IAM role permissions
aws iam get-role-policy \
    --role-name KinesisAnalyticsRole-[suffix] \
    --policy-name StreamProcessorPolicy
```

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../real-time-analytics-amazon-kinesis-data-streams.md)
2. Check [AWS Kinesis Data Streams documentation](https://docs.aws.amazon.com/kinesis/latest/dev/)
3. Review [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/latest/dg/)
4. Consult [CloudFormation resource reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-template-resource-type-ref.html)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and adapt security configurations for production use.