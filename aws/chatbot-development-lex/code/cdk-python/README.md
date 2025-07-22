# AWS CDK Python - Amazon Lex Chatbot Development

This directory contains the AWS CDK Python implementation for deploying a complete customer service chatbot solution using Amazon Lex V2.

## Architecture Overview

This CDK application deploys:

- **Amazon Lex V2 Bot**: Conversational AI interface with three intents (ProductInformation, OrderStatus, SupportRequest)
- **AWS Lambda Function**: Fulfillment logic for bot responses and business logic
- **Amazon DynamoDB**: Table for storing customer order data
- **Amazon S3**: Bucket for product catalog storage
- **IAM Roles**: Least privilege access for all services
- **CloudWatch Logs**: Logging and monitoring for Lambda functions

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Docker installed (for Lambda bundling)

### Required AWS Permissions

Your AWS credentials must have permissions to create:
- IAM roles and policies
- Lambda functions
- DynamoDB tables
- S3 buckets
- Amazon Lex bots
- CloudWatch log groups

## Quick Start

### 1. Install Dependencies

```bash
# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\\Scripts\\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Bootstrap CDK (First time only)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Deploy with default settings
cdk deploy

# Deploy with custom stack name
cdk deploy --context stack_name=my-chatbot-stack

# Deploy with custom unique suffix
cdk deploy --context unique_suffix=prod
```

### 4. Verify Deployment

After deployment, the stack outputs will provide:
- DynamoDB table name
- S3 bucket name  
- Lambda function ARN
- Lex service role ARN

## Configuration

### Environment Variables

The CDK app supports the following context variables:

```bash
# Set custom stack name
cdk deploy --context stack_name=my-custom-chatbot

# Set unique suffix for resource names
cdk deploy --context unique_suffix=prod

# Set specific AWS account and region
cdk deploy --context account=123456789012 --context region=us-east-1
```

### cdk.json Context

You can also modify the `cdk.json` file to set default values:

```json
{
  "context": {
    "stack_name": "customer-service-chatbot",
    "unique_suffix": "demo",
    "environment": "development"
  }
}
```

## Testing the Chatbot

### 1. Complete Lex Bot Configuration

After CDK deployment, you'll need to manually complete the Lex bot configuration:

```bash
# Get the outputs from the deployed stack
aws cloudformation describe-stacks \
    --stack-name customer-service-chatbot \
    --query 'Stacks[0].Outputs'

# Use the AWS CLI or Console to complete Lex bot setup
# (This step requires manual configuration as CDK L1 constructs are needed for Lex V2)
```

### 2. Test with Sample Conversations

Once the bot is configured, test with these sample phrases:

- **Product Information**: "Tell me about your electronics"
- **Order Status**: "Check order status for ORD123456"
- **Support Request**: "I need help with my account"

### 3. Verify Lambda Execution

```bash
# Check Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/lex-fulfillment"

# View recent log events
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/lex-fulfillment-demo" \
    --order-by LastEventTime \
    --descending
```

## Development

### Code Structure

```
cdk-python/
├── app.py                 # CDK application entry point
├── chatbot_stack.py       # Main stack definition
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
└── README.md             # This file
```

### Key Components

- **ChatbotStack**: Main CDK stack containing all resources
- **Lambda Fulfillment**: Handles bot logic and database queries
- **Custom Resource**: Populates sample data in DynamoDB
- **IAM Roles**: Least privilege access for all services

### Adding New Intents

To add new intents to the chatbot:

1. Update the Lambda function code in `chatbot_stack.py`
2. Add new intent handling logic
3. Redeploy the stack: `cdk deploy`
4. Manually configure the new intent in Lex (or use L1 constructs)

### Local Development

```bash
# Format code
black .

# Type checking
mypy .

# Run tests
pytest

# CDK diff to see changes
cdk diff

# Synthesize CloudFormation template
cdk synth
```

## Security Considerations

### IAM Permissions

- Lambda execution role has minimal permissions (DynamoDB read, S3 read)
- Lex service role follows AWS recommended policies
- No overly broad permissions granted

### Data Protection

- DynamoDB table has point-in-time recovery enabled
- S3 bucket has versioning and encryption enabled
- No sensitive data stored in Lambda environment variables

### Network Security

- All resources deployed in default VPC with AWS managed security
- No public endpoints exposed beyond AWS service endpoints
- Lambda function uses AWS managed subnets

## Cost Optimization

### Resource Sizing

- Lambda: 128MB memory, 30-second timeout
- DynamoDB: Pay-per-request billing
- S3: Standard storage class with lifecycle policies

### Cost Monitoring

Monitor costs through:
- AWS Cost Explorer
- CloudWatch billing alarms
- Resource tagging for cost allocation

### Estimated Monthly Costs

For testing workload (1000 bot interactions/month):
- Amazon Lex: ~$0.75 (after free tier)
- Lambda: ~$0.20
- DynamoDB: ~$1.25
- S3: ~$0.50
- **Total: ~$2.70/month**

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Error**
   ```bash
   # Ensure you have proper AWS credentials
   aws sts get-caller-identity
   
   # Bootstrap the environment
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Lambda Permission Error**
   ```bash
   # Check Lambda execution role
   aws iam get-role --role-name LexLambdaRole-demo
   ```

3. **DynamoDB Access Error**
   ```bash
   # Verify table exists and has sample data
   aws dynamodb scan --table-name customer-orders-demo --max-items 5
   ```

### Debug Mode

Enable CDK debug mode:
```bash
cdk deploy --debug
```

Enable Lambda debug logging by updating the function environment:
```python
environment={
    "LOG_LEVEL": "DEBUG",
    "ORDERS_TABLE_NAME": self.orders_table.table_name,
}
```

## Cleanup

### Destroy Resources

```bash
# Destroy the entire stack
cdk destroy

# Confirm deletion when prompted
```

### Manual Cleanup

Some resources may require manual cleanup:
- CloudWatch log groups (if retention is set to never expire)
- S3 bucket contents (if auto-delete is disabled)

## Next Steps

1. **Complete Lex Configuration**: Set up intents, slots, and sample utterances
2. **Integration**: Connect to web applications or messaging platforms
3. **Monitoring**: Set up CloudWatch dashboards and alarms
4. **Multi-language**: Add additional locales for international support
5. **Advanced Features**: Implement conversation logging and analytics

## Resources

- [AWS CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)
- [Amazon Lex V2 Developer Guide](https://docs.aws.amazon.com/lexv2/latest/dg/)
- [AWS Lambda Python Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)

## Support

For issues with this CDK application:
1. Check the troubleshooting section above
2. Review AWS CloudFormation stack events
3. Check CloudWatch logs for Lambda function errors
4. Refer to the original recipe documentation