# Infrastructure as Code for Enterprise API Integration with AgentCore Gateway and Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise API Integration with AgentCore Gateway and Step Functions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an intelligent API integration system that combines:

- **Amazon Bedrock AgentCore Gateway**: Transforms enterprise APIs into agent-compatible tools
- **AWS Step Functions**: Orchestrates complex workflow management with parallel processing
- **AWS Lambda Functions**: Handles data transformation and validation
- **Amazon API Gateway**: Provides secure external access with throttling and monitoring
- **IAM Roles**: Implements least-privilege security across all components

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Bedrock AgentCore Gateway (preview access required)
  - AWS Step Functions
  - AWS Lambda
  - Amazon API Gateway
  - IAM role creation and management
- Node.js 18+ (for CDK TypeScript implementation)
- Python 3.9+ (for CDK Python implementation)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $10-15 for testing resources

> **Note**: Amazon Bedrock AgentCore Gateway is currently in preview and requires console-based configuration. Ensure you have enabled Bedrock services in your AWS region.

## Quick Start

### Using CloudFormation (AWS)

Deploy the complete infrastructure stack:

```bash
# Deploy the main infrastructure stack
aws cloudformation create-stack \
    --stack-name enterprise-api-integration \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=api-integration-demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name enterprise-api-integration \
    --query 'Stacks[0].StackStatus'

# Get output values including API Gateway endpoint
aws cloudformation describe-stacks \
    --stack-name enterprise-api-integration \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

Initialize and deploy with TypeScript:

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the infrastructure
cdk deploy --require-approval never

# Get stack outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python (AWS)

Initialize and deploy with Python:

```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --require-approval never

# View deployment outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

Deploy using Terraform with official AWS provider:

```bash
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the deployment plan
terraform plan -var="project_name=api-integration-demo"

# Apply the infrastructure changes
terraform apply -var="project_name=api-integration-demo" -auto-approve

# View important output values
terraform output
```

### Using Bash Scripts

Quick deployment using automated bash scripts:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure with guided setup
./scripts/deploy.sh

# Monitor deployment status
./scripts/deploy.sh --status

# View endpoint information
./scripts/deploy.sh --outputs
```

## Manual AgentCore Gateway Configuration

After infrastructure deployment, complete the AgentCore Gateway setup:

1. **Navigate to Amazon Bedrock AgentCore Gateway Console**:
   ```
   https://console.aws.amazon.com/bedrock/agentcore/gateway
   ```

2. **Create Gateway**:
   - Name: `enterprise-gateway-{your-suffix}`
   - Description: "Enterprise API Integration Gateway"

3. **Add OpenAPI Target**:
   - Upload the generated `enterprise-api-spec.json`
   - Configure endpoint URL from deployment outputs
   - Set authentication method to OAuth/IAM

4. **Add Lambda Target**:
   - Function: `api-transformer-{your-suffix}`
   - Configure appropriate timeout settings

5. **Configure OAuth Authorizer**:
   - Set up OAuth2 credentials for agent authentication
   - Configure token validation rules

6. **Test Gateway Connectivity**:
   - Use the gateway testing interface
   - Verify tool discovery functionality

## Testing the Deployment

### Test API Gateway Endpoint

```bash
# Get the API Gateway endpoint from deployment outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name enterprise-api-integration \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayEndpoint`].OutputValue' \
    --output text)

# Test the integration with sample data
curl -X POST ${API_ENDPOINT}/integrate \
    -H "Content-Type: application/json" \
    -d '{
        "id": "test-001",
        "type": "erp",
        "data": {
            "transaction_type": "purchase_order",
            "amount": 1500.00,
            "vendor": "Acme Corp"
        },
        "validation_type": "financial"
    }'
```

### Monitor Step Functions Execution

```bash
# Get the state machine ARN
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
    --stack-name enterprise-api-integration \
    --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
    --output text)

# List recent executions
aws stepfunctions list-executions \
    --state-machine-arn ${STATE_MACHINE_ARN} \
    --max-items 5

# Get execution details (replace with actual execution ARN)
EXECUTION_ARN=$(aws stepfunctions list-executions \
    --state-machine-arn ${STATE_MACHINE_ARN} \
    --max-items 1 \
    --query 'executions[0].executionArn' --output text)

aws stepfunctions describe-execution \
    --execution-arn ${EXECUTION_ARN}
```

### Validate Lambda Functions

```bash
# Test data validator function
aws lambda invoke \
    --function-name data-validator-{your-suffix} \
    --payload '{
        "data": {
            "id": "test-123",
            "type": "financial",
            "amount": 250.50,
            "email": "test@example.com"
        },
        "validation_type": "financial"
    }' \
    validator-response.json

cat validator-response.json
```

## Customization

### Environment Variables

Configure deployment through environment variables:

```bash
# CloudFormation parameters
export PROJECT_NAME="my-api-integration"
export AWS_REGION="us-east-1"
export NOTIFICATION_EMAIL="admin@example.com"

# CDK context variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION="us-east-1"

