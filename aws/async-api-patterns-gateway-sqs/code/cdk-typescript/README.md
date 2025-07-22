# Asynchronous API Patterns with API Gateway and SQS - CDK TypeScript

This CDK TypeScript application implements an asynchronous API pattern using Amazon API Gateway, Amazon SQS, AWS Lambda, Amazon DynamoDB, and Amazon S3. The solution decouples API request processing from response delivery, enabling long-running task processing without client timeouts.

## Architecture

The solution implements the following components:

- **API Gateway**: REST API with `/submit` and `/status/{jobId}` endpoints
- **Amazon SQS**: Main processing queue with dead letter queue for failed messages
- **AWS Lambda**: Job processor and status checker functions
- **Amazon DynamoDB**: Job status tracking table
- **Amazon S3**: Results storage bucket
- **IAM Roles**: Secure cross-service communication

## Prerequisites

- Node.js 16.x or later
- AWS CLI v2 installed and configured
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- TypeScript installed globally (`npm install -g typescript`)
- Appropriate AWS permissions for all services

## Installation

1. **Clone and navigate to the project directory**:
   ```bash
   cd aws/asynchronous-api-patterns-api-gateway-sqs/code/cdk-typescript/
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK** (if not done previously):
   ```bash
   cdk bootstrap
   ```

## Configuration

You can customize the deployment by setting context variables:

```bash
# Set environment name (default: dev)
cdk deploy -c environment=prod

# Set project name (default: async-api)
cdk deploy -c projectName=my-async-api

# Set both
cdk deploy -c environment=staging -c projectName=custom-api
```

## Deployment

1. **Build the project**:
   ```bash
   npm run build
   ```

2. **Synthesize CloudFormation template** (optional):
   ```bash
   cdk synth
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

   Or with custom configuration:
   ```bash
   cdk deploy -c environment=prod -c projectName=production-async-api
   ```

4. **Note the outputs**: After deployment, CDK will display important outputs including:
   - API Gateway endpoint URL
   - Submit endpoint URL
   - Status endpoint URL
   - Queue URLs
   - Table and bucket names

## Usage

### Submit a Job

```bash
# Replace with your actual API endpoint from CDK outputs
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/prod"

# Submit a job
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"task": "process_data", "data": {"input": "test data"}}' \
  ${API_ENDPOINT}/submit
```

Response:
```json
{
  "jobId": "unique-job-id",
  "status": "queued",
  "message": "Job submitted successfully"
}
```

### Check Job Status

```bash
# Check status using the jobId from the submit response
curl ${API_ENDPOINT}/status/unique-job-id
```

Response:
```json
{
  "jobId": "unique-job-id",
  "status": "completed",
  "createdAt": "2025-01-27T10:00:00.000Z",
  "updatedAt": "2025-01-27T10:00:15.000Z",
  "result": "s3://bucket-name/results/unique-job-id.json"
}
```

## Testing

### Unit Tests

Run the included unit tests:

```bash
npm test
```

### Integration Testing

1. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

2. **Test job submission and processing**:
   ```bash
   # Submit test job
   RESPONSE=$(curl -s -X POST \
     -H "Content-Type: application/json" \
     -d '{"task": "test", "data": {"message": "hello world"}}' \
     ${API_ENDPOINT}/submit)
   
   # Extract job ID
   JOB_ID=$(echo $RESPONSE | jq -r '.jobId')
   
   # Check initial status (should be queued)
   curl ${API_ENDPOINT}/status/${JOB_ID}
   
   # Wait for processing
   sleep 15
   
   # Check final status (should be completed)
   curl ${API_ENDPOINT}/status/${JOB_ID}
   ```

3. **Verify results in S3**:
   ```bash
   # Download result file
   aws s3 cp s3://your-results-bucket/results/${JOB_ID}.json ./result.json
   cat result.json
   ```

## Monitoring

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# Job processor logs
aws logs tail /aws/lambda/async-api-dev-job-processor --follow

