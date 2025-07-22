# Infrastructure as Code for Developing Offline-First Mobile Applications with Amplify DataStore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developing Offline-First Mobile Applications with Amplify DataStore".

## Architecture Overview

This recipe demonstrates building offline-first mobile applications using AWS Amplify DataStore, which provides automatic synchronization between local device storage and cloud-based services. The architecture includes:

- **AWS Amplify**: Framework for building full-stack applications with offline-first capabilities
- **AWS AppSync**: Managed GraphQL API with real-time subscriptions and conflict resolution
- **Amazon DynamoDB**: NoSQL database for storing application data
- **Amazon Cognito**: User authentication and authorization service
- **AWS Lambda**: Serverless compute for custom resolvers (optional)

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- AWS Amplify CLI installed globally (`npm install -g @aws-amplify/cli`)
- React Native development environment (Node.js, React Native CLI, Android Studio/Xcode)
- Appropriate AWS permissions for creating:
  - AWS Amplify applications
  - AppSync GraphQL APIs
  - DynamoDB tables
  - Cognito User Pools
  - IAM roles and policies
  - Lambda functions (if using custom resolvers)

## Estimated Costs

- **Development/Testing**: $10-20/month
- **Production**: $50-200/month (varies by usage)
- **Key cost factors**:
  - DynamoDB read/write capacity and storage
  - AppSync API requests and real-time subscriptions
  - Cognito active users
  - Data transfer costs

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name offline-first-amplify-datastore \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=offline-tasks \
        ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name offline-first-amplify-datastore

# Get outputs
aws cloudformation describe-stacks \
    --stack-name offline-first-amplify-datastore \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --require-approval never

# Get outputs
cdk list
```

### Using CDK Python (AWS)

```bash
# Set up Python environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --require-approval never

# Get outputs
cdk list
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Set up environment variables
# 2. Initialize Amplify application
# 3. Configure authentication
# 4. Set up GraphQL API with DataStore
# 5. Deploy backend resources
```

## Configuration

### Key Parameters

- **ProjectName**: Name for your Amplify application
- **Environment**: Deployment environment (dev, staging, prod)
- **AuthenticationFlow**: Cognito authentication flow configuration
- **ConflictResolution**: DataStore conflict resolution strategy
- **SyncExpressions**: Selective synchronization rules

### GraphQL Schema

The implementation includes a comprehensive GraphQL schema with:

- **Task** model with priority and status enums
- **Project** model with task relationships
- Owner-based authorization rules
- Automatic timestamps and audit fields

### DataStore Configuration

- **Selective Sync**: Filters data based on user preferences and device capabilities
- **Conflict Resolution**: Auto-merge strategy with custom resolution logic
- **Real-time Subscriptions**: Automatic updates across devices
- **Offline Queuing**: Queues operations when offline for later synchronization

## Deployment Process

1. **Backend Infrastructure**: Creates AWS resources (AppSync, DynamoDB, Cognito)
2. **GraphQL Schema**: Deploys data models and resolvers
3. **Authentication**: Configures Cognito User Pool and identity providers
4. **DataStore Setup**: Enables offline synchronization and conflict resolution
5. **Real-time Subscriptions**: Configures WebSocket connections for live updates

## Validation & Testing

### Backend Validation

```bash
# Check Amplify status
amplify status

# Test GraphQL API
aws appsync list-graphql-apis \
    --region $AWS_REGION \
    --query 'graphqlApis[].name'

# Verify DynamoDB tables
aws dynamodb list-tables \
    --region $AWS_REGION \
    --query 'TableNames[?contains(@, `Task`) || contains(@, `Project`)]'
```

### Application Testing

```bash
# Create React Native project
npx react-native init OfflineTasksApp --template react-native-template-typescript

# Install Amplify dependencies
npm install aws-amplify @aws-amplify/datastore

# Configure Amplify
amplify configure

# Pull backend configuration
amplify pull --appId YOUR_APP_ID --envName dev
```

### Offline Testing

1. **Network Simulation**: Test with network disabled in simulator
2. **Data Persistence**: Verify local storage functionality
3. **Sync Behavior**: Test automatic synchronization when online
4. **Conflict Resolution**: Create conflicts from multiple devices
5. **Real-time Updates**: Verify live data updates

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name offline-first-amplify-datastore

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name offline-first-amplify-datastore
```

