# Infrastructure as Code for Processing Ordered Messages with SQS FIFO and Dead Letter Queues

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Processing Ordered Messages with SQS FIFO and Dead Letter Queues".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a robust ordered message processing system using:

- **SQS FIFO Queues**: Main processing queue with strict ordering and deduplication
- **Dead Letter Queue**: FIFO queue for handling poison messages
- **Lambda Functions**: Message processor, poison message handler, and replay functionality
- **DynamoDB**: Order state management with GSI for message group tracking
- **S3**: Message archival for forensic analysis and compliance
- **CloudWatch**: Comprehensive monitoring, metrics, and alerting
- **SNS**: Real-time operational alerts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- AWS account with permissions for SQS, Lambda, DynamoDB, CloudWatch, SNS, S3, and IAM
- Node.js 16+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Understanding of FIFO message ordering and dead letter queue concepts
- Estimated cost: $15-20 for testing resources (delete after completion)

## Quick Start

### Using CloudFormation

```bash
# Create the infrastructure stack
aws cloudformation create-stack \
    --stack-name fifo-processing-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-fifo-project

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name fifo-processing-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name fifo-processing-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=my-fifo-project

# View outputs
cdk output
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

# Deploy the stack
cdk deploy --parameters projectName=my-fifo-project

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_name=my-fifo-project"

# Apply the configuration
terraform apply -var="project_name=my-fifo-project"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# - Validate prerequisites
# - Create all necessary resources
# - Configure event source mappings
# - Set up monitoring and alerts
# - Provide deployment summary
```

## Testing the Solution

After deployment, test the ordered message processing system:

### Send Test Messages

```bash
# Get queue URL from outputs
MAIN_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name fifo-processing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`MainQueueUrl`].OutputValue' \
    --output text)

# Send valid messages in different groups
for group in "trading-group-1" "settlement-group-1" "order-group-1"; do
    for i in {1..3}; do
        MESSAGE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
        aws sqs send-message \
            --queue-url ${MAIN_QUEUE_URL} \
            --message-body "{
                \"orderId\": \"order-${group}-${i}\",
                \"orderType\": \"BUY\",
                \"amount\": $(( RANDOM % 1000 + 100 )),
                \"symbol\": \"STOCK${i}\",
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }" \
            --message-group-id ${group} \
            --message-deduplication-id ${MESSAGE_ID}
    done
done
```

### Send Poison Messages

```bash
# Test error handling with invalid messages
POISON_SCENARIOS=(
    '{"orderId": "poison-1", "orderType": "BUY", "amount": -100, "timestamp": "2025-01-11T12:00:00Z"}'
    '{"orderId": "poison-2", "orderType": "INVALID", "timestamp": "2025-01-11T12:00:00Z"}'
    '{"orderType": "BUY", "amount": 500, "timestamp": "2025-01-11T12:00:00Z"}'
)

for i in "${!POISON_SCENARIOS[@]}"; do
    MESSAGE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    aws sqs send-message \
        --queue-url ${MAIN_QUEUE_URL} \
        --message-body "${POISON_SCENARIOS[$i]}" \
        --message-group-id "poison-test-group" \
        --message-deduplication-id ${MESSAGE_ID}
done
```

### Monitor Results

```bash
# Check processed orders in DynamoDB
TABLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name fifo-processing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderTableName`].OutputValue' \
    --output text)

aws dynamodb scan \
    --table-name ${TABLE_NAME} \
    --projection-expression "OrderId, OrderType, Amount, #status, ProcessedAt" \
    --expression-attribute-names '{"#status": "Status"}' \
    --max-items 10

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace "FIFO/MessageProcessing" \
    --metric-name "ProcessedMessages" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name fifo-processing-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name fifo-processing-stack
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_name=my-fifo-project"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# The script will:
# - Delete Lambda functions and event source mappings
# - Remove SQS queues
# - Delete CloudWatch alarms
# - Remove DynamoDB table
# - Empty and delete S3 bucket
# - Clean up IAM roles and policies
```

## Customization

### Key Parameters

All implementations support these customization parameters:

- **Project Name**: Base name for all resources (default: `fifo-processing`)
- **AWS Region**: Target deployment region
- **Environment**: Environment tag (dev, staging, prod)
- **Message Retention**: Queue message retention period (1-14 days)
- **Lambda Timeout**: Function timeout in seconds (60-900)
- **Lambda Memory**: Function memory allocation (128-10240 MB)
- **DLQ Max Receive Count**: Maximum retry attempts before DLQ (1-1000)

### CloudFormation Parameters

```yaml
Parameters:
  ProjectName:
    Type: String
    Default: fifo-processing
    Description: Base name for all resources
  
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
    Description: Environment name
  
  MessageRetentionPeriod:
    Type: Number
    Default: 1209600
    MinValue: 60
    MaxValue: 1209600
    Description: Message retention period in seconds (14 days max)
