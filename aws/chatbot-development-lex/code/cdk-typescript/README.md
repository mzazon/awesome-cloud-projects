# Amazon Lex Chatbot Development - CDK TypeScript

This CDK TypeScript application implements a comprehensive customer service chatbot solution using Amazon Lex V2, AWS Lambda, and supporting AWS services.

## Architecture Overview

The solution deploys:

- **Amazon Lex V2 Bot**: Conversational interface with natural language understanding
- **AWS Lambda Function**: Fulfillment logic with business rule processing
- **Amazon DynamoDB**: Order tracking and customer data storage
- **Amazon S3**: Product catalog and document storage
- **IAM Roles**: Secure, least-privilege access controls
- **CloudWatch Logs**: Monitoring and debugging capabilities

## Features

### Chatbot Capabilities
- **Product Information**: Interactive product catalog queries
- **Order Status Tracking**: Real-time order status from DynamoDB
- **Support Escalation**: Intelligent handoff to human agents
- **Multi-slot Conversations**: Natural conversation flows with data validation

### Technical Features
- **TypeScript Implementation**: Type-safe infrastructure as code
- **Error Handling**: Comprehensive error handling and logging
- **Security Best Practices**: Least privilege IAM, encrypted storage
- **Sample Data**: Pre-populated test data for immediate testing
- **Monitoring**: CloudWatch integration for observability

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ and npm installed
- AWS CDK CLI installed: `npm install -g aws-cdk`
- TypeScript compiler: `npm install -g typescript`

## Quick Start

### 1. Install Dependencies

```bash
cd cdk-typescript/
npm install
```

### 2. Bootstrap CDK (if first time)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
npm run deploy
```

### 4. Complete Lex Bot Setup

After deployment, the stack outputs will provide instructions and ARNs needed to complete the Lex bot configuration:

```bash
# Example commands (use actual ARNs from stack outputs)
aws lexv2-models create-bot \\
    --bot-name "customer-service-bot" \\
    --role-arn "arn:aws:iam::ACCOUNT:role/lex-service-role-SUFFIX" \\
    --data-privacy '{"childDirected": false}' \\
    --idle-session-ttl-in-seconds 300

# Configure intents and build the bot
aws lexv2-models create-bot-locale \\
    --bot-id BOT_ID \\
    --bot-version DRAFT \\
    --locale-id en_US \\
    --nlu-intent-confidence-threshold 0.7
```

## Project Structure

```
cdk-typescript/
├── app.ts                           # CDK application entry point
├── lib/
│   └── chatbot-development-stack.ts # Main stack definition
├── package.json                     # Dependencies and scripts
├── tsconfig.json                    # TypeScript configuration
├── cdk.json                         # CDK configuration
└── README.md                        # This file
```

## Key Components

### Lambda Fulfillment Function

The Lambda function handles three main intents:

- **ProductInformation**: Provides product details and recommendations
- **OrderStatus**: Queries DynamoDB for real-time order information
- **SupportRequest**: Escalates complex requests to human support

### DynamoDB Schema

```typescript
OrdersTable: {
  OrderId: string (partition key)
  Status: string
  EstimatedDelivery: string
  CustomerEmail: string
  Total: string
}
```

### Sample Test Data

The stack automatically populates the DynamoDB table with sample orders:
- `ORD123456`: Shipped order
- `ORD789012`: Processing order
- `ORD345678`: Delivered order

## Customization

### Environment Variables

Modify environment-specific values in `app.ts`:

```typescript
const environment = {
  account: 'YOUR_ACCOUNT_ID',
  region: 'us-east-1', // Change to your preferred region
};
```

### Bot Configuration

Update intent configurations in the stack:

```typescript
// Add custom slot types, sample utterances, or business logic
// in the Lambda function code within the stack
```

### Cost Optimization

For production deployments:

1. Remove `removalPolicy: cdk.RemovalPolicy.DESTROY` from persistent resources
2. Configure appropriate backup and retention policies
3. Implement cost allocation tags
4. Consider using reserved capacity for DynamoDB

## Testing

### Unit Tests

```bash
npm test
```

### Integration Testing

Test the deployed bot using AWS CLI:

```bash
# Test product information intent
aws lexv2-runtime recognize-text \\
    --bot-id YOUR_BOT_ID \\
    --bot-alias-id TSTALIASID \\
    --locale-id en_US \\
    --session-id test-session \\
    --text "Tell me about your electronics"

# Test order status intent
aws lexv2-runtime recognize-text \\
    --bot-id YOUR_BOT_ID \\
    --bot-alias-id TSTALIASID \\
    --locale-id en_US \\
    --session-id test-session \\
    --text "Check order ORD123456"
```

## Monitoring and Debugging

### CloudWatch Logs

Monitor function execution:

```bash
aws logs tail /aws/lambda/lex-fulfillment-SUFFIX --follow
```

### Metrics

Key metrics to monitor:
- Lambda invocation count and duration
- DynamoDB read/write capacity utilization
- Lex conversation success rates
- Error rates and types

## Security Considerations

### IAM Permissions

The stack implements least privilege access:
- Lambda execution role: DynamoDB and S3 read access only
- Lex service role: Lambda invoke permissions only
- Custom resource role: Limited DynamoDB write for sample data

### Data Protection

- DynamoDB point-in-time recovery enabled
- S3 bucket encryption and versioning enabled
- CloudWatch log retention configured
- No hardcoded secrets or credentials

## Cost Estimation

Estimated monthly costs for moderate usage:

- **Amazon Lex**: ~$15-30 (10,000+ text interactions)
- **AWS Lambda**: ~$5-10 (100,000+ invocations)
- **DynamoDB**: ~$2-5 (pay-per-request pricing)
- **S3**: ~$1-3 (minimal storage)
- **CloudWatch**: ~$2-5 (log storage and metrics)

**Total estimated cost: $25-53/month**

## Cleanup

### Remove All Resources

```bash
npm run destroy
```

### Manual Cleanup

If needed, manually delete:
- Lex bots and aliases
- CloudWatch log groups (if retention configured)
- S3 bucket contents (if auto-delete disabled)

## Troubleshooting

### Common Issues

1. **Deployment Failures**
   - Ensure CDK is bootstrapped: `cdk bootstrap`
   - Check AWS credentials and permissions
   - Verify unique resource naming

2. **Lambda Function Errors**
   - Check CloudWatch logs for detailed error messages
   - Verify DynamoDB table name in environment variables
   - Ensure IAM permissions for DynamoDB access

3. **Lex Bot Configuration**
   - Verify Lambda function ARN in bot configuration
   - Ensure proper intent and slot configuration
   - Check bot build status and errors

### Support Resources

- [AWS CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-typescript.html)
- [Amazon Lex V2 Developer Guide](https://docs.aws.amazon.com/lexv2/latest/dg/what-is.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)

## Contributing

To extend this solution:

1. Fork the repository
2. Create feature branches for new functionality
3. Add comprehensive tests for new features
4. Update documentation
5. Submit pull requests with detailed descriptions

## License

This project is licensed under the MIT-0 License. See the LICENSE file for details.