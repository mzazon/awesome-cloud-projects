# CDK Python Implementation: Persistent Customer Support Agent with Bedrock AgentCore Memory

This directory contains a complete AWS CDK (Cloud Development Kit) Python application that deploys a sophisticated customer support system with persistent memory capabilities using Amazon Bedrock AgentCore Memory.

## Architecture Overview

The solution creates a serverless customer support system that maintains context across multiple sessions, enabling personalized and contextually-aware customer interactions:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Customer      │    │   API Gateway   │    │   Lambda        │
│   Interface     │───▶│   REST API      │───▶│   Support Agent │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
        ┌──────────────────────────────────────────────┼──────────────┐
        │                                              ▼              │
        │    ┌─────────────────┐              ┌─────────────────┐     │
        │    │   DynamoDB      │              │   Bedrock       │     │
        │    │   Customer Data │◀─────────────│   AgentCore     │     │
        │    └─────────────────┘              │   Memory        │     │
        │                                     └─────────────────┘     │
        │                                              │              │
        │                                              ▼              │
        │                                     ┌─────────────────┐     │
        │                                     │   Bedrock       │     │
        │                                     │   Foundation    │     │
        │                                     │   Models        │     │
        │                                     └─────────────────┘     │
        └───────────────────────────────────────────────────────────────┘
```

## Components Deployed

### 1. **Amazon DynamoDB Table**
- Stores customer metadata, preferences, and profile information
- Partition key: `customerId`
- Includes point-in-time recovery and encryption at rest
- Provisioned with 5 RCU/WCU for demo purposes

### 2. **AWS Lambda Function**
- Python 3.11 runtime with 512MB memory and 30-second timeout
- Handles customer support request processing and response generation
- Integrates with AgentCore Memory for context retrieval and storage
- Uses Bedrock foundation models for AI-powered responses
- Includes comprehensive error handling and logging

### 3. **Amazon API Gateway**
- REST API with CORS support for web client integration
- `/support` endpoint for POST requests
- Built-in throttling (100 requests/second, 200 burst)
- Request/response logging and CloudWatch metrics enabled
- Lambda proxy integration for seamless request forwarding

### 4. **IAM Roles and Policies**
- Least privilege access model
- Lambda execution role with specific permissions for:
  - Bedrock AgentCore Memory operations
  - Bedrock foundation model invocation
  - DynamoDB read/write operations
  - CloudWatch logging

### 5. **CloudWatch Log Group**
- Dedicated log group for Lambda function logs
- 1-week retention policy for demo purposes
- Structured logging for monitoring and debugging

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Python 3.8+** installed on your system
3. **AWS CDK CLI** installed globally (`npm install -g aws-cdk`)
4. **Appropriate AWS permissions** for creating the required resources
5. **Bedrock AgentCore** enabled in your AWS region (preview service)

### Required AWS Permissions

Your AWS credentials need permissions for:
- CloudFormation stack operations
- Lambda function creation and management
- API Gateway creation and deployment
- DynamoDB table creation and management
- IAM role and policy creation
- CloudWatch log group creation
- Bedrock AgentCore operations (once available)

## Installation and Deployment

### 1. Setup Python Virtual Environment

```bash
# Navigate to the CDK Python directory
cd aws/persistent-customer-support-agentcore-memory/code/cdk-python/

# Create a virtual environment
python -m venv .venv

# Activate the virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate
```

### 2. Install Dependencies

```bash
# Install Python dependencies
pip install -r requirements.txt

# Verify CDK installation
cdk --version
```

### 3. Bootstrap CDK (First-time setup)

```bash
# Bootstrap CDK in your AWS account and region
cdk bootstrap

# This creates the CDKToolkit stack with S3 bucket for storing assets
```

### 4. Review and Deploy

```bash
# Review the generated CloudFormation template
cdk synth

# Deploy the stack
cdk deploy

# Follow the prompts and confirm resource creation
```

### 5. Post-Deployment Setup

After the CDK deployment completes, you'll need to manually create the Bedrock AgentCore Memory:

```bash
# Get the stack outputs
aws cloudformation describe-stacks \
    --stack-name PersistentCustomerSupportStack \
    --query 'Stacks[0].Outputs'

# Note the MemoryName output and create AgentCore Memory
MEMORY_NAME=$(aws cloudformation describe-stacks \
    --stack-name PersistentCustomerSupportStack \
    --query 'Stacks[0].Outputs[?OutputKey==`AgentCoreMemoryName`].OutputValue' \
    --output text)

# Create AgentCore Memory (when service becomes available)
aws bedrock-agentcore-control create-memory \
    --name $MEMORY_NAME \
    --description "Customer support agent memory" \
    --event-expiry-duration "P30D"

# Update Lambda environment variable with Memory ID
MEMORY_ID=$(aws bedrock-agentcore-control get-memory \
    --name $MEMORY_NAME \
    --query 'memory.memoryId' \
    --output text)

FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name PersistentCustomerSupportStack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment Variables="{DDB_TABLE_NAME=$(aws cloudformation describe-stacks --stack-name PersistentCustomerSupportStack --query 'Stacks[0].Outputs[?OutputKey==`DynamoDBTableName`].OutputValue' --output text),MEMORY_ID=$MEMORY_ID}"
```

## Usage and Testing

### 1. Get API Endpoint

```bash
# Get the API Gateway endpoint URL
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name PersistentCustomerSupportStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

echo "API Endpoint: $API_ENDPOINT"
```

### 2. Test Customer Support Interaction

```bash
# Test initial customer request
curl -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "customer-001",
        "message": "I am having trouble with the analytics dashboard loading slowly.",
        "metadata": {
            "userAgent": "Mozilla/5.0 (Chrome)",
            "sessionLocation": "dashboard"
        }
    }'

# Test follow-up request to verify memory persistence
curl -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "customer-001",
        "message": "Is there any update on my previous issue?"
    }'
```

### 3. Add Sample Customer Data

```bash
# Get DynamoDB table name
TABLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name PersistentCustomerSupportStack \
    --query 'Stacks[0].Outputs[?OutputKey==`DynamoDBTableName`].OutputValue' \
    --output text)

# Add sample customer data
aws dynamodb put-item \
    --table-name $TABLE_NAME \
    --item '{
        "customerId": {"S": "customer-001"},
        "name": {"S": "Sarah Johnson"},
        "email": {"S": "sarah.johnson@example.com"},
        "supportTier": {"S": "premium"},
        "preferredChannel": {"S": "chat"}
    }'
```

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Tail logs in real-time
aws logs tail /aws/lambda/$FUNCTION_NAME --follow
```

### API Gateway Metrics

```bash
# View API Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --dimensions Name=ApiName,Value=$API_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

### DynamoDB Monitoring

```bash
# Check DynamoDB table status
aws dynamodb describe-table --table-name $TABLE_NAME

# Monitor DynamoDB metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedReadCapacityUnits \
    --dimensions Name=TableName,Value=$TABLE_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Customization Options

### Environment Variables

The Lambda function supports these environment variables:

- `DDB_TABLE_NAME`: DynamoDB table name for customer data
- `MEMORY_ID`: Bedrock AgentCore Memory identifier
- `LOG_LEVEL`: Logging level (DEBUG, INFO, WARNING, ERROR)

### Scaling Configuration

You can modify these parameters in `app.py`:

```python
# DynamoDB capacity
read_capacity=5,      # Adjust based on expected read volume
write_capacity=5,     # Adjust based on expected write volume

# Lambda configuration
timeout=Duration.seconds(30),    # Increase for complex processing
memory_size=512,                 # Increase for better performance

# API Gateway throttling
throttling_rate_limit=100,       # Requests per second
throttling_burst_limit=200,      # Burst capacity
```

### Security Enhancements

For production deployments, consider:

1. **API Gateway Authentication**: Add API keys or Cognito authentication
2. **VPC Configuration**: Deploy Lambda in private subnets
3. **Encryption**: Use customer-managed KMS keys
4. **WAF Protection**: Add AWS WAF for API Gateway
5. **Secrets Management**: Use AWS Secrets Manager for sensitive data

## Cost Optimization

The current configuration is optimized for demonstration. For production:

1. **DynamoDB**: Switch to On-Demand billing for variable workloads
2. **Lambda**: Optimize memory allocation based on performance testing
3. **API Gateway**: Implement caching for frequently accessed data
4. **Logs**: Adjust retention periods based on compliance requirements

## Cleanup and Destruction

### Using CDK

```bash
# Destroy the entire stack
cdk destroy

# Confirm destruction when prompted
```

### Manual Cleanup (if needed)

```bash
# Delete AgentCore Memory first
aws bedrock-agentcore-control delete-memory --name $MEMORY_NAME

# Then destroy CDK stack
cdk destroy
```

## Development and Testing

### Local Development

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run type checking
mypy app.py

# Run code formatting
black app.py

# Run linting
flake8 app.py

# Run tests (when test files are added)
pytest tests/ -v
```

### CDK Best Practices

This implementation follows CDK best practices:

- **Type hints**: Full type annotation for better IDE support
- **Construct composition**: Logical separation of concerns
- **Resource tagging**: Consistent tagging strategy
- **Security**: Least privilege IAM policies
- **Monitoring**: Built-in CloudWatch integration
- **Documentation**: Comprehensive inline documentation

## Troubleshooting Common Issues

### 1. CDK Bootstrap Issues

```bash
# Re-bootstrap if needed
cdk bootstrap --force
```

### 2. Permission Errors

Ensure your AWS credentials have the necessary permissions listed in the Prerequisites section.

### 3. Region Compatibility

Verify that Bedrock AgentCore is available in your chosen AWS region.

### 4. Memory Creation Failures

AgentCore Memory is a preview service. Ensure it's enabled in your account and region.

## Support and Resources

- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [Amazon Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)

For issues specific to this implementation, refer to the original recipe documentation or create an issue in the project repository.