```

### Terraform Variables

```hcl
variable "project_name" {
  description = "Base name for all resources"
  type        = string
  default     = "fifo-processing"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}
```

## Monitoring and Observability

The solution includes comprehensive monitoring:

### CloudWatch Metrics

- **ProcessedMessages**: Count of successfully processed messages
- **FailedMessages**: Count of failed message processing attempts
- **ProcessingTime**: Message processing latency in milliseconds
- **PoisonMessageCount**: Count of messages sent to DLQ

### CloudWatch Alarms

- **High Failure Rate**: Triggers when failure rate exceeds threshold
- **Poison Messages Detected**: Alerts on any messages in DLQ
- **High Processing Latency**: Monitors processing performance

### CloudWatch Logs

All Lambda functions log to CloudWatch with structured logging for:
- Message processing events
- Error details and stack traces
- Performance metrics
- Business logic outcomes

## Security Considerations

### IAM Roles and Policies

- **Principle of Least Privilege**: Each Lambda function has minimal required permissions
- **Resource-Scoped Policies**: All policies are scoped to specific resources
- **No Hardcoded Credentials**: All access uses IAM roles and temporary credentials

### Data Protection

- **Encryption in Transit**: All service-to-service communication is encrypted
- **Encryption at Rest**: DynamoDB and S3 use AWS managed encryption
- **Message Deduplication**: Content-based deduplication prevents message replay attacks

### Network Security

- **VPC Deployment**: Lambda functions can be deployed in private subnets
- **Security Groups**: Restrictive security group rules for VPC resources
- **Access Logging**: All API calls are logged via CloudTrail

## Troubleshooting

### Common Issues

1. **Messages Not Processing**
   - Check Lambda function logs in CloudWatch
   - Verify event source mapping configuration
   - Ensure IAM permissions are correct

2. **High Latency**
   - Monitor Lambda cold starts
   - Check DynamoDB throttling metrics
   - Review message batch sizes

3. **Poison Messages**
   - Review archived messages in S3
   - Check poison message handler logs
   - Verify message format and content

### Debug Commands

```bash
# Check Lambda function status
aws lambda get-function --function-name your-function-name

# View recent logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/your-function-name \
    --order-by LastEventTime \
    --descending

# Get queue attributes
aws sqs get-queue-attributes \
    --queue-url your-queue-url \
    --attribute-names All
```

## Performance Optimization

### FIFO Queue Optimization

- **Message Grouping**: Design message groups for optimal parallelism
- **Batch Size**: Configure appropriate batch sizes for Lambda triggers
- **Visibility Timeout**: Set appropriate timeout based on processing duration

### Lambda Optimization

- **Reserved Concurrency**: Prevent overwhelming downstream systems
- **Memory Allocation**: Right-size memory for optimal performance/cost
- **Connection Pooling**: Reuse database connections across invocations

### DynamoDB Optimization

- **Provisioned Capacity**: Monitor and adjust based on workload
- **Global Secondary Indexes**: Optimize GSI design for query patterns
- **Item Size**: Keep item sizes under 400KB for optimal performance

## Cost Optimization

### Expected Costs (per month)

- **SQS FIFO**: $0.50 per million requests
- **Lambda**: $0.20 per million requests + compute time
- **DynamoDB**: Based on provisioned capacity and storage
- **S3**: $0.023 per GB stored (Standard class)
- **CloudWatch**: Based on log retention and custom metrics

### Cost Reduction Strategies

- Use DynamoDB on-demand for variable workloads
- Implement S3 lifecycle policies for archived messages
- Optimize Lambda memory allocation
- Set appropriate log retention periods

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for solution context
2. **AWS Documentation**: Check service-specific AWS documentation
3. **Community Support**: Use AWS forums and Stack Overflow
4. **Professional Support**: Contact AWS Support for production issues

## Additional Resources

- [AWS SQS FIFO Queue Documentation](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues.html)
- [AWS Lambda Event Source Mapping](https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [CloudWatch Metrics and Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/working_with_metrics.html)