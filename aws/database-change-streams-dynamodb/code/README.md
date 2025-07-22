# Infrastructure as Code for Capturing Database Changes with DynamoDB Streams

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Capturing Database Changes with DynamoDB Streams".

## Solution Overview

This infrastructure deploys a complete real-time database change stream processing system that captures DynamoDB table modifications and processes them through AWS Lambda, enabling immediate response to data changes for fraud detection, inventory management, and user experience optimization.

## Architecture Components

- **DynamoDB Table**: Primary data store with streams enabled for change capture
- **DynamoDB Streams**: Captures item-level modifications in near real-time
- **Lambda Function**: Processes stream records and orchestrates downstream actions
- **IAM Roles & Policies**: Secure access control with least privilege principles
- **SNS Topic**: Real-time notification delivery system
- **S3 Bucket**: Durable audit log storage for compliance
- **SQS Dead Letter Queue**: Failed processing record capture and retry mechanism
- **CloudWatch Alarms**: Monitoring and alerting for system health

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Appropriate AWS permissions for:
  - DynamoDB (tables, streams)
  - Lambda (functions, event source mappings)
  - IAM (roles, policies)
  - SNS (topics, subscriptions)
  - S3 (buckets, objects)
  - SQS (queues)
  - CloudWatch (alarms, logs)
- Basic understanding of event-driven architecture and stream processing
- Email address for SNS notifications (required during deployment)

### Tool-Specific Prerequisites

