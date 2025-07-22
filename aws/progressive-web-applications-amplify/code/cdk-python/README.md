# Progressive Web Application with AWS Amplify - CDK Python

This directory contains the AWS CDK Python application for deploying a complete Progressive Web Application (PWA) infrastructure using AWS Amplify and related services.

## Architecture Overview

The CDK application deploys the following AWS services:

- **Amazon Cognito**: User authentication and authorization
- **AWS AppSync**: GraphQL API for real-time data operations
- **Amazon DynamoDB**: NoSQL database for task storage
- **Amazon S3**: Object storage for file attachments
- **AWS Lambda**: Custom resolver functions
- **AWS Amplify**: Frontend hosting and CI/CD
- **Amazon CloudWatch**: Monitoring and logging

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** configured with appropriate credentials
2. **Python 3.8+** installed
3. **Node.js 18+** and npm installed
4. **AWS CDK CLI** installed (`npm install -g aws-cdk`)
5. **Git** for version control

## Installation

1. **Clone the repository** or navigate to this directory:
   ```bash
   cd aws/progressive-web-applications-aws-amplify/code/cdk-python/
   ```

2. **Create a virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap
   ```

## Deployment

### Quick Start

Deploy with default settings:
```bash
cdk deploy
```

### Custom Configuration

Deploy with custom parameters:
```bash
cdk deploy \
  --parameters ProjectName=my-pwa \
  --parameters EnvironmentName=dev \
  --parameters EnableDeletionProtection=false
```

### Environment-Specific Deployment

Deploy to different environments:
```bash
# Development environment
cdk deploy ProgressiveWebAppStack-dev

# Staging environment
cdk deploy ProgressiveWebAppStack-staging \
  --parameters EnvironmentName=staging \
  --parameters EnableDeletionProtection=true

# Production environment
cdk deploy ProgressiveWebAppStack-prod \
  --parameters EnvironmentName=prod \
  --parameters EnableDeletionProtection=true
```

## Configuration

### Parameters

The CDK application accepts the following parameters:

| Parameter | Description | Default | Valid Values |
|-----------|-------------|---------|--------------|
| `ProjectName` | Name of the PWA project | `fullstack-pwa` | 3-50 characters, alphanumeric and hyphens |
| `EnvironmentName` | Environment name | `dev` | `dev`, `staging`, `prod` |
| `EnableDeletionProtection` | Enable deletion protection | `false` | `true`, `false` |

### Context Variables

Set context variables in `cdk.json` or via command line:
```bash
cdk deploy --context stackName=MyPWAStack --context environment=prod
```

## Stack Outputs

After deployment, the stack provides these outputs:

- **UserPoolId**: Cognito User Pool ID
- **UserPoolClientId**: Cognito User Pool Client ID
- **IdentityPoolId**: Cognito Identity Pool ID
- **GraphQLApiId**: AppSync GraphQL API ID
- **GraphQLApiUrl**: AppSync GraphQL API URL
- **TaskTableName**: DynamoDB table name
- **AttachmentsBucketName**: S3 bucket name
- **AmplifyAppId**: Amplify application ID
- **AmplifyAppUrl**: Amplify application URL

## Development

### Code Structure

```
cdk-python/
├── app.py                 # Main CDK application
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
├── schema.graphql        # GraphQL schema
├── README.md             # This file
└── tests/                # Test files
    └── test_stack.py     # Stack unit tests
```

### Testing

Run unit tests:
```bash
pytest tests/
```

Run tests with coverage:
```bash
pytest --cov=. tests/
```

### Code Quality

Format code with Black:
```bash
black .
```

Lint code with flake8:
```bash
flake8 .
```

Type checking with mypy:
```bash
mypy .
```

### CDK Commands

Common CDK commands:

```bash
# Show differences between deployed and current state
cdk diff

# List all stacks
cdk list

# Synthesize CloudFormation template
cdk synth

# Deploy stack
cdk deploy

# Destroy stack
cdk destroy

# Show stack outputs
aws cloudformation describe-stacks \
  --stack-name ProgressiveWebAppStack-dev \
  --query 'Stacks[0].Outputs'
```

## Security Considerations

### Authentication and Authorization

- **Cognito User Pool**: Manages user identities with configurable password policies
- **Identity Pool**: Provides temporary AWS credentials for authenticated users
- **IAM Roles**: Implement least-privilege access to AWS resources
- **AppSync Authorization**: Uses Cognito User Pool for GraphQL API security

### Data Protection

- **DynamoDB Encryption**: Tables encrypted at rest with AWS managed keys
- **S3 Encryption**: Bucket encrypted with S3 managed keys
- **API Security**: All GraphQL operations require authentication
- **CORS Configuration**: Properly configured for web application access

### Best Practices

1. **Use HTTPS**: All communications encrypted in transit
2. **Least Privilege**: IAM roles follow minimal permission principles
3. **Resource Isolation**: User data isolated using owner-based access patterns
4. **Monitoring**: CloudWatch logs enabled for all services
5. **Backup**: Point-in-time recovery enabled for DynamoDB

## Monitoring and Logging

### CloudWatch Integration

- **AppSync Logs**: Field-level logging for GraphQL operations
- **Lambda Logs**: Execution logs for resolver functions
- **DynamoDB Metrics**: Performance and usage metrics
- **S3 Access Logs**: Optional bucket access logging

### X-Ray Tracing

AppSync X-Ray tracing is enabled for performance monitoring and debugging.

## Cost Optimization

### Billing Mode

- **DynamoDB**: Pay-per-request billing mode for variable workloads
- **S3**: Lifecycle policies for cost-effective storage
- **Lambda**: Serverless pricing with automatic scaling
- **Cognito**: Free tier covers up to 50,000 MAUs

### Cost Monitoring

Set up billing alerts and cost budgets:
```bash
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json
```

## Troubleshooting

### Common Issues

1. **Bootstrap Required**: Run `cdk bootstrap` if you get toolkit errors
2. **Permissions**: Ensure your AWS credentials have sufficient permissions
3. **Resource Limits**: Check AWS service limits in your region
4. **Stack Updates**: Some updates may require resource replacement

### Debug Mode

Enable debug logging:
```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

### CloudFormation Events

Monitor deployment progress:
```bash
aws cloudformation describe-stack-events \
  --stack-name ProgressiveWebAppStack-dev
```

## Cleanup

To remove all resources:
```bash
cdk destroy
```

For production environments with deletion protection:
```bash
cdk destroy --parameters EnableDeletionProtection=false
```

## Support

For issues and questions:

1. Check the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
2. Review [AWS Amplify Documentation](https://docs.amplify.aws/)
3. Search [CDK GitHub Issues](https://github.com/aws/aws-cdk/issues)
4. Visit [AWS Developer Forums](https://forums.aws.amazon.com/)

## License

This project is licensed under the Apache License 2.0. See the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Changelog

### Version 1.0.0

- Initial release
- Complete PWA infrastructure with AWS Amplify
- Cognito authentication and authorization
- AppSync GraphQL API with real-time subscriptions
- DynamoDB storage with GSI indexes
- S3 file storage with lifecycle policies
- Lambda resolvers for custom business logic
- Comprehensive monitoring and logging