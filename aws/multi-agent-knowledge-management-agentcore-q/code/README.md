# Infrastructure as Code for Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a multi-agent knowledge management system that includes:

- **Supervisor Agent**: Orchestrates specialized agents and synthesizes responses
- **Specialized Agents**: Finance, HR, and Technical domain experts
- **Q Business Application**: Enterprise search and knowledge retrieval
- **Knowledge Storage**: Domain-specific S3 buckets with sample documents
- **API Gateway**: Secure external interface for user queries
- **Session Management**: DynamoDB-based conversation context storage

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- AWS account with Bedrock AgentCore and Q Business access (preview features enabled)
- Understanding of multi-agent architectures and enterprise knowledge management
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.9+ (Python)
- For Terraform: Terraform 1.6+ installed
- Estimated cost: $50-100 for testing (includes model inference, storage, and runtime costs)

### Required AWS Permissions

Your AWS credentials must have permissions for:
- IAM role and policy management
- Lambda function creation and management
- S3 bucket creation and object management
- API Gateway v2 management
- DynamoDB table creation and management
- Amazon Q Business application and data source management
- Amazon Bedrock AgentCore access (preview)

> **Note**: Bedrock AgentCore is in preview and requires enabling preview features in your AWS account. Refer to the [AgentCore documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/what-is-bedrock-agentcore.html) for availability and access requirements.

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete multi-agent system
aws cloudformation create-stack \
    --stack-name multi-agent-knowledge-mgmt \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=multi-agent-km \
                ParameterKey=Environment,ParameterValue=prod

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name multi-agent-knowledge-mgmt \
    --query 'Stacks[0].StackStatus'

# Get API endpoint for testing
aws cloudformation describe-stacks \
    --stack-name multi-agent-knowledge-mgmt \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Review planned deployment
cdk diff

# Deploy the multi-agent system
cdk deploy --all

# Get outputs including API endpoint
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Review planned deployment
cdk diff

# Deploy the multi-agent system
cdk deploy --all

# Get outputs including API endpoint
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned infrastructure changes
terraform plan

# Apply infrastructure changes
terraform apply

# Get API endpoint from outputs
terraform output api_endpoint
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete system
./scripts/deploy.sh

# The script will output the API endpoint for testing
```

## Post-Deployment Testing

After successful deployment, test the multi-agent system:

```bash
# Set your API endpoint (replace with actual endpoint from outputs)
export API_ENDPOINT="https://your-api-id.execute-api.us-east-1.amazonaws.com/prod"

# Test comprehensive query requiring multiple agents
curl -X POST ${API_ENDPOINT}/query \
    -H "Content-Type: application/json" \
    -d '{
        "query": "What is the budget approval process for international travel expenses and how does it relate to employee performance reviews?",
        "sessionId": "test-session-001"
    }' | jq '.'

# Test health endpoint
curl -X GET ${API_ENDPOINT}/health | jq '.'

# Test follow-up query for context awareness
curl -X POST ${API_ENDPOINT}/query \
    -H "Content-Type: application/json" \
    -d '{
        "query": "Can you provide more details about the approval timeframes mentioned earlier?",
        "sessionId": "test-session-001"
    }' | jq '.'
```

Expected responses should include:
- Synthesized answers from multiple specialized agents
- Source attributions from domain-specific knowledge bases
- Session context preservation across queries
- Confidence scores for agent responses

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- **Agent Performance**: Lambda function metrics, duration, and error rates
- **Q Business Usage**: Query patterns, data source synchronization status
- **API Gateway Metrics**: Request counts, latency, and error rates
- **Session Management**: DynamoDB read/write patterns and capacity utilization

### Key Metrics to Monitor

```bash
# Monitor Lambda function performance
aws logs filter-log-events \
    --log-group-name /aws/lambda/supervisor-agent \
    --start-time $(date -d '1 hour ago' +%s)000

# Check Q Business application health
aws qbusiness get-application \
    --application-id YOUR_Q_APP_ID \
    --query 'status'

# Monitor API Gateway usage
aws apigatewayv2 get-stage \
    --api-id YOUR_API_ID \
    --stage-name prod
```

## Customization

### Environment Variables

Each implementation supports customization through variables:

- **ProjectName**: Prefix for all resource names (default: multi-agent-km)
- **Environment**: Deployment environment (dev/staging/prod)
- **AgentTimeout**: Lambda function timeout in seconds (default: 60 for supervisor, 30 for specialists)
- **MemorySize**: Lambda memory allocation (default: 512MB for supervisor, 256MB for specialists)
- **ApiThrottleRateLimit**: API Gateway rate limiting (default: 500 requests/second)
- **SessionTTL**: DynamoDB session TTL in hours (default: 24 hours)

### Adding New Specialist Agents

To extend the system with additional domain expertise:

1. **Create Agent Code**: Follow the pattern established by existing agents
2. **Update Supervisor Logic**: Add new agent to the determination and invocation logic
3. **Add Knowledge Sources**: Create domain-specific S3 buckets and Q Business data sources
4. **Update Infrastructure**: Modify IaC templates to include new resources

### Knowledge Base Management

```bash
# Add new documents to existing knowledge bases
aws s3 cp new-finance-policy.pdf s3://finance-kb-bucket/ \
    --metadata "department=finance,type=policy,version=2.0"

