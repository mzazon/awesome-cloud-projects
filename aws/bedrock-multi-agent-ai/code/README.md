# Infrastructure as Code for Bedrock Multi-Agent AI Workflows with AgentCore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Bedrock Multi-Agent AI Workflows with AgentCore".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a collaborative multi-agent AI system using Amazon Bedrock that orchestrates specialized agents through event-driven coordination. The architecture includes:

- **Supervisor Agent**: Central coordinator for multi-agent workflows
- **Specialized Agents**: Domain-specific agents for finance, support, and analytics
- **Event-Driven Orchestration**: Amazon EventBridge for agent communication
- **Workflow Coordination**: AWS Lambda for task routing and aggregation
- **Shared Memory**: DynamoDB for agent context and conversation history
- **Monitoring**: CloudWatch and X-Ray for observability

## Prerequisites

### AWS Account and Permissions

- AWS account with Amazon Bedrock access and Claude 3 model access granted
- IAM permissions for the following services:
  - Amazon Bedrock (full access for agent creation and management)
  - AWS Lambda (function creation and execution)
  - Amazon EventBridge (custom bus and rule management)
  - Amazon DynamoDB (table creation and data access)
  - AWS IAM (role creation and policy management)
  - Amazon CloudWatch (logging and monitoring)
  - AWS X-Ray (distributed tracing)

### Tools and CLI

- AWS CLI v2 installed and configured (or use AWS CloudShell)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform deployment)

### Cost Estimates

- **Development/Testing**: $75-150 per month
  - Amazon Bedrock model usage: $50-100
  - AWS Lambda invocations: $5-15
  - EventBridge events: $1-5
  - DynamoDB storage: $5-10
  - CloudWatch logs/metrics: $10-20

- **Production**: $200-500+ per month (varies with usage)

## Quick Start

### Using CloudFormation

```bash
# Validate the template
aws cloudformation validate-template \
    --template-body file://cloudformation.yaml

# Create the stack
aws cloudformation create-stack \
    --stack-name multi-agent-bedrock-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
                ParameterKey=ProjectName,ParameterValue=multiagent-ai \
    --capabilities CAPABILITY_IAM \
    --enable-termination-protection

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name multi-agent-bedrock-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name multi-agent-bedrock-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Preview changes
npx cdk diff

# Deploy the stack
npx cdk deploy \
    --parameters Environment=dev \
    --parameters ProjectName=multiagent-ai \
    --require-approval never

# View stack outputs
npx cdk list
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

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy \
    --parameters Environment=dev \
    --parameters ProjectName=multiagent-ai \
    --require-approval never

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your specific values
nano terraform.tfvars

# Plan the deployment
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

# Run deployment script
./scripts/deploy.sh

# The script will:
# 1. Validate prerequisites
# 2. Set up environment variables
# 3. Deploy all infrastructure components
# 4. Configure agent relationships
# 5. Test the deployment

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

```bash
# Required
export AWS_REGION="us-east-1"
export PROJECT_NAME="multiagent-ai"
export ENVIRONMENT="dev"

# Optional
export BEDROCK_MODEL_ID="anthropic.claude-3-sonnet-20240229-v1:0"
export AGENT_SESSION_TTL="3600"
export LAMBDA_TIMEOUT="60"
export DYNAMODB_READ_CAPACITY="5"
export DYNAMODB_WRITE_CAPACITY="5"
export LOG_RETENTION_DAYS="30"
```

### CloudFormation Parameters

```yaml
Parameters:
  Environment:
    Type: String
    Default: dev
    Description: Environment name (dev, staging, prod)
  
  ProjectName:
    Type: String
    Default: multiagent-ai
    Description: Project name for resource naming
  
  BedrockModelId:
    Type: String
    Default: anthropic.claude-3-sonnet-20240229-v1:0
    Description: Bedrock foundation model ID
  
  AgentSessionTTL:
    Type: Number
    Default: 3600
    Description: Agent session timeout in seconds
```

### Terraform Variables

```hcl
# terraform.tfvars
project_name = "multiagent-ai"
environment  = "dev"
aws_region   = "us-east-1"

bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
agent_session_ttl = 3600
lambda_timeout = 60

# DynamoDB configuration
dynamodb_read_capacity  = 5
dynamodb_write_capacity = 5

# CloudWatch configuration
log_retention_days = 30

# Tags
tags = {
  Project     = "MultiAgent-AI"
  Environment = "dev"
  Owner       = "platform-team"
}
```

## Post-Deployment Configuration

### 1. Verify Agent Creation

```bash
# List all created agents
aws bedrock-agent list-agents \
    --query 'agentSummaries[].{Name:agentName,Status:agentStatus,ID:agentId}' \
    --output table

# Check agent aliases
aws bedrock-agent list-agent-aliases \
    --agent-id <SUPERVISOR_AGENT_ID> \
    --output table
