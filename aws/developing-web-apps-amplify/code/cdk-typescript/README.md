# Serverless Web Application CDK TypeScript

This CDK TypeScript application creates a complete serverless web application infrastructure using AWS Amplify, Lambda, API Gateway, Cognito, and DynamoDB. The application implements a Todo management system with user authentication and real-time data persistence.

## Architecture

The solution includes:

- **AWS Amplify**: Frontend hosting with CI/CD pipeline
- **Amazon Cognito**: User authentication and authorization
- **AWS Lambda**: Serverless API backend with TypeScript
- **Amazon API Gateway**: RESTful API with Cognito authorization
- **Amazon DynamoDB**: NoSQL database for todo storage
- **Amazon CloudWatch**: Monitoring and logging dashboard

## Prerequisites

- Node.js 18+ and npm
- AWS CLI v2 configured with appropriate permissions
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- TypeScript installed: `npm install -g typescript`

## Required AWS Permissions

Ensure your AWS credentials have permissions for:
- IAM role and policy management
- Lambda function management
- API Gateway management
- DynamoDB table management
- Cognito User Pool management
- Amplify app management
- CloudWatch dashboard management

## Getting Started

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Deploy the Infrastructure

```bash
# Review the resources that will be created
cdk diff

# Deploy the stack
cdk deploy
```

### 4. Configure Frontend Integration

After deployment, update your React frontend with the outputs:

```bash
# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ServerlessWebAppStack \
    --query 'Stacks[0].Outputs'
```

## Project Structure

```
├── app.ts                      # CDK application entry point
├── lib/
│   └── serverless-web-app-stack.ts  # Main stack definition
├── lambda/
│   └── todo-api.ts            # Lambda function for Todo API
├── package.json               # Dependencies and scripts
├── tsconfig.json             # TypeScript configuration
├── cdk.json                  # CDK configuration
└── README.md                 # This file
```

## Environment Variables

The Lambda function uses these environment variables (automatically configured by CDK):

- `TODO_TABLE_NAME`: DynamoDB table name for todos
- `USER_POOL_ID`: Cognito User Pool ID
- `CORS_ORIGIN`: Allowed CORS origin (configurable)
- `LOG_LEVEL`: Logging level (INFO, DEBUG, ERROR)
- `AWS_REGION`: AWS region

## API Endpoints

The API Gateway exposes these endpoints (all require Cognito authentication):

- `GET /todos` - Get all todos for the authenticated user
- `GET /todos/{id}` - Get a specific todo by ID
- `POST /todos` - Create a new todo
- `PUT /todos/{id}` - Update an existing todo
- `DELETE /todos/{id}` - Delete a todo

### Request/Response Examples

#### Create Todo (POST /todos)
```json
// Request
{
  "title": "Complete the CDK tutorial",
  "completed": false
}

// Response (201 Created)
{
  "id": "uuid-here",
  "title": "Complete the CDK tutorial",
  "completed": false,
  "createdAt": "2023-10-01T12:00:00.000Z",
  "updatedAt": "2023-10-01T12:00:00.000Z",
  "userId": "cognito-user-id"
}
```

#### Update Todo (PUT /todos/{id})
```json
// Request
{
  "title": "Complete the CDK tutorial - DONE!",
  "completed": true
}

// Response (200 OK)
{
  "id": "uuid-here",
  "title": "Complete the CDK tutorial - DONE!",
  "completed": true,
  "createdAt": "2023-10-01T12:00:00.000Z",
  "updatedAt": "2023-10-01T12:30:00.000Z",
  "userId": "cognito-user-id"
}
```

## Security Features

- **Authentication**: Cognito User Pools with JWT tokens
- **Authorization**: API Gateway Cognito authorizer
- **Data Isolation**: User-specific data access controls
- **CORS**: Configurable cross-origin resource sharing
- **Encryption**: DynamoDB encryption at rest
- **IAM**: Least privilege access policies

## Monitoring

The stack creates a CloudWatch dashboard with metrics for:

- Lambda function duration, errors, and invocations
- API Gateway latency and error rates
- DynamoDB latency and error metrics

Access the dashboard in the AWS Console under CloudWatch.

## Development

### Local Development

```bash
# Install dependencies
npm install

# Run tests
npm test

# Run tests in watch mode
npm run test:watch

# Build TypeScript
npm run build

# Watch for changes
npm run watch

# Lint code
npm run lint

# Fix linting issues
npm run lint:fix

# Format code
npm run format
```

### Testing the API

After deployment, you can test the API using the AWS CLI or curl:

```bash
# Get the API endpoint from stack outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name ServerlessWebAppStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Test with authentication (you'll need a valid JWT token)
curl -X GET "${API_ENDPOINT}todos" \
    -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## Customization

### Environment-Specific Configuration

You can customize the deployment using environment variables:

```bash
# Deploy to different environment
export ENVIRONMENT=production
cdk deploy

# Use custom table name
export TODO_TABLE_NAME=my-custom-todos
cdk deploy
```

### Stack Properties

Modify the stack instantiation in `app.ts` to customize:

```typescript
new ServerlessWebAppStack(app, 'ServerlessWebAppStack', {
  env: { account: '123456789012', region: 'us-west-2' },
  tableName: 'custom-todos',
  functionName: 'custom-api-function',
  appName: 'my-todo-app',
  enableMonitoring: true,
});
```

## Cost Optimization

- **DynamoDB**: Uses on-demand billing mode (pay per request)
- **Lambda**: Pay only for execution time and memory used
- **API Gateway**: Pay per API call
- **Cognito**: Free tier includes 50,000 MAUs
- **Amplify**: Pay for build minutes and data transfer

Estimated monthly cost for development: $5-15 depending on usage.

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
# Destroy all resources
cdk destroy

# Confirm deletion when prompted
```

**Note**: This will permanently delete all data in the DynamoDB table.

## Troubleshooting

### Common Issues

1. **Deployment Fails**: Ensure AWS credentials have sufficient permissions
2. **Lambda Function Errors**: Check CloudWatch logs for the Lambda function
3. **API Gateway 401 Errors**: Verify Cognito JWT token is valid and included in requests
4. **CORS Issues**: Check the CORS configuration in the Lambda function

### Debugging

Enable debug logging:

```bash
# Set log level to DEBUG
aws lambda update-function-configuration \
    --function-name YOUR_FUNCTION_NAME \
    --environment Variables="{LOG_LEVEL=DEBUG}"
```

### CloudWatch Logs

Access Lambda function logs:

```bash
# Get log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Tail logs
aws logs tail /aws/lambda/YOUR_FUNCTION_NAME --follow
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run tests and linting
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:

- Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
- Review [AWS Lambda best practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- Consult [API Gateway documentation](https://docs.aws.amazon.com/apigateway/)
- Open an issue in this repository