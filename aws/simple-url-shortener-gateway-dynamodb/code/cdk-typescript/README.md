# URL Shortener CDK TypeScript Application

This directory contains a complete AWS CDK TypeScript application for the **Simple URL Shortener with API Gateway and DynamoDB** recipe. The application creates a serverless URL shortening service that can create compact short links and redirect users to original URLs.

## Architecture

The application deploys the following AWS resources:

- **DynamoDB Table**: Stores URL mappings with `shortCode` as the partition key
- **Lambda Functions**: 
  - `CreateUrlFunction`: Handles POST requests to create short URLs
  - `RedirectFunction`: Handles GET requests to redirect to original URLs
- **API Gateway REST API**: Provides endpoints for URL creation and redirection
- **IAM Roles**: Least-privilege permissions for Lambda execution

## Prerequisites

- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)

## Required AWS Permissions

Your AWS credentials must have permissions for:
- IAM (create roles and policies)
- Lambda (create and manage functions)
- DynamoDB (create and manage tables)
- API Gateway (create and manage REST APIs)
- CloudFormation (deploy stacks)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if first time using CDK in this account/region)

```bash
cdk bootstrap
```

### 3. Deploy the Application

```bash
# Synthesize CloudFormation template (optional - for review)
cdk synth

# Deploy the stack
cdk deploy
```

### 4. Test the Application

After deployment, CDK will output the API endpoints. Use them to test:

```bash
# Create a short URL (replace with your actual API endpoint)
curl -X POST https://your-api-id.execute-api.region.amazonaws.com/prod/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://aws.amazon.com/lambda/"}'

# Test redirect (replace with returned short code)
curl -I https://your-api-id.execute-api.region.amazonaws.com/prod/abc123
```

## Configuration Options

You can customize the deployment using CDK context parameters:

```bash
# Deploy with custom stack name
cdk deploy -c stackName=MyUrlShortener

# Deploy with custom stage name
cdk deploy -c stageName=dev

# Deploy with CORS disabled
cdk deploy -c enableCors=false
```

## Project Structure

```
├── app.ts              # Main CDK application file
├── package.json        # NPM dependencies and scripts
├── tsconfig.json       # TypeScript configuration
├── cdk.json           # CDK configuration
└── README.md          # This file
```

## Key Features

### Security Best Practices

- **CDK Nag Integration**: Automatically validates security best practices
- **Least Privilege IAM**: Lambda functions have minimal required permissions
- **Encryption**: DynamoDB table uses AWS-managed encryption
- **Input Validation**: Comprehensive URL validation and error handling

### Scalability Features

- **Serverless Architecture**: Automatically scales with demand
- **DynamoDB On-Demand**: Pay-per-request billing with automatic scaling
- **API Gateway Throttling**: Built-in rate limiting and burst protection

### Operational Excellence

- **Structured Logging**: Lambda functions log important events
- **CloudWatch Integration**: Automatic metrics and monitoring
- **Point-in-Time Recovery**: DynamoDB backup enabled
- **Resource Tagging**: All resources tagged for cost tracking

## Available Scripts

```bash
# Build TypeScript code
npm run build

# Watch for changes and rebuild
npm run watch

# Run tests
npm run test

# Run tests in watch mode
npm run test:watch

# Generate test coverage report
npm run test:coverage

# Lint code
npm run lint

# Fix linting issues
npm run lint:fix

# Format code
npm run format

# CDK commands
npm run synth      # Synthesize CloudFormation template
npm run deploy     # Deploy the stack
npm run diff       # Show differences between deployed and current state
npm run destroy    # Delete the stack
```

## Customization

### Modifying Lambda Functions

The Lambda function code is embedded in the CDK application for simplicity. For production use, consider:

1. Moving Lambda code to separate files
2. Using `lambda.Code.fromAsset()` to bundle external code
3. Adding Lambda layers for shared dependencies
4. Implementing proper error handling and retry logic

### Adding Features

The CDK application is designed to be extensible. You can add:

1. **Custom Domains**: Use Route 53 and ACM for branded URLs
2. **Analytics**: Add CloudWatch dashboards for usage metrics
3. **Authentication**: Integrate with Amazon Cognito
4. **Rate Limiting**: Implement per-user throttling
5. **URL Expiration**: Add TTL support to DynamoDB

### Environment-Specific Configuration

```typescript
// Example: Different configurations per environment
const isProd = stageName === 'prod';

const urlShortenerStack = new UrlShortenerStack(app, stackName, {
  stageName,
  enableCors,
  dynamoDbBillingMode: isProd 
    ? dynamodb.BillingMode.PROVISIONED 
    : dynamodb.BillingMode.PAY_PER_REQUEST,
});
```

## Cost Optimization

The application is designed for cost efficiency:

- **Serverless Architecture**: No idle resource costs
- **DynamoDB On-Demand**: Pay only for requests
- **Lambda Provisioned Concurrency**: Disabled by default (enable for production if needed)
- **CloudWatch Logs**: Automatic retention policies

Estimated costs for testing: $0.10-0.50 (within AWS Free Tier limits)

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**: Run `cdk bootstrap` if you get bootstrap errors
2. **Permissions Denied**: Ensure your AWS credentials have required permissions
3. **Region Mismatch**: Verify your AWS CLI region matches CDK deployment region
4. **Node Version**: Ensure you're using Node.js 18.x or later

### Debugging

```bash
# Enable CDK debug logging
cdk deploy --debug

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name UrlShortenerStack

# Check Lambda function logs
aws logs tail /aws/lambda/your-function-name --follow
```

## Cleanup

To avoid ongoing charges, destroy the stack when testing is complete:

```bash
cdk destroy
```

This will delete all resources created by the CDK application.

## Security Considerations

### Production Deployment Checklist

- [ ] Enable DynamoDB deletion protection
- [ ] Implement API authentication (Cognito/Lambda authorizers)
- [ ] Add WAF rules for API Gateway
- [ ] Enable detailed CloudWatch monitoring
- [ ] Set up CloudWatch alarms for errors
- [ ] Review and document CDK Nag suppressions
- [ ] Implement backup strategies
- [ ] Add VPC endpoints if needed
- [ ] Configure custom domain with SSL certificate

### CDK Nag Compliance

The application includes CDK Nag for security validation. Address any warnings before production deployment:

```bash
# Review CDK Nag findings
cdk synth 2>&1 | grep -A5 -B5 "Warning\|Error"
```

## Contributing

When modifying this CDK application:

1. Follow TypeScript and CDK best practices
2. Update tests for any new functionality
3. Run linting and formatting before committing
4. Update documentation for new features
5. Validate CDK Nag compliance

## Support

For issues with this CDK application:

1. Check the [original recipe documentation](../../../simple-url-shortener-gateway-dynamodb.md)
2. Review AWS CDK documentation
3. Check AWS service-specific documentation
4. Search AWS forums and Stack Overflow

## License

This code is provided under the MIT License. See the original recipe for detailed terms and conditions.