- **CDK**: Node.js 18+ and AWS CDK v2 installed (`npm install -g aws-cdk`)
- **Terraform**: Terraform 1.0+ installed ([Installation Guide](https://developer.hashicorp.com/terraform/downloads))
- **CloudFormation**: AWS CLI with CloudFormation permissions

### Cost Considerations

Estimated monthly cost for moderate usage: $5-15
- DynamoDB Streams: No additional charge
- Lambda: Pay per invocation (~$0.20 per 1M requests)
- SNS: $0.50 per 1M notifications
- S3: $0.023 per GB stored
- SQS: $0.40 per 1M requests

## Quick Start

### Using CloudFormation

```bash
# Set your notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name dynamodb-streams-processing \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=${NOTIFICATION_EMAIL} \
    --capabilities CAPABILITY_IAM \
    --tags Key=Environment,Value=Production Key=Project,Value=StreamProcessing

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name dynamodb-streams-processing

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name dynamodb-streams-processing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set notification email in context
npm run cdk -- deploy \
    --context notificationEmail=your-email@example.com \
    --require-approval never

# View stack outputs
npm run cdk -- list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Set notification email environment variable
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
environment = "production"
project_name = "stream-processing"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"  # or your preferred region

# Deploy infrastructure
./scripts/deploy.sh

# The script will output resource ARNs and test the deployment
```

## Testing the Deployment

After deployment, test the stream processing with sample data:

```bash
# Get table name from outputs (replace with actual table name)
TABLE_NAME="your-dynamodb-table-name"

# Insert test data to trigger stream processing
aws dynamodb put-item \
    --table-name ${TABLE_NAME} \
    --item '{
        "UserId": {"S": "test-user-001"},
        "ActivityId": {"S": "login-001"},
        "ActivityType": {"S": "LOGIN"},
        "Timestamp": {"N": "'$(date +%s)'"},
        "IPAddress": {"S": "192.168.1.100"}
    }'

# Update the item to trigger MODIFY event
aws dynamodb update-item \
    --table-name ${TABLE_NAME} \
    --key '{
        "UserId": {"S": "test-user-001"},
        "ActivityId": {"S": "login-001"}
    }' \
    --update-expression "SET ActivityType = :type" \
    --expression-attribute-values '{
        ":type": {"S": "LOGOUT"}
    }'

# Check CloudWatch logs for processing confirmation
aws logs filter-log-events \
    --log-group-name /aws/lambda/stream-processor-* \
    --start-time $(date -d '5 minutes ago' +%s)000 \
    --filter-pattern 'Processing'
```

## Monitoring and Validation

### Check Lambda Function Execution

```bash
# View Lambda function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=your-function-name \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

### Verify S3 Audit Logs

```bash
# List audit records in S3 (replace with your bucket name)
aws s3 ls s3://your-audit-bucket/audit-logs/ --recursive

# Download and view an audit record
aws s3 cp s3://your-audit-bucket/audit-logs/path-to-record.json - | jq .
```

### Monitor Dead Letter Queue

```bash
# Check for failed processing messages
aws sqs receive-message --queue-url your-dlq-url
```

### Verify SNS Notifications

```bash
# Check SNS topic and subscription status
aws sns list-subscriptions-by-topic --topic-arn your-topic-arn

# View SNS metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/SNS \
    --metric-name NumberOfMessagesPublished \
    --dimensions Name=TopicName,Value=your-topic-name \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

## Customization

### Key Configuration Parameters

| Parameter | Description | Default | Customizable |
|-----------|-------------|---------|--------------|
| `notification_email` | Email for SNS notifications | Required | ✅ |
| `table_name` | DynamoDB table name | Auto-generated | ✅ |
| `lambda_memory` | Lambda memory allocation | 256 MB | ✅ |
| `lambda_timeout` | Lambda timeout | 60 seconds | ✅ |
| `batch_size` | Stream processing batch size | 10 | ✅ |
| `retry_attempts` | Maximum retry attempts | 3 | ✅ |
| `dlq_retention` | Dead letter queue retention | 14 days | ✅ |

### Environment-Specific Configurations

Create different parameter files for multiple environments:

```bash
# terraform.tfvars.dev
notification_email = "dev-team@example.com"
environment = "development"
lambda_memory = 128

# terraform.tfvars.prod  
notification_email = "ops-team@example.com"
environment = "production"
lambda_memory = 512
```

### Advanced Configuration Options

```bash
# CloudFormation with advanced parameters
aws cloudformation create-stack \
    --stack-name dynamodb-streams-processing \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=NotificationEmail,ParameterValue=admin@company.com \
        ParameterKey=LambdaMemorySize,ParameterValue=512 \
        ParameterKey=LambdaTimeout,ParameterValue=120 \
        ParameterKey=BatchSize,ParameterValue=25 \
        ParameterKey=ParallelizationFactor,ParameterValue=4 \
    --capabilities CAPABILITY_IAM

# Terraform with advanced variables
terraform apply \
    -var="notification_email=admin@company.com" \
    -var="lambda_memory_size=512" \
    -var="lambda_timeout=120" \
    -var="batch_size=25" \
    -var="parallelization_factor=4"
```

## Security Considerations

The infrastructure implements several security best practices:

- **Least Privilege IAM**: Lambda execution role has minimal required permissions
- **Encryption**: S3 bucket encryption enabled by default
- **VPC Security**: Optional VPC configuration for Lambda functions
- **Resource Tagging**: Comprehensive tagging for governance and cost allocation
- **Dead Letter Queue**: Secure handling of failed processing attempts
- **CloudWatch Logs**: Encrypted log storage with configurable retention

### IAM Permissions Summary

The Lambda execution role includes permissions for:
- DynamoDB stream read access
- CloudWatch Logs write access
- SNS publish permissions
- S3 object write permissions
- SQS send message permissions

## Performance Optimization

### Tuning Parameters

- **Batch Size**: Increase for higher throughput (max 100), decrease for lower latency
- **Parallelization Factor**: Adjust based on stream shard count (1-10)
- **Lambda Memory**: Increase for CPU-intensive processing (128MB-10GB)
- **Error Handling**: Configure `bisect-batch-on-function-error` for better fault tolerance

### Monitoring Key Metrics

```bash
# Monitor DynamoDB throttling
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ThrottledRequests \
    --dimensions Name=TableName,Value=${TABLE_NAME}

# Monitor Lambda duration and errors
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=${FUNCTION_NAME}
```

## Troubleshooting

### Common Issues

1. **Lambda Function Errors**:
   ```bash
   # Check function logs
   aws logs filter-log-events \
       --log-group-name /aws/lambda/your-function-name \
       --filter-pattern 'ERROR'
   ```

2. **Stream Processing Delays**:
   ```bash
   # Check stream metrics
   aws cloudwatch get-metric-statistics \
       --namespace AWS/DynamoDB \
       --metric-name UserReads \
       --dimensions Name=StreamLabel,Value=your-stream-label
   ```

3. **SNS Delivery Failures**:
   ```bash
   # Check SNS topic metrics
   aws sns get-topic-attributes --topic-arn your-topic-arn
   ```

4. **Event Source Mapping Issues**:
   ```bash
   # Check mapping status
   aws lambda list-event-source-mappings \
       --function-name your-function-name
   ```

### Debug Commands

```bash
# View complete Lambda function configuration
aws lambda get-function --function-name ${FUNCTION_NAME}

# Check DynamoDB table stream status
aws dynamodb describe-table \
    --table-name ${TABLE_NAME} \
    --query 'Table.StreamSpecification'

# Monitor dead letter queue
aws sqs get-queue-attributes \
    --queue-url ${DLQ_URL} \
    --attribute-names ApproximateNumberOfMessages
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name dynamodb-streams-processing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name dynamodb-streams-processing
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
npm run cdk -- destroy

# Python
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before destroying resources
```

## Advanced Features

### Multi-Region Deployment

For high availability across regions:

1. Deploy the infrastructure in multiple AWS regions
2. Configure DynamoDB Global Tables for cross-region replication
3. Set up cross-region event processing coordination

### Integration with Analytics

Extend the solution for real-time analytics:

1. Add Kinesis Data Firehose for data lake integration
2. Configure Amazon QuickSight for real-time dashboards
3. Implement Amazon Kinesis Data Analytics for stream aggregations

### Enhanced Error Handling

Implement sophisticated error handling:

1. Configure multiple retry policies based on error types
2. Add exponential backoff for transient failures
3. Implement custom dead letter queue processing

### Scaling Considerations

For high-throughput scenarios:

1. Monitor concurrent Lambda execution limits
2. Implement fan-out patterns for parallel processing
3. Consider Aurora Serverless for downstream data aggregation
4. Use ElastiCache for real-time caching

## Cost Optimization Strategies

### S3 Storage Classes

```bash
# Configure S3 lifecycle policies for audit logs
aws s3api put-bucket-lifecycle-configuration \
    --bucket ${S3_BUCKET_NAME} \
    --lifecycle-configuration file://lifecycle-policy.json
```

### CloudWatch Log Retention

```bash
# Set log retention to reduce costs
aws logs put-retention-policy \
    --log-group-name /aws/lambda/${FUNCTION_NAME} \
    --retention-in-days 30
```

### Lambda Provisioned Concurrency

For predictable workloads, consider provisioned concurrency to reduce cold starts:

```bash
# Configure provisioned concurrency
aws lambda put-provisioned-concurrency-config \
    --function-name ${FUNCTION_NAME} \
    --qualifier '$LATEST' \
    --provisioned-concurrency-config ProvisionedConcurrencyConfigs=10
```

## Support and Documentation

- **AWS DynamoDB Streams**: [Official Documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Streams.html)
- **AWS Lambda Event Source Mappings**: [Official Documentation](https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html)
- **Recipe Documentation**: See the original recipe markdown file for detailed implementation steps
- **Cost Calculator**: [AWS Pricing Calculator](https://calculator.aws/) for detailed cost estimates
- **AWS Well-Architected Framework**: [Serverless Applications Lens](https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/)

### Community Resources

- **AWS Samples**: [DynamoDB Streams Examples](https://github.com/aws-samples/amazon-dynamodb-streams-examples)
- **AWS Workshops**: [Event-Driven Architecture Workshop](https://event-driven-architecture.workshop.aws/)
- **AWS Blogs**: [DynamoDB Streams Best Practices](https://aws.amazon.com/blogs/database/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS service documentation.