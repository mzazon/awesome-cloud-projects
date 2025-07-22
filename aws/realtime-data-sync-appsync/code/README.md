# Infrastructure as Code for Real-Time Data Synchronization with AppSync

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Data Synchronization with AppSync".

## Overview

This solution implements a serverless real-time data synchronization architecture using AWS AppSync GraphQL subscriptions and DynamoDB Streams. The infrastructure creates a scalable, event-driven system that automatically pushes data changes to connected clients through WebSocket connections, eliminating the need for polling-based approaches.

## Architecture Components

- **AWS AppSync GraphQL API**: Managed GraphQL service with real-time subscriptions
- **DynamoDB Table**: NoSQL database with streams enabled for change data capture
- **Lambda Function**: Serverless compute for processing stream events
- **IAM Roles**: Secure access control for service interactions
- **CloudWatch Logs**: Monitoring and logging for observability

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript
- **CDK Python**: AWS Cloud Development Kit with Python
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for AppSync, DynamoDB, Lambda, CloudWatch, and IAM
- Basic understanding of GraphQL concepts (queries, mutations, subscriptions)
- Familiarity with DynamoDB and serverless architectures

### Required IAM Permissions

Ensure your AWS credentials have the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "appsync:*",
        "dynamodb:*",
        "lambda:*",
        "iam:*",
        "logs:*",
        "secretsmanager:GetRandomPassword"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### Using CloudFormation

```bash
# Set deployment parameters
export AWS_REGION=$(aws configure get region)
export STACK_NAME="appsync-realtime-sync"

# Generate unique suffix for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

# Deploy the stack
aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=ResourceSuffix,ParameterValue=${RANDOM_SUFFIX} \
        ParameterKey=ProjectName,ParameterValue=AppSyncRealTimeSync \
    --capabilities CAPABILITY_IAM
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
npx cdk deploy --require-approval never
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --require-approval never
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for configuration and deploy all resources
```

## Configuration

### Environment Variables

The following environment variables can be set to customize the deployment:

- `AWS_REGION`: AWS region for deployment (default: configured region)
- `RESOURCE_SUFFIX`: Unique suffix for resource names
- `PROJECT_NAME`: Project name for resource tagging (default: AppSyncRealTimeSync)

### Customizable Parameters

- **DynamoDB Table Name**: Name of the DynamoDB table for data storage
- **Lambda Function Name**: Name of the Lambda function for stream processing
- **AppSync API Name**: Name of the AppSync GraphQL API
- **Billing Mode**: DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)
- **Stream View Type**: DynamoDB stream view type (NEW_AND_OLD_IMAGES recommended)

## Testing the Deployment

### Verify Infrastructure

1. **Check DynamoDB Table**:
   ```bash
   aws dynamodb describe-table --table-name RealTimeData-${RANDOM_SUFFIX} \
       --query 'Table.{Status:TableStatus,StreamEnabled:StreamSpecification.StreamEnabled}'
   ```

2. **Verify AppSync API**:
   ```bash
   aws appsync list-graphql-apis --query 'graphqlApis[?name==`RealTimeSyncAPI-${RANDOM_SUFFIX}`]'
   ```

3. **Test Lambda Function**:
   ```bash
   aws lambda invoke \
       --function-name AppSyncNotifier-${RANDOM_SUFFIX} \
       --payload '{"Records":[{"eventName":"INSERT","dynamodb":{"NewImage":{"id":{"S":"test-123"}}}}]}' \
       response.json
   ```

### Test GraphQL Operations

1. **Get API Details**:
   ```bash
   APPSYNC_API_ID=$(aws appsync list-graphql-apis \
       --query 'graphqlApis[?name==`RealTimeSyncAPI-${RANDOM_SUFFIX}`].apiId' \
       --output text)
   
   APPSYNC_API_URL=$(aws appsync get-graphql-api \
       --api-id ${APPSYNC_API_ID} \
       --query 'graphqlApi.uris.GRAPHQL' --output text)
   
   APPSYNC_API_KEY=$(aws appsync list-api-keys \
       --api-id ${APPSYNC_API_ID} \
       --query 'apiKeys[0].id' --output text)
   ```

2. **Test Mutation**:
   ```bash
   curl -X POST \
       -H "Content-Type: application/json" \
       -H "x-api-key: ${APPSYNC_API_KEY}" \
       -d '{
         "query": "mutation CreateItem($input: CreateDataItemInput!) { createDataItem(input: $input) { id title content timestamp version } }",
         "variables": {
           "input": {
             "title": "Test Item",
             "content": "Testing real-time sync"
           }
         }
       }' \
       ${APPSYNC_API_URL}
   ```

## Monitoring and Observability

### CloudWatch Metrics

Monitor the following key metrics:

- **AppSync Metrics**:
  - `4XXError`: Client errors
  - `5XXError`: Server errors
  - `Latency`: Request latency
  - `ConnectedSubscriptions`: Active WebSocket connections

- **DynamoDB Metrics**:
  - `ConsumedReadCapacityUnits`: Read capacity consumption
  - `ConsumedWriteCapacityUnits`: Write capacity consumption
  - `StreamRecords`: Records processed by streams

- **Lambda Metrics**:
  - `Invocations`: Function invocation count
  - `Errors`: Function errors
  - `Duration`: Function execution time

### CloudWatch Alarms

Set up alarms for:

