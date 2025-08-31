# Interactive Data Analytics with Bedrock AgentCore Code Interpreter - CDK TypeScript

This CDK TypeScript application deploys an intelligent data analytics system that combines AWS Bedrock AgentCore Code Interpreter with serverless infrastructure for natural language data analysis.

## Architecture Overview

The solution creates:

- **S3 Buckets**: Secure storage for raw data and analysis results with lifecycle policies
- **Lambda Function**: Serverless orchestration of analytics workflows
- **Bedrock AgentCore**: AI-powered code interpreter for natural language queries
- **API Gateway**: RESTful API for external access with CORS support
- **CloudWatch**: Comprehensive monitoring, logging, and dashboards
- **SQS**: Dead letter queue for error handling and reliability
- **IAM**: Least privilege security policies

## Prerequisites

Before deploying this solution, ensure you have:

1. **AWS CLI v2** installed and configured with appropriate credentials
2. **Node.js 18+** and npm 8+ installed
3. **AWS CDK v2** installed globally (`npm install -g aws-cdk`)
4. **TypeScript** installed globally (`npm install -g typescript`)
5. **AWS account** with permissions for:
   - Bedrock AgentCore (preview feature access required)
   - S3, Lambda, CloudWatch, API Gateway, SQS, IAM
6. **CDK Bootstrap** completed in your target account/region

### AWS Account Setup

```bash
# Install AWS CDK globally
npm install -g aws-cdk

# Verify AWS CLI configuration
aws sts get-caller-identity

# Bootstrap CDK (if not already done)
cdk bootstrap aws://ACCOUNT-ID/REGION
```

## Installation

1. **Clone or download the source code:**

   ```bash
   cd aws/interactive-data-analytics-bedrock-codeinterpreter/code/cdk-typescript/
   ```

2. **Install dependencies:**

   ```bash
   npm install
   ```

3. **Build the TypeScript code:**

   ```bash
   npm run build
   ```

4. **Validate the setup:**

   ```bash
   npm run validate
   ```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export AWS_REGION=$CDK_DEFAULT_REGION
```

### Custom Configuration

You can customize the deployment by modifying the stack parameters in `app.ts`:

- **Resource naming**: Change the `uniqueSuffix` generation logic
- **Retention policies**: Modify CloudWatch log retention and S3 lifecycle rules
- **Lambda configuration**: Adjust timeout, memory, and environment variables
- **Monitoring thresholds**: Update CloudWatch alarm thresholds

## Deployment

### Quick Deployment

```bash
# Deploy with default settings
npm run deploy
```

### Step-by-Step Deployment

```bash
# 1. Synthesize CloudFormation templates
npm run synth

# 2. Review the generated CloudFormation template
cat cdk.out/InteractiveDataAnalyticsStack.template.json

# 3. Deploy with approval prompts
cdk deploy --require-approval broadening

# 4. Monitor deployment progress
# The deployment typically takes 3-5 minutes
```

### Post-Deployment Setup

After successful deployment, the CDK will output important values:

```bash
# Example outputs:
✅  InteractiveDataAnalyticsStack

Outputs:
InteractiveDataAnalyticsStack.ApiGatewayUrl = https://abc123.execute-api.us-east-1.amazonaws.com/prod/
InteractiveDataAnalyticsStack.ApiGatewayAnalyticsEndpoint = https://abc123.execute-api.us-east-1.amazonaws.com/prod/analytics
InteractiveDataAnalyticsStack.RawDataBucketName = analytics-raw-data-12345678
InteractiveDataAnalyticsStack.ResultsBucketName = analytics-results-12345678
InteractiveDataAnalyticsStack.LambdaFunctionName = analytics-orchestrator-12345678
InteractiveDataAnalyticsStack.DashboardUrl = https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=Analytics-Dashboard-12345678
```

### Upload Sample Data

```bash
# Get bucket name from CDK outputs
RAW_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name InteractiveDataAnalyticsStack \
  --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucketName`].OutputValue' \
  --output text)

# Create sample data file
cat > sample_sales_data.csv << EOF
date,product,region,sales_amount,quantity,customer_segment
2024-01-01,Widget A,North,1250.50,25,Enterprise
2024-01-02,Widget B,South,890.75,18,SMB
2024-01-03,Widget A,East,2150.25,43,Enterprise
2024-01-04,Widget C,West,567.30,12,Startup
2024-01-05,Widget B,North,1875.60,38,Enterprise
EOF

# Upload sample data
aws s3 cp sample_sales_data.csv s3://$RAW_BUCKET/datasets/
```

## Usage

### Via API Gateway

Test the analytics API using curl:

```bash
# Get API endpoint from CDK outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name InteractiveDataAnalyticsStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayAnalyticsEndpoint`].OutputValue' \
  --output text)

# Send analytics request
curl -X POST $API_ENDPOINT \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Analyze the sales data and provide insights on regional performance and top products"
  }'
```

### Via AWS Lambda Console

1. Navigate to the AWS Lambda console
2. Find the function named `analytics-orchestrator-<suffix>`
3. Use the Test tab with this sample event:

```json
{
  "query": "Calculate total sales by region and identify growth opportunities"
}
```

### Via AWS CLI

```bash
# Get Lambda function name
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name InteractiveDataAnalyticsStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
  --output text)

