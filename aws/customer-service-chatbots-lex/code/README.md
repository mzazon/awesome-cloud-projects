# Infrastructure as Code for Customer Service Chatbots with Amazon Lex

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Customer Service Chatbots with Lex".

## Overview

This solution deploys an intelligent customer service chatbot using Amazon Lex that automatically handles common inquiries through natural language understanding. The infrastructure includes:

- **Amazon Lex V2 Bot** for natural language processing and conversation management
- **AWS Lambda Function** for intent fulfillment and backend integration
- **DynamoDB Table** for customer data storage
- **IAM Roles and Policies** for secure service-to-service communication

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The solution creates a serverless chatbot architecture that can:
- Handle order status inquiries
- Process billing and account balance requests
- Provide product information
- Escalate complex issues to human agents
- Scale automatically based on customer demand

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured with appropriate credentials
- An AWS account with permissions to create:
  - Amazon Lex V2 bots and resources
  - Lambda functions
  - DynamoDB tables
  - IAM roles and policies
- Basic understanding of conversational AI concepts

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions

#### CDK TypeScript
- Node.js (version 18 or later)
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript (`npm install -g typescript`)

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI (`npm install -g aws-cdk`)
- pip (Python package manager)

#### Terraform
- Terraform v1.0 or later
- AWS provider for Terraform

## Cost Estimation

Resources deployed by this solution:
- **Amazon Lex V2**: Free tier includes 10,000 text requests and 5,000 speech requests per month for first year
- **AWS Lambda**: Free tier includes 1M requests and 400,000 GB-seconds per month
- **DynamoDB**: Free tier includes 25GB storage and 25 read/write capacity units
- **IAM**: No additional charges

**Estimated monthly cost** (after free tier): $5-15 depending on usage volume

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name customer-service-lex-bot \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BotName,ParameterValue=CustomerServiceBot \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name customer-service-lex-bot

# Get outputs
aws cloudformation describe-stacks \
    --stack-name customer-service-lex-bot \
    --query 'Stacks[0].Outputs'
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
cdk deploy --parameters botName=CustomerServiceBot

# View outputs
cdk list
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
cdk deploy --parameters bot-name=CustomerServiceBot

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
terraform plan -var="bot_name=CustomerServiceBot"

# Apply configuration
terraform apply -var="bot_name=CustomerServiceBot"

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
```

## Testing the Deployed Bot

After deployment, you can test the chatbot using the AWS CLI:

```bash
# Get bot details from CloudFormation outputs or Terraform outputs
export BOT_ID="your-bot-id"
export BOT_ALIAS_ID="TSTALIASID"

# Test order status inquiry
aws lexv2-runtime recognize-text \
    --bot-id "$BOT_ID" \
    --bot-alias-id "$BOT_ALIAS_ID" \
    --locale-id "en_US" \
    --session-id "test-session-1" \
    --text "What is my order status for customer 12345?"

# Test billing inquiry
aws lexv2-runtime recognize-text \
    --bot-id "$BOT_ID" \
    --bot-alias-id "$BOT_ALIAS_ID" \
    --locale-id "en_US" \
    --session-id "test-session-2" \
    --text "Check my account balance for customer 67890"

# Test product information
aws lexv2-runtime recognize-text \
    --bot-id "$BOT_ID" \
    --bot-alias-id "$BOT_ALIAS_ID" \
    --locale-id "en_US" \
    --session-id "test-session-3" \
    --text "Tell me about your laptops"
```

## Customization

### Environment Variables

The implementations support customization through variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `bot_name` | Name of the Lex bot | `CustomerServiceBot` |
| `lambda_function_name` | Name of the Lambda function | `lex-fulfillment-function` |
| `dynamodb_table_name` | Name of the DynamoDB table | `customer-data` |
| `aws_region` | AWS region for deployment | `us-east-1` |

### Modifying Customer Data

To add more sample customer data, modify the DynamoDB items in the respective implementation:

```json
{
  "CustomerId": "99999",
  "Name": "Your Customer",
  "Email": "customer@example.com",
  "LastOrderId": "ORD-123",
  "LastOrderStatus": "Delivered",
  "AccountBalance": "0.00"
}
```

### Adding New Intents

To extend the bot with additional intents:

1. Add new intent definitions in the IaC code
2. Update the Lambda function to handle new intent types
3. Add corresponding sample utterances and slots
4. Redeploy the infrastructure

### Multi-Channel Integration

The deployed bot can be integrated with:
- **Amazon Connect** for voice-based customer service
- **Web applications** using the AWS SDK for JavaScript
- **Mobile applications** using AWS Mobile SDKs
- **Slack, Facebook Messenger** through Amazon Lex channel integrations

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor the solution using CloudWatch:

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/lex-fulfillment"

# View Lex conversation logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lex"
```

### Common Issues

1. **Bot build failures**: Check intent configuration and sample utterances
2. **Lambda timeout errors**: Increase timeout in function configuration
3. **DynamoDB access errors**: Verify IAM permissions
4. **Intent recognition issues**: Add more diverse sample utterances

### Performance Optimization

- Monitor Lambda execution duration and optimize code
- Adjust DynamoDB read/write capacity based on usage patterns
- Implement conversation analytics for intent recognition improvements
- Cache frequently accessed data in Lambda memory

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name customer-service-lex-bot

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name customer-service-lex-bot
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
terraform destroy -var="bot_name=CustomerServiceBot"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Service roles have minimal required permissions
- **Encryption**: DynamoDB encryption at rest enabled by default
- **VPC Integration**: Lambda functions can be deployed in VPC for enhanced security
- **Logging**: CloudWatch logs for audit and troubleshooting

## Production Readiness

For production deployments, consider:

1. **Enable conversation logs** for analytics and compliance
2. **Implement session persistence** for complex conversations
3. **Add sentiment analysis** using Amazon Comprehend
4. **Set up CloudWatch alarms** for monitoring
5. **Configure backup policies** for DynamoDB
6. **Implement API rate limiting** to prevent abuse
7. **Enable AWS X-Ray tracing** for performance monitoring

## Integration with Existing Systems

The chatbot can be integrated with:

- **CRM systems** (Salesforce, HubSpot) via API Gateway
- **Ticketing systems** (Jira, ServiceNow) for escalations
- **Knowledge bases** for dynamic content retrieval
- **Payment gateways** for transaction-related inquiries
- **Analytics platforms** for conversation insights

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation for [Amazon Lex](https://docs.aws.amazon.com/lex/)
3. Consult the [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
4. Reference [DynamoDB documentation](https://docs.aws.amazon.com/dynamodb/)

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any new features
4. Validate all implementations work correctly

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to your organization's policies for production usage guidelines.