```bash
# High error rate alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "AppSync-HighErrorRate" \
    --alarm-description "AppSync 4XX/5XX error rate is high" \
    --metric-name "4XXError" \
    --namespace "AWS/AppSync" \
    --statistic "Sum" \
    --period 300 \
    --threshold 10 \
    --comparison-operator "GreaterThanThreshold"

# Lambda function errors
aws cloudwatch put-metric-alarm \
    --alarm-name "Lambda-ProcessingErrors" \
    --alarm-description "Lambda function processing errors" \
    --metric-name "Errors" \
    --namespace "AWS/Lambda" \
    --statistic "Sum" \
    --period 300 \
    --threshold 5 \
    --comparison-operator "GreaterThanThreshold"
```

## Cost Optimization

### Estimated Monthly Costs

For a moderate usage scenario (1,000 mutations/day, 10 connected clients):

- **AppSync**: ~$1-3/month (operations + subscriptions)
- **DynamoDB**: ~$1-2/month (on-demand pricing)
- **Lambda**: ~$0.10-0.20/month (minimal processing)
- **CloudWatch**: ~$0.50/month (logs and metrics)

**Total Estimated Cost**: $2.60-5.70/month

### Cost Optimization Tips

1. **Use DynamoDB On-Demand**: Pay only for actual usage
2. **Optimize Lambda Memory**: Right-size memory allocation
3. **Monitor AppSync Subscriptions**: Track connection counts
4. **Set CloudWatch Log Retention**: Avoid indefinite log storage
5. **Use API Key Expiration**: Implement automatic key rotation

## Security Considerations

### IAM Best Practices

- Use principle of least privilege for all IAM roles
- Implement resource-based policies where possible
- Enable AWS CloudTrail for API audit logging
- Use AWS IAM Access Analyzer for policy validation

### AppSync Security

- Implement proper authentication (API Key, Cognito, IAM)
- Use field-level authorization for sensitive data
- Enable request/response logging for debugging
- Implement rate limiting to prevent abuse

### DynamoDB Security

- Enable encryption at rest and in transit
- Use VPC endpoints for private connectivity
- Implement fine-grained access control
- Enable point-in-time recovery for data protection

## Troubleshooting

### Common Issues

1. **Schema Deployment Failures**:
   - Check GraphQL schema syntax
   - Verify resolver template syntax
   - Ensure proper field type definitions

2. **Lambda Function Timeouts**:
   - Increase timeout configuration
   - Optimize processing logic
   - Check DynamoDB stream batch size

3. **AppSync Connection Issues**:
   - Verify API key validity
   - Check authentication configuration
   - Monitor connection limits

4. **DynamoDB Stream Processing Delays**:
   - Check Lambda concurrency limits
   - Verify stream configuration
   - Monitor error rates

### Debugging Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/AppSyncNotifier"

# View AppSync API logs
aws logs describe-log-groups --log-group-name-prefix "/aws/appsync/apis"

# Check DynamoDB table metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedReadCapacityUnits \
    --dimensions Name=TableName,Value=RealTimeData-${RANDOM_SUFFIX} \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Average
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name ${STACK_NAME}

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy --force
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Advanced Configuration

### Multi-Environment Setup

Configure different environments using parameter files:

```bash
# Deploy to development environment
aws cloudformation create-stack \
    --stack-name appsync-realtime-dev \
    --template-body file://cloudformation.yaml \
    --parameters file://parameters-dev.json

# Deploy to production environment
aws cloudformation create-stack \
    --stack-name appsync-realtime-prod \
    --template-body file://cloudformation.yaml \
    --parameters file://parameters-prod.json
```

### Custom Domain Configuration

Add custom domain support to AppSync:

```bash
# Create custom domain
aws appsync create-domain-name \
    --domain-name api.example.com \
    --certificate-arn arn:aws:acm:region:account:certificate/cert-id

# Associate with API
aws appsync associate-api \
    --domain-name api.example.com \
    --api-id ${APPSYNC_API_ID}
```

### VPC Integration

For enhanced security, integrate Lambda with VPC:

```yaml
# Add to CloudFormation template
VpcConfig:
  SubnetIds:
    - subnet-12345678
    - subnet-87654321
  SecurityGroupIds:
    - sg-12345678
```

## Performance Optimization

### Lambda Optimization

- Use provisioned concurrency for consistent performance
- Implement connection pooling for external services
- Optimize payload size and processing logic
- Use appropriate memory allocation

### DynamoDB Optimization

- Design efficient partition keys
- Use Global Secondary Indexes (GSI) strategically
- Implement proper error handling and retries
- Monitor hot partitions and throttling

### AppSync Optimization

- Implement efficient resolver templates
- Use caching for frequently accessed data
- Optimize subscription filtering
- Monitor connection patterns

## Support

For issues with this infrastructure code:

1. Check the [AWS AppSync Documentation](https://docs.aws.amazon.com/appsync/)
2. Review the [DynamoDB Streams Documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Streams.html)
3. Consult the [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
4. Visit the [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
5. Check the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)

## License

This infrastructure code is provided under the MIT License. See the original recipe documentation for complete terms and conditions.

## Contributing

When contributing to this infrastructure code:

1. Follow AWS Well-Architected Framework principles
2. Implement proper error handling and logging
3. Include comprehensive documentation
4. Test across multiple environments
5. Follow security best practices
6. Maintain compatibility with all IaC implementations