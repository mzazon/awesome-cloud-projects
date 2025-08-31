# Infrastructure as Code for Simple Time Zone Converter with Lambda and API Gateway

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Time Zone Converter with Lambda and API Gateway".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for creating:
  - Lambda functions
  - API Gateway REST APIs
  - IAM roles and policies
- Tool-specific prerequisites:
  - **CloudFormation**: AWS CLI version 2.0+
  - **CDK TypeScript**: Node.js 18+, npm, AWS CDK CLI
  - **CDK Python**: Python 3.8+, pip, AWS CDK CLI
  - **Terraform**: Terraform 1.0+
  - **Bash Scripts**: AWS CLI, jq (optional for JSON parsing)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name timezone-converter-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=FunctionName,ParameterValue=timezone-converter

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name timezone-converter-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint URL
aws cloudformation describe-stacks \
    --stack-name timezone-converter-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
# Install dependencies and deploy
cd cdk-typescript/
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
# Set up Python environment and deploy
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Initialize and deploy
cd terraform/
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable and deploy
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the API endpoint URL upon completion
```

## Testing the Deployed API

Once deployed, test your timezone converter API:

```bash
# Replace YOUR_API_ENDPOINT with the actual endpoint from deployment output
export API_ENDPOINT="https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/prod"

# Test timezone conversion
curl -X POST ${API_ENDPOINT}/convert \
    -H "Content-Type: application/json" \
    -d '{
      "timestamp": "2025-07-12T15:30:00",
      "from_timezone": "UTC",
      "to_timezone": "America/New_York"
    }' | python -m json.tool

# Test with different timezones
curl -X POST ${API_ENDPOINT}/convert \
    -H "Content-Type: application/json" \
    -d '{
      "timestamp": "2025-07-12T09:00:00",
      "from_timezone": "America/Los_Angeles",
      "to_timezone": "Europe/London"
    }' | python -m json.tool
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name timezone-converter-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name timezone-converter-stack
```

### Using CDK (AWS)

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
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

### CloudFormation Parameters

- `FunctionName`: Name for the Lambda function (default: timezone-converter)
- `ApiName`: Name for the API Gateway (default: timezone-converter-api)
- `Stage`: API Gateway deployment stage (default: prod)

### CDK Configuration

Modify the following in the CDK code:

- Function memory size and timeout
- API Gateway throttling settings
- CloudWatch log retention period
- CORS configuration

### Terraform Variables

Available variables in `terraform/variables.tf`:

- `function_name`: Lambda function name
- `api_name`: API Gateway name
- `stage_name`: Deployment stage name
- `region`: AWS region for deployment

### Environment Variables

All implementations support these environment variables:

- `AWS_REGION`: Target AWS region
- `FUNCTION_NAME`: Lambda function name
- `API_NAME`: API Gateway name

## Architecture Components

The IaC implementations create the following AWS resources:

1. **IAM Role**: Lambda execution role with CloudWatch Logs permissions
2. **Lambda Function**: Python 3.12 runtime with timezone conversion logic
3. **API Gateway**: REST API with `/convert` POST endpoint
4. **Lambda Permission**: Allows API Gateway to invoke the function
5. **API Deployment**: Deploys the API to a stage for public access

## Security Considerations

- Lambda function uses least privilege IAM permissions
- API Gateway has CORS enabled for web browser compatibility
- No API authentication by default (consider adding for production)
- CloudWatch Logs enabled for monitoring and debugging

## Monitoring and Logging

All implementations include:

- CloudWatch Logs for Lambda function execution
- API Gateway access logging
- Basic CloudWatch metrics for both services

Monitor key metrics:
- Lambda duration and error rates
- API Gateway 4xx/5xx error rates
- Request count and latency

## Cost Optimization

This solution uses AWS Free Tier eligible services:

- **Lambda**: 1M free requests per month
- **API Gateway**: 1M API calls per month (12 months for new accounts)
- **CloudWatch Logs**: 5GB free per month

Estimated monthly cost after free tier: $0.20-$5.00 depending on usage.

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Function Timeout**: Default timeout is 30 seconds, adjust if needed
3. **CORS Issues**: Check that CORS headers are properly configured
4. **Invalid Timezone**: Verify timezone names use IANA format (e.g., "America/New_York")

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/timezone-converter

# View recent log events
aws logs tail /aws/lambda/YOUR_FUNCTION_NAME --follow

# Test Lambda function directly
aws lambda invoke \
    --function-name YOUR_FUNCTION_NAME \
    --payload '{"timestamp":"2025-07-12T15:30:00","to_timezone":"America/New_York"}' \
    response.json && cat response.json
```

## Extensions and Enhancements

Consider these improvements for production use:

1. **API Authentication**: Add API keys or JWT authentication
2. **Rate Limiting**: Configure API Gateway throttling
3. **Caching**: Enable API Gateway response caching
4. **Custom Domain**: Set up a custom domain name
5. **Monitoring**: Add CloudWatch alarms and dashboards
6. **Testing**: Implement automated testing with AWS SAM or CDK testing constructs

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS service documentation:
   - [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
   - [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
3. Review CloudWatch logs for runtime errors
4. Validate IAM permissions and resource configurations

## Version Compatibility

- **AWS CLI**: 2.0+
- **CDK**: 2.100+
- **Terraform**: 1.0+
- **Python**: 3.8+ (for CDK Python)
- **Node.js**: 18+ (for CDK TypeScript)

Last updated: 2025-07-12