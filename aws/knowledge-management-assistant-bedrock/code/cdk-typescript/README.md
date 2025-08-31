# Knowledge Management Assistant with Amazon Bedrock - CDK TypeScript

This CDK TypeScript application deploys a complete knowledge management assistant using Amazon Bedrock Agents and Knowledge Bases. The solution provides enterprise employees with intelligent, contextual answers from company documents through natural language queries.

## Architecture

The solution implements the following AWS services:

- **Amazon Bedrock Agents**: Orchestrates natural language understanding and response generation
- **Amazon Bedrock Knowledge Bases**: Provides retrieval-augmented generation (RAG) capabilities
- **Amazon S3**: Stores enterprise documents with security features
- **AWS Lambda**: Provides API integration with enhanced error handling
- **Amazon API Gateway**: Serves as the REST API endpoint for queries
- **Amazon OpenSearch Serverless**: Vector storage for document embeddings (managed by CDK)

## Features

### Enterprise Security
- S3 bucket encryption with SSL enforcement
- IAM roles following least privilege principle
- VPC endpoint support for private communication
- Comprehensive logging and monitoring

### Advanced AI Capabilities
- Claude 3.5 Sonnet for superior reasoning and response generation
- Amazon Titan Text Embeddings V2 for semantic understanding
- Enhanced chunking strategies for optimal retrieval
- Foundation model parsing for complex documents

### Production Ready
- CDK Nag integration for security best practices
- Comprehensive error handling and logging
- CORS support for web applications
- Cost optimization with S3 lifecycle policies

## Prerequisites

1. **AWS Account**: With Amazon Bedrock access and model permissions
2. **AWS CLI**: Version 2.x or later, configured with appropriate credentials
3. **Node.js**: Version 18 or later
4. **npm**: Version 8 or later
5. **AWS CDK**: Version 2.165.0 or later

### Bedrock Model Access

Ensure you have enabled access to the following models in your AWS region:
- `anthropic.claude-3-5-sonnet-20241022-v2:0`
- `amazon.titan-embed-text-v2:0`

Enable model access in the AWS Console: Amazon Bedrock → Model access

## Installation

1. **Clone and Navigate**:
   ```bash
   cd aws/knowledge-management-assistant-bedrock/code/cdk-typescript/
   ```

2. **Install Dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK** (if not already done):
   ```bash
   npm run bootstrap
   ```

## Configuration

### Environment Variables

Set the following environment variables or use CDK context:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
```

### CDK Context

Configure deployment through `cdk.json` or command line:

```bash
# Deploy with custom stack name
cdk deploy -c stackName=MyKnowledgeAssistant

# Deploy with custom bucket name
cdk deploy -c bucketName=my-enterprise-docs

# Deploy without CDK Nag (not recommended)
cdk deploy -c enableCdkNag=false

# Deploy to different environment
cdk deploy -c environment=production
```

## Deployment

### Basic Deployment

```bash
# Synthesize and validate CloudFormation template
npm run synth

# Deploy the stack
npm run deploy
```

### Advanced Deployment Options

```bash
# Deploy with specific configuration
cdk deploy KnowledgeManagementAssistant \
  -c stackName=ProductionKnowledgeAssistant \
  -c environment=production \
  -c costCenter=engineering

# Deploy with approval required
cdk deploy --require-approval any-change

# Deploy with specific profile
cdk deploy --profile production
```

### Regional Considerations

Deploy in regions where Bedrock models are available:
- `us-east-1` (N. Virginia) - Recommended
- `us-west-2` (Oregon)
- `eu-west-1` (Ireland)
- `ap-southeast-1` (Singapore)

## Usage

### Upload Documents

After deployment, upload your enterprise documents to the S3 bucket:

```bash
# Get bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name KnowledgeManagementAssistant \
  --query 'Stacks[0].Outputs[?OutputKey==`DocumentBucketName`].OutputValue' \
  --output text)

# Upload documents
aws s3 cp my-documents/ s3://${BUCKET_NAME}/documents/ --recursive
```

### Query the API

```bash
# Get API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name KnowledgeManagementAssistant \
  --query 'Stacks[0].Outputs[?OutputKey==`QueryEndpoint`].OutputValue' \
  --output text)

# Send query
curl -X POST ${API_ENDPOINT} \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is our remote work policy?",
    "sessionId": "user-session-123"
  }'