# Status checker logs
aws logs tail /aws/lambda/async-api-dev-status-checker --follow
```

### DynamoDB Console

View job records in the DynamoDB console or using CLI:

```bash
aws dynamodb scan --table-name async-api-dev-jobs
```

### SQS Monitoring

Monitor queue metrics:

```bash
# Check queue attributes
aws sqs get-queue-attributes \
  --queue-url https://sqs.region.amazonaws.com/account/async-api-dev-main-queue \
  --attribute-names All
```

## Development

### Project Structure

```
cdk-typescript/
├── app.ts                          # CDK app entry point
├── lib/
│   └── asynchronous-api-stack.ts   # Main stack definition
├── package.json                    # Dependencies and scripts
├── tsconfig.json                   # TypeScript configuration
├── cdk.json                        # CDK configuration
└── README.md                       # This file
```

### Code Formatting

```bash
# Lint code
npm run lint

# Fix linting issues
npm run lint:fix
```

### Watch Mode

For development, use watch mode to automatically rebuild on changes:

```bash
npm run watch
```

## Customization

### Extending the Job Processor

Modify the job processor Lambda function code in `lib/asynchronous-api-stack.ts`:

```typescript
// Replace the simulated processing logic
time.sleep(10)  // Simulate work

// With your actual processing logic
result = your_processing_function(job_data)
```

### Adding New Endpoints

Add new API Gateway resources and methods:

```typescript
// Add new resource
const newResource = api.root.addResource('new-endpoint');

// Add method with Lambda integration
newResource.addMethod('POST', new apigateway.LambdaIntegration(yourFunction));
```

### Environment-Specific Configuration

Use CDK context for environment-specific settings:

```typescript
const config = {
  dev: { retentionDays: 1, timeout: 60 },
  prod: { retentionDays: 14, timeout: 300 }
};

const envConfig = config[environment] || config.dev;
```

## Security

### IAM Roles

The stack creates minimal IAM roles with least-privilege access:

- **API Gateway Role**: SQS SendMessage permissions only
- **Lambda Role**: DynamoDB, S3, and SQS permissions scoped to specific resources

### Encryption

- **S3**: Server-side encryption with AWS managed keys
- **DynamoDB**: Encryption at rest with AWS managed keys
- **SQS**: Messages encrypted in transit

### API Security

Consider adding authentication:

```typescript
// Add API key requirement
submitResource.addMethod('POST', integration, {
  apiKeyRequired: true
});

// Or add Lambda authorizer
const authorizer = new apigateway.TokenAuthorizer(this, 'Authorizer', {
  handler: authorizerFunction
});

submitResource.addMethod('POST', integration, {
  authorizer: authorizer
});
```

## Troubleshooting

### Common Issues

1. **Job stuck in "queued" status**:
   - Check Lambda function logs for errors
   - Verify SQS event source mapping is active
   - Check Lambda function permissions

2. **API Gateway 403 errors**:
   - Verify API Gateway role has SQS permissions
   - Check resource ARNs in IAM policies

3. **DynamoDB write errors**:
   - Verify Lambda role has DynamoDB permissions
   - Check table name environment variable

### Debug Commands

```bash
# Check stack status
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name YourStackName

# Check Lambda function configuration
aws lambda get-function --function-name async-api-dev-job-processor
```

## Cost Optimization

- **SQS**: No charges for idle queues
- **Lambda**: Pay only for execution time
- **DynamoDB**: On-demand billing scales with usage
- **API Gateway**: Pay per API call
- **S3**: Pay for storage and requests

Estimated monthly cost for development usage: $5-10

## Cleanup

Remove all resources to avoid ongoing charges:

```bash
cdk destroy
```

Confirm deletion when prompted. This will remove all AWS resources created by the stack.

## Additional Resources

- [AWS CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/api/v2/typescript/)
- [API Gateway SQS Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-sqs.html)
- [AWS Lambda with SQS](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [Asynchronous Messaging Patterns](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-integrating-microservices/asynchronous-patterns.html)

## Support

For issues related to this CDK implementation:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Check CDK GitHub repository for known issues
4. Refer to the original recipe documentation