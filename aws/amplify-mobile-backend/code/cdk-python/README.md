# Mobile Backend Services CDK Python Application

This AWS CDK Python application deploys a complete mobile backend infrastructure using AWS Amplify-compatible services. The solution provides authentication, real-time GraphQL APIs, file storage, analytics, and push notifications for mobile applications.

## Architecture Overview

The CDK application creates the following AWS services:

- **Amazon Cognito**: User authentication and authorization
- **AWS AppSync**: GraphQL API with real-time subscriptions
- **Amazon DynamoDB**: NoSQL database for posts and user data
- **Amazon S3**: File storage for images and media
- **AWS Lambda**: Custom business logic processing
- **Amazon Pinpoint**: Analytics and push notifications
- **Amazon CloudWatch**: Monitoring and logging

## Prerequisites

### Software Requirements

- Python 3.8 or later
- AWS CLI v2 installed and configured
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Node.js 16.x or later (for CDK CLI)

### AWS Requirements

- AWS account with appropriate permissions
- AWS CLI configured with credentials
- Required IAM permissions for:
  - Cognito User Pools and Identity Pools
  - AppSync GraphQL APIs
  - DynamoDB tables
  - S3 buckets
  - Lambda functions
  - Pinpoint applications
  - CloudWatch dashboards
  - IAM roles and policies

### Estimated Costs

Development environment: $10-20/month
- DynamoDB: Pay-per-request pricing
- AppSync: $4 per million query/mutation operations
- Cognito: Free tier covers most development usage
- S3: Standard storage pricing
- Lambda: Pay-per-invocation
- Pinpoint: $1 per million push notifications

## Installation

1. **Clone the repository and navigate to the CDK directory**:
   ```bash
   cd aws/mobile-backend-services-amplify/code/cdk-python/
   ```

2. **Create and activate a Python virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install development dependencies (optional)**:
   ```bash
   pip install -e ".[dev]"
   ```

## Configuration

### Environment Variables

Set the following environment variables or update the `cdk.json` context:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
```

### CDK Context

Customize deployment by modifying the context in `cdk.json`:

```json
{
  "context": {
    "mobile-backend-amplify": {
      "environment": "development",
      "region": "us-east-1"
    },
    "feature-flags": {
      "enable-advanced-auth": true,
      "enable-push-notifications": true,
      "enable-analytics": true
    }
  }
}
```

## Deployment

### Bootstrap CDK (First-time only)

```bash
cdk bootstrap
```

### Deploy the Stack

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the infrastructure
cdk deploy

# Deploy with approval for IAM changes
cdk deploy --require-approval never
```

### Verify Deployment

After deployment, the CDK will output important resource information:

```bash
Outputs:
MobileBackendStack.UserPoolId = us-east-1_ABC123DEF
MobileBackendStack.GraphQLAPIURL = https://xyz.appsync-api.us-east-1.amazonaws.com/graphql
MobileBackendStack.StorageBucketName = mobilebackendstack-user-files-123456789012
```

## Usage

### Mobile App Integration

1. **Configure Amplify in your mobile app**:
   ```javascript
   import { Amplify } from 'aws-amplify';
   
   const config = {
     Auth: {
       region: 'us-east-1',
       userPoolId: 'us-east-1_ABC123DEF',
       userPoolWebClientId: 'client-id-from-output'
     },
     API: {
       GraphQL: {
         endpoint: 'https://xyz.appsync-api.us-east-1.amazonaws.com/graphql',
         region: 'us-east-1',
         defaultAuthMode: 'userPool'
       }
     },
     Storage: {
       S3: {
         bucket: 'bucket-name-from-output',
         region: 'us-east-1'
       }
     }
   };
   
   Amplify.configure(config);
   ```

2. **Use Amplify libraries for authentication**:
   ```javascript
   import { Auth } from 'aws-amplify';
   
   // Sign up
   await Auth.signUp({
     username: 'user@example.com',
     password: 'SecurePassword123!',
     attributes: {
       email: 'user@example.com',
       given_name: 'John',
       family_name: 'Doe'
     }
   });
   
   // Sign in
   await Auth.signIn('user@example.com', 'SecurePassword123!');
   ```

3. **Use GraphQL API for data operations**:
   ```javascript
   import { API } from 'aws-amplify';
   
   // Create a post
   const createPost = `
     mutation CreatePost($input: CreatePostInput!) {
       createPost(input: $input) {
         id
         title
         content
         authorId
         createdAt
       }
     }
   `;
   
   const newPost = await API.graphql({
     query: createPost,
     variables: {
       input: {
         title: 'My First Post',
         content: 'Hello, mobile world!',
         authorId: 'user-id'
       }
     }
   });
   ```

### Testing the API

1. **Test authentication**:
   ```bash
   # Get User Pool ID from stack outputs
   aws cognito-idp list-users --user-pool-id us-east-1_ABC123DEF
   ```

