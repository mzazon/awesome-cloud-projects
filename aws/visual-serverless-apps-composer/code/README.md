# Infrastructure as Code for Visual Serverless Applications with Infrastructure Composer

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Visual Serverless Applications with Infrastructure Composer".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete serverless application architecture that includes:

- **API Gateway**: REST API with CORS support and X-Ray tracing
- **Lambda Function**: Python runtime for user CRUD operations
- **DynamoDB Table**: NoSQL database with encryption and point-in-time recovery
- **SQS Dead Letter Queue**: Error handling for failed Lambda invocations
- **CloudWatch Log Group**: Centralized logging with retention policies
- **IAM Roles**: Least privilege access policies for all services

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - API Gateway
  - Lambda
  - DynamoDB
  - CloudFormation
  - IAM
  - CloudWatch
  - SQS
  - X-Ray
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $5-15 for resources created during deployment

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name visual-serverless-app-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Stage,ParameterValue=dev \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name visual-serverless-app-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint
aws cloudformation describe-stacks \
    --stack-name visual-serverless-app-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy VisualServerlessAppStack

# Get outputs
cdk ls --long
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

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy VisualServerlessAppStack

# Get outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Set up environment variables
# 2. Create all AWS resources
# 3. Configure proper IAM permissions
# 4. Display deployment outputs
```

## Testing the Deployment

After deployment, test the API endpoints:

```bash
# Set the API endpoint (replace with your actual endpoint)
export API_ENDPOINT="https://your-api-id.execute-api.us-east-1.amazonaws.com/dev"

# Test GET endpoint (list users)
curl -X GET "${API_ENDPOINT}/users" \
    -H "Content-Type: application/json"

# Test POST endpoint (create user)
curl -X POST "${API_ENDPOINT}/users" \
    -H "Content-Type: application/json" \
    -d '{"id": "user1", "name": "Test User", "email": "test@example.com"}'

# Test GET endpoint again to see the created user
curl -X GET "${API_ENDPOINT}/users" \
    -H "Content-Type: application/json"
```

## Customization

### CloudFormation Parameters

Modify the `Parameters` section in `cloudformation.yaml`:

```yaml
Parameters:
  Stage:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
  
  LambdaMemorySize:
    Type: Number
    Default: 256
    MinValue: 128
    MaxValue: 3008
```

### CDK Configuration

For CDK implementations, modify the stack parameters in the main application file:

```typescript
// CDK TypeScript
const app = new cdk.App();
new VisualServerlessAppStack(app, 'VisualServerlessAppStack', {
  stage: 'dev',
  lambdaMemorySize: 256,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
```

### Terraform Variables

Modify `variables.tf` or create a `terraform.tfvars` file:

```hcl
# terraform.tfvars
stage = "dev"
lambda_memory_size = 256
lambda_timeout = 30
region = "us-east-1"
```

### Bash Script Configuration

Modify environment variables in `scripts/deploy.sh`:

```bash
# Configuration variables
export STAGE="dev"
export LAMBDA_MEMORY_SIZE="256"
export LAMBDA_TIMEOUT="30"
export AWS_REGION="us-east-1"
```

## Monitoring and Observability

### CloudWatch Logs

View Lambda function logs:

```bash
# Get log group name
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/"

# Stream logs
aws logs tail /aws/lambda/your-function-name --follow
```

### X-Ray Tracing

View distributed traces:

```bash
# Get trace summaries
aws xray get-trace-summaries \
    --time-range-type TimeRangeByStartTime \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```

### CloudWatch Metrics

Monitor API Gateway and Lambda metrics:

```bash
# Get API Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --dimensions Name=ApiName,Value=ServerlessAPI \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Security Considerations

### IAM Policies

The infrastructure implements least privilege access:

- Lambda execution role has minimal DynamoDB permissions
- API Gateway has execution permissions only for specific Lambda functions
- CloudWatch logging permissions are scoped to specific log groups

### Data Encryption

- DynamoDB table encryption at rest is enabled
- API Gateway uses TLS 1.2 for data in transit
- Lambda environment variables are encrypted using AWS KMS

### Network Security

- API Gateway includes CORS configuration
- Lambda functions run in AWS managed VPC
- DynamoDB access is restricted to Lambda execution role

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name visual-serverless-app-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name visual-serverless-app-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From the CDK directory
cdk destroy VisualServerlessAppStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete all created resources
# 2. Clean up IAM roles and policies
# 3. Remove log groups
# 4. Confirm successful cleanup
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM policies for required services

2. **Resource Already Exists**
   - Use unique names for resources
   - Check for existing resources in your account

3. **Lambda Function Errors**
   - Check CloudWatch logs for detailed error messages
   - Verify DynamoDB table exists and is accessible

4. **API Gateway 502 Errors**
   - Check Lambda function permissions
   - Verify Lambda function is properly configured

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name visual-serverless-app-stack

# Test Lambda function directly
aws lambda invoke \
    --function-name your-function-name \
    --payload '{"httpMethod":"GET","body":null}' \
    response.json

# Check API Gateway configuration
aws apigateway get-rest-apis
```

## CodeCatalyst Integration

This infrastructure is designed to work with AWS CodeCatalyst for CI/CD automation:

1. **Repository Setup**: Connect your CodeCatalyst project to this infrastructure code
2. **Workflow Configuration**: Use the provided workflow templates for automated deployment
3. **Environment Management**: Configure development, staging, and production environments
4. **Monitoring**: Set up deployment notifications and health checks

For detailed CodeCatalyst integration, refer to the main recipe documentation.

## Performance Optimization

### Lambda Optimization

- **Memory Configuration**: Adjust Lambda memory based on workload requirements
- **Provisioned Concurrency**: Enable for consistent performance
- **Connection Pooling**: Implement for DynamoDB connections

### API Gateway Optimization

- **Caching**: Enable response caching for frequently accessed endpoints
- **Request Validation**: Implement request/response validation
- **Rate Limiting**: Configure usage plans and API keys

### DynamoDB Optimization

- **Read/Write Capacity**: Monitor and adjust based on usage patterns
- **Global Secondary Indexes**: Add for query optimization
- **DAX**: Consider for microsecond latency requirements

## Cost Optimization

### Cost Monitoring

```bash
# Get cost estimates
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost
```

### Optimization Strategies

1. **Lambda**: Use ARM64 architecture for better price-performance
2. **DynamoDB**: Use on-demand billing for unpredictable workloads
3. **API Gateway**: Implement caching to reduce Lambda invocations
4. **CloudWatch**: Set appropriate log retention periods

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Consult the original recipe documentation
4. Check AWS CloudFormation/CDK documentation for service-specific issues

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify according to your organization's requirements and security policies.