### Using CDK (AWS)

```bash
# Destroy the infrastructure
cd cdk-typescript/  # or cdk-python/
cdk destroy --force

# Clean up local files
rm -rf cdk.out/
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Clean up state files
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Amplify backend resources
# 2. Remove local configuration files
# 3. Verify complete cleanup
```

## Customization

### Environment Variables

```bash
# Core settings
export AWS_REGION="us-east-1"
export PROJECT_NAME="offline-tasks"
export ENVIRONMENT="dev"

# Authentication settings
export COGNITO_USER_POOL_NAME="${PROJECT_NAME}-user-pool"
export COGNITO_IDENTITY_POOL_NAME="${PROJECT_NAME}-identity-pool"

# API settings
export APPSYNC_API_NAME="${PROJECT_NAME}-api"
export CONFLICT_RESOLUTION_STRATEGY="AUTOMERGE"
```

### Schema Customization

Modify the GraphQL schema to add:
- Additional data models
- Custom fields and relationships
- Advanced authorization rules
- Custom scalar types

### Sync Configuration

Customize selective synchronization:
- Filter by user preferences
- Limit by device capabilities
- Optimize for bandwidth constraints
- Implement custom sync expressions

## Troubleshooting

### Common Issues

1. **Amplify CLI Issues**:
   ```bash
   # Update Amplify CLI
   npm install -g @aws-amplify/cli@latest
   
   # Clear cache
   amplify delete
   ```

2. **Authentication Problems**:
   ```bash
   # Check Cognito configuration
   aws cognito-idp list-user-pools --max-results 10
   
   # Verify user pool settings
   aws cognito-idp describe-user-pool --user-pool-id YOUR_POOL_ID
   ```

3. **DataStore Sync Issues**:
   ```bash
   # Check AppSync API
   aws appsync get-graphql-api --api-id YOUR_API_ID
   
   # Verify DynamoDB tables
   aws dynamodb describe-table --table-name YOUR_TABLE_NAME
   ```

### Performance Optimization

- **Selective Sync**: Use sync expressions to reduce data transfer
- **Batch Operations**: Group related operations for efficiency
- **Caching**: Implement intelligent caching strategies
- **Monitoring**: Use CloudWatch for performance metrics

## Security Considerations

- **Authentication**: Implement proper user authentication flows
- **Authorization**: Use fine-grained access controls
- **Data Encryption**: Enable encryption at rest and in transit
- **Network Security**: Configure VPC endpoints for private connectivity
- **Monitoring**: Set up CloudTrail for audit logging

## Advanced Features

### Custom Conflict Resolution

```typescript
// Custom conflict resolution logic
const resolveConflict = (localModel, remoteModel) => {
  // Implement business logic for conflict resolution
  return localModel.priority > remoteModel.priority 
    ? localModel 
    : remoteModel;
};
```

### File Upload Support

```typescript
// S3 integration for file uploads
import { Storage } from 'aws-amplify';

const uploadFile = async (file) => {
  const result = await Storage.put('file.jpg', file, {
    contentType: 'image/jpeg',
    level: 'private'
  });
  return result.key;
};
```

### Real-time Notifications

```typescript
// Push notifications for sync events
import { PushNotification } from '@aws-amplify/notifications';

const setupNotifications = () => {
  PushNotification.onNotification((notification) => {
    // Handle sync notifications
    console.log('Sync notification:', notification);
  });
};
```

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review AWS Amplify documentation
3. Consult AWS support resources
4. Check GitHub issues for known problems

## Contributing

When contributing to this infrastructure code:
1. Follow AWS best practices
2. Update documentation for changes
3. Test all deployment scenarios
4. Ensure proper cleanup procedures
5. Maintain backward compatibility

## Resources

- [AWS Amplify Documentation](https://docs.amplify.aws/)
- [AWS AppSync Documentation](https://docs.aws.amazon.com/appsync/)
- [Amazon DynamoDB Documentation](https://docs.aws.amazon.com/dynamodb/)
- [Amazon Cognito Documentation](https://docs.aws.amazon.com/cognito/)
- [DataStore Documentation](https://docs.amplify.aws/lib/datastore/getting-started/)