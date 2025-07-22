# Infrastructure as Code for Event Sourcing with EventBridge and DynamoDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event Sourcing with EventBridge and DynamoDB".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate IAM permissions for EventBridge, DynamoDB, Lambda, IAM, SQS, and CloudWatch
- One of the following tools installed (depending on your chosen deployment method):
  - AWS CLI (for CloudFormation and scripts)
  - Node.js 18+ and npm (for CDK TypeScript)
  - Python 3.8+ and pip (for CDK Python)
  - Terraform >= 1.0 (for Terraform)
- Understanding of event sourcing patterns and CQRS concepts
- Estimated cost: $10-15 per month for development/testing workloads

## Architecture Overview

This implementation creates a complete event sourcing architecture with:

- **EventBridge Custom Bus**: Central event routing with archiving capabilities
- **DynamoDB Event Store**: Immutable event storage with DynamoDB Streams
- **DynamoDB Read Model**: Optimized projections for queries
- **Lambda Functions**: Command handler, projection handler, and query handler
- **SQS Dead Letter Queue**: Failed event processing resilience
- **CloudWatch Monitoring**: Comprehensive observability and alerting
- **IAM Roles**: Least privilege security configuration

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name event-sourcing-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name event-sourcing-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name event-sourcing-stack \
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

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
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

# Deploy the infrastructure
./scripts/deploy.sh

# The script will create all resources and display important outputs
```

## Testing the Deployment

After deployment, test the event sourcing system:

### 1. Test Account Creation

```bash
# Get the command handler function name from outputs
COMMAND_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name event-sourcing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`CommandHandlerFunction`].OutputValue' \
    --output text)

# Test account creation
aws lambda invoke \
    --function-name $COMMAND_FUNCTION \
    --payload '{
        "aggregateId": "account-123",
        "eventType": "AccountCreated",
        "eventData": {
            "accountId": "account-123",
            "customerId": "customer-456",
            "accountType": "checking",
            "createdAt": "2024-01-15T10:00:00Z"
        }
    }' \
    response.json

# Check response
cat response.json
```

### 2. Test Transaction Processing

```bash
# Test transaction processing
aws lambda invoke \
    --function-name $COMMAND_FUNCTION \
    --payload '{
        "aggregateId": "account-123",
        "eventType": "TransactionProcessed",
        "eventData": {
            "transactionId": "tx-789",
            "amount": 100.50,
            "type": "deposit",
            "timestamp": "2024-01-15T10:30:00Z"
        }
    }' \
    response2.json

# Check response
cat response2.json
```

### 3. Verify Event Store

```bash
# Get the event store table name from outputs
EVENT_STORE_TABLE=$(aws cloudformation describe-stacks \
    --stack-name event-sourcing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`EventStoreTable`].OutputValue' \
    --output text)

# Query events from event store
aws dynamodb query \
    --table-name $EVENT_STORE_TABLE \
    --key-condition-expression "AggregateId = :aid" \
    --expression-attribute-values '{":aid": {"S": "account-123"}}' \
    --scan-index-forward
```

### 4. Test Query Capabilities

```bash
# Get the query handler function name from outputs
QUERY_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name event-sourcing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`QueryHandlerFunction`].OutputValue' \
    --output text)

# Test state reconstruction
aws lambda invoke \
    --function-name $QUERY_FUNCTION \
    --payload '{
        "queryType": "reconstructState",
        "aggregateId": "account-123"
    }' \
    reconstruction.json

# Check reconstruction result
cat reconstruction.json
```

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates CloudWatch alarms for:
- DynamoDB write throttles on event store
- Lambda function errors
- EventBridge failed invocations

### Viewing Metrics

```bash
# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "event-sourcing"

# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/event-sourcing"
```

### Event Archive and Replay

```bash
# Get the archive name from outputs
ARCHIVE_NAME=$(aws cloudformation describe-stacks \
    --stack-name event-sourcing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`EventArchive`].OutputValue' \
    --output text)

# Start an event replay (example for last hour)
aws events start-replay \
    --replay-name "test-replay-$(date +%s)" \
    --event-source-arn "arn:aws:events:$(aws configure get region):$(aws sts get-caller-identity --query Account --output text):archive/$ARCHIVE_NAME" \
    --event-start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --event-end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --destination "Arn=arn:aws:events:$(aws configure get region):$(aws sts get-caller-identity --query Account --output text):event-bus/$(aws cloudformation describe-stacks --stack-name event-sourcing-stack --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' --output text)"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name event-sourcing-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name event-sourcing-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Customization

### Environment Variables

The infrastructure can be customized using the following parameters:

- **Environment**: Deployment environment (dev, staging, prod)
- **RetentionDays**: Event archive retention period (default: 365 days)
- **ReadCapacityUnits**: DynamoDB read capacity (default: 10)
- **WriteCapacityUnits**: DynamoDB write capacity (default: 10)

### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name event-sourcing-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=prod \
        ParameterKey=RetentionDays,ParameterValue=2555 \
        ParameterKey=ReadCapacityUnits,ParameterValue=20 \
        ParameterKey=WriteCapacityUnits,ParameterValue=20
```

### CDK Context

```bash
# Set context for CDK deployment
cdk deploy -c environment=prod -c retentionDays=2555
```

### Terraform Variables

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
environment = "prod"
retention_days = 2555
read_capacity_units = 20
write_capacity_units = 20
EOF

terraform apply -var-file="terraform.tfvars"
```

## Advanced Configuration

### Cross-Region Replication

For production deployments, consider implementing cross-region replication:

1. Deploy DynamoDB Global Tables for the event store
2. Set up EventBridge replication rules
3. Configure cross-region monitoring

### Security Hardening

- Enable DynamoDB encryption at rest
- Configure EventBridge with KMS encryption
- Implement VPC endpoints for private communication
- Use AWS Secrets Manager for sensitive configuration

### Performance Optimization

- Implement DynamoDB on-demand billing for variable workloads
- Configure Lambda reserved concurrency
- Use DynamoDB DAX for read-heavy workloads
- Implement event batching for high-throughput scenarios

## Cost Optimization

### Monitoring Costs

```bash
# Check DynamoDB costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE

# Monitor Lambda costs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/event-sourcing" \
    --query 'logGroups[*].[logGroupName,storedBytes]'
```

### Cost Reduction Strategies

- Use DynamoDB on-demand for unpredictable workloads
- Implement intelligent archiving policies
- Optimize Lambda memory allocation
- Use reserved capacity for predictable workloads

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**
   - Verify the deployment role has necessary permissions
   - Check CloudTrail logs for specific permission denials

2. **DynamoDB Throttling**
   - Monitor CloudWatch metrics for throttling events
   - Consider increasing provisioned capacity or switching to on-demand

3. **Lambda Timeouts**
   - Increase Lambda timeout values
   - Optimize function code for better performance

4. **EventBridge Delivery Failures**
   - Check dead letter queue for failed events
   - Verify target permissions and configurations

### Debugging Commands

```bash
# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/event-sourcing-command-handler" \
    --start-time $(date -d '1 hour ago' +%s)000

# Check EventBridge metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Sum

# Check DynamoDB metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedReadCapacityUnits \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Sum
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation
3. Verify IAM permissions and resource configurations
4. Monitor CloudWatch logs and metrics
5. Test with minimal event payloads first

## Related Resources

- [AWS EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Event Sourcing Pattern](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-data-persistence/service-per-team.html)
- [CQRS Pattern](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-data-persistence/cqrs-pattern.html)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's security and compliance requirements.