# Terraform variables
export TF_VAR_project_name="my-api-integration"
export TF_VAR_aws_region="us-east-1"
export TF_VAR_enable_monitoring="true"
```

### Resource Configuration

Modify key parameters in each implementation:

- **Lambda Function Configuration**:
  - Memory allocation (256MB - 3008MB)
  - Timeout settings (30s - 900s)
  - Environment variables for external API endpoints

- **Step Functions Settings**:
  - State machine type (STANDARD vs EXPRESS)
  - Retry configuration and backoff strategies
  - Error handling and dead letter queue settings

- **API Gateway Configuration**:
  - Throttling limits and rate limiting
  - CORS settings for web applications
  - Request/response transformation templates

### Security Customization

Enhance security based on your requirements:

```bash
# Configure VPC endpoints for private communication
# Add WAF rules for API Gateway protection
# Implement AWS Secrets Manager for sensitive credentials
# Enable AWS X-Ray for distributed tracing
```

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- **API Integration Overview**: Request rates, error rates, latency metrics
- **Lambda Performance**: Function duration, errors, concurrent executions
- **Step Functions Execution**: Success rates, execution duration, state transitions

### CloudWatch Alarms

Configured alarms for proactive monitoring:

- API Gateway 4xx/5xx error rates
- Lambda function errors and timeout
- Step Functions execution failures
- High latency alerts

### AWS X-Ray Tracing

Enable distributed tracing for request flow visibility:

```bash
# View trace map in AWS X-Ray console
# Analyze service dependencies
# Identify performance bottlenecks
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name enterprise-api-integration

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name enterprise-api-integration \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy CDK resources
cd cdk-typescript/ # or cdk-python/
cdk destroy --force

# Clean up CDK bootstrap (optional)
# aws cloudformation delete-stack --stack-name CDKToolkit
```

### Using Terraform

```bash
cd terraform/

# Destroy Terraform-managed resources
terraform destroy -var="project_name=api-integration-demo" -auto-approve

# Clean up Terraform state files
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Automated cleanup
./scripts/destroy.sh

# Confirm cleanup completion
./scripts/destroy.sh --verify
```

### Manual AgentCore Gateway Cleanup

Clean up AgentCore Gateway resources manually:

1. Delete gateway targets (OpenAPI and Lambda)
2. Remove OAuth authorizer configurations
3. Delete the AgentCore Gateway

## Cost Optimization

### Resource Sizing

- **Lambda Functions**: Start with 256MB memory, monitor and adjust
- **API Gateway**: Use caching to reduce backend calls
- **Step Functions**: Choose EXPRESS type for high-volume, short-duration workflows

### Cost Monitoring

```bash
# Set up AWS Budgets for cost tracking
aws budgets create-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget file://budget-config.json

# Configure AWS Cost Anomaly Detection
aws ce create-anomaly-monitor \
    --anomaly-monitor file://cost-monitor-config.json
```

### Reserved Capacity

Consider reserved capacity for production workloads:

- API Gateway: Request-based pricing optimization
- Lambda: Provisioned concurrency for consistent performance
- Step Functions: Standard vs Express workflow selection

## Troubleshooting

### Common Issues

1. **AgentCore Gateway Access**: Ensure Bedrock services are enabled in your region
2. **IAM Permissions**: Verify all required permissions are granted
3. **Lambda Timeouts**: Increase timeout for external API calls
4. **Step Functions Errors**: Check CloudWatch Logs for detailed error messages

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
aws logs tail "/aws/lambda/api-transformer-{suffix}" --follow

# Monitor Step Functions executions
aws stepfunctions list-executions --state-machine-arn ${STATE_MACHINE_ARN}

# Validate API Gateway health
aws apigateway get-rest-apis
aws apigateway test-invoke-method --rest-api-id ${API_ID} --resource-id ${RESOURCE_ID} --http-method POST
```

### Performance Tuning

- Monitor Lambda cold start times and consider provisioned concurrency
- Optimize Step Functions workflow for parallel execution
- Implement API Gateway caching for frequently accessed data
- Use CloudWatch Insights for detailed performance analysis

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Consult AWS service documentation:
   - [Amazon Bedrock AgentCore Gateway Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway.html)
   - [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)
   - [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
   - [Amazon API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/welcome.html)
3. Check AWS CloudFormation/CDK/Terraform documentation for specific resource configurations
4. Review AWS Well-Architected Framework for best practices

## Security Considerations

- All IAM roles follow least privilege principle
- API Gateway includes throttling and monitoring
- Lambda functions have restricted execution permissions
- AgentCore Gateway implements OAuth2 authentication
- All data in transit is encrypted using TLS 1.2+
- CloudTrail logging enabled for audit compliance

## Next Steps

1. Configure AgentCore Gateway targets for your specific enterprise APIs
2. Customize validation rules in the data validator Lambda function
3. Extend the solution with additional API transformation logic
4. Implement comprehensive monitoring and alerting
5. Add integration with your existing identity provider for OAuth authentication

This infrastructure provides a robust foundation for enterprise API integration using AWS serverless technologies with intelligent agent capabilities through Amazon Bedrock AgentCore Gateway.