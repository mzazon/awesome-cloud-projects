# CDK TypeScript Implementation for Progressive Web Applications with AWS Amplify

This directory contains the AWS CDK TypeScript implementation for building a comprehensive Progressive Web Application (PWA) using AWS Amplify, Cognito, AppSync, and related services.

## Architecture Overview

This CDK application creates a complete serverless architecture for a Progressive Web App with the following components:

- **Amazon Cognito**: User authentication and authorization with User Pool and Identity Pool
- **AWS AppSync**: GraphQL API with real-time subscriptions and offline sync capabilities
- **Amazon DynamoDB**: Scalable NoSQL database for task data storage
- **Amazon S3**: Object storage for file uploads and static assets
- **Amazon CloudFront**: Global content delivery network
- **AWS Amplify**: Hosting platform with CI/CD pipeline
- **AWS IAM**: Fine-grained access control and security policies

## Features

### Progressive Web App Capabilities
- **Offline-first architecture** with automatic data synchronization
- **Real-time updates** across all connected devices
- **Push notifications** support
- **App-like experience** with service worker caching
- **Responsive design** for all screen sizes

### Authentication & Security
- **Secure user authentication** with Amazon Cognito
- **Multi-factor authentication** (optional)
- **OAuth 2.0 and OpenID Connect** support
- **Fine-grained authorization** with IAM policies
- **Data encryption** at rest and in transit

### Real-time Features
- **GraphQL subscriptions** for live updates
- **Conflict resolution** for offline synchronization
- **Collaborative editing** capabilities
- **Event-driven architecture** with DynamoDB Streams

### Scalability & Performance
- **Serverless architecture** with automatic scaling
- **Global content delivery** with CloudFront
- **Pay-per-use pricing** model
- **High availability** across multiple regions

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured
   ```bash
   aws --version
   aws configure
   ```

2. **Node.js** version 18 or higher
   ```bash
   node --version
   npm --version
   ```

3. **AWS CDK** installed globally
   ```bash
   npm install -g aws-cdk
   cdk --version
   ```

4. **TypeScript** installed globally
   ```bash
   npm install -g typescript
   tsc --version
   ```

5. **AWS Account** with appropriate permissions for:
   - Amazon Cognito
   - AWS AppSync
   - Amazon DynamoDB
   - Amazon S3
   - Amazon CloudFront
   - AWS Amplify
   - AWS IAM

## Getting Started

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (First Time Only)

If this is your first time using CDK in this AWS account and region:

```bash
cdk bootstrap
```

### 3. Configure Environment Variables

Set the following environment variables or use CDK context:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export APP_NAME="my-pwa-app"
export ENVIRONMENT="dev"
```

### 4. Synthesize CloudFormation Template

```bash
cdk synth
```

### 5. Deploy the Stack

```bash
cdk deploy
```

The deployment will create all necessary AWS resources and output important configuration values.

## Configuration Options

### Application Settings

You can customize the application using CDK context values:

```bash
# Set application name
cdk deploy -c appName=my-custom-app

# Set environment
cdk deploy -c environment=production

# Enable custom domain
cdk deploy -c enableCustomDomain=true -c customDomainName=my-app.example.com

# Enable MFA
cdk deploy -c enableMFA=true

# Enable analytics
cdk deploy -c enableAnalytics=true
```

### Password Policy

The Cognito User Pool password policy can be customized by modifying the `passwordPolicy` configuration in the stack:

```typescript
passwordPolicy: {
  minLength: 8,
  requireUppercase: true,
  requireLowercase: true,
  requireNumbers: true,
  requireSymbols: true,
}
```

## Architecture Components

### Authentication Flow

1. **User Registration/Login**: Users authenticate through Cognito User Pool
2. **Token Exchange**: Cognito provides JWT tokens for API access
3. **Identity Pool**: Temporary AWS credentials for direct service access
4. **Authorization**: Fine-grained permissions through IAM policies

### Data Flow

1. **Client Operations**: React app makes GraphQL operations
2. **AppSync Processing**: GraphQL API processes requests
3. **Data Storage**: DynamoDB stores task data
4. **Real-time Updates**: Subscriptions push updates to all clients
5. **Offline Support**: DataStore caches data locally

### File Storage

1. **Upload Request**: Client requests signed upload URL
2. **Direct Upload**: Files uploaded directly to S3
3. **CDN Distribution**: CloudFront serves files globally
4. **Access Control**: IAM policies ensure proper access

## GraphQL Schema

The application uses a comprehensive GraphQL schema with the following key types:

- **Task**: Core data model with fields for title, description, priority, status, etc.
- **UserProfile**: User information and preferences
- **TaskAnalytics**: Productivity metrics and reporting
- **FileUpload**: File attachment management
- **Notification**: Real-time notifications

### Key Operations

```graphql
# Query tasks
query ListTasks {
  listTasks {
    items {
      id
      title
      completed
      priority
      createdAt
    }
  }
}

# Create task
mutation CreateTask($input: CreateTaskInput!) {
  createTask(input: $input) {
    id
    title
    completed
    priority
  }
}

