# CDK TypeScript Implementation - Serverless GraphQL APIs with AWS AppSync and EventBridge Scheduler

This directory contains a complete CDK TypeScript implementation for deploying a serverless task management system with GraphQL APIs using AWS AppSync and EventBridge Scheduler.

## Architecture Overview

This implementation creates:

- **AWS AppSync GraphQL API** - Fully managed GraphQL service with real-time subscriptions
- **DynamoDB Table** - Serverless NoSQL database for task storage with optimized access patterns
- **Lambda Function** - Serverless compute for task processing and business logic
- **EventBridge Scheduler** - Serverless scheduling service for automated task reminders
- **IAM Roles** - Least privilege security configurations for all services

## Project Structure

```
cdk-typescript/
├── app.ts                          # CDK application entry point
├── serverless-graphql-api-stack.ts # Main stack with all resources
├── package.json                    # Dependencies and scripts
├── tsconfig.json                   # TypeScript configuration
├── cdk.json                        # CDK configuration
└── README.md                       # This file
```

## Prerequisites

Before deploying this solution, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Node.js** (version 18 or later) and npm installed
3. **AWS CDK** CLI installed globally: `npm install -g aws-cdk`
4. **AWS Account** with permissions to create:
   - AppSync APIs
   - DynamoDB tables
   - Lambda functions
   - IAM roles and policies
   - EventBridge schedules
   - CloudWatch logs
5. **CDK Bootstrap** completed in your target AWS account/region

## Installation

1. **Install dependencies**:
   ```bash
   cd cdk-typescript/
   npm install
   ```

2. **Build the TypeScript code**:
   ```bash
   npm run build
   ```

3. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

## Deployment

### Quick Deploy

Deploy the entire stack with default settings:

```bash
cdk deploy
```

### Deploy with Custom Stack Name

```bash
cdk deploy --context stackName=MyTaskManagerAPI
```

### Deploy with Environment Context

```bash
cdk deploy --context environment=production
```

### Preview Changes Before Deployment

```bash
cdk diff
```

## Configuration Options

You can customize the deployment using CDK context parameters:

- `stackName`: Custom name for the CloudFormation stack (default: `ServerlessGraphQLApi`)
- `environment`: Environment tag for resources (default: `dev`)

Example with custom parameters:
```bash
cdk deploy \
  --context stackName=ProdTaskAPI \
  --context environment=production
```

## Stack Outputs

After successful deployment, the stack provides these outputs:

- **GraphQLAPIURL**: The AppSync GraphQL endpoint URL
- **GraphQLAPIID**: The AppSync API identifier
- **GraphQLAPIKey**: The API key for authentication (if configured)
- **TasksTableName**: The DynamoDB table name
- **TasksTableArn**: The DynamoDB table ARN
- **TaskProcessorFunctionName**: The Lambda function name
- **TaskProcessorFunctionArn**: The Lambda function ARN
- **Region**: The AWS region where resources are deployed

## GraphQL Schema

The API includes a complete task management schema with:

### Types
- `Task` - Core task entity with all properties
- `TaskStatus` - Enumeration for task states (PENDING, IN_PROGRESS, COMPLETED, CANCELLED)

### Inputs
- `CreateTaskInput` - Input for creating new tasks
- `UpdateTaskInput` - Input for updating existing tasks

### Operations
- **Queries**: `getTask`, `listUserTasks`
- **Mutations**: `createTask`, `updateTask`, `deleteTask`, `sendReminder`
- **Subscriptions**: `onTaskCreated`, `onTaskUpdated`, `onTaskDeleted`

## Security Configuration

The implementation follows AWS security best practices:

- **IAM Authentication** as the primary authorization mode
- **API Key** as an additional authorization mode for development
- **Least privilege** IAM roles for all services
- **Encryption at rest** for DynamoDB table
- **CloudWatch logging** enabled for all services
- **AWS X-Ray tracing** enabled for performance monitoring

## Cost Optimization Features

- **DynamoDB Pay-per-Request billing** - Only pay for actual usage
- **Lambda provisioned concurrency disabled** - Cost-optimized for variable workloads
- **AppSync caching disabled** - Reduces costs for development environments
- **CloudWatch log retention** set to 1 week to minimize storage costs

## Development Workflow

### Local Development

1. **Make changes** to the TypeScript code
2. **Build and validate**:
   ```bash
   npm run build
   npm run test  # Run tests if available
   ```

