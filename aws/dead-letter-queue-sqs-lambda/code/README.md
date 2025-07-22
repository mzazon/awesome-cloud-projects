# Infrastructure as Code for Dead Letter Queue Processing with SQS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Dead Letter Queue Processing with SQS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive dead letter queue processing system that:
- Captures failed messages automatically using SQS dead letter queues
- Analyzes error patterns with intelligent categorization
- Provides automated retry mechanisms for transient failures
- Monitors system health with CloudWatch alarms and metrics
- Ensures zero message loss for critical business processes

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - SQS (CreateQueue, SendMessage, ReceiveMessage, DeleteQueue)
  - Lambda (CreateFunction, InvokeFunction, DeleteFunction)
  - IAM (CreateRole, AttachRolePolicy, PassRole)
  - CloudWatch (PutMetricData, PutMetricAlarm)
  - Logs (CreateLogGroup, PutLogEvents)
- For CDK implementations: Node.js 18+ and Python 3.9+
- For Terraform: Terraform 1.5+ installed
- Estimated cost: $5-10 per month for development workloads

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name dlq-processing-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=RandomSuffix,ParameterValue=$(openssl rand -hex 3)

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name dlq-processing-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name dlq-processing-stack \
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

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
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

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Testing the Solution

After deployment, test the dead letter queue processing:

```bash
# Get queue URL from stack outputs
MAIN_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name dlq-processing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`MainQueueUrl`].OutputValue' \
    --output text)

# Send test messages
for i in {1..10}; do
    ORDER_VALUE=$((RANDOM % 2000 + 50))
    aws sqs send-message \
        --queue-url ${MAIN_QUEUE_URL} \
        --message-body '{
            "orderId": "ORD-'$(date +%s)'-'${i}'",
            "orderValue": '${ORDER_VALUE}',
            "customerId": "CUST-'${i}'",
            "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
        }'
done

# Monitor processing (wait 30 seconds)
sleep 30

# Check queue depths
DLQ_URL=$(aws cloudformation describe-stacks \
    --stack-name dlq-processing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DLQUrl`].OutputValue' \
    --output text)

echo "Main queue messages:"
aws sqs get-queue-attributes \
    --queue-url ${MAIN_QUEUE_URL} \
    --attribute-names ApproximateNumberOfMessages \
    --query 'Attributes.ApproximateNumberOfMessages'

echo "DLQ messages:"
aws sqs get-queue-attributes \
    --queue-url ${DLQ_URL} \
    --attribute-names ApproximateNumberOfMessages \
    --query 'Attributes.ApproximateNumberOfMessages'
```

## Monitoring and Observability

### CloudWatch Logs
```bash
# View main processor logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/order-processor-$(terraform output -raw random_suffix)" \
    --start-time $(date -d '10 minutes ago' +%s)000

# View DLQ monitor logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/dlq-monitor-$(terraform output -raw random_suffix)" \
    --start-time $(date -d '10 minutes ago' +%s)000