# Subscribe to task updates
subscription OnTaskUpdated {
  onTaskUpdated {
    id
    title
    completed
    priority
  }
}
```

## Deployment Environments

### Development Environment

```bash
cdk deploy -c environment=dev
```

- Basic monitoring and logging
- Development-friendly configurations
- Cost-optimized settings

### Production Environment

```bash
cdk deploy -c environment=prod
```

- Enhanced monitoring and alerting
- Production-grade security settings
- High availability configurations
- Backup and disaster recovery

## Monitoring and Logging

### CloudWatch Integration

- **API Metrics**: AppSync API performance and error rates
- **Database Metrics**: DynamoDB read/write capacity and throttling
- **Storage Metrics**: S3 request counts and data transfer
- **CDN Metrics**: CloudFront cache hit rates and latency

### X-Ray Tracing

- End-to-end request tracing
- Performance bottleneck identification
- Error root cause analysis

### Custom Metrics

- User engagement metrics
- Task completion rates
- Application performance indicators

## Security Considerations

### Data Protection

- **Encryption at Rest**: All data encrypted in DynamoDB and S3
- **Encryption in Transit**: TLS 1.2+ for all communications
- **Field-level Encryption**: Sensitive data encrypted at application level

### Access Control

- **Principle of Least Privilege**: Minimal required permissions
- **Resource-based Policies**: S3 bucket policies for fine-grained access
- **User-based Isolation**: Data scoped to authenticated users

### Compliance

- **SOC 2 Type II**: AWS services compliance
- **GDPR Ready**: Data portability and deletion capabilities
- **HIPAA Eligible**: Services support healthcare workloads

## Cost Optimization

### Serverless Benefits

- **Pay-per-use**: Only pay for actual usage
- **Automatic Scaling**: No over-provisioning required
- **No Server Management**: Reduced operational overhead

### Cost Monitoring

- **AWS Cost Explorer**: Track spending by service
- **Budgets and Alerts**: Proactive cost management
- **Reserved Capacity**: DynamoDB reserved capacity for predictable workloads

### Optimization Strategies

- **DynamoDB On-Demand**: Automatic scaling based on demand
- **S3 Intelligent Tiering**: Automatic cost optimization
- **CloudFront Caching**: Reduced origin requests

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   - Verify Cognito User Pool configuration
   - Check IAM policies and permissions
   - Validate JWT tokens

2. **GraphQL Errors**
   - Check AppSync logs in CloudWatch
   - Verify schema and resolver configurations
   - Test queries in AppSync console

3. **Offline Sync Issues**
   - Verify DataStore configuration
   - Check network connectivity
   - Review conflict resolution settings

### Debugging Tools

- **AWS X-Ray**: Distributed tracing and performance analysis
- **CloudWatch Logs**: Detailed application logs
- **AppSync Console**: GraphQL query testing and debugging

## Testing

### Unit Tests

```bash
npm test
```

### Integration Tests

```bash
npm run test:integration
```

### End-to-End Tests

```bash
npm run test:e2e
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
cdk destroy
```

**Warning**: This will delete all resources including data in DynamoDB and S3. Ensure you have backups if needed.

## Advanced Features

### Custom Domains

Configure custom domains for both the Amplify app and API:

```typescript
// Enable custom domain in stack configuration
enableCustomDomain: true,
customDomainName: 'my-app.example.com'
```

### Multi-region Deployment

Deploy to multiple regions for global availability:

```bash
# Deploy to us-east-1
cdk deploy -c region=us-east-1

# Deploy to eu-west-1
cdk deploy -c region=eu-west-1
```

### CI/CD Pipeline

The Amplify app includes automatic CI/CD capabilities:

- **Source Control**: Connect to GitHub, GitLab, or CodeCommit
- **Build Process**: Automatic builds on code changes
- **Deployment**: Automatic deployment to multiple environments
- **Branch-based Deployments**: Feature branch previews

## API Reference

### Stack Outputs

After deployment, the stack provides these outputs:

- `UserPoolId`: Cognito User Pool ID
- `UserPoolClientId`: Cognito User Pool Client ID
- `IdentityPoolId`: Cognito Identity Pool ID
- `GraphQLApiUrl`: AppSync GraphQL API endpoint
- `StorageBucketName`: S3 bucket name for file storage
- `DistributionDomainName`: CloudFront distribution domain
- `AmplifyAppId`: Amplify app ID
- `AmplifyConfig`: Complete configuration for client applications

### Environment Variables

Use these in your React application:

```javascript
const amplifyConfig = {
  aws_project_region: 'us-east-1',
  aws_cognito_region: 'us-east-1',
  aws_user_pools_id: 'us-east-1_ABC123',
  aws_user_pools_web_client_id: 'abc123def456',
  aws_cognito_identity_pool_id: 'us-east-1:abc123-def456',
  aws_appsync_graphqlEndpoint: 'https://abc123.appsync-api.us-east-1.amazonaws.com/graphql',
  aws_appsync_region: 'us-east-1',
  aws_appsync_authenticationType: 'AMAZON_COGNITO_USER_POOLS',
  aws_content_delivery_bucket: 'my-app-storage-bucket',
  aws_content_delivery_bucket_region: 'us-east-1',
  aws_user_files_s3_bucket: 'my-app-storage-bucket',
  aws_user_files_s3_bucket_region: 'us-east-1',
};
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Support

For issues and questions:

1. Check the AWS CDK documentation
2. Review AWS service documentation
3. Search existing GitHub issues
4. Create a new issue with detailed information

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Amplify Documentation](https://docs.aws.amazon.com/amplify/)
- [AWS AppSync Documentation](https://docs.aws.amazon.com/appsync/)
- [Amazon Cognito Documentation](https://docs.aws.amazon.com/cognito/)
- [Progressive Web Apps Guide](https://web.dev/progressive-web-apps/)

---

**Note**: This CDK application creates AWS resources that may incur charges. Review the AWS pricing documentation for each service before deploying to production.