```

### Example Response

```json
{
  "response": "According to the company policies, all employees are eligible for remote work arrangements with manager approval. Remote workers must maintain regular communication during business hours and attend quarterly in-person meetings.",
  "sessionId": "user-session-123",
  "timestamp": "abc123-def456-ghi789"
}
```

## Development

### Local Development

```bash
# Watch for changes
npm run watch

# Run tests
npm run test

# Run tests in watch mode
npm run test:watch
```

### Code Quality

```bash
# Build TypeScript
npm run build

# Check for CDK differences
npm run diff

# Validate with CDK Nag
cdk synth | grep -i "warning\|error"
```

## Customization

### Modify Foundation Models

Edit `lib/knowledge-management-assistant-stack.ts`:

```typescript
// Change embedding model
embeddingsModel: bedrock.BedrockFoundationModel.COHERE_EMBED_MULTILINGUAL_V3,

// Change agent model
foundationModel: bedrock.BedrockFoundationModel.ANTHROPIC_CLAUDE_3_HAIKU_20240307_V1_0,
```

### Adjust Chunking Strategy

```typescript
// Modify chunking configuration
chunkingStrategy: bedrock.ChunkingStrategy.semantic({
  bufferSize: 0,
  breakpointPercentileThreshold: 95,
  maxTokens: 300,
}),
```

### Add Authentication

Integrate with Amazon Cognito:

```typescript
import { ApiGatewayToCognito } from '@aws-solutions-constructs/aws-cognito-apigateway-lambda';

// Replace ApiGatewayToLambda with authenticated version
const authenticatedApi = new ApiGatewayToCognito(this, 'AuthenticatedApi', {
  // ... configuration
});
```

## Monitoring

### CloudWatch Dashboards

Monitor the solution through:
- Lambda function metrics and logs
- API Gateway request metrics
- Bedrock usage metrics
- S3 bucket access patterns

### Key Metrics

- Lambda invocation count and duration
- API Gateway 4xx/5xx error rates
- Bedrock token usage and latency
- Knowledge base ingestion status

### Troubleshooting

Common issues and solutions:

1. **Model Access Denied**: Enable Bedrock model access in AWS Console
2. **Ingestion Failures**: Check S3 bucket permissions and document formats
3. **API Timeout**: Increase Lambda timeout or optimize queries
4. **CORS Issues**: Verify CORS configuration in API Gateway

## Security Considerations

### Production Deployment

For production environments:

1. **Enable Authentication**: Implement Cognito or custom authorizers
2. **Network Security**: Deploy in VPC with private subnets
3. **Data Encryption**: Use customer-managed KMS keys
4. **Access Logging**: Enable CloudTrail and VPC Flow Logs
5. **Secrets Management**: Use AWS Secrets Manager for credentials

### IAM Best Practices

- Use least privilege access
- Regularly rotate access keys
- Monitor IAM usage with Access Analyzer
- Implement resource-based policies

## Cost Optimization

### Cost Estimates

Monthly costs for moderate usage (1000 queries/day):
- Bedrock Claude 3.5 Sonnet: ~$50-100
- Bedrock Titan Embeddings: ~$10-20
- Lambda: ~$5-10
- API Gateway: ~$10-15
- S3 and OpenSearch: ~$20-30

**Total estimated cost: $95-175/month**

### Cost Reduction Strategies

1. **Optimize Chunking**: Reduce token usage with efficient chunking
2. **Cache Responses**: Implement response caching for common queries
3. **Use Cheaper Models**: Consider Claude 3 Haiku for simpler queries
4. **Monitor Usage**: Set up billing alerts and usage quotas

## Cleanup

To remove all resources:

```bash
# Destroy the stack
npm run destroy

# Or with confirmation
cdk destroy KnowledgeManagementAssistant
```

**Note**: S3 bucket objects are automatically deleted due to `autoDeleteObjects: true` setting.

## Support and Contributing

### Getting Help

1. **AWS Documentation**: [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/)
2. **CDK Documentation**: [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
3. **GenAI CDK Constructs**: [GitHub Repository](https://github.com/cdklabs/generative-ai-cdk-constructs)

### Contributing

1. Fork the repository
2. Create a feature branch
3. Implement changes with tests
4. Submit a pull request

## License

This solution is licensed under the MIT-0 License. See the LICENSE file for details.

## Additional Resources

- [Amazon Bedrock Agents Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html)
- [Amazon Bedrock Knowledge Bases Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
- [AWS Solutions Constructs](https://aws.amazon.com/solutions/constructs/)
- [CDK Nag for Security](https://github.com/cdklabs/cdk-nag)