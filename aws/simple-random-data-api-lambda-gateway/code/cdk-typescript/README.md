# Simple Random Data API - CDK TypeScript Implementation

This CDK TypeScript application deploys a serverless REST API that generates random data including quotes, numbers, and colors using AWS Lambda and API Gateway.

## Architecture

The application uses AWS Solutions Constructs to implement best practices for API Gateway and Lambda integration:

- **API Gateway REST API**: Handles HTTP requests and routing
- **AWS Lambda Function**: Generates random data (quotes, numbers, colors)
- **CloudWatch Logs**: Captures application and access logs
- **CDK Nag**: Validates security best practices

## Features

- ✅ **Serverless Architecture**: Automatically scales and only pay for usage
- ✅ **Security Best Practices**: Uses AWS Solutions Constructs with CDK Nag validation
- ✅ **CORS Enabled**: Supports browser-based applications
- ✅ **Request Validation**: Validates query parameters at API Gateway level
- ✅ **Observability**: Includes CloudWatch logging and X-Ray tracing
- ✅ **Type Safety**: Full TypeScript implementation with proper typing
- ✅ **Infrastructure as Code**: Reproducible deployments with AWS CDK

## Prerequisites

- **AWS CLI v2** installed and configured
- **Node.js 18+** and npm installed
- **AWS CDK v2** installed globally: `npm install -g aws-cdk`
- **TypeScript** installed globally: `npm install -g typescript`
- **AWS Account** with appropriate permissions for Lambda, API Gateway, and CloudWatch

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (First Time Only)

```bash
cdk bootstrap
```

### 3. Synthesize CloudFormation Template

```bash
npm run synth
# or
cdk synth
```

This command validates your CDK code and generates CloudFormation templates.

### 4. Deploy the Stack

```bash
npm run deploy
# or
cdk deploy
```

The deployment will create:
- Lambda function for random data generation
- API Gateway REST API with /random endpoint
- CloudWatch log groups for monitoring
- IAM roles with least privilege permissions

### 5. Test the API

After deployment, CDK will output the API Gateway URL. Test the endpoints:

```bash
# Get random quote (default)
curl "https://YOUR_API_ID.execute-api.REGION.amazonaws.com/dev/random"

# Get random quote explicitly
curl "https://YOUR_API_ID.execute-api.REGION.amazonaws.com/dev/random?type=quote"

# Get random number (1-1000)
curl "https://YOUR_API_ID.execute-api.REGION.amazonaws.com/dev/random?type=number"

# Get random color with hex and RGB values
curl "https://YOUR_API_ID.execute-api.REGION.amazonaws.com/dev/random?type=color"
```

## API Documentation

### Endpoint

```
GET /random?type={quote|number|color}
```

### Query Parameters

- `type` (optional): Data type to generate
  - `quote` (default): Returns inspirational quotes
  - `number`: Returns random number between 1-1000
  - `color`: Returns color with name, hex, and RGB values

### Response Format

```json
{
  "type": "quote",
  "data": "The only way to do great work is to love what you do. - Steve Jobs",
  "timestamp": "request-id-12345",
  "message": "Random quote generated successfully"
}
```

### Error Response

```json
{
  "error": "Internal server error",
  "message": "Failed to generate random data"
}
```

## Development Commands

### Build and Test

```bash
# Compile TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm test

# Lint code
npm run lint
```

### CDK Commands

```bash
# Synthesize CloudFormation template
npm run synth

# Deploy stack
npm run deploy

# Show diff between deployed and local
cdk diff

# Destroy stack
npm run destroy
```

## Security Considerations

This implementation includes several security best practices:

### ✅ Applied Security Measures

- **AWS Solutions Constructs**: Implements vetted security patterns
- **CDK Nag Validation**: Ensures compliance with AWS security best practices
- **Least Privilege IAM**: Lambda function has minimal required permissions
- **CloudWatch Logging**: All function invocations and errors are logged
- **Request Validation**: API Gateway validates request parameters
- **CORS Configuration**: Properly configured for web application access

