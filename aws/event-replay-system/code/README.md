# Infrastructure as Code for Event Replay with EventBridge Archive

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event Replay with EventBridge Archive".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive event replay system that includes:

- Custom EventBridge event bus for isolated event processing
- Event archive with selective filtering for order and user events
- Lambda function for processing both original and replayed events
- IAM roles and policies with least privilege access
- S3 bucket for logs and automation scripts
- CloudWatch monitoring and alerting

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - EventBridge (event buses, rules, archives, replays)
  - Lambda (functions, roles, permissions)
  - IAM (roles, policies, attachments)
  - S3 (buckets, objects)
  - CloudWatch (alarms, logs)
- Node.js 18+ and npm (for CDK TypeScript)
- Python 3.9+ and pip (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name eventbridge-replay-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name eventbridge-replay-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name eventbridge-replay-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy EventBridgeReplayStack

# Get stack outputs
cdk list
```

### Using CDK Python
```bash
# Create virtual environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy EventBridgeReplayStack

# Get stack outputs
cdk list
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
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

# The script will output important resource ARNs and names
```

## Post-Deployment Testing

After deployment, test the event replay mechanism:

1. **Generate Test Events**:
   ```bash
   # Get event bus name from stack outputs
   EVENT_BUS_NAME=$(aws cloudformation describe-stacks \
       --stack-name eventbridge-replay-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' \
       --output text)
   
   # Send test events
   aws events put-events \
       --entries Source=myapp.orders,DetailType="Order Created",Detail='{"orderId":"test-123","amount":250,"customerId":"customer-456"}' \
       --event-bus-name $EVENT_BUS_NAME
   ```

2. **Wait for Archive Population**:
   ```bash
   # Archives have up to 10 minute delay
   sleep 600
   
   # Check archive status
   ARCHIVE_NAME=$(aws cloudformation describe-stacks \
       --stack-name eventbridge-replay-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`ArchiveName`].OutputValue' \
       --output text)
   
   aws events describe-archive --archive-name $ARCHIVE_NAME
   ```

3. **Test Event Replay**:
   ```bash
   # Start replay for the last hour
   START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
   END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
   
   aws events start-replay \
       --replay-name test-replay-$(date +%s) \
       --event-source-arn $(aws events describe-archive --archive-name $ARCHIVE_NAME --query 'SourceArn' --output text) \
       --event-start-time $START_TIME \
       --event-end-time $END_TIME \
       --destination '{"Arn":"'$(aws events describe-archive --archive-name $ARCHIVE_NAME --query 'SourceArn' --output text)'"}'
   ```

## Monitoring and Observability

### CloudWatch Logs
Monitor Lambda function execution:
```bash
# View recent Lambda logs
aws logs tail /aws/lambda/[FUNCTION_NAME] --follow
```

### EventBridge Metrics
Monitor event processing metrics:
```bash
# Get event bus metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --dimensions Name=EventBusName,Value=$EVENT_BUS_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

### Archive Status
Check archive health:
```bash
# Monitor archive statistics
aws events describe-archive \
    --archive-name $ARCHIVE_NAME \
    --query '{Name:ArchiveName,State:State,EventCount:EventCount,SizeBytes:SizeBytes}'
```

## Customization

### Key Variables/Parameters

#### CloudFormation Parameters
- `Environment`: Deployment environment (dev, staging, prod)
- `RetentionDays`: Archive retention period (default: 30)
- `LogRetentionDays`: CloudWatch log retention (default: 14)

#### CDK Configuration
- `environment`: Target AWS environment
- `archiveRetentionDays`: Event archive retention
- `lambdaTimeout`: Lambda function timeout
- `lambdaMemorySize`: Lambda memory allocation

#### Terraform Variables
- `environment`: Environment tag for resources
- `archive_retention_days`: Archive retention period
- `lambda_timeout`: Lambda function timeout
- `lambda_memory_size`: Lambda memory allocation
- `log_retention_days`: CloudWatch log retention

### Customizing Event Patterns

Modify the event patterns in each implementation to match your specific event types:

```json
{
  "source": ["myapp.orders", "myapp.users", "myapp.inventory"],
  "detail-type": ["Order Created", "User Registered", "Inventory Updated"]
}
```

### Extending Lambda Processing

The Lambda function can be enhanced to:
- Implement different logic for replayed events
- Add custom metrics and logging
- Integrate with external systems
- Implement event deduplication

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Minimal required permissions
- **Resource-Based Policies**: EventBridge and Lambda permissions
- **Encryption**: S3 bucket encryption enabled
- **Network Security**: VPC configuration available for Lambda
- **Audit Logging**: CloudWatch logs for all operations

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

- EventBridge: $1.00 per million events
- Lambda: $0.20 per million requests + compute charges
- S3: $0.023 per GB storage
- CloudWatch: $0.50 per GB ingested
- Archive: $0.10 per GB per month

### Cost Optimization Tips

1. **Optimize Archive Retention**: Set appropriate retention periods
2. **Filter Events**: Use selective event patterns to reduce archive size
3. **Monitor Usage**: Set up billing alerts for unexpected costs
4. **Cleanup**: Regularly remove old replays and unused resources

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name eventbridge-replay-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name eventbridge-replay-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy EventBridgeReplayStack

# Confirm deletion when prompted
```

### Using Terraform
```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will remove all created resources
```

## Troubleshooting

### Common Issues

1. **Archive Not Populating**:
   - Check event patterns match your events
   - Verify events are being sent to the correct event bus
   - Archives have up to 10 minute delay

2. **Replay Not Starting**:
   - Ensure archive has events in the requested time range
   - Check IAM permissions for replay operations
   - Verify destination event bus exists

3. **Lambda Function Errors**:
   - Check CloudWatch logs for error details
   - Verify Lambda execution role permissions
   - Ensure event payload matches expected format

4. **Permission Errors**:
   - Verify IAM roles have necessary permissions
   - Check resource-based policies
   - Ensure cross-service permissions are configured

### Debug Commands

```bash
# Check EventBridge rule targets
aws events list-targets-by-rule \
    --rule [RULE_NAME] \
    --event-bus-name [EVENT_BUS_NAME]

# Test event patterns
aws events test-event-pattern \
    --event-pattern '{"source":["myapp.orders"]}' \
    --event '{"source":"myapp.orders","detail-type":"Order Created"}'

# List recent replays
aws events list-replays \
    --name-prefix [REPLAY_PREFIX]
```

## Advanced Features

### Automated Replay Scripts

The S3 bucket includes automation scripts for:
- Scheduled replay operations
- Bulk replay management
- Replay monitoring and alerting

### Cross-Region Deployment

For multi-region deployments:
1. Deploy in multiple regions
2. Configure cross-region event replication
3. Implement region-specific replay strategies

### Integration with CI/CD

Include replay testing in your deployment pipeline:
1. Deploy infrastructure changes
2. Run replay tests against archived events
3. Validate system behavior with replayed events

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS EventBridge documentation
4. Review CloudWatch logs for detailed error information

## References

- [AWS EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [EventBridge Archive Documentation](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-archive.html)
- [EventBridge Replay Documentation](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-replay.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)