# Trigger data source synchronization
aws qbusiness start-data-source-sync-job \
    --application-id YOUR_Q_APP_ID \
    --data-source-id YOUR_DATA_SOURCE_ID
```

## Security Considerations

### IAM Roles and Policies

The deployment follows least privilege principles:

- **Agent Execution Role**: Minimal permissions for Lambda execution and Q Business access
- **Q Business Service Role**: Permissions for S3 data source access
- **API Gateway**: No authentication required for demo (implement authentication for production)

### Data Protection

- **Encryption at Rest**: All S3 buckets use AES-256 server-side encryption
- **Encryption in Transit**: All communications use TLS 1.2+
- **Session Data**: Stored in DynamoDB with automatic TTL for privacy
- **Access Controls**: Q Business user groups control knowledge access

### Production Security Recommendations

```bash
# Enable API Gateway authentication
aws apigatewayv2 create-authorizer \
    --api-id YOUR_API_ID \
    --authorizer-type JWT \
    --name multi-agent-authorizer

# Enable CloudTrail for audit logging
aws cloudtrail create-trail \
    --name multi-agent-audit-trail \
    --s3-bucket-name audit-logs-bucket
```

## Troubleshooting

### Common Issues

1. **AgentCore Preview Access**: Ensure your account has preview features enabled
2. **Q Business Permissions**: Verify IAM roles have proper Q Business permissions
3. **Data Source Sync**: Check S3 bucket permissions and object accessibility
4. **Lambda Timeouts**: Increase timeout values for complex queries
5. **API Gateway CORS**: Verify CORS configuration for web application integration

### Debug Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/supervisor-agent --follow

# Verify Q Business data source status
aws qbusiness list-data-source-sync-jobs \
    --application-id YOUR_Q_APP_ID \
    --data-source-id YOUR_DATA_SOURCE_ID

# Test individual agent functions
aws lambda invoke \
    --function-name finance-agent \
    --payload '{"query": "expense approval process"}' \
    response.json && cat response.json
```

### Support Resources

- [Amazon Q Business Documentation](https://docs.aws.amazon.com/amazonq/latest/qbusiness-ug/)
- [Bedrock AgentCore Developer Guide](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [Multi-Agent System Design Patterns](https://aws.amazon.com/blogs/machine-learning/)

## Cleanup

### Using CloudFormation

```bash
# Delete the complete stack
aws cloudformation delete-stack \
    --stack-name multi-agent-knowledge-mgmt

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name multi-agent-knowledge-mgmt \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy --all
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy --all
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script includes confirmation prompts for safety
```

## Cost Optimization

### Resource Sizing

- **Lambda Functions**: Start with default memory settings and adjust based on CloudWatch metrics
- **DynamoDB**: Uses on-demand billing for unpredictable workloads
- **S3 Storage**: Implement lifecycle policies for document archival
- **Q Business**: Monitor usage patterns and adjust data source refresh schedules

### Cost Monitoring

```bash
# Enable cost allocation tags
aws resourcegroupstaggingapi tag-resources \
    --resource-arn-list "arn:aws:lambda:region:account:function:*agent*" \
    --tags Project=MultiAgentKM,Environment=prod
```

## Performance Optimization

### Scaling Considerations

- **Lambda Concurrency**: Configure reserved concurrency for consistent performance
- **API Gateway Caching**: Enable caching for frequently accessed responses
- **Q Business Indexing**: Optimize data source refresh schedules based on content update frequency
- **Session Management**: Implement connection pooling for high-volume scenarios

### Monitoring Performance

```bash
# Create CloudWatch dashboard for key metrics
aws cloudwatch put-dashboard \
    --dashboard-name "MultiAgentKnowledgeManagement" \
    --dashboard-body file://dashboard-config.json
```

## Version History

- **v1.0**: Initial implementation with basic multi-agent coordination
- **v1.1**: Enhanced error handling and fallback mechanisms
- **v1.2**: Added session persistence and context awareness
- **v1.3**: Improved Q Business integration and source attribution

## Contributing

To contribute improvements to this infrastructure:

1. Test changes in a development environment
2. Update relevant IaC implementations
3. Validate security and performance implications
4. Update documentation and examples

For questions or issues with this infrastructure code, refer to the original recipe documentation or AWS service documentation.