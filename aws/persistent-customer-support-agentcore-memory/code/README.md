# Infrastructure as Code for Persistent Customer Support Agent with Bedrock AgentCore Memory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Persistent Customer Support Agent with Bedrock AgentCore Memory".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with permissions for Bedrock AgentCore, Lambda, DynamoDB, and API Gateway
- Bedrock AgentCore service activated in your AWS region (preview service)
- Appropriate IAM permissions for resource creation and management
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+

> **Note**: Bedrock AgentCore is currently in preview and may require service activation. Ensure your region supports AgentCore services before proceeding.

## Architecture Overview

This solution deploys:
- **Amazon Bedrock AgentCore Memory** for persistent context storage
- **AWS Lambda** function for support agent logic
- **Amazon DynamoDB** table for customer metadata
- **Amazon API Gateway** for secure client access
- **IAM roles and policies** with least privilege access

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name persistent-support-agent \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=MemoryName,ParameterValue=customer-support-memory

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name persistent-support-agent \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using Terraform
```bash
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

# Check deployment status
aws apigateway get-rest-apis --query 'items[?name==`support-api-*`]'
```

## Configuration Options

### CloudFormation Parameters
- `MemoryName`: Name for the AgentCore Memory (default: customer-support-memory)
- `LambdaMemorySize`: Lambda function memory allocation (default: 512MB)
- `DynamoDBReadCapacity`: DynamoDB read capacity units (default: 5)
- `DynamoDBWriteCapacity`: DynamoDB write capacity units (default: 5)

### CDK Configuration
Edit the configuration in `app.ts` (TypeScript) or `app.py` (Python):
```typescript
const config = {
  memoryName: 'customer-support-memory',
  lambdaMemorySize: 512,
  dynamodbReadCapacity: 5,
  dynamodbWriteCapacity: 5
};
```

### Terraform Variables
Configure in `terraform.tfvars` or pass via command line:
```hcl
memory_name = "customer-support-memory"
lambda_memory_size = 512
dynamodb_read_capacity = 5
dynamodb_write_capacity = 5
aws_region = "us-east-1"
```

## Testing the Deployment

After deployment, test the customer support agent:

```bash
# Get the API endpoint (adjust based on your deployment method)
API_ENDPOINT=$(aws apigateway get-rest-apis \
    --query 'items[?name==`support-api-*`].{id:id}[0].id' \
    --output text)
API_URL="https://${API_ENDPOINT}.execute-api.${AWS_REGION}.amazonaws.com/prod"

# Test customer interaction
curl -X POST ${API_URL}/support \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "customer-001",
        "message": "Hi, I am having trouble with the analytics dashboard loading slowly.",
        "metadata": {
            "userAgent": "Mozilla/5.0 (Chrome)",
            "sessionLocation": "dashboard"
        }
    }'

# Test follow-up to verify memory persistence
curl -X POST ${API_URL}/support \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "customer-001",
        "message": "Is there any update on the dashboard performance issue I reported?"
    }'
```

## Key Features

### Memory Persistence
- **Short-term Memory**: Session context for immediate interactions
- **Long-term Memory**: Customer preferences and historical insights
- **Automatic Extraction**: AI-powered insight extraction from conversations
- **Semantic Search**: Context-aware memory retrieval

### Scalability
- **Serverless Architecture**: Auto-scaling based on demand
- **DynamoDB**: Managed NoSQL database with predictable performance
- **API Gateway**: Built-in throttling and monitoring
- **Lambda**: Pay-per-use execution model

### Security
- **IAM Roles**: Least privilege access for all components
- **Encryption**: Data encryption at rest and in transit
- **API Gateway**: Secure endpoint with optional authentication
- **VPC Support**: Optional VPC deployment for enhanced security

## Customization

### Adding Authentication
To add API authentication, modify the API Gateway configuration:

**CloudFormation**:
```yaml
ApiGatewayMethod:
  Properties:
    AuthorizationType: AWS_IAM  # or COGNITO_USER_POOLS
```

**CDK TypeScript**:
```typescript
const method = resource.addMethod('POST', integration, {
  authorizationType: apigateway.AuthorizationType.IAM
});
```

