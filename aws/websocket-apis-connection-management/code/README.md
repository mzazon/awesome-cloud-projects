# Infrastructure as Code for Managing WebSocket APIs with Route and Connection Handling

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Managing WebSocket APIs with Route and Connection Handling".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - API Gateway WebSocket APIs
  - Lambda functions
  - DynamoDB tables
  - IAM roles and policies
  - CloudWatch logs
- Python 3.9+ (for testing WebSocket connections)
- Node.js 18+ (for CDK TypeScript)
- Terraform 1.0+ (for Terraform deployment)

## Architecture Overview

This infrastructure creates a complete WebSocket API with:

- **API Gateway WebSocket API** with route management ($connect, $disconnect, $default, custom routes)
- **Lambda Functions** for connection handling, message processing, and routing
- **DynamoDB Tables** for connection state, room management, and message persistence
- **IAM Roles and Policies** with least privilege access
- **CloudWatch Integration** for monitoring and logging

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name websocket-api-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name websocket-api-stack \
    --query 'Stacks[0].StackStatus'

# Get WebSocket endpoint
aws cloudformation describe-stacks \
    --stack-name websocket-api-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`WebSocketApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy WebSocketApiStack

# Get outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
# Set up Python virtual environment
cd cdk-python/
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy WebSocketApiStack

# Get outputs
cdk ls --long
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# Get WebSocket endpoint
terraform output websocket_endpoint
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the WebSocket endpoint when complete
```

## Testing Your Deployment

### Install Python WebSocket Client

```bash
pip install websockets
```

### Test Connection

```bash
# Replace with your actual WebSocket endpoint
WEBSOCKET_ENDPOINT="wss://your-api-id.execute-api.region.amazonaws.com/staging"

# Test basic connection
python3 -c "
import asyncio
import websockets
import json

async def test_connection():
    uri = '${WEBSOCKET_ENDPOINT}?userId=testuser1&username=TestUser1&roomId=general&token=valid_test_token'
    async with websockets.connect(uri) as websocket:
        print('✅ Connection successful')
        
        # Send test message
        await websocket.send(json.dumps({
            'type': 'chat',
            'message': 'Hello WebSocket!'
        }))
        
        # Receive response
        response = await websocket.recv()
        print(f'Received: {response}')

asyncio.run(test_connection())
"
```

### Interactive Testing

Use the included WebSocket client for interactive testing:

```bash
# Download the test client (if not included)
curl -O https://raw.githubusercontent.com/your-repo/websocket_client.py

# Run interactive client
python3 websocket_client.py wss://your-api-id.execute-api.region.amazonaws.com/staging
```

Available commands in the interactive client:
- `/chat <message>` - Send chat message
- `/join <room_id>` - Join a room
- `/private <user_id> <message>` - Send private message
- `/rooms` - List active rooms
- `/quit` - Disconnect

## Configuration Options

### Environment Variables

All implementations support these environment variables:

- `ENVIRONMENT` - Deployment environment (dev, staging, prod)
- `PROJECT_NAME` - Project name for resource naming
- `REGION` - AWS region for deployment
- `ENABLE_DETAILED_MONITORING` - Enable detailed CloudWatch monitoring
- `ENABLE_XRAY_TRACING` - Enable X-Ray tracing for Lambda functions

### CloudFormation Parameters

- `Environment` - Environment name (dev/staging/prod)
- `ProjectName` - Project name for resource naming
- `EnableDetailedMonitoring` - Enable detailed monitoring (true/false)
- `MessageRetentionHours` - Message retention period in hours

### CDK Context Variables

Configure via `cdk.json` or command line:

```bash
cdk deploy -c environment=prod -c enableXrayTracing=true
```

### Terraform Variables

Configure via `terraform.tfvars`:

```hcl
environment = "dev"
project_name = "websocket-api"
region = "us-east-1"
enable_detailed_monitoring = true
enable_xray_tracing = true
message_retention_hours = 24
```

## Monitoring and Observability

### CloudWatch Dashboards

The infrastructure includes CloudWatch dashboards for monitoring:

- **Connection Metrics**: Active connections, connect/disconnect rates
- **Message Metrics**: Message throughput, error rates
- **Lambda Metrics**: Function duration, error rates, throttles
- **DynamoDB Metrics**: Read/write capacity, throttles

