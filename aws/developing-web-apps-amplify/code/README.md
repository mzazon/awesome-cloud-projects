# Infrastructure as Code for Developing Web Apps with Amplify and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developing Web Apps with Amplify and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete serverless web application stack including:

- **AWS Amplify**: Frontend hosting with CI/CD pipeline
- **AWS Lambda**: Serverless compute for API backend
- **Amazon API Gateway**: REST API management and routing
- **Amazon Cognito**: User authentication and authorization
- **Amazon DynamoDB**: NoSQL database for data persistence
- **Amazon CloudFront**: Global content delivery network

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amplify (FullAccess or custom policy)
  - Lambda (FullAccess or custom policy)
  - API Gateway (FullAccess or custom policy)
  - Cognito (FullAccess or custom policy)
  - DynamoDB (FullAccess or custom policy)
  - IAM (CreateRole, AttachRolePolicy permissions)
  - CloudFormation (for stack deployment)
- Node.js (v14 or later) and npm (for CDK implementations)
- Python 3.8+ (for CDK Python implementation)
- Terraform v1.0+ (for Terraform implementation)
- Estimated cost: $5-15 per month for development workloads

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name serverless-web-app-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AppName,ParameterValue=my-serverless-app \
                 ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name serverless-web-app-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name serverless-web-app-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy ServerlessWebAppStack

# Get stack outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy ServerlessWebAppStack

# Get stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan -var="app_name=my-serverless-app" -var="environment=dev"

# Apply configuration
terraform apply -var="app_name=my-serverless-app" -var="environment=dev"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
# Script will create all necessary resources
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| AppName | Application name for resource naming | serverless-web-app | Yes |
| Environment | Environment name (dev, staging, prod) | dev | Yes |
| DynamoDBBillingMode | DynamoDB billing mode | PAY_PER_REQUEST | No |
| LambdaRuntime | Lambda runtime version | nodejs18.x | No |
| ApiGatewayStageName | API Gateway stage name | api | No |

### CDK Configuration

Both CDK implementations support environment variables:

```bash
export APP_NAME=my-serverless-app
export ENVIRONMENT=dev
export AWS_REGION=us-east-1
```

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| app_name | Application name | string | "serverless-web-app" |
| environment | Environment name | string | "dev" |
| aws_region | AWS region | string | "us-east-1" |
| dynamodb_billing_mode | DynamoDB billing mode | string | "PAY_PER_REQUEST" |
| lambda_runtime | Lambda runtime | string | "nodejs18.x" |

Create a `terraform.tfvars` file:

```hcl
app_name    = "my-custom-app"
environment = "production"
aws_region  = "us-west-2"
```

## Deployment Process

### Infrastructure Components

1. **IAM Roles and Policies**: Created for Lambda execution and cross-service access
2. **DynamoDB Table**: NoSQL database with on-demand billing
3. **Lambda Function**: API backend with CRUD operations
4. **API Gateway**: REST API with Lambda integration
5. **Cognito User Pool**: User authentication service
6. **Amplify App**: Frontend hosting with CI/CD capabilities

### Post-Deployment Steps

After infrastructure deployment, you'll need to:

1. **Configure Amplify CLI**: Initialize your local Amplify project
2. **Deploy Frontend**: Upload your React application to Amplify hosting
3. **Configure Authentication**: Set up Cognito user pool in your application
4. **Test Integration**: Verify all services are properly connected

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check Lambda function
aws lambda get-function --function-name <function-name>

# Test API Gateway endpoint
API_ENDPOINT=$(aws apigateway get-rest-apis \
    --query "items[?name=='<app-name>-api'].id" --output text)
curl https://${API_ENDPOINT}.execute-api.${AWS_REGION}.amazonaws.com/api/todos

# Verify DynamoDB table
aws dynamodb describe-table --table-name <table-name>

# Check Cognito User Pool
aws cognito-idp list-user-pools --max-items 10
```

### Load Testing

```bash
# Test Lambda scaling
for i in {1..10}; do
    curl -X GET "https://${API_ENDPOINT}.execute-api.${AWS_REGION}.amazonaws.com/api/todos" &
done
wait

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=<function-name> \
    --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Monitoring and Logging

### CloudWatch Integration

All implementations include comprehensive monitoring:

- **Lambda Metrics**: Duration, errors, invocations, throttles
- **API Gateway Metrics**: Request count, latency, 4XX/5XX errors
- **DynamoDB Metrics**: Read/write capacity, throttles
- **Amplify Metrics**: Build status, deployment metrics

### Log Analysis

```bash
# View Lambda logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/

# Stream real-time logs
aws logs tail /aws/lambda/<function-name> --follow

# Filter error logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/<function-name> \
    --filter-pattern "ERROR"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name serverless-web-app-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name serverless-web-app-stack
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy ServerlessWebAppStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="app_name=my-serverless-app" -var="environment=dev"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

After automated cleanup, verify resource deletion:

```bash
# Check remaining Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `<app-name>`)]'

# Check remaining API Gateways
aws apigateway get-rest-apis --query 'items[?contains(name, `<app-name>`)]'

# Check remaining DynamoDB tables
aws dynamodb list-tables --query 'TableNames[?contains(@, `<app-name>`)]'

# Check Amplify apps
aws amplify list-apps --query 'apps[?contains(name, `<app-name>`)]'
```

## Troubleshooting

### Common Issues

1. **Lambda Timeout**: Increase timeout in function configuration
2. **API Gateway CORS**: Ensure proper CORS headers in Lambda response
3. **DynamoDB Access**: Verify Lambda execution role has DynamoDB permissions
4. **Amplify Build Failures**: Check build settings and environment variables

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name serverless-web-app-stack

# View CDK diff
cdk diff ServerlessWebAppStack

# Terraform state inspection
terraform show
terraform state list
```

### Log Analysis

```bash
# Lambda function logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/<function-name> \
    --order-by LastEventTime --descending

# API Gateway access logs
aws logs describe-log-streams \
    --log-group-name API-Gateway-Execution-Logs_<api-id>/<stage-name>
```

## Customization

### Adding New API Endpoints

1. Update Lambda function code with new route handlers
2. Modify API Gateway resource definitions
3. Update IAM policies if accessing new AWS services
4. Redeploy infrastructure

### Environment-Specific Configurations

Create separate parameter files or variable files for different environments:

```bash
# CloudFormation
aws cloudformation create-stack \
    --stack-name serverless-web-app-prod \
    --template-body file://cloudformation.yaml \
    --parameters file://parameters-prod.json

# Terraform
terraform apply -var-file="prod.tfvars"
```

### Security Hardening

- Enable AWS WAF for API Gateway
- Implement API key authentication
- Configure VPC endpoints for private communication
- Enable encryption at rest for DynamoDB
- Implement least privilege IAM policies

## Cost Optimization

### DynamoDB Optimization

- Use on-demand billing for variable workloads
- Switch to provisioned capacity for predictable workloads
- Implement TTL for temporary data

### Lambda Optimization

- Right-size memory allocation based on performance testing
- Use provisioned concurrency for consistent performance
- Implement connection pooling for database connections

### API Gateway Optimization

- Enable caching for frequently accessed endpoints
- Implement request throttling to control costs
- Use regional endpoints for single-region applications

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for specific resources
3. Consult provider-specific troubleshooting guides
4. Review CloudWatch logs for error details

## Additional Resources

- [AWS Amplify Documentation](https://docs.aws.amazon.com/amplify/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [Amazon Cognito Developer Guide](https://docs.aws.amazon.com/cognito/latest/developerguide/)
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)