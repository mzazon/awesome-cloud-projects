# Infrastructure as Code for Email List Management with SES and DynamoDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Email List Management with SES and DynamoDB".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a serverless email list management system that includes:

- **DynamoDB Table**: Stores subscriber information with email as the primary key
- **Lambda Functions**: Three functions for subscribe, newsletter sending, and list management
- **IAM Role**: Provides necessary permissions for Lambda functions to access DynamoDB and SES
- **SES Configuration**: Email service for sending newsletters (requires manual email verification)

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for:
  - DynamoDB (CreateTable, PutItem, GetItem, UpdateItem, DeleteItem, Scan)
  - Lambda (CreateFunction, UpdateFunctionCode, InvokeFunction)
  - IAM (CreateRole, AttachRolePolicy, PassRole)
  - SES (VerifyEmailIdentity, SendEmail)
- A verified email address in Amazon SES for sending emails
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

> **Note**: New SES accounts start in sandbox mode. For production use, request removal from sandbox mode through the AWS console.

## Quick Start

### Using CloudFormation

```bash
# Set your verified SES email address
export SENDER_EMAIL="your-verified-email@example.com"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name email-list-management \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SenderEmail,ParameterValue=$SENDER_EMAIL \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name email-list-management

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name email-list-management \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set your verified SES email address
export SENDER_EMAIL="your-verified-email@example.com"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set your verified SES email address
export SENDER_EMAIL="your-verified-email@example.com"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Set your verified SES email address
export TF_VAR_sender_email="your-verified-email@example.com"

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set your verified SES email address
export SENDER_EMAIL="your-verified-email@example.com"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment results
echo "Deployment complete! Check the output for function names and table details."
```

## Testing the Deployment

After deployment, test the email list management system:

### 1. Subscribe a Test User

```bash
# Get the subscribe function name from your deployment outputs
SUBSCRIBE_FUNCTION_NAME="your-subscribe-function-name"

# Test subscription
aws lambda invoke \
    --function-name $SUBSCRIBE_FUNCTION_NAME \
    --payload '{"email":"test@example.com","name":"Test User"}' \
    response.json

cat response.json
```

### 2. List Subscribers

```bash
# Get the list function name from your deployment outputs
LIST_FUNCTION_NAME="your-list-function-name"

# List all subscribers
aws lambda invoke \
    --function-name $LIST_FUNCTION_NAME \
    --payload '{}' \
    response.json

cat response.json
```

### 3. Send Newsletter

```bash
# Get the newsletter function name from your deployment outputs
NEWSLETTER_FUNCTION_NAME="your-newsletter-function-name"

# Send test newsletter
aws lambda invoke \
    --function-name $NEWSLETTER_FUNCTION_NAME \
    --payload '{"subject":"Welcome Newsletter","message":"Thank you for joining our community!"}' \
    response.json

cat response.json
```

## Configuration Options

### Environment Variables

- `SENDER_EMAIL`: Your verified SES email address (required)
- `AWS_REGION`: AWS region for deployment (defaults to your CLI configuration)
- `TABLE_NAME`: Custom DynamoDB table name (optional, defaults to generated name)

### CloudFormation Parameters

- `SenderEmail`: Your verified SES email address
- `Environment`: Environment name (dev, staging, prod)
- `TableBillingMode`: DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)

### Terraform Variables

- `sender_email`: Your verified SES email address
- `environment`: Environment name (default: "dev")
- `aws_region`: AWS region (default: "us-east-1")
- `table_billing_mode`: DynamoDB billing mode (default: "PAY_PER_REQUEST")

### CDK Context Variables

```json
{
  "senderEmail": "your-verified-email@example.com",
  "environment": "dev",
  "tableBillingMode": "PAY_PER_REQUEST"
}
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name email-list-management

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name email-list-management
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

This implementation follows AWS security best practices:

- **IAM Roles**: Lambda functions use least-privilege IAM roles
- **Encryption**: DynamoDB encryption at rest is enabled by default
- **SES Sandbox**: New accounts start in sandbox mode for security
- **Input Validation**: Lambda functions validate email addresses and inputs
- **Error Handling**: Comprehensive error handling prevents information disclosure

## Cost Optimization

The solution is designed for cost efficiency:

- **DynamoDB**: Uses on-demand billing to pay only for actual usage
- **Lambda**: Pay-per-execution pricing with optimized memory allocation
- **SES**: Extremely low cost for email sending (free tier available)
- **No Always-On Resources**: Fully serverless with no baseline costs

## Monitoring and Logging

All Lambda functions include CloudWatch logging by default:

```bash
# View logs for subscribe function
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/email-subscribe"

# Stream logs in real-time
aws logs tail "/aws/lambda/email-subscribe-SUFFIX" --follow
```

## Troubleshooting

### Common Issues

1. **SES Email Not Verified**
   - Verify your sender email address in the SES console
   - Check for verification email in your inbox

2. **Lambda Function Timeout**
   - Newsletter function may timeout with large subscriber lists
   - Increase timeout in configuration if needed

3. **Permission Denied Errors**
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM roles are properly attached to Lambda functions

4. **DynamoDB Access Issues**
   - Verify the table exists and has correct permissions
   - Check the table name matches your configuration

### Debug Commands

```bash
# Check SES verification status
aws ses get-identity-verification-attributes \
    --identities your-email@example.com

# Test DynamoDB table access
aws dynamodb describe-table --table-name your-table-name

# Check Lambda function configuration
aws lambda get-function --function-name your-function-name
```

## Integration with Applications

### REST API Integration

Consider adding API Gateway for web application integration:

```bash
# Example API Gateway integration (manual step)
aws apigateway create-rest-api --name email-list-api
```

### Web Form Integration

HTML form example for subscriber registration:

```html
<form id="subscribe-form">
    <input type="email" name="email" required placeholder="Enter your email">
    <input type="text" name="name" required placeholder="Enter your name">
    <button type="submit">Subscribe</button>
</form>
```

## Advanced Configuration

### Custom Domain Setup

For production deployments, consider:

1. Setting up SES with a custom domain
2. Configuring DKIM and SPF records
3. Implementing bounce and complaint handling

### Batch Processing

For large newsletters:

1. Implement SQS for batch processing
2. Use SES batch sending capabilities
3. Add retry logic for failed deliveries

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation:
   - [Amazon SES Developer Guide](https://docs.aws.amazon.com/ses/latest/dg/)
   - [DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)
   - [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
3. Consult provider-specific troubleshooting guides

## Contributing

When modifying this infrastructure:

1. Test all changes in a development environment
2. Update documentation for any new parameters or outputs
3. Ensure cleanup scripts remove all created resources
4. Follow the provider's best practices and coding standards