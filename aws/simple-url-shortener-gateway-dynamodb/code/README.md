# Infrastructure as Code for Simple URL Shortener with API Gateway and DynamoDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple URL Shortener with API Gateway and DynamoDB".

## Architecture Overview

This serverless URL shortener creates a scalable, cost-effective solution using:
- **API Gateway**: RESTful API endpoints for URL creation and redirection
- **Lambda Functions**: Serverless compute for URL processing logic
- **DynamoDB**: NoSQL database for URL mappings with single-digit millisecond latency
- **IAM**: Least privilege security roles and policies

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript
- **CDK Python**: AWS Cloud Development Kit with Python
- **Terraform**: Multi-cloud infrastructure as code using AWS provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with permissions for:
  - API Gateway (create/manage REST APIs)
  - Lambda (create/manage functions)
  - DynamoDB (create/manage tables)
  - IAM (create/manage roles and policies)
  - CloudWatch Logs (for function logging)
- For CDK deployments: Node.js 18+ or Python 3.9+
- For Terraform deployments: Terraform v1.0+
- Estimated cost: $0.10-0.50 for testing (within AWS Free Tier limits)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name url-shortener-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=url-shortener

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name url-shortener-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint URL
aws cloudformation describe-stacks \
    --stack-name url-shortener-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
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
cdk deploy

# Get outputs
cdk ls --long
```

### Using CDK Python
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

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

# Apply configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the API endpoint URL upon completion
```

## Testing Your Deployment

After successful deployment, test your URL shortener:

### 1. Create a Short URL
```bash
# Replace YOUR_API_ENDPOINT with the actual endpoint from deployment outputs
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/prod"

# Create a short URL
curl -X POST ${API_ENDPOINT}/shorten \
    -H "Content-Type: application/json" \
    -d '{"url": "https://aws.amazon.com/lambda/"}'

# Expected response:
# {
#   "shortCode": "abc123",
#   "shortUrl": "https://your-api-endpoint/abc123",
#   "originalUrl": "https://aws.amazon.com/lambda/"
# }
```

### 2. Test URL Redirection
```bash
# Use the shortCode from the previous response
SHORT_CODE="abc123"

# Test redirect (should return HTTP 302)
curl -I ${API_ENDPOINT}/${SHORT_CODE}

# Or test in browser by visiting: https://your-api-endpoint/abc123
```

### 3. Validate Database Storage
```bash
# Check DynamoDB table (replace table name with actual name from outputs)
aws dynamodb scan --table-name url-shortener-table --select COUNT

# View specific item
aws dynamodb get-item \
    --table-name url-shortener-table \
    --key '{"shortCode":{"S":"abc123"}}'
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name url-shortener-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name url-shortener-stack
```

### Using CDK
```bash
# From the appropriate CDK directory
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
# From the terraform directory
cd terraform/
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Customization

### Common Configuration Options

All implementations support these customization parameters:

- **Project Name**: Prefix for resource naming (default: `url-shortener`)
- **Environment**: Deployment environment tag (default: `dev`)
- **DynamoDB Billing Mode**: `PAY_PER_REQUEST` or `PROVISIONED`
- **Lambda Runtime**: Python runtime version (default: `python3.12`)
- **API Gateway Stage**: Deployment stage name (default: `prod`)

### CloudFormation Parameters
```bash
# Deploy with custom parameters
aws cloudformation create-stack \
    --stack-name url-shortener-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=my-shortener \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=DynamoDBBillingMode,ParameterValue=PROVISIONED
```

### CDK Customization
```typescript
// In CDK TypeScript (app.ts)
const app = new cdk.App();
new UrlShortenerStack(app, 'UrlShortenerStack', {
  projectName: 'my-shortener',
  environment: 'production',
  // Additional customizations...
});
```

### Terraform Variables
```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_name = "my-shortener"
environment = "production"
dynamodb_billing_mode = "PROVISIONED"
lambda_runtime = "python3.12"
EOF

