# Infrastructure as Code for Interactive Business Process Automation with Bedrock Agents and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Interactive Business Process Automation with Bedrock Agents and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent business process automation system that combines:

- **Amazon Bedrock Agents** for AI-powered document analysis and decision making
- **Amazon EventBridge** for event-driven workflow orchestration
- **AWS Lambda** functions for business process handlers
- **Amazon S3** for secure document storage
- **IAM roles and policies** following least privilege principles

The system automatically processes business documents (invoices, contracts, compliance documents), makes intelligent routing decisions, and triggers appropriate business workflows based on document type and AI confidence scores.

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- AWS account with appropriate permissions for:
  - Amazon Bedrock (with access to Anthropic Claude models)
  - EventBridge
  - Lambda
  - S3
  - IAM
- One of the following depending on your chosen deployment method:
  - **CloudFormation**: No additional tools required
  - **CDK TypeScript**: Node.js 18+ and npm
  - **CDK Python**: Python 3.8+ and pip
  - **Terraform**: Terraform 1.0+ installed
  - **Bash Scripts**: Standard bash shell

## Cost Considerations

Estimated cost for testing: $5-15 (varies by document volume and model usage)

- Amazon Bedrock: Pay per API call and tokens processed
- EventBridge: Pay per published event
- Lambda: Pay per invocation and execution time
- S3: Pay per storage and requests

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name business-automation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=biz-automation

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name business-automation-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name business-automation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the application
npx cdk deploy BusinessAutomationStack

# View deployed resources
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the application
cdk deploy BusinessAutomationStack

# View deployed resources
cdk list
```

### Using Terraform

```bash
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

# The script will:
# 1. Validate prerequisites
# 2. Create all required resources
# 3. Configure IAM permissions
# 4. Set up the Bedrock Agent
# 5. Configure EventBridge rules
# 6. Deploy Lambda functions
```

## Testing the Deployment

After deployment, test the system with these steps:

### 1. Upload a Test Document

```bash
# Create a sample invoice document
echo "INVOICE - TechSupplies Inc - Amount: $1,250.00 - Due: 2024-01-15" > test-invoice.txt

# Upload to S3 (replace BUCKET_NAME with actual bucket name from outputs)
aws s3 cp test-invoice.txt s3://BUCKET_NAME/incoming/
```

### 2. Invoke the Bedrock Agent

```bash
# Replace AGENT_ID and AGENT_ALIAS_ID with values from deployment outputs
aws bedrock-agent-runtime invoke-agent \
    --agent-id AGENT_ID \
    --agent-alias-id AGENT_ALIAS_ID \
    --session-id "test-session-$(date +%s)" \
    --input-text "Please analyze the invoice document and classify it as an invoice type document" \
    --output-file agent-response.json

# View agent response
cat agent-response.json
```

### 3. Check Event Processing

```bash
# View CloudWatch logs for Lambda functions (replace PROJECT_NAME)
aws logs filter-log-events \
    --log-group-name "/aws/lambda/PROJECT_NAME-approval" \
    --start-time $(date -d '10 minutes ago' +%s)000
```

## Customization

### Environment Variables

You can customize the deployment by modifying these parameters:

- **ProjectName**: Unique identifier for your resources (default: biz-automation)
- **Environment**: Deployment environment (dev, staging, prod)
- **DocumentBucketName**: S3 bucket name for document storage
- **AgentFoundationModel**: Bedrock foundation model to use
- **EventBusName**: Custom EventBridge event bus name

### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name business-automation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=my-automation \
        ParameterKey=Environment,ParameterValue=prod \
        ParameterKey=AgentFoundationModel,ParameterValue=anthropic.claude-3-sonnet-20240229-v1:0
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_name = "my-automation"
environment = "prod"
agent_foundation_model = "anthropic.claude-3-sonnet-20240229-v1:0"
lambda_memory_size = 512
lambda_timeout = 60
```

### CDK Context

For CDK deployments, modify `cdk.json` or pass context values:

```bash
npx cdk deploy -c projectName=my-automation -c environment=prod
```

## Security Considerations

This deployment implements several security best practices:

- **IAM Least Privilege**: All roles have minimal required permissions
- **S3 Encryption**: Documents are encrypted at rest using AES-256
- **S3 Versioning**: Enabled for document audit trails
- **EventBridge Permissions**: Custom event bus with restricted access
- **Lambda Security**: Functions run with minimal IAM permissions
- **Bedrock Access**: Agent has specific model access only

## Monitoring and Observability

The deployment includes monitoring capabilities:

- **CloudWatch Logs**: All Lambda functions log to CloudWatch
- **CloudWatch Metrics**: EventBridge and Lambda metrics available
- **X-Ray Tracing**: Enabled for distributed tracing (optional)
- **EventBridge Monitoring**: Event processing metrics and failure tracking

### Key Metrics to Monitor

- EventBridge rule invocations and failures
- Lambda function duration and errors
- Bedrock Agent invocation count and latency
- S3 document upload and processing rates

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name business-automation-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name business-automation-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy BusinessAutomationStack
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy BusinessAutomationStack
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

# The script will:
# 1. Remove all Lambda functions
# 2. Delete EventBridge rules and event bus
# 3. Remove Bedrock Agent and aliases
# 4. Delete IAM roles and policies
# 5. Empty and delete S3 bucket
# 6. Clean up any remaining resources
```

## Troubleshooting

### Common Issues

1. **Bedrock Model Access**: Ensure you have enabled access to Anthropic Claude models in Amazon Bedrock console
2. **IAM Permissions**: Verify your AWS credentials have permissions for all required services
3. **Region Support**: Ensure all services are available in your chosen AWS region
4. **Agent Preparation**: Bedrock Agents require time to prepare after creation

### Debug Commands

```bash
# Check CloudFormation stack events
aws cloudformation describe-stack-events --stack-name business-automation-stack

# Check Lambda function logs
aws logs tail /aws/lambda/FUNCTION_NAME --follow

# Check EventBridge rule details
aws events describe-rule --name RULE_NAME --event-bus-name EVENT_BUS_NAME

# Check Bedrock Agent status
aws bedrock-agent get-agent --agent-id AGENT_ID
```

### Support Resources

- [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)

## Advanced Configuration

### Multiple Document Types

To support additional document types, modify the EventBridge rules and Lambda function logic:

1. Update the agent action schema to include new document types
2. Add corresponding EventBridge rules for new document patterns
3. Enhance Lambda function processing logic for new document types

### Knowledge Base Integration

For enhanced AI capabilities, consider integrating Amazon Bedrock Knowledge Base:

1. Create a Knowledge Base with company policies and procedures
2. Associate the Knowledge Base with your Bedrock Agent
3. Update agent instructions to reference knowledge base content

### Human-in-the-Loop Workflows

To add human approval processes:

1. Implement Step Functions for workflow orchestration
2. Add SES for email notifications
3. Create API Gateway endpoints for approval interfaces
4. Update EventBridge rules to route low-confidence documents to human review

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation
2. AWS service-specific documentation linked above
3. AWS support channels for service-specific issues
4. Community forums for best practices and troubleshooting