### 📋 CDK Nag Suppressions

The following CDK Nag rules are suppressed with justification:

- **AwsSolutions-APIG4**: Authorization not required for public random data API
- **AwsSolutions-APIG3**: WAF not required for this simple example
- **AwsSolutions-IAM4/IAM5**: AWS Solutions Constructs use appropriate managed policies

### 🔒 Production Recommendations

For production deployments, consider:

1. **Enable WAF**: Add Web Application Firewall for additional protection
2. **API Authentication**: Implement API keys or Cognito authentication
3. **Rate Limiting**: Configure API Gateway usage plans
4. **Custom Domain**: Use Route 53 and ACM for custom domain names
5. **Environment Variables**: Use AWS Systems Manager Parameter Store for configuration
6. **Error Handling**: Implement comprehensive error handling and monitoring

## Monitoring and Observability

### CloudWatch Resources Created

- **Lambda Function Logs**: `/aws/lambda/SimpleRandomDataApiStack-RandomDataApi*`
- **API Gateway Execution Logs**: Enabled for troubleshooting
- **X-Ray Tracing**: Distributed tracing for request flow analysis

### Monitoring Commands

```bash
# View Lambda function logs
aws logs tail /aws/lambda/FUNCTION_NAME --follow

# View API Gateway metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=Simple\ Random\ Data\ API \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Cost Optimization

This serverless architecture is designed for cost efficiency:

- **Lambda**: Pay per invocation (1M free requests/month)
- **API Gateway**: Pay per API call (1M free calls/month for first 12 months)
- **CloudWatch**: Basic logging included in free tier
- **Estimated Monthly Cost**: $0.00 - $5.00 for moderate usage

### Cost Monitoring

```bash
# Enable cost allocation tags
aws ce put-dimension-key \
  --key "Project" \
  --value "SimpleRandomDataApi"
```

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**
   ```bash
   Error: Need to perform AWS CDK bootstrap
   Solution: cdk bootstrap
   ```

2. **Insufficient Permissions**
   ```bash
   Error: AccessDenied creating Lambda function
   Solution: Ensure IAM user has Lambda, API Gateway, and CloudWatch permissions
   ```

3. **CDK Version Mismatch**
   ```bash
   Error: CDK version mismatch
   Solution: npm install -g aws-cdk@latest && npm update
   ```

### Debug Mode

Enable verbose CDK output:

```bash
cdk deploy --verbose
cdk synth --verbose
```

### Function Testing

Test Lambda function locally:

```bash
# Install SAM CLI for local testing
pip install aws-sam-cli

# Generate SAM template from CDK
cdk synth --no-staging > template.yaml

# Start local API
sam local start-api
```

## Customization

### Modify Lambda Function

Edit the `lambdaFunctionCode` variable in `app.ts` to customize the random data generation logic.

### Add New Endpoints

Extend the API by adding resources to the `apiLambdaConstruct.apiGateway.root`:

```typescript
const healthResource = apiLambdaConstruct.apiGateway.root.addResource('health');
healthResource.addMethod('GET', new aws_apigateway.MockIntegration({
  integrationResponses: [{
    statusCode: '200',
    responseTemplates: {
      'application/json': '{"status": "healthy"}'
    }
  }]
}));
```

### Environment Configuration

Configure different environments by modifying the stack props:

```typescript
const prodStack = new SimpleRandomDataApiStack(app, 'SimpleRandomDataApiProdStack', {
  env: {
    account: 'PROD_ACCOUNT_ID',
    region: 'us-east-1'
  },
  terminationProtection: true
});
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
npm run destroy
# or
cdk destroy
```

This will remove all created AWS resources including:
- Lambda function
- API Gateway
- CloudWatch log groups
- IAM roles and policies

## Support and Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Solutions Constructs](https://aws.amazon.com/solutions/constructs/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [CDK Nag Rules Reference](https://github.com/cdklabs/cdk-nag/blob/main/RULES.md)

For issues specific to this implementation, refer to the original recipe documentation or AWS support resources.