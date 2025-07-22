# Infrastructure as Code for Asynchronous API Patterns with SQS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Asynchronous API Patterns with SQS".

## Overview

This solution implements an asynchronous API pattern using Amazon API Gateway and Amazon SQS to decouple request processing from response delivery. The architecture includes:

- **API Gateway**: REST API with /submit and /status endpoints
- **SQS**: Main processing queue with dead letter queue for reliability
- **Lambda Functions**: Job processor and status checker
- **DynamoDB**: Job status tracking table
- **S3**: Result storage bucket
- **IAM**: Roles and policies for secure service integration

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - API Gateway (create REST APIs, methods, deployments)
  - SQS (create queues, send/receive messages)
  - Lambda (create functions, event source mappings)
  - DynamoDB (create tables, read/write items)
  - S3 (create buckets, put/get objects)
  - IAM (create roles, attach policies)
- For CDK implementations: Node.js 18+ or Python 3.9+
- For Terraform: Terraform CLI 1.0+

### Estimated Costs

- Development usage: $5-10/month
- Production usage: Scales with API calls, message volume, and storage
- Pay-per-use pricing for all services

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name async-api-patterns \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-async-api

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name async-api-patterns

# Get the API endpoint
aws cloudformation describe-stacks \
    --stack-name async-api-patterns \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# The API endpoint will be displayed in the output
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# The API endpoint will be displayed in the output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get the API endpoint
terraform output api_endpoint
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will display the API endpoint when complete
```

## Testing the Deployment

Once deployed, test the asynchronous API:

1. **Submit a job**:
   ```bash
   # Replace YOUR_API_ENDPOINT with the actual endpoint
   curl -X POST \
       -H "Content-Type: application/json" \
       -d '{"task": "process_data", "data": {"input": "test data"}}' \
       YOUR_API_ENDPOINT/submit
   ```

2. **Check job status**:
   ```bash
   # Replace JOB_ID with the jobId from the submit response
   curl YOUR_API_ENDPOINT/status/JOB_ID
   ```

3. **Verify processing**:
   - Job should progress from "queued" to "processing" to "completed"
   - Results are stored in the S3 bucket
   - Job status is tracked in DynamoDB

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Prefix for all resource names (default: async-api-patterns)
- `Environment`: Environment tag for resources (default: dev)

### CDK Configuration

Modify the stack configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// cdk-typescript/app.ts
const app = new cdk.App();
new AsyncApiStack(app, 'AsyncApiStack', {
  projectName: 'my-async-api',
  environment: 'production'
});
```

### Terraform Variables

Configure in `terraform.tfvars`:

```hcl
project_name = "my-async-api"
environment  = "production"
region      = "us-west-2"
```

### Bash Script Configuration

Set environment variables before running:

```bash
export PROJECT_NAME="my-async-api"
export AWS_REGION="us-west-2"
./scripts/deploy.sh
```

## Architecture Components

### API Gateway

- **Submit Endpoint**: `POST /submit` - Accepts job requests, returns job ID
- **Status Endpoint**: `GET /status/{jobId}` - Returns current job status
- **Regional endpoints** for optimal latency
- **CORS enabled** for web application integration

### SQS Configuration

- **Main Queue**: Receives job messages from API Gateway
- **Dead Letter Queue**: Captures failed messages for investigation
- **Visibility timeout**: 300 seconds (5 minutes)
- **Message retention**: 14 days
- **Redrive policy**: 3 attempts before moving to DLQ

### Lambda Functions

- **Job Processor**: Processes messages from SQS, updates DynamoDB, stores results in S3
- **Status Checker**: Retrieves job status from DynamoDB for API queries
- **Error handling**: Failed jobs marked with error status in DynamoDB

### DynamoDB Table

- **Partition key**: jobId
- **Pay-per-request billing** for cost efficiency
- **Attributes**: jobId, status, createdAt, updatedAt, result, error

### S3 Bucket

- **Results storage**: Processed job results in JSON format
- **Lifecycle policies**: Can be configured for cost optimization
- **Server-side encryption**: Enabled by default

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics:

