# Infrastructure as Code for Processing Event-Driven Streams with Kinesis and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Processing Event-Driven Streams with Kinesis and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating Kinesis, Lambda, DynamoDB, IAM, SQS, CloudWatch, and SNS resources
- For CDK deployments: Node.js 14+ and npm/yarn
- For Terraform: Terraform 1.0+ installed
- Python 3.8+ for Lambda function code
- Basic understanding of streaming data concepts

### Required AWS Permissions

Your AWS credentials need permissions for:
- Kinesis Data Streams (create, describe, delete)
- Lambda (create, update, delete functions and event source mappings)
- DynamoDB (create, describe, delete tables)
- IAM (create, attach, detach, delete roles and policies)
- SQS (create, delete queues)
- CloudWatch (create, delete alarms and put metric data)
- SNS (create, delete topics and subscriptions)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name retail-event-processing \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=retail-analytics

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name retail-event-processing

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name retail-event-processing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only in region)
npx cdk bootstrap

# Preview changes
npx cdk diff

# Deploy the stack
npx cdk deploy --require-approval never

# Get stack outputs
npx cdk ls --long
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

# Bootstrap CDK (first time only in region)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk ls --long
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file (optional)
cat > terraform.tfvars << EOF
project_name = "retail-analytics"
environment = "dev"
enable_sns_notifications = true
notification_email = "your-email@example.com"
EOF

# Preview changes
terraform plan

# Apply changes
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

# Test the deployment (generates sample data)
./scripts/test-pipeline.sh

# View deployment outputs
./scripts/show-outputs.sh
```

## Testing the Deployment

After successful deployment, you can test the real-time processing pipeline:

### Send Test Events

For CloudFormation/CDK deployments:
```bash
# Get the stream name from stack outputs
STREAM_NAME=$(aws cloudformation describe-stacks \
    --stack-name retail-event-processing \
    --query 'Stacks[0].Outputs[?OutputKey==`KinesisStreamName`].OutputValue' \
    --output text)

# Send a test event
aws kinesis put-record \
    --stream-name $STREAM_NAME \
    --data '{"userId":"test-user-123","eventType":"purchase","productId":"P0001","timestamp":1640995200000}' \
    --partition-key "test-user-123"
```

For Terraform deployments:
```bash
# Get the stream name from Terraform outputs
STREAM_NAME=$(terraform output -raw kinesis_stream_name)

# Send a test event
aws kinesis put-record \
    --stream-name $STREAM_NAME \
    --data '{"userId":"test-user-123","eventType":"purchase","productId":"P0001","timestamp":1640995200000}' \
    --partition-key "test-user-123"
```

### Verify Processing

1. **Check Lambda Logs**:
```bash
# Get Lambda function name
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name retail-event-processing \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# View recent logs
aws logs tail /aws/lambda/$LAMBDA_FUNCTION --follow
```

2. **Query DynamoDB**:
```bash
# Get table name
TABLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name retail-event-processing \
    --query 'Stacks[0].Outputs[?OutputKey==`DynamoDBTableName`].OutputValue' \
    --output text)

# Scan for processed records
aws dynamodb scan --table-name $TABLE_NAME --limit 5
```

3. **Check CloudWatch Metrics**:
```bash
# View custom metrics
aws cloudwatch get-metric-statistics \
    --namespace RetailEventProcessing \
    --metric-name ProcessedEvents \
    --statistics Sum \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300
```

## Customization

### Environment Variables

All implementations support customization through variables:

- **ProjectName**: Prefix for all resource names (default: "retail-analytics")
- **Environment**: Environment tag (default: "dev")
- **KinesisShardCount**: Number of Kinesis shards (default: 1)
- **LambdaMemorySize**: Lambda memory allocation in MB (default: 256)
- **LambdaTimeout**: Lambda timeout in seconds (default: 120)
- **DynamoDBBillingMode**: DynamoDB billing mode (default: "PAY_PER_REQUEST")
- **EnableSNSNotifications**: Enable email notifications for alarms (default: false)
- **NotificationEmail**: Email for alarm notifications

### Terraform Variables Example

```hcl
# terraform.tfvars
project_name = "my-retail-pipeline"
environment = "production"
kinesis_shard_count = 3
lambda_memory_size = 512
lambda_timeout = 180
enable_sns_notifications = true
notification_email = "alerts@mycompany.com"

# Custom tags
common_tags = {
  Owner = "data-team"
  CostCenter = "analytics"
  Compliance = "SOX"
}
```

### CloudFormation Parameters Example

```bash
aws cloudformation create-stack \
    --stack-name retail-event-processing-prod \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=retail-prod \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=KinesisShardCount,ParameterValue=3 \
        ParameterKey=LambdaMemorySize,ParameterValue=512 \
        ParameterKey=EnableSNSNotifications,ParameterValue=true \
        ParameterKey=NotificationEmail,ParameterValue=alerts@mycompany.com
