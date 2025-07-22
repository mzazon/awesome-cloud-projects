# Infrastructure as Code for Conversational AI Applications with Bedrock

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Conversational AI Applications with Bedrock".

## Overview

This solution implements a scalable conversational AI application using Amazon Bedrock's Claude models, DynamoDB for conversation state management, and Lambda functions for business logic orchestration. The architecture provides access to Anthropic's Claude models through a managed service, eliminating the need for model hosting and maintenance.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript
- **CDK Python**: AWS Cloud Development Kit with Python
- **Terraform**: Multi-cloud infrastructure as code using AWS provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

- **Amazon Bedrock**: Claude model access for natural language processing
- **AWS Lambda**: Serverless compute for conversation handling
- **Amazon DynamoDB**: NoSQL database for conversation history storage
- **API Gateway**: REST API endpoints with CORS support
- **IAM Roles**: Secure access control with least privilege principles
- **CloudWatch**: Logging and monitoring with X-Ray tracing

## Prerequisites

### General Requirements

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions to create IAM roles, Lambda functions, API Gateway, DynamoDB tables, and access Amazon Bedrock
- **Amazon Bedrock model access**: Must request access to Claude models through AWS Console
- Basic understanding of conversational AI concepts and REST APIs

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions
- Understanding of YAML syntax

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI: `npm install -g aws-cdk`
- TypeScript: `npm install -g typescript`

#### CDK Python
- Python 3.9 or later
- AWS CDK CLI: `pip install aws-cdk-lib`
- Virtual environment recommended

#### Terraform
- Terraform v1.0 or later
- AWS provider v5.0 or later

#### Bash Scripts
- Bash shell environment
- jq for JSON processing: `apt-get install jq` or `brew install jq`
- Python 3.9+ with requests library for testing

### Cost Considerations

- **Amazon Bedrock**: ~$0.008/1K input tokens, ~$0.024/1K output tokens
- **AWS Lambda**: ~$0.20/million requests + compute time
- **DynamoDB**: ~$0.25/million requests (on-demand pricing)
- **API Gateway**: ~$3.50/million requests
- **CloudWatch**: Standard logging and monitoring costs

## Quick Start

### Step 1: Request Bedrock Model Access

**IMPORTANT**: Before deploying any infrastructure, you must request access to Claude models:

1. Go to AWS Console → Amazon Bedrock → Model access
2. Request access to Claude models (Claude 3 Haiku, Sonnet, or Opus)
3. Wait for approval (usually takes a few minutes to hours)
4. Verify access with: `aws bedrock list-foundation-models --query 'modelSummaries[?contains(modelId, \`claude\`)].modelId'`

### Step 2: Choose Your Deployment Method

#### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name conversational-ai-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ClaudeModelId,ParameterValue=anthropic.claude-3-haiku-20240307-v1:0

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name conversational-ai-stack

# Get API endpoint
aws cloudformation describe-stacks \
    --stack-name conversational-ai-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

#### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy ConversationalAiStack

# Get outputs
cdk list --json
```

#### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy ConversationalAiStack

# Get outputs
cdk list --json
```

#### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Get outputs
terraform output api_endpoint
terraform output test_command
```

#### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the deployment progress and note the API endpoint
```

## Testing Your Deployment

### Basic API Test

```bash
# Replace with your actual API endpoint
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/prod"

# Send a test message
curl -X POST "${API_ENDPOINT}/chat" \
    -H "Content-Type: application/json" \
    -d '{
        "message": "Hello! Can you help me understand machine learning?",
        "session_id": "test-session-123",
        "user_id": "test-user"
    }'
```

### Interactive Testing Script

Each deployment includes a Python test script:

```bash
# Install requests library
pip install requests

# Run interactive chat
python test_conversational_ai.py

# Run automated test
python test_conversational_ai.py test
```

### Conversation Memory Test

```bash
# Test conversation context retention
python test_context.py
```

## Configuration Options

### Environment Variables

- `CLAUDE_MODEL_ID`: Claude model identifier (default: claude-3-haiku)
- `MAX_TOKENS`: Maximum response length (default: 1000)
- `TEMPERATURE`: Response creativity (default: 0.7)
- `CONVERSATION_LIMIT`: Max conversation history items (default: 10)

### CloudFormation Parameters

- `ClaudeModelId`: Bedrock Claude model identifier
- `LambdaTimeout`: Function timeout in seconds (default: 30)
- `LambdaMemorySize`: Function memory in MB (default: 512)
- `ApiStageName`: API Gateway stage name (default: prod)

### CDK Configuration

Modify the stack parameters in the CDK app files:

```typescript
// TypeScript example
const stack = new ConversationalAiStack(app, 'ConversationalAiStack', {
    claudeModelId: 'anthropic.claude-3-sonnet-20240229-v1:0',
    lambdaTimeout: Duration.seconds(45),
    lambdaMemorySize: 1024
});
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
claude_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
lambda_timeout = 45
lambda_memory_size = 1024
api_stage_name = "prod"
environment = "production"
```

