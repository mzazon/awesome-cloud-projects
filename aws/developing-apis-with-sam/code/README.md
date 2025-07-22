# Infrastructure as Code for Developing APIs with SAM and API Gatewayexisting_folder_name

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developing APIs with SAM and API Gatewayexisting_folder_name".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Lambda (create/update functions)
  - API Gateway (create/manage APIs)
  - DynamoDB (create/manage tables)
  - CloudFormation (create/manage stacks)
  - IAM (create/manage roles and policies)
  - CloudWatch (create/manage logs and dashboards)
- Python 3.9+ installed (for Lambda functions)
- Estimated cost: $5-10 for DynamoDB, Lambda, and API Gateway usage during development

### Tool-Specific Prerequisites

#### For CloudFormation
- AWS CLI v2 with CloudFormation permissions

#### For CDK TypeScript
- Node.js 16+ and npm
- AWS CDK CLI installed (`npm install -g aws-cdk`)

#### For CDK Python
- Python 3.9+ and pip
- AWS CDK CLI installed (`npm install -g aws-cdk`)

#### For Terraform
- Terraform v1.0+ installed
- AWS provider configured

#### For SAM CLI (Original Implementation)
- SAM CLI installed and configured
- Docker installed (for local testing)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name serverless-api-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name serverless-api-stack

# Get API Gateway URL
aws cloudformation describe-stacks \
    --stack-name serverless-api-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters environment=dev

# Get outputs
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters environment=dev

# Get outputs
cdk output
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="environment=dev"

# Apply configuration
terraform apply -var="environment=dev"

# Get outputs
terraform output api_gateway_url
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for environment name and other parameters
```

### Using SAM CLI (Original Recipe Implementation)
```bash
# Build the SAM application
sam build

# Deploy with guided setup
sam deploy --guided --stack-name serverless-api-sam

# For subsequent deployments
sam deploy
```

## Testing the Deployed API

After successful deployment, test your API endpoints:

```bash
# Set API Gateway URL (replace with your actual URL)
export API_URL="https://your-api-id.execute-api.region.amazonaws.com/dev/"

# Test GET /users (list all users)
curl -s "${API_URL}users" | python3 -m json.tool

# Create a test user
curl -X POST "${API_URL}users" \
    -H "Content-Type: application/json" \
    -d '{"name": "John Doe", "email": "john@example.com", "age": 30}'

# Get specific user (replace USER_ID with actual ID)
curl -s "${API_URL}users/USER_ID" | python3 -m json.tool

# Update user
curl -X PUT "${API_URL}users/USER_ID" \
    -H "Content-Type: application/json" \
    -d '{"name": "John Updated", "age": 31}'

# Delete user
curl -X DELETE "${API_URL}users/USER_ID"
```

## Monitoring and Observability

### CloudWatch Dashboards
All implementations create CloudWatch dashboards for monitoring:
- API Gateway request count and latency
- Lambda function duration and error rates
- DynamoDB read/write capacity and throttling

### Accessing Logs
```bash
# View API Gateway logs
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway/"

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Stream logs in real-time (replace with actual log group name)
aws logs tail /aws/lambda/function-name --follow
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name serverless-api-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name serverless-api-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="environment=dev"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Using SAM CLI
```bash
# Delete SAM stack
sam delete --stack-name serverless-api-sam
```

## Customization

### Environment Variables
Customize deployments by modifying these key parameters:

- **Environment**: dev, staging, prod
- **DynamoDB Table Name**: Custom table naming
- **API Gateway Stage**: Custom stage configuration
- **Lambda Memory/Timeout**: Performance tuning
- **CORS Settings**: Cross-origin request configuration

### CloudFormation Parameters
```yaml
Parameters:
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
  
  ApiGatewayStageName:
    Type: String
    Default: dev
  
  LambdaMemorySize:
    Type: Number
    Default: 128
    MinValue: 128
    MaxValue: 3008
```

### Terraform Variables
```hcl
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "lambda_memory_size" {
  description = "Lambda function memory size"
  type        = number
  default     = 128
}

variable "api_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "dev"
}
```

## Architecture Overview

The infrastructure creates:

1. **API Gateway REST API** with CORS enabled
2. **Five Lambda Functions** for CRUD operations:
   - `ListUsersFunction` (GET /users)
   - `CreateUserFunction` (POST /users)
   - `GetUserFunction` (GET /users/{id})
   - `UpdateUserFunction` (PUT /users/{id})
   - `DeleteUserFunction` (DELETE /users/{id})
3. **DynamoDB Table** for user data storage
4. **IAM Roles and Policies** with least privilege access
5. **CloudWatch Log Groups** for monitoring
6. **CloudWatch Dashboard** for observability

## Security Considerations

### IAM Policies
- Lambda functions use least privilege IAM policies
- DynamoDB access is restricted to specific tables
- API Gateway has appropriate throttling limits

### API Security
- CORS is configured for web browser access
- API endpoints include input validation
- Error messages don't expose sensitive information

### Data Protection
- DynamoDB table uses encryption at rest
- CloudWatch logs are encrypted
- API Gateway requests are logged for audit

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Verify AWS credentials and permissions
   - Check IAM roles have necessary policies attached

2. **API Gateway 5xx Errors**
   - Check Lambda function logs in CloudWatch
   - Verify DynamoDB table exists and is accessible

3. **DynamoDB Access Issues**
   - Confirm Lambda execution role has DynamoDB permissions
   - Verify table name environment variable is set correctly

4. **Local SAM Testing Issues**
   - Ensure Docker is running
   - Check port 3000 is available
   - Verify SAM CLI version compatibility

### Debugging Commands
```bash
# Check CloudFormation stack events
aws cloudformation describe-stack-events --stack-name serverless-api-stack

# View Lambda function configuration
aws lambda get-function --function-name YourFunctionName

# Test Lambda function directly
aws lambda invoke \
    --function-name YourFunctionName \
    --payload '{"test": "data"}' \
    response.json

# Check API Gateway configuration
aws apigateway get-rest-apis
```

## Performance Optimization

### Lambda Configuration
- Adjust memory allocation based on function complexity
- Enable provisioned concurrency for consistent performance
- Use Lambda layers for shared dependencies

### DynamoDB Optimization
- Configure auto-scaling for read/write capacity
- Use Global Secondary Indexes for query patterns
- Implement caching with DynamoDB Accelerator (DAX)

### API Gateway Optimization
- Enable caching for GET endpoints
- Configure request/response compression
- Implement API throttling limits

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS service documentation for specific services
3. Review CloudWatch logs for error details
4. Consult AWS support for service-specific issues

## Additional Resources

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/)
- [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)