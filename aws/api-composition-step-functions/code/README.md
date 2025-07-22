# Infrastructure as Code for API Composition with Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "API Composition with Step Functions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - Step Functions state machines
  - API Gateway REST APIs
  - Lambda functions
  - DynamoDB tables
  - IAM roles and policies
  - CloudWatch logs
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+

## Architecture Overview

This implementation creates:
- **Step Functions state machine** for order processing workflow orchestration
- **API Gateway REST API** with Step Functions integration
- **Lambda functions** for microservices (user validation, inventory checking)
- **DynamoDB tables** for orders and audit logging
- **IAM roles and policies** for secure service integration
- **CloudWatch logs** for monitoring and debugging

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name api-composition-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-api-composition

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name api-composition-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint
aws cloudformation describe-stacks \
    --stack-name api-composition-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# Get outputs
terraform output api_endpoint
terraform output state_machine_arn
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output API endpoint and other important values
```

## Testing the Deployment

After deployment, test the API composition:

```bash
# Get the API endpoint from your deployment outputs
export API_ENDPOINT="<your-api-endpoint>"

# Test successful order processing
curl -X POST "${API_ENDPOINT}/orders" \
    -H "Content-Type: application/json" \
    -d '{
      "orderId": "order-123",
      "userId": "user456",
      "items": [
        {
          "productId": "prod-1",
          "quantity": 2
        },
        {
          "productId": "prod-2",
          "quantity": 1
        }
      ]
    }'

# Test order status endpoint
curl -X GET "${API_ENDPOINT}/orders/order-123/status"

# Test error handling with invalid user
curl -X POST "${API_ENDPOINT}/orders" \
    -H "Content-Type: application/json" \
    -d '{
      "orderId": "order-fail-123",
      "userId": "xx",
      "items": [
        {
          "productId": "prod-1",
          "quantity": 2
        }
      ]
    }'
```

## Monitoring and Debugging

### CloudWatch Logs
Monitor execution logs:
```bash
# View Step Functions execution logs
aws logs describe-log-groups --log-group-name-prefix "/aws/stepfunctions/"

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# View API Gateway logs
aws logs describe-log-groups --log-group-name-prefix "API-Gateway-Execution-Logs"
```

### Step Functions Console
- Navigate to AWS Step Functions console
- View state machine executions
- Analyze execution history and visual workflow
- Debug failed executions

### API Gateway Console
- Monitor API usage and performance metrics
- View request/response logs
- Test API methods directly

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name api-composition-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name api-composition-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the respective CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Environment Variables
All implementations support customization through variables:

- **ProjectName**: Prefix for resource names (default: "api-composition")
- **Environment**: Deployment environment (default: "dev")
- **LogRetentionDays**: CloudWatch log retention period (default: 7 days)
- **ApiStageName**: API Gateway stage name (default: "prod")

### CloudFormation Parameters
Customize deployment by modifying parameters:
```bash
aws cloudformation create-stack \
    --stack-name api-composition-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=my-project \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=LogRetentionDays,ParameterValue=30
```

### CDK Context
Configure CDK deployments using `cdk.json`:
```json
{
  "context": {
    "projectName": "my-api-composition",
    "environment": "production",
    "logRetentionDays": 30
  }
}
```

### Terraform Variables
Create `terraform.tfvars` file:
```hcl
project_name        = "my-api-composition"
environment         = "production"
log_retention_days  = 30
api_stage_name      = "prod"
```

## Security Considerations

### IAM Policies
All implementations follow the principle of least privilege:
- Step Functions role has minimal permissions for DynamoDB and Lambda
- Lambda execution roles are scoped to specific resources
- API Gateway has limited permissions for Step Functions execution

### Data Encryption
- DynamoDB tables use AWS managed encryption at rest
- CloudWatch logs are encrypted
- API Gateway supports TLS 1.2+ for data in transit

### Network Security
- All services communicate within AWS backbone
- No public endpoints except API Gateway
- Consider implementing WAF rules for production deployments

## Production Considerations

### Scaling
- DynamoDB tables use on-demand billing for automatic scaling
- Lambda functions scale automatically based on demand
- API Gateway handles up to 10,000 requests per second by default
- Step Functions supports 2,000+ concurrent executions

### Cost Optimization
- Lambda functions use ARM-based Graviton2 processors where possible
- DynamoDB on-demand billing reduces costs for variable workloads
- CloudWatch log retention is configurable to manage storage costs

### High Availability
- All services are deployed across multiple Availability Zones
- DynamoDB provides 99.999% availability SLA
- API Gateway and Step Functions are highly available by default

### Monitoring and Alerting
Consider adding:
- CloudWatch alarms for error rates and latencies
- X-Ray tracing for distributed request tracking
- Custom metrics for business-specific monitoring

## Troubleshooting

### Common Issues

**State Machine Execution Failures**
- Check IAM permissions for Step Functions role
- Verify Lambda function configurations
- Review CloudWatch logs for detailed error messages

**API Gateway 5xx Errors**
- Validate integration configurations
- Check Step Functions permissions
- Review request mapping templates

**DynamoDB Access Errors**
- Verify table names match configuration
- Check IAM policies for DynamoDB permissions
- Ensure tables exist in the correct region

**Lambda Function Timeouts**
- Increase function timeout settings
- Optimize function code for performance
- Consider using Step Functions Express Workflows for short-duration tasks

### Debug Commands
```bash
# List Step Functions executions
aws stepfunctions list-executions \
    --state-machine-arn <state-machine-arn> \
    --max-items 10

# Get execution details
aws stepfunctions describe-execution \
    --execution-arn <execution-arn>

# View execution history
aws stepfunctions get-execution-history \
    --execution-arn <execution-arn>

# Test Lambda functions directly
aws lambda invoke \
    --function-name <function-name> \
    --payload '{"userId":"test123"}' \
    response.json
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation
3. Consult provider-specific troubleshooting guides
4. Use AWS Support for service-specific issues

## Contributing

When modifying the infrastructure code:
1. Test changes in a non-production environment
2. Update variable descriptions and documentation
3. Validate security configurations
4. Update this README with any new requirements or procedures

## Version History

- **v1.0**: Initial implementation with basic API composition
- **v1.1**: Added enhanced error handling and compensation logic
- **v1.2**: Improved security configurations and monitoring capabilities

---

**Note**: This infrastructure code implements the complete solution described in the "API Composition with Step Functions" recipe. Review the original recipe for detailed explanations of the architecture and business logic.