## Monitoring and Debugging

### CloudWatch Logs

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/conversational-ai

# Stream real-time logs
aws logs tail /aws/lambda/conversational-ai-handler --follow
```

### DynamoDB Conversation History

```bash
# View recent conversations
aws dynamodb scan \
    --table-name ConversationalAI-ConversationHistory \
    --max-items 10 \
    --query 'Items[].{Session:session_id.S,Role:role.S,Content:content.S}'
```

### API Gateway Monitoring

```bash
# Get API Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --dimensions Name=ApiName,Value=conversational-ai-api \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name conversational-ai-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name conversational-ai-stack
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
cdk destroy ConversationalAiStack

# Python
cd cdk-python/
source .venv/bin/activate
cdk destroy ConversationalAiStack
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

## Troubleshooting

### Common Issues

1. **Bedrock Access Denied**
   - Solution: Request model access through AWS Console → Bedrock → Model access
   - Verify with: `aws bedrock list-foundation-models`

2. **Lambda Timeout Errors**
   - Solution: Increase timeout in configuration (default: 30s)
   - Monitor function duration in CloudWatch

3. **DynamoDB Throttling**
   - Solution: Check table capacity settings
   - Consider switching to provisioned capacity for high traffic

4. **API Gateway CORS Issues**
   - Solution: Verify CORS headers in OPTIONS method response
   - Check browser developer tools for CORS errors

5. **High Bedrock Costs**
   - Solution: Implement rate limiting, reduce MAX_TOKENS, use cheaper models
   - Monitor usage with CloudWatch metrics

### Debug Mode

Enable debug logging by setting environment variables:

```bash
# CloudFormation
aws cloudformation update-stack \
    --stack-name conversational-ai-stack \
    --use-previous-template \
    --parameters ParameterKey=LogLevel,ParameterValue=DEBUG

# Terraform
terraform apply -var="log_level=DEBUG"
```

### Performance Optimization

1. **Cold Start Reduction**: Consider provisioned concurrency for Lambda
2. **Model Selection**: Use Claude Haiku for faster responses, Sonnet/Opus for complex reasoning
3. **Conversation History**: Limit history length to reduce token usage
4. **Caching**: Implement response caching for common questions

## Security Considerations

### IAM Best Practices

- All roles follow least privilege principle
- Service-specific policies for Bedrock, DynamoDB, and CloudWatch access
- No hardcoded credentials in Lambda functions

### Data Protection

- Conversation data encrypted at rest in DynamoDB
- API Gateway uses HTTPS endpoints only
- CloudWatch logs retention configured appropriately

### Rate Limiting

Consider implementing additional rate limiting:

```bash
# API Gateway usage plans
aws apigateway create-usage-plan \
    --name conversational-ai-plan \
    --throttle burst-limit=100,rate-limit=50
```

## Advanced Features

### Multi-Model Support

Modify the Lambda function to support different Claude models:

```python
MODEL_MAPPING = {
    "fast": "anthropic.claude-3-haiku-20240307-v1:0",
    "balanced": "anthropic.claude-3-sonnet-20240229-v1:0",
    "advanced": "anthropic.claude-3-opus-20240229-v1:0"
}
```

### Streaming Responses

Implement real-time streaming with WebSocket API:

1. Create WebSocket API Gateway
2. Use Bedrock's streaming response API
3. Implement connection management in Lambda

### Multi-Language Support

Add language detection and model selection:

```python
def detect_language(text):
    # Implement language detection
    pass

def get_model_for_language(language):
    # Return appropriate model for language
    pass
```

## Integration Examples

### React Frontend

```javascript
const sendMessage = async (message, sessionId) => {
    const response = await fetch(`${API_ENDPOINT}/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            message,
            session_id: sessionId,
            user_id: 'web-user'
        })
    });
    return response.json();
};
```

### Mobile App Integration

```swift
// iOS Swift example
func sendMessage(message: String, sessionId: String) async {
    let url = URL(string: "\(apiEndpoint)/chat")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body = [
        "message": message,
        "session_id": sessionId,
        "user_id": "ios-user"
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    
    let (data, _) = try await URLSession.shared.data(for: request)
    // Process response
}
```

## Support and Resources

### Documentation Links

- [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/)
- [Claude Models Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-claude.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/latest/developerguide/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)

### Community Resources

- [AWS Samples Repository](https://github.com/aws-samples)
- [Anthropic Claude Documentation](https://docs.anthropic.com/claude)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service status pages
3. Consult the original recipe documentation
4. Reference provider documentation for specific services

### Contributing

To improve this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow AWS Well-Architected Framework principles
3. Update documentation for any configuration changes
4. Ensure security best practices are maintained

---

**Note**: This infrastructure creates AWS resources that incur costs. Monitor your usage and clean up resources when not needed to avoid unexpected charges.