# Apply with variables
terraform apply
```

## Security Considerations

This implementation follows AWS security best practices:

- **IAM Roles**: Lambda functions use least privilege IAM roles
- **API Gateway**: CORS configured for web application integration
- **DynamoDB**: Table-level permissions with specific action grants
- **Lambda**: Functions isolated with minimal required permissions
- **Input Validation**: Comprehensive URL validation and sanitization
- **Error Handling**: Secure error responses without information disclosure

### Additional Security Enhancements

For production deployments, consider:

1. **API Authentication**: Add API keys or AWS Cognito authentication
2. **Rate Limiting**: Implement API Gateway usage plans
3. **WAF Integration**: Add AWS WAF for additional protection
4. **Custom Domains**: Use custom domain names with SSL certificates
5. **VPC Integration**: Deploy Lambda functions in private VPC if required

## Monitoring and Observability

The deployed solution includes:

- **CloudWatch Logs**: Automatic logging for Lambda functions
- **API Gateway Metrics**: Request/response metrics and error rates
- **DynamoDB Metrics**: Read/write capacity and throttling metrics
- **X-Ray Tracing**: Optional distributed tracing (can be enabled)

### Useful CloudWatch Queries

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/url-shortener"

# Get API Gateway access logs
aws logs filter-log-events \
    --log-group-name "API-Gateway-Execution-Logs_${API_ID}/prod" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify AWS credentials and permissions
   - Check for resource naming conflicts
   - Ensure region supports all required services

2. **API Gateway 502 Errors**:
   - Check Lambda function logs in CloudWatch
   - Verify IAM permissions for Lambda execution
   - Confirm DynamoDB table accessibility

3. **CORS Issues**:
   - Verify OPTIONS method is properly configured
   - Check response headers in browser developer tools
   - Confirm API Gateway CORS settings

4. **DynamoDB Throttling**:
   - Monitor read/write capacity metrics
   - Consider switching to on-demand billing mode
   - Implement exponential backoff in application code

### Debug Commands

```bash
# Check stack events (CloudFormation)
aws cloudformation describe-stack-events --stack-name url-shortener-stack

# View Lambda function configuration
aws lambda get-function --function-name url-shortener-create

# Test Lambda function directly
aws lambda invoke \
    --function-name url-shortener-create \
    --payload '{"body":"{\"url\":\"https://example.com\"}"}' \
    response.json
```

## Performance Optimization

### DynamoDB Optimization
- Use on-demand billing for variable workloads
- Implement DynamoDB Accelerator (DAX) for microsecond latency
- Consider Global Tables for multi-region deployment

### Lambda Optimization
- Optimize function memory allocation based on usage patterns
- Use Lambda Provisioned Concurrency for consistent performance
- Implement connection pooling for external resources

### API Gateway Optimization
- Enable caching for frequently accessed short codes
- Use CloudFront distribution for global edge locations
- Implement request/response compression

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

- **DynamoDB**: $0.25 per million reads, $1.25 per million writes
- **Lambda**: $0.0000166667 per GB-second, $0.20 per million requests
- **API Gateway**: $3.50 per million API calls
- **CloudWatch Logs**: $0.50 per GB ingested

### Cost Reduction Tips

1. Use DynamoDB on-demand billing for low/variable traffic
2. Optimize Lambda memory allocation to balance cost and performance
3. Enable API Gateway caching to reduce backend calls
4. Set CloudWatch log retention periods appropriately
5. Use AWS Cost Explorer to monitor and optimize spending

## Extensions and Enhancements

The infrastructure can be extended with:

1. **Analytics Dashboard**: Add CloudWatch Dashboard for URL metrics
2. **Custom Domains**: Implement Route 53 and ACM for branded URLs
3. **Batch Operations**: Add SQS for bulk URL processing
4. **Caching Layer**: Integrate ElastiCache for improved performance
5. **Multi-Region**: Deploy across multiple AWS regions for redundancy

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for latest features and limits
3. Validate IAM permissions and resource configurations
4. Monitor CloudWatch logs for detailed error information
5. Use AWS Support for service-specific issues

## Version History

- **v1.0**: Initial implementation with basic URL shortening
- **v1.1**: Enhanced error handling and CORS support, improved security practices

---

**Note**: This infrastructure creates AWS resources that may incur charges. Always review costs and clean up resources when no longer needed.