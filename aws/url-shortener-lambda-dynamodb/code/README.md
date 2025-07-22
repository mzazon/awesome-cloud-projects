# Infrastructure as Code for Basic URL Shortener Service with Lambda and DynamoDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "URL Shortener Service with Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a serverless URL shortener service that includes:

- **AWS Lambda**: Serverless compute for URL processing and redirection
- **Amazon DynamoDB**: NoSQL database for storing URL mappings
- **API Gateway**: HTTP API for RESTful endpoints
- **CloudWatch**: Monitoring and logging
- **IAM**: Security roles and policies

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Node.js 18+ (for CDK TypeScript implementation)
- Python 3.9+ (for CDK Python implementation)
- Terraform 1.0+ (for Terraform implementation)
- Bash shell (for script implementation)
- AWS account with permissions for:
  - Lambda function creation and management
  - DynamoDB table creation and management
  - API Gateway HTTP API creation
  - IAM role and policy management
  - CloudWatch dashboard and log group creation

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name url-shortener-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=url-shortener

# Monitor deployment status
aws cloudformation wait stack-create-complete \
    --stack-name url-shortener-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name url-shortener-stack \
    --query 'Stacks[0].Outputs' \
    --output table
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
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

# View deployment outputs
echo "Check the script output for API Gateway URL and other details"
```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Name prefix for all resources (default: url-shortener)
- `Environment`: Environment name (default: dev)
- `LambdaTimeout`: Lambda function timeout in seconds (default: 30)
- `LambdaMemorySize`: Lambda function memory in MB (default: 256)

### CDK Configuration

Modify the following in the CDK app files:

- `stackName`: Name of the CloudFormation stack
- `functionTimeout`: Lambda function timeout
- `functionMemorySize`: Lambda function memory allocation
- `tableName`: DynamoDB table name

### Terraform Variables

Configure in `terraform.tfvars` or via command line:

```bash
# Example terraform.tfvars
project_name = "url-shortener"
environment = "dev"
aws_region = "us-east-1"
lambda_timeout = 30
lambda_memory_size = 256
```

## Testing the Deployment

After successful deployment, test the URL shortener service:

```bash
# Set API Gateway URL (replace with your actual URL)
export API_URL="https://your-api-id.execute-api.us-east-1.amazonaws.com"

# Test URL shortening
curl -X POST ${API_URL}/shorten \
    -H "Content-Type: application/json" \
    -d '{
        "url": "https://docs.aws.amazon.com/lambda/latest/dg/welcome.html"
    }'

# Test URL redirection (replace SHORT_ID with returned value)
curl -I ${API_URL}/SHORT_ID
```

## Monitoring and Observability

The deployment includes CloudWatch monitoring:

- **Lambda Metrics**: Function invocations, errors, duration
- **DynamoDB Metrics**: Read/write capacity consumption
- **API Gateway Metrics**: Request count, latency, errors
- **Custom Dashboard**: Combined view of all service metrics

Access the CloudWatch dashboard in the AWS Console to monitor your URL shortener service.

## Security Considerations

The infrastructure implements security best practices:

- **IAM Least Privilege**: Lambda execution role with minimal required permissions
- **HTTPS Only**: API Gateway enforces HTTPS connections
- **Input Validation**: Lambda function validates URL format and structure
- **URL Expiration**: Short URLs automatically expire after 30 days
- **CORS Configuration**: Controlled cross-origin resource sharing

## Cost Optimization

This serverless architecture provides cost-effective scaling:

- **Pay-per-Use**: No charges during idle periods
- **DynamoDB On-Demand**: Automatic scaling without capacity planning
- **Lambda Provisioned Concurrency**: Optional for consistent performance
- **API Gateway HTTP API**: Lower cost than REST API for simple use cases

Estimated monthly costs for low-traffic usage (within Free Tier):
- Lambda: $0.00 (1M requests/month free)
- DynamoDB: $0.00 (25GB storage + 25 RCU/WCU free)
- API Gateway: $0.00 (1M requests/month free)
- CloudWatch: ~$0.50 (dashboard and logs)

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name url-shortener-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name url-shortener-stack
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
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

### Adding Custom Domains

To use a custom domain for your URL shortener:

1. **Register domain in Route 53** or configure DNS
2. **Request SSL certificate** in AWS Certificate Manager
3. **Configure API Gateway custom domain**
4. **Update DNS records** to point to API Gateway

### Implementing Rate Limiting

Add rate limiting to prevent abuse:

```yaml
# CloudFormation example
UsagePlan:
  Type: AWS::ApiGateway::UsagePlan
  Properties:
    Throttle:
      RateLimit: 1000
      BurstLimit: 2000
```

### Adding Authentication

Integrate with Amazon Cognito for user authentication:

```yaml
# CloudFormation example
Authorizer:
  Type: AWS::ApiGatewayV2::Authorizer
  Properties:
    AuthorizerType: JWT
    IdentitySource:
      - "$request.header.Authorization"
```

### Enhanced Analytics

Implement detailed analytics with:

- **DynamoDB Streams**: Capture data changes
- **Kinesis Data Firehose**: Stream data to analytics services
- **Amazon QuickSight**: Create business intelligence dashboards

## Troubleshooting

### Common Issues

1. **Lambda Timeout**: Increase timeout value in configuration
2. **DynamoDB Throttling**: Switch to provisioned capacity or increase on-demand limits
3. **API Gateway 5XX Errors**: Check Lambda function logs in CloudWatch
4. **CORS Issues**: Verify CORS configuration in API Gateway

### Debugging Steps

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/url-shortener

# View recent log events
aws logs tail /aws/lambda/url-shortener-function --follow

# Check DynamoDB table status
aws dynamodb describe-table --table-name url-shortener-table

# Test Lambda function directly
aws lambda invoke \
    --function-name url-shortener-function \
    --payload '{"httpMethod":"GET","path":"/test"}' \
    response.json
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for step-by-step instructions
2. **AWS Documentation**: Consult official AWS service documentation
3. **Community Support**: AWS forums and Stack Overflow
4. **Professional Support**: AWS Support plans for production workloads

### Useful Links

- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/latest/developerguide/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **AWS CDK Version**: ^2.100.0
- **Terraform AWS Provider**: ~> 5.0
- **CloudFormation Template Version**: 2010-09-09