**Terraform**:
```hcl
resource "aws_api_gateway_method" "support_post" {
  authorization = "AWS_IAM"
}
```

### Custom Memory Strategies
Modify the memory extraction strategies in the Lambda function:

```python
memory_strategies = [
    {
        "summarization": {"enabled": True}
    },
    {
        "semantic_memory": {"enabled": True}
    },
    {
        "user_preferences": {"enabled": True}
    },
    {
        "custom": {
            "enabled": True,
            "systemPrompt": "Your custom extraction prompt here",
            "modelId": "anthropic.claude-3-haiku-20240307-v1:0"
        }
    }
]
```

### Multi-Channel Support
Extend the solution to support multiple communication channels:

1. **Email Integration**: Add SES for email support
2. **SMS Support**: Integrate with SNS for text messaging
3. **Voice Support**: Connect with Amazon Connect for phone support
4. **Chat Widgets**: Deploy web-based chat interfaces

## Monitoring and Observability

### CloudWatch Dashboards
Monitor your deployment with these key metrics:
- Lambda function duration and error rates
- DynamoDB read/write capacity utilization
- API Gateway request counts and latencies
- AgentCore Memory usage and extraction rates

### X-Ray Tracing
Enable distributed tracing for the Lambda function:

```bash
aws lambda update-function-configuration \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --tracing-config Mode=Active
```

### Custom Metrics
Track custom business metrics:
- Customer satisfaction scores
- Resolution times
- Memory retrieval accuracy
- Session completion rates

## Cost Optimization

### DynamoDB
- Use On-Demand billing for variable workloads
- Enable DynamoDB Contributor Insights for optimization
- Consider DynamoDB Accelerator (DAX) for high-frequency access

### Lambda
- Optimize memory allocation based on usage patterns
- Use Provisioned Concurrency for consistent performance
- Consider ARM-based Graviton2 processors for cost savings

### API Gateway
- Monitor request patterns and optimize caching
- Use regional endpoints for better performance
- Consider usage plans for rate limiting

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name persistent-support-agent

# Verify deletion
aws cloudformation describe-stacks --stack-name persistent-support-agent
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm destruction
cdk ls
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
aws lambda list-functions --query 'Functions[?FunctionName==`support-agent-*`]'
```

## Troubleshooting

### Common Issues

1. **Bedrock AgentCore Not Available**
   - Ensure your region supports AgentCore (currently limited preview)
   - Verify service activation in your AWS account
   - Check IAM permissions for Bedrock services

2. **Lambda Timeout Errors**
   - Increase Lambda timeout setting (current: 30 seconds)
   - Monitor CloudWatch logs for performance bottlenecks
   - Optimize memory retrieval queries

3. **Memory Extraction Delays**
   - Allow 1-2 minutes for memory extraction to complete
   - Monitor AgentCore service status
   - Verify model permissions for extraction strategies

4. **DynamoDB Throttling**
   - Increase read/write capacity units
   - Consider switching to On-Demand billing
   - Implement exponential backoff in Lambda function

### Debugging Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/support-agent"

# Verify AgentCore Memory status
aws bedrock-agentcore-control get-memory --name ${MEMORY_NAME}

# Test DynamoDB access
aws dynamodb scan --table-name ${DDB_TABLE_NAME} --limit 1

# Check API Gateway configuration
aws apigateway get-rest-apis --query 'items[?name==`support-api-*`]'
```

## Security Considerations

### Data Protection
- All customer data is encrypted at rest and in transit
- Memory records are automatically purged based on retention policies
- PII detection and handling through custom extraction strategies

### Access Control
- IAM roles follow least privilege principle
- API Gateway supports multiple authentication methods
- Resource-based policies for cross-account access

### Compliance
- GDPR compliance through data retention controls
- HIPAA eligible services used where applicable
- SOC 2 Type II compliance for all AWS services

## Support and Resources

### Documentation
- [Amazon Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/latest/developerguide/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)

### Community
- AWS re:Post for technical questions
- GitHub Issues for infrastructure code improvements
- AWS Support for production deployments

### Professional Services
- AWS Professional Services for enterprise implementations
- AWS Partner Network for certified implementation partners
- Third-party consulting for custom integrations

---

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.