```

### 2. Test Multi-Agent Workflow

```bash
# Invoke supervisor agent with test request
aws bedrock-agent-runtime invoke-agent \
    --agent-id <SUPERVISOR_AGENT_ID> \
    --agent-alias-id <ALIAS_ID> \
    --session-id test-session-$(date +%s) \
    --input-text "Please coordinate a business analysis including financial review, customer satisfaction analysis, and sales trends." \
    --output text --query 'completion'
```

### 3. Monitor System Health

```bash
# Check CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name MultiAgentWorkflow-<RANDOM_SUFFIX>

# View Lambda function logs
aws logs tail /aws/lambda/<COORDINATOR_FUNCTION_NAME> \
    --since 1h
```

## Troubleshooting

### Common Issues

1. **Bedrock Model Access Denied**
   - Ensure your account has access to Claude 3 models in Amazon Bedrock
   - Request model access through the AWS console if needed

2. **Agent Creation Timeout**
   - Agent preparation can take 2-3 minutes
   - Check agent status with `aws bedrock-agent get-agent`

3. **EventBridge Rule Not Triggering**
   - Verify Lambda function permissions
   - Check EventBridge rule pattern matching

4. **DynamoDB Throttling**
   - Increase read/write capacity units
   - Consider using on-demand billing mode

### Debug Commands

```bash
# Check IAM role assumptions
aws sts get-caller-identity

# Verify Bedrock service availability
aws bedrock list-foundation-models \
    --by-provider anthropic

# Test EventBridge connectivity
aws events test-event-pattern \
    --event-pattern file://event-pattern.json \
    --event file://test-event.json

# Check Lambda function configuration
aws lambda get-function \
    --function-name <COORDINATOR_FUNCTION_NAME>
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name multi-agent-bedrock-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name multi-agent-bedrock-stack

# Verify stack deletion
aws cloudformation describe-stacks \
    --stack-name multi-agent-bedrock-stack 2>/dev/null || echo "Stack deleted successfully"
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Destroy the stack
npx cdk destroy \
    --require-approval never

# Verify cleanup
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Activate virtual environment
source .venv/bin/activate

# Destroy the stack
cdk destroy \
    --require-approval never

# Deactivate virtual environment
deactivate
```

### Using Terraform

```bash
cd terraform/

# Plan destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy \
    -auto-approve

# Clean up state files (optional)
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Prompt for confirmation
# 2. Delete resources in reverse order
# 3. Verify cleanup completion
# 4. Remove local configuration files
```

## Customization

### Adding New Specialized Agents

1. **Modify Infrastructure Code**: Add new agent resource definitions
2. **Update Coordinator Logic**: Extend Lambda function routing logic
3. **Configure EventBridge Rules**: Add routing rules for new agent types
4. **Update Monitoring**: Include new agent in dashboards and alerts

### Scaling Considerations

- **DynamoDB**: Consider on-demand billing for variable workloads
- **Lambda**: Adjust memory and timeout based on coordination complexity
- **Bedrock**: Monitor token usage and implement cost controls
- **EventBridge**: Design for event replay and dead letter queue management

### Security Hardening

- Enable AWS CloudTrail for audit logging
- Implement VPC endpoints for private connectivity
- Use AWS Secrets Manager for sensitive configuration
- Configure resource-based policies for cross-service access
- Enable AWS Config rules for compliance monitoring

## Monitoring and Observability

### Key Metrics to Monitor

- **Agent Performance**: Invocation latency, success rates, token usage
- **Workflow Coordination**: EventBridge message processing, Lambda execution
- **System Health**: DynamoDB throttling, error rates, timeout events
- **Cost Management**: Bedrock token consumption, Lambda duration

### CloudWatch Dashboards

The deployment creates comprehensive dashboards showing:

- Real-time agent performance metrics
- Workflow execution patterns
- Error rates and timeout events
- Cost tracking and optimization opportunities

### Alerts and Notifications

Configure CloudWatch alarms for:

- High agent error rates (>5%)
- Excessive response times (>30 seconds)
- DynamoDB throttling events
- Lambda function failures

## Security Considerations

### IAM Best Practices

- All services use least-privilege access principles
- Cross-service access uses resource-based policies
- Role assumption is limited to specific services
- Regular access review and rotation recommended

### Data Protection

- Agent conversations stored in DynamoDB with encryption at rest
- CloudWatch logs encrypted by default
- EventBridge events support encryption in transit
- No sensitive data stored in Lambda environment variables

### Network Security

- All services communicate within AWS backbone
- Optional VPC deployment for additional isolation
- API Gateway can be added for external access control
- Consider AWS WAF for additional API protection

## Support and Documentation

### AWS Documentation

- [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)

### Additional Resources

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Amazon Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Community Support

- AWS re:Post for community questions
- GitHub Issues for infrastructure code problems
- AWS Support for production issues
- AWS Developer Forums for best practices

## License

This infrastructure code is provided as-is under the MIT License. See the original recipe documentation for detailed usage terms and conditions.

---

**Note**: This README provides deployment instructions for the complete multi-agent AI workflow infrastructure. For detailed explanation of the solution architecture and business use cases, refer to the original recipe documentation.