3. **Preview changes**:
   ```bash
   cdk diff
   ```

4. **Deploy updates**:
   ```bash
   cdk deploy
   ```

### Continuous Integration

This implementation is designed to work with CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Install dependencies
  run: cd cdk-typescript && npm ci

- name: Build TypeScript
  run: cd cdk-typescript && npm run build

- name: Run CDK diff
  run: cd cdk-typescript && cdk diff

- name: Deploy to staging
  run: cd cdk-typescript && cdk deploy --require-approval never
```

## Testing the API

After deployment, you can test the GraphQL API using:

### AWS AppSync Console
1. Navigate to the AppSync console
2. Select your API
3. Use the built-in query editor

### GraphQL Clients
Use the API URL from stack outputs with GraphQL clients like:
- Apollo Client
- Relay
- GraphQL Playground
- Postman

### Example Queries

```graphql
# Create a task
mutation CreateTask {
  createTask(input: {
    title: "Complete project documentation"
    description: "Write comprehensive docs"
    dueDate: "2024-12-31T23:59:59Z"
    reminderTime: "2024-12-31T09:00:00Z"
  }) {
    id
    title
    status
    createdAt
  }
}

# Get all tasks for a user
query ListUserTasks {
  listUserTasks(userId: "user123") {
    id
    title
    status
    dueDate
  }
}

# Subscribe to task updates
subscription OnTaskUpdated {
  onTaskUpdated(userId: "user123") {
    id
    title
    status
    updatedAt
  }
}
```

## Monitoring and Observability

The implementation includes comprehensive monitoring:

- **CloudWatch Logs** for all Lambda functions and AppSync
- **AWS X-Ray tracing** for performance analysis
- **DynamoDB metrics** for table performance
- **AppSync metrics** for API performance

Access monitoring through:
- AWS CloudWatch Console
- AWS X-Ray Console
- AppSync Console Monitoring tab

## Cleanup

To remove all resources and avoid ongoing costs:

```bash
cdk destroy
```

Confirm the deletion when prompted. This will remove:
- All AWS resources created by the stack
- CloudFormation stack
- CloudWatch logs (after retention period)

> **Warning**: This action is irreversible and will delete all data in the DynamoDB table.

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**
   ```
   Error: Need to perform AWS CDK bootstrap
   ```
   **Solution**: Run `cdk bootstrap` in your target account/region

2. **Insufficient Permissions**
   ```
   Error: User is not authorized to perform action
   ```
   **Solution**: Ensure your AWS credentials have necessary permissions

3. **Resource Naming Conflicts**
   ```
   Error: Resource already exists
   ```
   **Solution**: Use custom stack name or check for existing resources

4. **Lambda Function Timeout**
   ```
   Error: Task timed out after 60 seconds
   ```
   **Solution**: Check CloudWatch logs for the Lambda function

### Getting Help

For issues specific to this implementation:
1. Check CloudWatch logs for error details
2. Use `cdk diff` to see what changes would be made
3. Verify AWS permissions and resource limits
4. Refer to the original recipe documentation

## Advanced Customization

### Adding Custom Resolvers

To add custom GraphQL resolvers:

1. Create new resolver in the `configureDataSources()` method
2. Add corresponding schema fields
3. Redeploy the stack

### Integrating with Cognito

To add user authentication:

1. Create Cognito User Pool
2. Update AppSync authorization configuration
3. Modify resolver templates to use Cognito identity

### Adding More Data Sources

To integrate additional AWS services:

1. Create new data source in CDK stack
2. Add corresponding resolvers
3. Update IAM permissions as needed

## Best Practices

- **Environment Separation**: Use different stack names for dev/staging/prod
- **Resource Tagging**: Leverage the built-in tagging for cost tracking
- **Security**: Review IAM policies regularly and apply least privilege
- **Monitoring**: Set up CloudWatch alarms for critical metrics
- **Backup**: Enable point-in-time recovery for production DynamoDB tables
- **Documentation**: Keep GraphQL schema documentation updated

## Support

This CDK implementation is based on the AWS recipe for "Serverless GraphQL APIs with AppSync and Scheduler". For detailed explanations of the architecture and business use cases, refer to the original recipe documentation.

For AWS service-specific questions, consult the official AWS documentation:
- [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/)
- [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)