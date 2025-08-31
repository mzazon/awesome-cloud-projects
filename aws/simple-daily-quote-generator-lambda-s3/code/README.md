# Infrastructure as Code for Simple Daily Quote Generator with Lambda and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Daily Quote Generator with Lambda and S3".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This serverless solution creates:
- S3 bucket for storing quote data (quotes.json)
- Lambda function for serving random quotes
- IAM role with minimal permissions (principle of least privilege)
- Lambda Function URL for direct HTTPS access
- Server-side encryption for S3 bucket

## Prerequisites

- AWS CLI installed and configured (v2.0 or later)
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - Lambda function creation and management
  - IAM role and policy creation
  - Lambda Function URL configuration
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+

> **Note**: This solution uses AWS Free Tier eligible services. Lambda provides 1 million free requests per month, and S3 provides 5GB of free storage.

## Quick Start

### Using CloudFormation
```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name daily-quote-generator \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketNameSuffix,ParameterValue=$(date +%s)

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name daily-quote-generator

# Get the Function URL
aws cloudformation describe-stacks \
    --stack-name daily-quote-generator \
    --query 'Stacks[0].Outputs[?OutputKey==`FunctionUrl`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# The Function URL will be displayed in the output
```

### Using CDK Python
```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# The Function URL will be displayed in the output
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply -auto-approve

# Get the Function URL
terraform output function_url
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the Function URL upon completion
```

## Testing Your Deployment

Once deployed, test your quote API:

```bash
# Replace YOUR_FUNCTION_URL with the actual URL from deployment output
curl -s YOUR_FUNCTION_URL | jq '.'

# Example response:
# {
#   "quote": "The only way to do great work is to love what you do.",
#   "author": "Steve Jobs",
#   "timestamp": "12345678-1234-1234-1234-123456789012"
# }

# Test multiple calls to verify randomness
for i in {1..3}; do
  echo "Request $i:"
  curl -s YOUR_FUNCTION_URL | jq '.quote'
  echo
done
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name daily-quote-generator

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name daily-quote-generator
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Customization

### Available Parameters/Variables

All implementations support these customizable values:

- **Bucket Name Suffix**: Random suffix for S3 bucket uniqueness
- **Function Name**: Name of the Lambda function (default: "daily-quote-generator")
- **Memory Size**: Lambda function memory allocation (default: 128 MB)
- **Timeout**: Lambda function timeout (default: 30 seconds)
- **Runtime**: Python runtime version (default: python3.12)

### Quote Data Customization

To modify the quotes:

1. Edit the `quotes.json` structure in your chosen implementation
2. Add, remove, or modify quotes in the JSON array
3. Redeploy using your preferred method

Example quote structure:
```json
{
  "quotes": [
    {
      "text": "Your custom quote here",
      "author": "Author Name"
    }
  ]
}
```

### Security Considerations

- The IAM role follows least privilege principles (S3 read-only access to specific bucket)
- S3 bucket uses server-side encryption with AES-256
- Lambda Function URL has CORS configured for web browser access
- No authentication is required (suitable for public quote API)

## Cost Estimation

Typical monthly costs for light usage:
- **Lambda**: $0.00 (within Free Tier - 1M requests/month)
- **S3**: $0.01-$0.02 (within Free Tier - 5GB storage)
- **Data Transfer**: $0.00-$0.01 (minimal for JSON responses)

**Total Estimated Cost**: $0.01-$0.05 per month for typical usage

> **Tip**: Use AWS Cost Explorer to monitor actual costs and set up billing alerts to track spending.

## Troubleshooting

### Common Issues

1. **Bucket name already exists**: S3 bucket names must be globally unique. The implementations include random suffixes to avoid conflicts.

2. **IAM permissions insufficient**: Ensure your AWS credentials have permissions to create IAM roles, Lambda functions, and S3 buckets.

3. **Lambda function timeout**: The default 30-second timeout should be sufficient for this simple use case.

4. **Function URL not accessible**: Verify that the Function URL was created and CORS is properly configured.

## Performance Optimization

- **Cold Start Optimization**: The function uses minimal dependencies to reduce cold start times
- **Memory Allocation**: 128 MB is optimal for this simple JSON processing task
- **Caching**: Consider implementing ElastiCache for high-traffic scenarios
- **S3 Transfer Acceleration**: Enable for global user base (additional cost)

## Security Best Practices

- The solution implements AWS Well-Architected security principles
- IAM role uses minimal required permissions
- S3 bucket encryption is enabled by default
- No sensitive data is stored or transmitted
- Function URL supports HTTPS only

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics:
- Lambda invocations and errors
- Lambda duration and memory usage
- S3 GET request count
- HTTP 4xx/5xx error rates

### Recommended Alarms

Set up CloudWatch alarms for:
- Lambda error rate > 5%
- Lambda duration > 10 seconds
- S3 4xx errors > 10 per hour

### Logging

- Lambda function logs are automatically sent to CloudWatch Logs
- Log retention is set to 14 days by default
- Enable X-Ray tracing for detailed performance insights

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service status at [AWS Service Health Dashboard](https://status.aws.amazon.com/)
3. Consult the [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
4. Review the [Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/)

## Extensions and Enhancements

Consider these enhancements for production use:

1. **API Gateway Integration**: Add request throttling, API keys, and usage plans
2. **DynamoDB Caching**: Cache frequently requested quotes for better performance
3. **CloudFront Distribution**: Add CDN for global content delivery
4. **Custom Domain**: Use Route 53 and Certificate Manager for branded URLs
5. **Monitoring Dashboard**: Create CloudWatch dashboard for operational visibility