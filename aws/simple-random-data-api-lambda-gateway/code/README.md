# Infrastructure as Code for Simple Random Data API with Lambda and API Gateway

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Random Data API with Lambda and API Gateway".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with Lambda, API Gateway, and IAM permissions
- Basic understanding of REST APIs and JSON responses
- Text editor or IDE for customizing configurations
- For CDK implementations: Node.js 18+ or Python 3.8+
- For Terraform: Terraform CLI v1.0+
- Estimated cost: $0.00-$0.20 for testing (within AWS Free Tier limits)

> **Note**: This solution uses AWS Free Tier resources. Lambda provides 1 million free requests per month, and API Gateway provides 1 million free API calls per month for the first 12 months.

## Architecture Overview

The infrastructure creates:
- AWS Lambda function with Python 3.12 runtime for random data generation
- IAM role with basic execution permissions for Lambda
- API Gateway REST API with `/random` endpoint
- CloudWatch log groups for monitoring and debugging
- Lambda permission for API Gateway invocation

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name random-data-api-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=FunctionName,ParameterValue=my-random-api

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name random-data-api-stack

# Get the API endpoint URL
aws cloudformation describe-stacks \
    --stack-name random-data-api-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# The API endpoint URL will be displayed in the output
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# The API endpoint URL will be displayed in the output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get the API endpoint URL
terraform output api_endpoint_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the API endpoint URL upon completion
```

## Testing Your Deployment

Once deployed, test your API using these commands:

```bash
# Replace YOUR_API_ENDPOINT with the actual endpoint URL from deployment output

# Test random quote (default)
curl -X GET "YOUR_API_ENDPOINT" | jq .

# Test with explicit quote parameter
curl -X GET "YOUR_API_ENDPOINT?type=quote" | jq .

# Test random number generation
curl -X GET "YOUR_API_ENDPOINT?type=number" | jq .

# Test random color generation
curl -X GET "YOUR_API_ENDPOINT?type=color" | jq .
```

Expected responses:
- **Quote**: JSON with random inspirational quote
- **Number**: JSON with random number between 1-1000
- **Color**: JSON with color name, hex value, and RGB values

## Customization

### CloudFormation Parameters

- `FunctionName`: Name for the Lambda function (default: random-data-api)
- `ApiName`: Name for the API Gateway (default: random-data-api)
- `StageName`: API Gateway stage name (default: dev)

### CDK Configuration

Modify the stack configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript
const stack = new RandomDataApiStack(app, 'RandomDataApiStack', {
  functionName: 'my-custom-function',
  apiName: 'my-custom-api',
  stageName: 'prod'
});
```

```python
# CDK Python
stack = RandomDataApiStack(
    app, "RandomDataApiStack",
    function_name="my-custom-function",
    api_name="my-custom-api",
    stage_name="prod"
)
```

### Terraform Variables

Create a `terraform.tfvars` file or modify `variables.tf`:

```hcl
# terraform.tfvars
function_name = "my-random-api"
api_name = "my-random-data-api"
stage_name = "prod"
aws_region = "us-west-2"
```

### Bash Script Variables

Modify variables at the top of `deploy.sh`:

```bash
# Customizable variables
FUNCTION_NAME="my-random-api"
API_NAME="my-random-data-api"
STAGE_NAME="prod"
```

## Monitoring and Logs

### CloudWatch Logs

```bash
# View Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/YOUR_FUNCTION_NAME" \
    --start-time $(date -d '1 hour ago' +%s)000

# View API Gateway access logs (if enabled)
aws logs filter-log-events \
    --log-group-name "API-Gateway-Execution-Logs_YOUR_API_ID/dev"
```

### API Gateway Metrics

```bash
# Get API Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --dimensions Name=ApiName,Value=YOUR_API_NAME \
    --start-time $(date -d '1 hour ago' -Iseconds) \
    --end-time $(date -Iseconds) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name random-data-api-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name random-data-api-stack
```

### Using CDK (AWS)

```bash
# From the CDK directory (TypeScript or Python)
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# From the terraform/ directory
terraform destroy

# Type 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Security Considerations

- **IAM Permissions**: The Lambda function uses the minimal `AWSLambdaBasicExecutionRole` policy
- **API Security**: The API is publicly accessible; consider adding authentication for production use
- **CORS**: Configured to allow all origins (`*`) for development; restrict for production
- **Resource Limits**: Lambda timeout set to 30 seconds with 128MB memory allocation

## Cost Optimization

- **Lambda**: Pay-per-invocation model with generous free tier
- **API Gateway**: 1 million free API calls per month for first 12 months
- **CloudWatch**: Basic logging included in free tier
- **Estimated Monthly Cost**: $0.00-$5.00 for typical development usage

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure AWS CLI is configured with appropriate IAM permissions
2. **Function Not Found**: Wait for Lambda function to be fully deployed before testing
3. **API Gateway 502 Error**: Check Lambda function logs for runtime errors
4. **CORS Issues**: Verify CORS headers are properly configured in Lambda response

### Debug Commands

```bash
# Check Lambda function status
aws lambda get-function --function-name YOUR_FUNCTION_NAME

# Test Lambda function directly
aws lambda invoke \
    --function-name YOUR_FUNCTION_NAME \
    --payload '{"queryStringParameters":{"type":"quote"}}' \
    response.json

# Check API Gateway configuration
aws apigateway get-rest-api --rest-api-id YOUR_API_ID
```

## Extensions

Consider these enhancements for production use:

1. **Authentication**: Add API Gateway authorizers or Cognito integration
2. **Rate Limiting**: Implement API Gateway usage plans and throttling
3. **Caching**: Enable API Gateway response caching for better performance
4. **Monitoring**: Add custom CloudWatch metrics and alarms
5. **CI/CD**: Integrate with AWS CodePipeline for automated deployments

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation for detailed explanations
2. Review AWS CloudFormation, CDK, or Terraform documentation
3. Examine CloudWatch logs for runtime errors
4. Verify AWS CLI configuration and permissions

## Additional Resources

- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [API Gateway REST API Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-rest-api.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html)