```

### CloudWatch Metrics
```bash
# Check DLQ custom metrics
aws cloudwatch get-metric-statistics \
    --namespace DLQ/Processing \
    --metric-name FailedMessages \
    --start-time $(date -d '30 minutes ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Sum
```

### CloudWatch Alarms
```bash
# Check alarm status
aws cloudwatch describe-alarms \
    --alarm-name-prefix "DLQ-"
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name dlq-processing-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name dlq-processing-stack
```

### Using CDK
```bash
# From the cdk-typescript/ or cdk-python/ directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Key Parameters

Each implementation supports customization through variables/parameters:

- **RandomSuffix**: Unique identifier for resource names
- **QueueVisibilityTimeout**: SQS message visibility timeout (default: 300 seconds)
- **MessageRetentionPeriod**: How long messages are retained (default: 14 days)
- **MaxReceiveCount**: Maximum retries before sending to DLQ (default: 3)
- **LambdaTimeout**: Lambda function timeout (default: 30-60 seconds)
- **LambdaMemorySize**: Lambda memory allocation (default: 128-256 MB)

### Environment-Specific Configurations

For different environments (dev/staging/prod), modify:

```bash
# CloudFormation
aws cloudformation create-stack \
    --stack-name dlq-processing-prod \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=prod \
        ParameterKey=MaxReceiveCount,ParameterValue=5 \
        ParameterKey=LambdaMemorySize,ParameterValue=512

# Terraform
terraform apply -var="environment=prod" -var="max_receive_count=5"

# CDK (set in cdk.json or environment variables)
export ENVIRONMENT=prod
export MAX_RECEIVE_COUNT=5
cdk deploy
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Lambda functions have minimal required permissions
- **Encryption**: SQS queues support encryption at rest (can be enabled via parameters)
- **VPC Support**: Lambda functions can be deployed in VPC for additional network isolation
- **Resource-based Policies**: SQS queues restrict access to authorized principals only

### Enabling Encryption
```bash
# CloudFormation parameter
--parameters ParameterKey=EnableEncryption,ParameterValue=true

# Terraform variable
terraform apply -var="enable_encryption=true"
```

## Troubleshooting

### Common Issues

1. **Lambda Function Timeout**
   ```bash
   # Increase timeout in parameters
   --parameters ParameterKey=LambdaTimeout,ParameterValue=60
   ```

2. **Insufficient IAM Permissions**
   ```bash
   # Check CloudTrail logs for denied API calls
   aws logs filter-log-events \
       --log-group-name CloudTrail/APIGateway \
       --filter-pattern "ERROR"
   ```

3. **DLQ Not Receiving Messages**
   ```bash
   # Verify redrive policy configuration
   aws sqs get-queue-attributes \
       --queue-url ${MAIN_QUEUE_URL} \
       --attribute-names RedrivePolicy
   ```

4. **High Error Rates**
   ```bash
   # Analyze error patterns in CloudWatch Logs Insights
   aws logs start-query \
       --log-group-name "/aws/lambda/order-processor-${RANDOM_SUFFIX}" \
       --start-time $(date -d '1 hour ago' +%s) \
       --end-time $(date +%s) \
       --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20'
   ```

### Performance Optimization

- **Batch Size Tuning**: Adjust SQS event source mapping batch size based on processing time
- **Concurrent Executions**: Monitor Lambda concurrent executions and adjust reserved concurrency
- **Memory Optimization**: Use AWS Lambda Power Tuning to find optimal memory settings
- **Cold Start Reduction**: Consider using provisioned concurrency for consistent performance

## Cost Optimization

### Resource Costs (Estimated Monthly)

- **SQS**: ~$0.01 per 1M requests
- **Lambda**: ~$0.20 per 1M requests + compute time
- **CloudWatch**: ~$0.50 per alarm + log storage
- **Total**: $5-10 for development workloads

### Cost Reduction Strategies

1. **Adjust Message Retention**: Reduce retention period for non-critical queues
2. **Optimize Lambda Memory**: Use appropriate memory allocation
3. **Batch Processing**: Increase batch sizes to reduce Lambda invocations
4. **Log Management**: Set CloudWatch Logs retention policies

## Extensions and Enhancements

Consider these enhancements for production deployments:

1. **Multi-Region Setup**: Deploy across multiple AWS regions for high availability
2. **Advanced Monitoring**: Integrate with AWS X-Ray for distributed tracing
3. **Notification Integration**: Add SNS topics for alert notifications
4. **Message Enrichment**: Add external service integrations for message enhancement
5. **Automated Remediation**: Implement self-healing capabilities for common errors

## Support

- For infrastructure code issues: Review the deployment logs and AWS documentation
- For recipe questions: Refer to the original recipe documentation
- For AWS service questions: Consult the [AWS SQS Documentation](https://docs.aws.amazon.com/sqs/) and [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)

## Version Information

- **Recipe Version**: 1.1
- **Generator Version**: 1.3
- **Last Updated**: 2025-07-12
- **AWS CLI Version**: 2.x required
- **CDK Version**: 2.x (latest stable)
- **Terraform Version**: 1.5+ required