```

## Architecture Overview

The deployed infrastructure includes:

- **Amazon Kinesis Data Stream**: Ingests real-time event data
- **AWS Lambda Function**: Processes stream records and generates insights
- **Amazon DynamoDB Table**: Stores processed events and analytics results
- **Amazon SQS Queue**: Dead letter queue for failed processing attempts
- **CloudWatch Alarms**: Monitors processing errors and system health
- **IAM Roles and Policies**: Secure access between services
- **SNS Topic** (optional): Email notifications for critical alerts

## Monitoring and Observability

### Key Metrics to Monitor

1. **Kinesis Metrics**:
   - `IncomingRecords`: Rate of incoming data
   - `IncomingBytes`: Data volume
   - `WriteProvisionedThroughputExceeded`: Throttling events

2. **Lambda Metrics**:
   - `Invocations`: Number of function executions
   - `Duration`: Function execution time
   - `Errors`: Failed executions
   - `Throttles`: Concurrent execution limits

3. **DynamoDB Metrics**:
   - `ConsumedReadCapacityUnits`: Read usage
   - `ConsumedWriteCapacityUnits`: Write usage
   - `ThrottledRequests`: Capacity exceeded events

4. **Custom Application Metrics**:
   - `RetailEventProcessing.ProcessedEvents`: Successfully processed events
   - `RetailEventProcessing.FailedEvents`: Processing failures

### CloudWatch Dashboards

Create a custom dashboard to monitor the pipeline:

```bash
# Get stack outputs for dashboard creation
aws cloudformation describe-stacks \
    --stack-name retail-event-processing \
    --query 'Stacks[0].Outputs' > stack-outputs.json

# Create dashboard (example provided in scripts/create-dashboard.sh)
./scripts/create-dashboard.sh
```

## Security Considerations

### IAM Best Practices

- Lambda execution role follows principle of least privilege
- DynamoDB access limited to specific table operations
- Kinesis access restricted to specific stream
- CloudWatch logs access for debugging only

### Data Encryption

- Kinesis stream supports server-side encryption with AWS KMS
- DynamoDB encryption at rest enabled by default
- Lambda environment variables can be encrypted with KMS

### Network Security

- All services operate within AWS managed network
- No public endpoints exposed
- VPC deployment option available for enhanced isolation

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**:
   - Increase memory allocation or timeout values
   - Optimize processing logic
   - Check for external API dependencies

2. **DynamoDB Throttling**:
   - Switch to on-demand billing mode
   - Increase provisioned capacity
   - Optimize partition key distribution

3. **Kinesis Shard Limits**:
   - Monitor shard utilization
   - Implement resharding strategy
   - Consider Kinesis Enhanced Fan-out

4. **High Error Rates**:
   - Check CloudWatch Logs for specific errors
   - Validate input data format
   - Review IAM permissions

### Debug Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name $LAMBDA_FUNCTION

# View recent CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Check DynamoDB table status
aws dynamodb describe-table --table-name $TABLE_NAME

# Monitor Kinesis stream health
aws kinesis describe-stream --stream-name $STREAM_NAME
```

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

- **Kinesis Data Stream**: ~$15/month (1 shard)
- **Lambda**: ~$5-20/month (depends on invocations)
- **DynamoDB**: ~$10-50/month (depends on storage and requests)
- **CloudWatch**: ~$5/month (logs and metrics)
- **Total**: ~$35-90/month for moderate usage

### Cost Optimization Tips

1. **Right-size Kinesis shards** based on actual throughput
2. **Use DynamoDB on-demand billing** for variable workloads
3. **Optimize Lambda memory allocation** for your processing needs
4. **Set up CloudWatch log retention policies** to control log storage costs
5. **Monitor and delete unused resources** regularly

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name retail-event-processing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name retail-event-processing

# Verify deletion
aws cloudformation describe-stacks --stack-name retail-event-processing
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npx cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate  # If using virtual environment
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
./scripts/verify-cleanup.sh
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:
- Kinesis Data Stream
- Lambda Function and Event Source Mapping
- DynamoDB Table
- SQS Queue (Dead Letter Queue)
- IAM Roles and Policies
- CloudWatch Alarms
- SNS Topic and Subscriptions (if created)

## Support and Documentation

- **Original Recipe**: See `../real-time-data-processing-with-kinesis-lambda.md`
- **AWS Kinesis Documentation**: https://docs.aws.amazon.com/kinesis/
- **AWS Lambda Documentation**: https://docs.aws.amazon.com/lambda/
- **AWS DynamoDB Documentation**: https://docs.aws.amazon.com/dynamodb/
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/
- **AWS CDK Documentation**: https://docs.aws.amazon.com/cdk/

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation.