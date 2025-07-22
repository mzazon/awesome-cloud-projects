# Real-time Recommendation Systems with Amazon Personalize - CDK TypeScript

This CDK TypeScript application deploys a complete real-time recommendation system using Amazon Personalize and API Gateway. The infrastructure includes all necessary components for training machine learning models, deploying recommendation campaigns, and serving real-time recommendations through a scalable API.

## Architecture Overview

The solution creates:

- **S3 Bucket**: Storage for training data and model artifacts
- **IAM Roles**: Secure access permissions for Personalize and Lambda
- **Lambda Function**: Serverless API handler for recommendation requests
- **API Gateway**: RESTful API endpoints with monitoring and caching
- **CloudWatch Monitoring**: Alarms and dashboards for operational visibility

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ and npm installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Appropriate AWS permissions for creating the required resources

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if first time using CDK in this account/region):
   ```bash
   cdk bootstrap
   ```

3. **Deploy the infrastructure**:
   ```bash
   npm run deploy
   ```

4. **Complete the Personalize setup** (see Post-Deployment Steps below)

## Configuration Options

You can customize the deployment using CDK context variables:

```bash
# Deploy with custom configuration
cdk deploy -c region=us-west-2 -c environment=production -c minProvisionedTPS=2
```

### Available Configuration Options

| Context Variable | Default | Description |
|------------------|---------|-------------|
| `region` | `us-east-1` | AWS region for deployment |
| `environment` | `development` | Environment name for tagging |
| `solutionName` | `user-personalization` | Name for the Personalize solution |
| `campaignName` | `real-time-recommendations` | Name for the Personalize campaign |
| `minProvisionedTPS` | `1` | Minimum provisioned TPS for campaign |
| `enableDetailedMonitoring` | `true` | Enable detailed CloudWatch monitoring |
| `enableXRayTracing` | `true` | Enable X-Ray tracing for Lambda and API Gateway |
| `lambdaMemorySize` | `256` | Lambda function memory size (MB) |
| `lambdaTimeout` | `30` | Lambda function timeout (seconds) |
| `apiStageName` | `prod` | API Gateway stage name |
| `corsOrigins` | `*` | CORS allowed origins |
| `enableApiCaching` | `true` | Enable API Gateway caching |
| `enableThrottling` | `true` | Enable API Gateway throttling |
| `burstLimit` | `2000` | API Gateway burst limit |
| `rateLimit` | `1000` | API Gateway rate limit |

## Post-Deployment Steps

After the CDK deployment completes, you need to set up Amazon Personalize manually:

### 1. Create Dataset Group

```bash
# Get the outputs from CDK deployment
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name RecommendationSystemStack \
  --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
  --output text)

PERSONALIZE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name RecommendationSystemStack \
  --query 'Stacks[0].Outputs[?OutputKey==`PersonalizeRoleArn`].OutputValue' \
  --output text)

# Create dataset group
aws personalize create-dataset-group \
  --name ecommerce-recommendations \
  --region us-east-1
```

### 2. Create Schema and Dataset

```bash
# Create interaction schema
cat > interactions-schema.json << EOF
{
    "type": "record",
    "name": "Interactions",
    "namespace": "com.amazonaws.personalize.schema",
    "fields": [
        {"name": "USER_ID", "type": "string"},
        {"name": "ITEM_ID", "type": "string"},
        {"name": "TIMESTAMP", "type": "long"},
        {"name": "EVENT_TYPE", "type": "string"}
    ],
    "version": "1.0"
}
EOF

# Create schema
aws personalize create-schema \
  --name interaction-schema \
  --schema file://interactions-schema.json

# Create dataset and import data
# (Follow the complete process as described in the recipe)
```

### 3. Update Lambda Environment

Once your campaign is created, update the Lambda function:

```bash
LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name RecommendationSystemStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
  --output text)

CAMPAIGN_ARN="your-campaign-arn-here"

aws lambda update-function-configuration \
  --function-name $LAMBDA_FUNCTION_NAME \
  --environment Variables="{CAMPAIGN_ARN=${CAMPAIGN_ARN},REGION=us-east-1,LOG_LEVEL=INFO}"
```

## API Usage

### Get Recommendations

```bash
# Get the API URL from stack outputs
API_URL=$(aws cloudformation describe-stacks \
  --stack-name RecommendationSystemStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text)

# Test the API
curl -X GET "${API_URL}recommendations/user1?numResults=5" \
  -H "Content-Type: application/json"
```

### API Response Format

```json
{
  "userId": "user1",
  "recommendations": [
    {
      "itemId": "item101",
      "score": 0.8543
    },
    {
      "itemId": "item102",
      "score": 0.7234
    }
  ],
  "numResults": 2,
  "requestId": "12345678-1234-1234-1234-123456789012"
}
```

## Monitoring and Troubleshooting

### CloudWatch Alarms

The deployment creates several CloudWatch alarms:

- **API Gateway 4XX Errors**: Monitors client errors
- **API Gateway 5XX Errors**: Monitors server errors
- **Lambda Errors**: Monitors function execution errors
- **Lambda Duration**: Monitors function execution time

### Log Groups

Check the following log groups for troubleshooting:

- `/aws/lambda/recommendation-api-[suffix]`: Lambda function logs
- `/aws/apigateway/RecommendationAPI`: API Gateway access logs

### Common Issues

1. **"Campaign not configured" error**: Ensure the CAMPAIGN_ARN environment variable is set in Lambda
2. **"Invalid user ID" error**: Verify the user ID format matches your training data
3. **High latency**: Consider enabling API Gateway caching and optimizing Lambda memory
4. **Throttling**: Adjust API Gateway rate limits or increase campaign TPS

## Development Commands

```bash
# Build the TypeScript code
npm run build

# Watch for changes and rebuild
npm run watch

# Run tests
npm test

# Lint code
npm run lint

# Fix linting issues
npm run lint:fix

# Synthesize CloudFormation template
npm run synth

# Compare deployed stack with current state
cdk diff

# Deploy with approval prompts
cdk deploy

# Destroy the stack
npm run destroy
```

## Security Considerations

- **IAM Roles**: Use least-privilege permissions
- **API Gateway**: Enable request validation and rate limiting
- **Lambda**: Implement proper error handling and logging
- **S3**: Block public access and enable versioning
- **Monitoring**: Set up CloudWatch alarms for security events

## Cost Optimization

- **Personalize**: Use appropriate TPS provisioning for your workload
- **API Gateway**: Enable caching to reduce Lambda invocations
- **Lambda**: Optimize memory allocation and execution time
- **S3**: Use lifecycle policies for training data

## Scaling Considerations

- **Campaign TPS**: Monitor and adjust based on traffic patterns
- **Lambda Concurrency**: Set reserved concurrency if needed
- **API Gateway**: Consider regional vs edge-optimized endpoints
- **Caching**: Implement multi-level caching strategies

## Cleanup

To remove all resources:

```bash
# Destroy the CDK stack
npm run destroy

# Clean up any remaining Personalize resources manually
# (Campaigns, solutions, datasets, dataset groups)
```

## Support

For issues with this CDK application:
1. Check the CloudWatch logs for error details
2. Verify all prerequisites are met
3. Ensure AWS credentials have sufficient permissions
4. Review the original recipe documentation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.