# Infrastructure as Code for Serverless GraphQL APIs with AppSync and Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless GraphQL APIs with AppSync and Scheduler".

## Overview

This infrastructure creates a complete serverless task management system using AWS AppSync for GraphQL APIs, EventBridge Scheduler for automated reminders, DynamoDB for data storage, and Lambda for task processing. The solution provides real-time updates via WebSocket subscriptions and scheduled automation without managing any infrastructure.

## Architecture

The solution deploys:

- **AWS AppSync**: Managed GraphQL API with real-time subscriptions
- **DynamoDB**: Serverless NoSQL database for task storage
- **Lambda**: Function for processing scheduled task reminders
- **EventBridge Scheduler**: Serverless scheduling service for automated reminders
- **IAM Roles**: Security roles for service-to-service communication
- **GraphQL Schema**: Complete CRUD operations with real-time subscriptions

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AppSync (CreateGraphqlApi, UpdateGraphqlApi, DeleteGraphqlApi)
  - DynamoDB (CreateTable, DeleteTable, DescribeTable)
  - Lambda (CreateFunction, UpdateFunction, DeleteFunction)
  - EventBridge Scheduler (CreateSchedule, DeleteSchedule)
  - IAM (CreateRole, AttachRolePolicy, DeleteRole)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Cost Estimation

Estimated monthly costs for light usage:
- AWS AppSync: ~$4 per million requests
- DynamoDB: Pay-per-request pricing (~$1.25 per million reads/writes)
- Lambda: Free tier covers most usage (1M requests/month)
- EventBridge Scheduler: $1.00 per million invocations
- **Total estimated cost**: $5-10/month for development workloads

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name appsync-eventbridge-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name appsync-eventbridge-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name appsync-eventbridge-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
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

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for confirmation and show progress
```

## Configuration

### Environment Variables

All implementations support these configuration options:

- `PROJECT_NAME`: Name prefix for all resources (default: "TaskManager")
- `ENVIRONMENT`: Environment name (dev/staging/prod)
- `AWS_REGION`: AWS region for deployment
- `TABLE_BILLING_MODE`: DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)
- `LAMBDA_MEMORY_SIZE`: Lambda function memory allocation (default: 256MB)
- `LAMBDA_TIMEOUT`: Lambda function timeout (default: 60 seconds)

### GraphQL Schema Customization

The GraphQL schema can be customized by modifying the schema files in each implementation. The schema includes:

- Task CRUD operations (Create, Read, Update, Delete)
- Real-time subscriptions for task changes
- Task status management (PENDING, IN_PROGRESS, COMPLETED, CANCELLED)
- User-based task filtering

### Security Configuration

The infrastructure implements security best practices:

- IAM roles with least privilege permissions
- DynamoDB encryption at rest (enabled by default)
- AppSync with AWS IAM authorization
- Lambda function with minimal permissions
- EventBridge Scheduler with secure role assumption

## Testing the Deployment

After deployment, test the GraphQL API:

```bash
# Get the GraphQL endpoint from outputs
GRAPHQL_URL=$(aws cloudformation describe-stacks \
    --stack-name appsync-eventbridge-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`GraphQLApiUrl`].OutputValue' \
    --output text)

# Test the API with a simple query
curl -X POST "${GRAPHQL_URL}" \
    -H "Content-Type: application/json" \
    -H "Authorization: AWS4-HMAC-SHA256 ..." \
    --data '{"query":"{ __typename }"}'
```

## Real-time Subscriptions

To test WebSocket subscriptions:

1. Connect to the subscription endpoint (provided in outputs)
2. Subscribe to task updates:
   ```graphql
   subscription {
     onTaskCreated(userId: "user123") {
       id
       title
       status
       createdAt
     }
   }
   ```
3. Create tasks via mutations to see real-time updates

## Scheduled Reminders

The EventBridge Scheduler integration allows for:

- Automatic task reminders at specified times
- Scheduled task status updates
- Recurring reminder schedules
- Integration with external notification systems

Example schedule creation:

```bash
# Create a reminder schedule
aws scheduler create-schedule \
    --name "task-reminder-123" \
    --schedule-expression "at(2024-12-31T09:00:00)" \
    --target '{
        "Arn": "'${GRAPHQL_API_ARN}'",
        "RoleArn": "'${SCHEDULER_ROLE_ARN}'",
        "AppSyncParameters": {
            "GraphqlOperation": "{\"query\": \"mutation { sendReminder(taskId: \\\"123\\\") { id } }\"}"
        }
    }' \
    --flexible-time-window '{"Mode": "OFF"}'
```

## Monitoring and Observability

The infrastructure includes CloudWatch integration for monitoring:

- AppSync request metrics and error rates
- DynamoDB read/write capacity and throttling
- Lambda function duration and error rates
- EventBridge Scheduler execution success/failure

Enable detailed monitoring:

```bash
# Enable AppSync logging (if not already enabled)
aws logs create-log-group --log-group-name /aws/appsync/apis/${API_ID}
```

## Troubleshooting

### Common Issues

1. **Schema deployment fails**: Ensure GraphQL schema is valid and all types are properly defined
2. **IAM permission errors**: Verify all required permissions are attached to service roles
3. **DynamoDB access denied**: Check that AppSync role has proper DynamoDB permissions
4. **EventBridge scheduling fails**: Verify scheduler role can invoke AppSync mutations

### Debug Commands

```bash
# Check AppSync API status
aws appsync get-graphql-api --api-id ${API_ID}

# Verify DynamoDB table
aws dynamodb describe-table --table-name ${TABLE_NAME}

# Check Lambda function logs
aws logs tail /aws/lambda/${FUNCTION_NAME} --follow

# List EventBridge schedules
aws scheduler list-schedules
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name appsync-eventbridge-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name appsync-eventbridge-stack
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deletion
```

## Customization

### Adding New GraphQL Operations

1. Update the GraphQL schema file in your chosen implementation
2. Add corresponding resolvers for new operations
3. Update IAM permissions if accessing new resources
4. Redeploy the infrastructure

### Extending Task Management Features

- Add task categories and tags
- Implement task dependencies and subtasks
- Add file attachments using S3 integration
- Implement team collaboration features
- Add advanced search and filtering

### Integration with Other Services

- **Amazon SNS**: Add email/SMS notifications for reminders
- **Amazon SES**: Send detailed email reports
- **Amazon Cognito**: Implement user authentication and authorization
- **AWS X-Ray**: Add distributed tracing for performance monitoring

## Performance Optimization

- Enable AppSync caching for frequently accessed data
- Use DynamoDB Global Secondary Indexes for efficient queries
- Implement GraphQL query complexity analysis
- Configure Lambda reserved concurrency for predictable performance
- Use AppSync pipeline resolvers for complex operations

## Security Best Practices

- Enable AWS CloudTrail for API audit logging
- Implement field-level authorization in GraphQL resolvers
- Use AWS Secrets Manager for sensitive configuration
- Enable VPC endpoints for private network access
- Implement rate limiting and request validation

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service documentation:
   - [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/)
   - [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/)
   - [DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/)
3. Refer to the original recipe documentation
4. Check AWS service status page for any ongoing issues

## Contributing

To improve this infrastructure code:

1. Follow AWS best practices and security guidelines
2. Test changes in a development environment
3. Update documentation for any new features
4. Ensure backward compatibility when possible