- API Gateway: Request count, latency, 4XX/5XX errors
- SQS: Messages sent, received, visible, approximate age
- Lambda: Invocation count, duration, errors, throttles
- DynamoDB: Consumed capacity, throttled requests

### CloudWatch Logs

Log groups created for:

- API Gateway execution logs
- Lambda function logs
- Application-specific logs

### Alarms (Optional Enhancement)

Consider setting up alarms for:

- High API Gateway error rates
- SQS dead letter queue message count
- Lambda function errors or high duration
- DynamoDB throttling events

## Security Considerations

### IAM Roles and Policies

- **Principle of least privilege** applied to all roles
- **API Gateway role**: SendMessage permission to SQS only
- **Lambda role**: Read/write permissions to DynamoDB, S3, and SQS
- **No hardcoded credentials** in any configuration

### Data Protection

- **Encryption in transit**: HTTPS for API Gateway, encrypted connections between services
- **Encryption at rest**: S3 server-side encryption, DynamoDB encryption
- **Access logging**: API Gateway access logs (optional, can be enabled)

### Network Security

- **Regional endpoints** to minimize data travel
- **VPC integration** possible for enhanced security (not implemented in basic version)
- **WAF integration** possible for additional protection (not implemented in basic version)

## Performance Optimization

### Scaling Characteristics

- **API Gateway**: Scales automatically to handle traffic spikes
- **SQS**: Handles millions of messages per second
- **Lambda**: Automatic scaling up to account limits
- **DynamoDB**: On-demand billing scales with usage

### Optimization Tips

1. **Lambda memory allocation**: Monitor and adjust based on actual usage
2. **SQS batch size**: Increase for higher throughput (up to 10 messages)
3. **DynamoDB capacity**: Monitor consumed capacity and adjust if needed
4. **S3 storage class**: Use appropriate storage class for result retention requirements

## Cost Optimization

### Pay-per-Use Pricing

All services use pay-per-use pricing models:

- **API Gateway**: Per request
- **SQS**: Per message
- **Lambda**: Per invocation and duration
- **DynamoDB**: Per request (on-demand)
- **S3**: Per storage and requests

### Cost Reduction Strategies

1. **Implement result TTL**: Auto-delete old results from S3
2. **Optimize Lambda memory**: Right-size based on profiling
3. **Use SQS long polling**: Reduce empty receives
4. **Implement efficient status polling**: Use exponential backoff

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name async-api-patterns

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name async-api-patterns
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm the deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm the deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete in this order:

1. API Gateway REST API
2. Lambda functions
3. SQS queues (main and DLQ)
4. DynamoDB table
5. S3 bucket (empty first, then delete)
6. IAM roles and policies

## Troubleshooting

### Common Issues

1. **IAM permission errors**: Ensure AWS CLI is configured with appropriate permissions
2. **Resource name conflicts**: Change the project name if resources already exist
3. **Region-specific issues**: Ensure all resources are created in the same region
4. **Lambda timeout**: Jobs taking longer than 5 minutes will timeout

### Debugging Steps

1. **Check CloudWatch logs** for Lambda function errors
2. **Monitor SQS dead letter queue** for failed messages
3. **Verify IAM role permissions** if access denied errors occur
4. **Check API Gateway logs** for request/response issues

### Support Resources

- [AWS API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [AWS SQS Documentation](https://docs.aws.amazon.com/sqs/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS DynamoDB Documentation](https://docs.aws.amazon.com/dynamodb/)

## Extension Ideas

This implementation provides a foundation for more advanced patterns:

1. **Webhook notifications**: Add webhook support for job completion
2. **Job priorities**: Implement priority queues for different job types
3. **Batch processing**: Handle multiple jobs in a single Lambda invocation
4. **WebSocket integration**: Real-time status updates without polling
5. **Job scheduling**: Integration with EventBridge for delayed jobs

## License

This infrastructure code is provided as-is for educational and development purposes. Review and modify according to your organization's requirements before production use.