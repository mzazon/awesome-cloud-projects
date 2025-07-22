# Visual Serverless Application CDK TypeScript

This directory contains the AWS CDK TypeScript implementation for the Visual Serverless Application recipe. This implementation demonstrates how to build serverless applications that can be visually designed with AWS Application Composer and deployed via CodeCatalyst CI/CD pipelines.

## Architecture Overview

The CDK application creates a complete serverless architecture including:

- **API Gateway REST API**: HTTP endpoints with CORS support and throttling
- **Lambda Functions**: Python-based serverless compute for business logic
- **DynamoDB Table**: NoSQL database with encryption and point-in-time recovery
- **SQS Dead Letter Queue**: Error handling for failed Lambda invocations
- **CloudWatch Monitoring**: Log groups, metrics, and dashboards
- **X-Ray Tracing**: Distributed tracing for observability
- **IAM Roles**: Least privilege access policies

## Prerequisites

- Node.js 18.0.0 or later
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Python 3.11 (for Lambda function runtime)

## Required AWS Permissions

Your AWS credentials need permissions for:
- CloudFormation stack operations
- Lambda function management
- API Gateway configuration
- DynamoDB table operations
- SQS queue management
- CloudWatch logs and metrics
- X-Ray tracing configuration
- IAM role creation

## Installation

1. Navigate to the CDK TypeScript directory:
   ```bash
   cd cdk-typescript/
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Bootstrap CDK (if not already done):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

Set the following environment variables or use CDK context:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export STAGE=dev  # or staging, prod
```

### CDK Context

Alternatively, use CDK context parameters:

```bash
cdk deploy --context stage=dev --context region=us-east-1
```

## Deployment

### Development Environment

```bash
# Build the TypeScript code
npm run build

# Preview the CloudFormation template
npm run synth

# Deploy to development environment
npm run deploy:dev
```

### Staging Environment

```bash
# Deploy to staging environment
npm run deploy:staging
```

### Production Environment

```bash
# Deploy to production environment (with additional protection)
npm run deploy:prod
```

### Manual Deployment

```bash
# Standard deployment
cdk deploy

# With specific context
cdk deploy --context stage=prod --context region=us-west-2
```

## Development Workflow

### Building and Testing

```bash
# Build TypeScript code
npm run build

# Watch for changes and rebuild
npm run watch

# Run tests
npm run test

# Run tests with coverage
npm run test:coverage

# Run tests in watch mode
npm run test:watch
```

### Code Quality

```bash
# Lint TypeScript code
npm run lint

# Fix linting issues
npm run lint:fix

# Format code with Prettier
npm run format

# Check code formatting
npm run format:check
```

### CDK Commands

```bash
# Synthesize CloudFormation template
npm run synth

# Show differences between deployed and local
npm run diff

# Deploy stack
npm run deploy

# Destroy stack
npm run destroy
```

## Lambda Function Code

The Lambda function code should be placed in the following directory structure:

```
../../src/handlers/
├── users.py          # Main Lambda function
└── requirements.txt  # Python dependencies (if needed)
```

The CDK stack automatically packages and deploys the Lambda function code from this location.

## Monitoring and Observability

### CloudWatch Dashboard

The stack creates a CloudWatch dashboard with:
- API Gateway request metrics
- Lambda function performance metrics
- DynamoDB capacity metrics
- Error rates and latency tracking

### X-Ray Tracing

X-Ray tracing is enabled for:
- API Gateway requests
- Lambda function execution
- DynamoDB operations

### CloudWatch Logs

Log groups are created with:
- 14-day retention period
- Structured logging format
- Centralized log aggregation

## Security Features

### Encryption

- DynamoDB table encrypted with AWS managed keys
- SQS dead letter queue encrypted
- API Gateway with SSL/TLS termination

### IAM Policies

- Lambda function with minimal required permissions
- API Gateway with proper resource-based policies
- DynamoDB access limited to specific table operations

### Network Security

- API Gateway with request validation
- CORS configuration for web applications
- Rate limiting and throttling

## Cost Optimization

### Serverless Pricing

- Lambda: Pay-per-invocation with 1M free requests/month
- API Gateway: Pay-per-API call with 1M free requests/month
- DynamoDB: Pay-per-request pricing mode
- CloudWatch: Pay-per-log ingestion and retention

### Resource Limits

- Lambda reserved concurrency: 100
- API Gateway throttling: 500 requests/second
- DynamoDB: On-demand scaling

## Environment-Specific Configuration

### Development (dev)

- Basic monitoring
- Shorter log retention
- Lower resource limits
- Destroy on stack deletion

### Staging (staging)

- Enhanced monitoring
- Standard log retention
- Production-like resource limits
- Retain on stack deletion

### Production (prod)

- Comprehensive monitoring
- Extended log retention
- Higher resource limits
- Deletion protection enabled
- Point-in-time recovery enabled

## Troubleshooting

### Common Issues

1. **Bootstrap Error**: Ensure CDK is bootstrapped in your account/region
2. **Permission Errors**: Verify AWS credentials have required permissions
3. **Lambda Packaging**: Ensure Lambda code exists in `../../src/handlers/`
4. **Build Errors**: Run `npm run build` to check TypeScript compilation

### Debugging

```bash
# Enable CDK debug logging
cdk deploy --debug

# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name visual-serverless-app-dev

# View Lambda logs
aws logs tail /aws/lambda/dev-users-function --follow
```

## Integration with Application Composer

This CDK implementation can be imported into AWS Application Composer for visual editing:

1. Deploy the stack using CDK
2. Open AWS Application Composer in the AWS Console
3. Import the CloudFormation template from the deployed stack
4. Edit the architecture visually
5. Export the updated template for CDK integration

## Integration with CodeCatalyst

This CDK application is designed to work with CodeCatalyst CI/CD pipelines:

1. Create a CodeCatalyst project
2. Connect to your Git repository
3. Configure build workflows to run CDK commands
4. Set up environment-specific deployment stages
5. Enable automated testing and deployment

## Cleanup

### Development Environment

```bash
npm run destroy:dev
```

### All Environments

```bash
# Destroy specific environment
cdk destroy --context stage=staging

# Destroy all stacks (use with caution)
cdk destroy --all
```

### Clean Local Artifacts

```bash
# Remove build artifacts and dependencies
npm run clean

# Remove CDK output
rm -rf cdk.out/
```

## Additional Resources

- [AWS CDK TypeScript Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-typescript.html)
- [AWS Application Composer Documentation](https://docs.aws.amazon.com/application-composer/latest/dg/what-is-composer.html)
- [CodeCatalyst User Guide](https://docs.aws.amazon.com/codecatalyst/latest/userguide/welcome.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [API Gateway Best Practices](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-basic-concept.html)

## Support

For issues with this CDK implementation:
1. Check the troubleshooting section above
2. Review AWS CDK documentation
3. Consult the original recipe documentation
4. Check AWS CloudFormation events for deployment issues