# Invoke function directly
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{"query": "Perform comprehensive sales analysis"}' \
  --cli-binary-format raw-in-base64-out \
  response.json

# View response
cat response.json | jq '.'
```

## Monitoring and Troubleshooting

### CloudWatch Dashboard

Access the monitoring dashboard using the URL from CDK outputs:

- **Analytics Execution Metrics**: Track successful executions and errors
- **Lambda Performance**: Monitor duration, invocations, and errors
- **System Health**: Overall system performance indicators

### Log Analysis

```bash
# View Lambda function logs
aws logs tail /aws/lambda/$FUNCTION_NAME --follow

# View Code Interpreter logs (when available)
aws logs tail /aws/bedrock/agentcore/analytics-interpreter-<suffix> --follow
```

### Common Issues

1. **Bedrock AgentCore Not Available**:
   - Ensure you have preview access to Bedrock AgentCore
   - Verify the service is available in your region
   - Check IAM permissions for Bedrock services

2. **S3 Access Denied**:
   - Verify bucket policies and IAM roles
   - Check if bucket names conflict with existing resources
   - Ensure proper SSL enforcement

3. **Lambda Timeout**:
   - Increase timeout in `app.ts` if processing large datasets
   - Monitor CloudWatch metrics for performance patterns
   - Consider increasing memory allocation

4. **API Gateway CORS Issues**:
   - Verify CORS configuration in the CDK code
   - Test with proper headers in requests
   - Check browser developer tools for error details

### Performance Optimization

1. **Lambda Optimization**:
   ```bash
   # Update memory configuration
   aws lambda update-function-configuration \
     --function-name $FUNCTION_NAME \
     --memory-size 1024
   ```

2. **S3 Performance**:
   - Use multipart uploads for large files
   - Implement proper prefix patterns for high-throughput scenarios
   - Monitor request metrics in CloudWatch

3. **Cost Optimization**:
   - Review S3 lifecycle policies
   - Monitor Lambda execution duration
   - Use reserved concurrency appropriately

## Development

### Running Tests

```bash
# Run unit tests
npm test

# Run tests in watch mode
npm run test:watch

# Run linting
npm run lint

# Fix linting issues automatically
npm run lint:fix
```

### Code Formatting

```bash
# Format code
npm run format

# Check formatting
npm run format:check
```

### Making Changes

1. **Modify the stack**: Edit `app.ts` to change infrastructure
2. **Test changes**: Run `npm run validate` to verify syntax
3. **Preview changes**: Use `cdk diff` to see what will change
4. **Deploy changes**: Run `npm run deploy`

### Adding New Features

To extend the solution:

1. **Additional data sources**: Add new S3 integrations or data connectors
2. **Enhanced monitoring**: Add custom CloudWatch metrics and alarms
3. **Security improvements**: Implement VPC endpoints or enhanced encryption
4. **Performance features**: Add caching layers or optimized data processing

## Cleanup

### Remove All Resources

```bash
# Destroy the stack (removes all resources)
npm run destroy

# Or use CDK directly
cdk destroy --force
```

### Partial Cleanup

```bash
# Empty S3 buckets before destruction (if needed)
aws s3 rm s3://$RAW_BUCKET --recursive
aws s3 rm s3://$RESULTS_BUCKET --recursive
```

### Verify Cleanup

```bash
# Check that stack is deleted
aws cloudformation describe-stacks --stack-name InteractiveDataAnalyticsStack
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Minimal required permissions
- **Encryption**: S3 server-side encryption and SSL enforcement
- **Network Security**: Private subnets and security groups (when applicable)
- **Logging**: Comprehensive audit trails via CloudTrail and CloudWatch
- **Access Control**: API Gateway authentication and authorization options

### Security Enhancements

For production deployments, consider:

1. **VPC Integration**: Deploy Lambda in private subnets
2. **WAF Protection**: Add AWS WAF to API Gateway
3. **API Authentication**: Implement Cognito or API keys
4. **Secrets Management**: Use AWS Secrets Manager for sensitive data
5. **Network ACLs**: Add additional network-level controls

## Cost Estimation

Typical daily costs for testing (assuming moderate usage):

- **Lambda**: $2-5 (based on execution time and frequency)
- **S3**: $1-3 (storage and requests)
- **CloudWatch**: $1-2 (logs and metrics)
- **API Gateway**: $1-2 (requests and data transfer)
- **Bedrock AgentCore**: $5-15 (based on usage and model complexity)

**Total estimated daily cost**: $10-27

### Cost Optimization Tips

1. Use S3 lifecycle policies to transition to cheaper storage classes
2. Set CloudWatch log retention to reasonable periods
3. Monitor and optimize Lambda memory allocation
4. Use API Gateway caching for frequently accessed endpoints

## Support and Contributing

For issues or questions:

1. **AWS Documentation**: [CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
2. **Bedrock Documentation**: [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/)
3. **Community Support**: [AWS CDK GitHub Issues](https://github.com/aws/aws-cdk/issues)
4. **AWS Support**: Open a support case for account-specific issues

### Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Make your changes with proper tests
4. Submit a pull request with detailed description

## License

This project is licensed under the Apache License 2.0. See the LICENSE file for details.

## Additional Resources

- [AWS CDK Workshop](https://cdkworkshop.com/)
- [AWS Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Serverless Application Lens](https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/)