2. **Test GraphQL API**:
   ```bash
   # Use the AWS AppSync console or GraphQL playground
   # Navigate to: https://console.aws.amazon.com/appsync/
   ```

3. **Test Lambda function**:
   ```bash
   aws lambda invoke \
     --function-name MobileBackendStack-PostProcessorFunction \
     --payload '{"action": "healthCheck"}' \
     response.json
   ```

## Monitoring

### CloudWatch Dashboard

The deployment creates a CloudWatch dashboard for monitoring:

- AppSync API metrics (requests, errors, latency)
- DynamoDB metrics (read/write capacity, latency)
- Lambda function metrics (invocations, errors, duration)
- Cognito authentication metrics

### Log Groups

Monitor application logs in CloudWatch:

- `/aws/lambda/MobileBackendStack-PostProcessorFunction`
- `/aws/appsync/apis/{api-id}`
- Cognito authentication logs

### Alarms (Optional)

Add CloudWatch alarms for production monitoring:

```python
# Add to the stack
error_alarm = cloudwatch.Alarm(
    self, "APIErrorAlarm",
    metric=self.graphql_api.metric_4xx_error(),
    threshold=10,
    evaluation_periods=2
)
```

## Customization

### Adding New Features

1. **Add new GraphQL types**:
   - Update `schema.graphql`
   - Add corresponding resolvers in `app.py`

2. **Extend Lambda function**:
   - Modify the Lambda code in `_create_lambda_function()`
   - Add new business logic handlers

3. **Configure social login**:
   - Update Cognito User Pool configuration
   - Add identity providers (Google, Facebook, Apple)

### Environment-Specific Deployments

1. **Create environment-specific contexts**:
   ```json
   {
     "environments": {
       "development": {
         "account": "123456789012",
         "region": "us-east-1"
       },
       "production": {
         "account": "987654321098",
         "region": "us-west-2"
       }
     }
   }
   ```

2. **Deploy to specific environment**:
   ```bash
   cdk deploy --context environment=production
   ```

## Security Considerations

### Authentication & Authorization

- Cognito User Pool provides secure authentication
- AppSync uses Cognito for API authorization
- IAM roles follow least privilege principle
- All API operations require authentication

### Data Protection

- DynamoDB encryption at rest (AWS managed)
- S3 bucket encryption (S3 managed)
- SSL/TLS for data in transit
- CORS configured for mobile app domains

### Network Security

- S3 bucket blocks public access
- AppSync API requires authentication
- VPC endpoints can be added for private connectivity

## Troubleshooting

### Common Issues

1. **CDK deployment fails**:
   ```bash
   # Check CDK version
   cdk --version
   
   # Update CDK
   npm update -g aws-cdk
   
   # Clear CDK cache
   cdk context --clear
   ```

2. **GraphQL schema errors**:
   ```bash
   # Validate schema syntax
   # Use GraphQL schema validation tools
   ```

3. **Lambda function errors**:
   ```bash
   # Check CloudWatch logs
   aws logs tail /aws/lambda/MobileBackendStack-PostProcessorFunction --follow
   ```

4. **Authentication issues**:
   ```bash
   # Verify User Pool configuration
   aws cognito-idp describe-user-pool --user-pool-id us-east-1_ABC123DEF
   ```

### Getting Help

- AWS CDK Documentation: https://docs.aws.amazon.com/cdk/
- AWS Amplify Documentation: https://docs.amplify.aws/
- AWS AppSync Documentation: https://docs.aws.amazon.com/appsync/
- GitHub Issues: https://github.com/aws/aws-cdk/issues

## Cleanup

### Remove All Resources

```bash
# Delete the CDK stack
cdk destroy

# Confirm deletion when prompted
```

### Manual Cleanup (if needed)

Some resources may require manual deletion:

1. **S3 bucket contents**:
   ```bash
   aws s3 rm s3://bucket-name --recursive
   ```

2. **CloudWatch logs**:
   ```bash
   aws logs delete-log-group --log-group-name /aws/lambda/function-name
   ```

## Development

### Code Style

This project uses Python code formatting tools:

```bash
# Format code
black .

# Sort imports
isort .

# Lint code
flake8 .

# Type checking
mypy .
```

### Testing

```bash
# Run tests
pytest

# Run tests with coverage
pytest --cov=.
```

### Security Scanning

```bash
# Check for security vulnerabilities
safety check

# Security linting
bandit -r .
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and add tests
4. Run code quality checks
5. Submit a pull request

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Support

For support with this CDK application:

1. Check the troubleshooting section
2. Review AWS documentation
3. Open an issue in the GitHub repository
4. Contact the AWS support team

---

*This CDK application is part of the AWS Cloud Recipes collection, providing production-ready infrastructure patterns for common use cases.*