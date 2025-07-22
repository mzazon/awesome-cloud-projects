# Infrastructure as Code for Chatbot Development with Amazon Lex

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Chatbot Development with Amazon Lex".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Amazon Lex V2
  - AWS Lambda
  - Amazon DynamoDB
  - Amazon S3
  - AWS IAM
  - Amazon CloudWatch
- Node.js 16+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python and Lambda runtime)
- Terraform 1.0+ (for Terraform implementation)
- Appropriate IAM permissions for resource creation and management

## Architecture Overview

This implementation creates:
- Amazon Lex V2 bot with customer service intents
- AWS Lambda function for conversation fulfillment
- DynamoDB table for order tracking
- S3 bucket for product catalog
- IAM roles and policies for secure service integration
- CloudWatch logs for monitoring and debugging

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name lex-chatbot-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BotName,ParameterValue=customer-service-bot \
                 ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name lex-chatbot-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name lex-chatbot-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
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

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
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

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and guide you through the deployment process
```

## Configuration Options

### Environment Variables
Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export BOT_NAME=customer-service-bot
export ENVIRONMENT=dev
export LAMBDA_TIMEOUT=30
export DDB_BILLING_MODE=PAY_PER_REQUEST
```

### CloudFormation Parameters
- `BotName`: Name for the Lex bot (default: customer-service-bot)
- `Environment`: Environment tag (dev/staging/prod)
- `LambdaTimeout`: Lambda function timeout in seconds (default: 30)
- `DynamoDBBillingMode`: DynamoDB billing mode (default: PAY_PER_REQUEST)

### CDK Context Variables
Configure in `cdk.json`:

```json
{
  "context": {
    "botName": "customer-service-bot",
    "environment": "dev",
    "lambdaTimeout": 30,
    "enableLogging": true
  }
}
```

### Terraform Variables
Configure in `terraform.tfvars`:

```hcl
bot_name = "customer-service-bot"
environment = "dev"
lambda_timeout = 30
enable_detailed_monitoring = true
```

## Testing the Deployment

After successful deployment, test the chatbot:

```bash
# Get bot details from outputs
BOT_ID=$(aws cloudformation describe-stacks \
    --stack-name lex-chatbot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BotId`].OutputValue' \
    --output text)

BOT_ALIAS_ID=$(aws cloudformation describe-stacks \
    --stack-name lex-chatbot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BotAliasId`].OutputValue' \
    --output text)

# Test product information intent
aws lexv2-runtime recognize-text \
    --bot-id $BOT_ID \
    --bot-alias-id $BOT_ALIAS_ID \
    --locale-id en_US \
    --session-id test-session-1 \
    --text "Tell me about your electronics"

# Test order status intent
aws lexv2-runtime recognize-text \
    --bot-id $BOT_ID \
    --bot-alias-id $BOT_ALIAS_ID \
    --locale-id en_US \
    --session-id test-session-2 \
    --text "Check order status for ORD123456"
```

## Monitoring and Troubleshooting

### CloudWatch Logs
Monitor the Lambda function logs:

```bash
# View recent Lambda logs
aws logs tail /aws/lambda/lex-fulfillment-function --follow

# View Lex conversation logs (if enabled)
aws logs tail aws/lex/customer-service-bot --follow
```

### Bot Analytics
Access bot analytics in the AWS Console:
1. Navigate to Amazon Lex V2
2. Select your bot
3. View Analytics tab for conversation metrics

### Common Issues
- **Permission Errors**: Ensure IAM roles have necessary permissions
- **Build Failures**: Check CloudWatch logs for detailed error messages
- **Integration Issues**: Verify Lambda function permissions and configuration

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name lex-chatbot-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name lex-chatbot-stack
```

### Using CDK
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

# Follow prompts to confirm resource deletion
```

## Customization

### Adding New Intents
To add new intents, modify the infrastructure code:

1. **CloudFormation**: Add new intent resources in the template
2. **CDK**: Extend the bot construct with additional intents
3. **Terraform**: Add intent resources to the configuration
4. **Lambda**: Update the fulfillment function to handle new intents

### Integration with External Systems
Extend the Lambda function to integrate with:
- CRM systems via API Gateway
- Email services via Amazon SES
- Notification systems via Amazon SNS
- Analytics platforms via Amazon Kinesis

### Multi-language Support
Add additional locales to the bot:
- Configure additional bot locales in IaC
- Update Lambda function for multi-language responses
- Add language detection logic

## Security Considerations

- IAM roles follow least privilege principle
- Lambda function includes input validation
- DynamoDB access is restricted to specific operations
- CloudWatch logging enabled for auditing
- Bot data privacy settings configured appropriately

## Cost Optimization

- DynamoDB uses on-demand billing by default
- Lambda functions have appropriate timeout settings
- S3 bucket configured with intelligent tiering (optional)
- CloudWatch log retention configured to 14 days

## Support

For issues with this infrastructure code:
1. Check CloudWatch logs for error details
2. Refer to the original recipe documentation
3. Consult AWS documentation for specific services:
   - [Amazon Lex V2 Developer Guide](https://docs.aws.amazon.com/lexv2/latest/dg/)
   - [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
   - [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)

## Additional Resources

- [Amazon Lex V2 Best Practices](https://docs.aws.amazon.com/lexv2/latest/dg/best-practices.html)
- [Conversational AI Design Patterns](https://aws.amazon.com/blogs/machine-learning/design-patterns-for-developing-conversational-experiences/)
- [AWS CDK Examples](https://github.com/aws-samples/aws-cdk-examples)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)