# Conversational AI with Amazon Bedrock and Claude - CDK TypeScript

This AWS CDK TypeScript application deploys a complete conversational AI solution using Amazon Bedrock's Claude models, DynamoDB for conversation storage, Lambda for processing, and API Gateway for HTTP access.

## Architecture

The application creates:

- **DynamoDB Table**: Stores conversation history with automatic TTL cleanup
- **Lambda Function**: Processes chat requests and integrates with Bedrock Claude models
- **API Gateway**: Provides REST API with CORS support for web/mobile integration
- **IAM Roles**: Least privilege permissions for Bedrock, DynamoDB, and CloudWatch access
- **CloudWatch Logs**: Centralized logging with configurable retention

## Prerequisites

1. **AWS Account**: With appropriate permissions for CDK deployment
2. **AWS CLI**: Version 2.x configured with credentials
3. **Node.js**: Version 18.x or later
4. **AWS CDK**: Version 2.117.0 or later
5. **Bedrock Access**: Request access to Claude models in AWS Console

### Requesting Bedrock Model Access

Before deploying, you must request access to Claude models:

1. Go to AWS Console → Amazon Bedrock → Model access
2. Request access to Claude models (Claude 3 Haiku, Sonnet, or Opus)
3. Wait for approval (usually takes a few minutes)

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/conversational-ai-applications-amazon-bedrock-claude/code/cdk-typescript/
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Configure AWS credentials** (if not already done):
   ```bash
   aws configure
   ```

4. **Bootstrap CDK** (if not already done in your account/region):
   ```bash
   npx cdk bootstrap
   ```

## Deployment

### Quick Deployment

Deploy with default settings:

```bash
npx cdk deploy
```

### Customized Deployment

Deploy with custom configuration:

```bash
npx cdk deploy \
  --context environment=production \
  --context claudeModelId=anthropic.claude-3-sonnet-20240229-v1:0 \
  --context enableXRayTracing=true
```

### Environment-Specific Deployment

Deploy to specific environments:

```bash
# Development environment
npx cdk deploy --context environment=development

# Production environment (with additional protections)
npx cdk deploy --context environment=production
```

## Configuration Options

The CDK application supports several configuration options via CDK context:

| Context Key | Default Value | Description |
|-------------|---------------|-------------|
| `environment` | `development` | Deployment environment (affects naming, retention, etc.) |
| `claudeModelId` | `anthropic.claude-3-haiku-20240307-v1:0` | Bedrock Claude model to use |
| `enableXRayTracing` | `true` | Enable AWS X-Ray tracing for Lambda |
| `tableNameSuffix` | `conversational-ai` | Suffix for DynamoDB table name |

## Usage

After deployment, the stack outputs the API endpoint URL. Use it to send chat requests:

### REST API Example

```bash
# Get the API URL from stack outputs
API_URL=$(aws cloudformation describe-stacks \
  --stack-name ConversationalAIStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text)

# Send a chat message
curl -X POST "${API_URL}" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello! Can you help me understand machine learning?",
    "session_id": "test-session-123",
    "user_id": "test-user"
  }'
```

### JavaScript/Node.js Example

```javascript
const apiUrl = 'YOUR_API_ENDPOINT_URL'; // From CDK output

const sendMessage = async (message, sessionId = null, userId = 'anonymous') => {
  const response = await fetch(apiUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: message,
      session_id: sessionId || generateSessionId(),
      user_id: userId
    })
  });
  
  if (response.ok) {
    return await response.json();
  } else {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }
};

const generateSessionId = () => {
  return 'session-' + Math.random().toString(36).substr(2, 9);
};

// Usage
sendMessage("Hello, how can you help me?")
  .then(result => {
    console.log('AI Response:', result.response);
    console.log('Session ID:', result.session_id);
  })
  .catch(error => {
    console.error('Error:', error);
  });
```

## Testing

### Unit Tests

Run CDK unit tests:

```bash
npm test
```

### Integration Testing

Test the deployed API:

```bash
# Test with curl
curl -X POST "${API_URL}" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test message", "session_id": "test-123"}'

# Test conversation memory
curl -X POST "${API_URL}" \
  -H "Content-Type: application/json" \
  -d '{"message": "My name is Alice", "session_id": "memory-test"}'

curl -X POST "${API_URL}" \
  -H "Content-Type: application/json" \
  -d '{"message": "What is my name?", "session_id": "memory-test"}'
```

## Monitoring and Observability

### CloudWatch Dashboards

Create a custom dashboard to monitor your conversational AI:

```bash
# View Lambda function metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=conversational-ai-development \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### X-Ray Tracing

If X-Ray tracing is enabled, view trace data in the AWS Console:
- AWS Console → X-Ray → Service map
- Analyze request flows and identify bottlenecks

### CloudWatch Logs

View application logs:

```bash
# View recent logs
aws logs tail /aws/lambda/conversational-ai-development --follow

# Filter for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/conversational-ai-development \
  --filter-pattern "ERROR"
```

## Cost Optimization

### Bedrock Costs

- **Claude 3 Haiku**: ~$0.00025/1K input tokens, ~$0.00125/1K output tokens
- **Claude 3 Sonnet**: ~$0.003/1K input tokens, ~$0.015/1K output tokens
- **Claude 3 Opus**: ~$0.015/1K input tokens, ~$0.075/1K output tokens

### Lambda Costs

- **ARM64 Architecture**: Better price-performance ratio
- **Reserved Concurrency**: Limits maximum costs
- **Memory Configuration**: 512MB provides good balance

### DynamoDB Costs

- **On-Demand Billing**: Scales with usage automatically
- **TTL Cleanup**: Automatic deletion prevents storage cost growth

## Security Considerations

### IAM Permissions

The application follows least privilege principles:
- Lambda role has minimal required permissions
- Bedrock access restricted to specific Claude models
- DynamoDB permissions scoped to the conversation table

### API Security

For production deployments:
- API key authentication enabled
- Usage plans with rate limiting
- CORS configured for specific origins (customize as needed)

### Data Protection

- DynamoDB encryption at rest using AWS managed keys
- Conversation TTL for automatic data cleanup
- CloudWatch logs encrypted in transit

## Troubleshooting

### Common Issues

1. **Bedrock Access Denied**:
   - Ensure you've requested and received access to Claude models
   - Verify the model ID is correct for your region

2. **Lambda Timeout**:
   - Increase timeout in the stack (currently 30 seconds)
   - Check CloudWatch logs for performance bottlenecks

3. **DynamoDB Throttling**:
   - Switch to provisioned billing if consistent high traffic
   - Check for hot partition keys

4. **API Gateway 403 Errors**:
   - Verify CORS configuration
   - Check API key requirements for production environment

### Debugging

Enable debug logging:

```bash
npx cdk deploy --context environment=development
```

This sets the Lambda log level to DEBUG for detailed troubleshooting.

## Cleanup

Remove all resources:

```bash
npx cdk destroy
```

Confirm deletion when prompted. This will remove:
- Lambda function and associated logs
- API Gateway
- DynamoDB table (if not in production mode)
- IAM roles and policies

## Customization

### Using Different Claude Models

Specify a different Claude model:

```bash
npx cdk deploy --context claudeModelId=anthropic.claude-3-opus-20240229-v1:0
```

Available Claude models:
- `anthropic.claude-3-haiku-20240307-v1:0` (Fast, cost-effective)
- `anthropic.claude-3-sonnet-20240229-v1:0` (Balanced performance)
- `anthropic.claude-3-opus-20240229-v1:0` (Most capable, highest cost)

### Extending the Lambda Function

The Lambda code is embedded in the CDK stack. To modify:

1. Edit the `getLambdaCode()` method in `lib/conversational-ai-stack.ts`
2. Add additional environment variables as needed
3. Redeploy with `npx cdk deploy`

### Adding Authentication

For production use, consider adding:
- Amazon Cognito user pools
- API Gateway authorizers
- Custom authentication middleware

## Support

For issues and questions:
- Review CloudWatch logs for error details
- Check AWS documentation for Bedrock and Lambda
- Ensure all prerequisites are met
- Verify IAM permissions

## License

This code is provided under the MIT License. See the LICENSE file for details.