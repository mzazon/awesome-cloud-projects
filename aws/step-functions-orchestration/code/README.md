# Infrastructure as Code for Step Functions Microservices Orchestration

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Step Functions Microservices Orchestration".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - Step Functions state machines
  - Lambda functions
  - IAM roles and policies
  - EventBridge rules
- Basic understanding of microservices orchestration patterns
- Estimated cost: $10-15 for Step Functions executions and Lambda invocations during testing

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name microservices-stepfunctions-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-microservices

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name microservices-stepfunctions-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name microservices-stepfunctions-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get stack outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get stack outputs
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

# Check deployment status
aws stepfunctions list-state-machines \
    --query 'stateMachines[?contains(name, `microservices`)].{Name:name,Status:status}'
```

## Testing the Deployment

### Test Individual Lambda Functions

```bash
# Test user service
aws lambda invoke \
    --function-name microservices-stepfn-user-service \
    --payload '{"userId": "test123"}' \
    response.json && cat response.json

# Test order service
aws lambda invoke \
    --function-name microservices-stepfn-order-service \
    --payload '{"orderData":{"items":[{"productId":"PROD001","quantity":2,"price":29.99}]},"userData":{"userId":"test123"}}' \
    response.json && cat response.json
```

### Execute Step Functions Workflow

```bash
# Get the state machine ARN
STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
    --query 'stateMachines[?contains(name, `microservices`)].stateMachineArn' \
    --output text)

# Start workflow execution
aws stepfunctions start-execution \
    --state-machine-arn $STATE_MACHINE_ARN \
    --input '{
      "userId": "test123",
      "orderData": {
        "items": [
          {"productId": "PROD001", "quantity": 2, "price": 29.99},
          {"productId": "PROD002", "quantity": 1, "price": 49.99}
        ]
      }
    }'

# Monitor execution
aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --max-items 5
```

### Test EventBridge Integration

```bash
# Send test event to trigger workflow
aws events put-events \
    --entries Source=microservices.orders,DetailType="Order Submitted",Detail='{"userId":"test123","orderData":{"items":[{"productId":"PROD001","quantity":1,"price":99.99}]}}'

# Check for new executions
aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --status-filter RUNNING,SUCCEEDED
```

## Monitoring and Troubleshooting

### View Step Functions Execution History

```bash
# Get execution ARN from recent executions
EXECUTION_ARN=$(aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --max-items 1 \
    --query 'executions[0].executionArn' \
    --output text)

# Get execution history
aws stepfunctions get-execution-history \
    --execution-arn $EXECUTION_ARN
```

### Monitor Lambda Function Logs

```bash
# View recent log events for user service
aws logs describe-log-streams \
    --log-group-name /aws/lambda/microservices-stepfn-user-service \
    --order-by LastEventTime \
    --descending --max-items 1

# Get latest log stream
LATEST_STREAM=$(aws logs describe-log-streams \
    --log-group-name /aws/lambda/microservices-stepfn-user-service \
    --order-by LastEventTime \
    --descending --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text)

# View log events
aws logs get-log-events \
    --log-group-name /aws/lambda/microservices-stepfn-user-service \
    --log-stream-name $LATEST_STREAM
```

### Check EventBridge Rules

```bash
# List EventBridge rules
aws events list-rules \
    --name-prefix microservices

# Check rule targets
aws events list-targets-by-rule \
    --rule microservices-stepfn-trigger
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name microservices-stepfunctions-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name microservices-stepfunctions-stack
```

### Using CDK (AWS)

```bash
# From the appropriate CDK directory (typescript or python)
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
aws stepfunctions list-state-machines \
    --query 'stateMachines[?contains(name, `microservices`)]'
```

## Customization

### CloudFormation Parameters

- **ProjectName**: Prefix for all resource names (default: microservices-stepfn)
- **Environment**: Environment tag for resources (default: dev)

### CDK Configuration

Modify the following in the CDK code:
- Resource naming patterns in the stack constructor
- Lambda function configurations (runtime, timeout, memory)
- Step Functions state machine definition
- EventBridge rule patterns

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:
- `project_name`: Project identifier for resource naming
- `environment`: Environment tag
- `lambda_timeout`: Lambda function timeout in seconds
- `lambda_memory_size`: Lambda function memory allocation

### Script Configuration

Environment variables in bash scripts:
- `PROJECT_NAME`: Base name for resources
- `AWS_REGION`: Target AWS region
- `LAMBDA_RUNTIME`: Lambda runtime version

## Architecture Overview

This implementation creates:

1. **Lambda Functions**: Five microservices for user, order, payment, inventory, and notification processing
2. **Step Functions State Machine**: Orchestrates the microservices workflow with parallel processing
3. **EventBridge Rule**: Triggers workflows automatically based on order events
4. **IAM Roles**: Proper permissions for Step Functions to invoke Lambda functions
5. **CloudWatch Log Groups**: Comprehensive logging for debugging and monitoring

## Best Practices Implemented

- **Error Handling**: Automatic retries with exponential backoff
- **Parallel Processing**: Simultaneous execution of independent operations
- **Loose Coupling**: Services communicate through Step Functions orchestration
- **Observability**: CloudWatch integration for monitoring and debugging
- **Security**: Least privilege IAM roles and policies
- **Scalability**: Serverless architecture that scales automatically

## Cost Optimization

- Lambda functions use appropriate memory allocation for workload
- Step Functions execution costs are minimized through efficient state design
- EventBridge rules are scoped to specific event patterns
- CloudWatch log retention is configured appropriately

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../microservices-step-functions.md)
- [AWS Step Functions Documentation](https://docs.aws.amazon.com/step-functions/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)

## Security Considerations

- All Lambda functions run with minimal required permissions
- Step Functions state machine uses dedicated execution role
- EventBridge rules follow least privilege access patterns
- CloudWatch logs are enabled for audit trails
- No hardcoded credentials or sensitive data in configurations