### CloudWatch Alarms

Pre-configured alarms for:

- High error rates in Lambda functions
- DynamoDB throttling
- API Gateway 4XX/5XX errors
- Connection failures

### X-Ray Tracing

Enable distributed tracing by setting `ENABLE_XRAY_TRACING=true` to trace:

- WebSocket connection lifecycle
- Message processing flow
- DynamoDB operations
- Inter-service communication

## Security Considerations

### IAM Roles and Policies

- Lambda functions use least privilege IAM policies
- DynamoDB access limited to required tables and operations
- API Gateway Management API access scoped to specific API

### Data Protection

- WebSocket connections support TLS 1.2+
- DynamoDB encryption at rest enabled
- CloudWatch logs encrypted
- No sensitive data in environment variables

### Authentication

- Token-based authentication in connection handler
- Configurable for integration with Amazon Cognito
- Rate limiting and throttling enabled

## Costs and Optimization

### Cost Components

- **API Gateway WebSocket**: $0.29 per million messages + $0.245 per million connection minutes
- **Lambda**: $0.0000167 per GB-second + $0.20 per 1M requests
- **DynamoDB**: $0.25 per million reads + $1.25 per million writes (on-demand)
- **CloudWatch**: $0.50 per million API requests + log storage

### Optimization Tips

- Use DynamoDB on-demand billing for variable workloads
- Implement connection pooling for high-traffic scenarios
- Configure appropriate Lambda memory sizes
- Use DynamoDB TTL for automatic message cleanup
- Monitor and adjust API Gateway throttling limits

## Troubleshooting

### Common Issues

1. **Connection Failed (403)**
   - Check IAM permissions for API Gateway
   - Verify Lambda function permissions
   - Check authentication token validation

2. **Messages Not Delivered**
   - Verify API Gateway Management API permissions
   - Check for stale connections in DynamoDB
   - Review CloudWatch logs for errors

3. **DynamoDB Throttling**
   - Increase read/write capacity
   - Consider on-demand billing
   - Implement exponential backoff

4. **Lambda Timeouts**
   - Increase function timeout
   - Optimize DynamoDB queries
   - Review function memory allocation

### Debugging Commands

```bash
# Check API Gateway logs
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway"

# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda"

# Check DynamoDB table status
aws dynamodb describe-table --table-name websocket-connections-suffix

# Test API Gateway endpoint
aws apigatewayv2 get-api --api-id your-api-id
```

## Cleanup

### Using CloudFormation (AWS)

```bash
aws cloudformation delete-stack --stack-name websocket-api-stack
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy WebSocketApiStack
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

## Advanced Features

### Message Persistence

- Messages stored in DynamoDB with TTL
- Configurable retention periods
- Query support for message history

### Room Management

- Dynamic room creation and joining
- Room-based message broadcasting
- User presence tracking per room

### Private Messaging

- Direct user-to-user messaging
- Multi-device support for users
- Message delivery confirmation

### Scaling Considerations

- DynamoDB Global Secondary Indexes for efficient queries
- Lambda concurrency controls
- API Gateway throttling configuration
- Connection state cleanup mechanisms

## Integration Examples

### Frontend Integration

```javascript
// React/JavaScript WebSocket client
const ws = new WebSocket('wss://your-api-id.execute-api.region.amazonaws.com/staging?userId=user123&token=valid_token');

ws.onopen = () => {
    console.log('Connected to WebSocket');
};

ws.onmessage = (event) => {
    const message = JSON.parse(event.data);
    console.log('Received:', message);
};

ws.send(JSON.dumps({
    type: 'chat',
    message: 'Hello from frontend!'
}));
```

### Backend Integration

```python
# Python backend integration
import boto3
import json

def send_message_to_connection(api_id, stage, connection_id, message):
    client = boto3.client('apigatewaymanagementapi',
        endpoint_url=f'https://{api_id}.execute-api.{region}.amazonaws.com/{stage}')
    
    response = client.post_to_connection(
        ConnectionId=connection_id,
        Data=json.dumps(message)
    )
    return response
```

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review CloudWatch logs for detailed error messages
3. Refer to the original recipe documentation
4. Check AWS service documentation for latest features

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify as needed for your specific use case.