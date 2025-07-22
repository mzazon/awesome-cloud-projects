# Infrastructure as Code for Implementing Real-Time Chat Applications with AppSync and GraphQLexisting_folder_name

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Real-Time Chat Applications with AppSync and GraphQLexisting_folder_name".

## Overview

This solution implements a serverless real-time chat application using AWS AppSync, DynamoDB, Amazon Cognito, and AWS Lambda. The architecture provides WebSocket-based real-time messaging with automatic scaling, user authentication, and message persistence.

## Architecture Components

- **AWS AppSync**: Managed GraphQL API with real-time subscriptions
- **Amazon DynamoDB**: NoSQL database for messages, conversations, and user data
- **Amazon Cognito**: User authentication and authorization
- **AWS Lambda**: Message processing and user presence management
- **Amazon CloudWatch**: Logging and monitoring

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AppSync (full access)
  - DynamoDB (full access)
  - Cognito (full access)
  - Lambda (full access)
  - IAM (role creation and policy management)
  - CloudWatch (logs access)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.0 or later
- CloudFormation permissions

#### CDK TypeScript
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK v2 installed globally: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK v2 installed: `pip install aws-cdk-lib`

#### Terraform
- Terraform v1.0 or later
- AWS provider v5.0 or later

#### Bash Scripts
- AWS CLI v2 configured with appropriate permissions
- jq for JSON processing (optional but recommended)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name realtime-chat-app \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name realtime-chat-app

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name realtime-chat-app \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the application
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the application
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### Environment Variables

Set these environment variables before deployment to customize your installation:

```bash
export CHAT_APP_ENVIRONMENT=dev        # Environment name (dev, staging, prod)
export CHAT_APP_REGION=us-east-1       # AWS region
export CHAT_APP_PREFIX=mycompany       # Resource prefix for naming
```

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Environment name | dev | Yes |
| AppPrefix | Prefix for resource names | realtime-chat | No |
| CognitoPasswordPolicy | Password complexity requirements | Strong | No |
| DynamoDBBillingMode | DynamoDB billing mode | PAY_PER_REQUEST | No |

### Terraform Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
environment = "dev"
app_prefix  = "realtime-chat"
aws_region  = "us-east-1"

# DynamoDB configuration
dynamodb_billing_mode = "PAY_PER_REQUEST"

# Cognito configuration
cognito_password_min_length = 8
cognito_require_uppercase   = true
cognito_require_lowercase   = true
cognito_require_numbers     = true
cognito_require_symbols     = false

# AppSync configuration
appsync_log_level = "ALL"

# Tags
tags = {
  Project     = "RealTimeChat"
  Environment = "dev"
  Owner       = "DevOps Team"
}
```

## Post-Deployment Configuration

### 1. Test User Setup

After deployment, create test users for validation:

```bash
# Get User Pool ID from outputs
USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name realtime-chat-app \
    --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
    --output text)

# Create test users
aws cognito-idp admin-create-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "testuser1" \
    --user-attributes Name=email,Value=test1@example.com \
    --temporary-password "TempPassword123!" \
    --message-action SUPPRESS

aws cognito-idp admin-create-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "testuser2" \
    --user-attributes Name=email,Value=test2@example.com \
    --temporary-password "TempPassword123!" \
    --message-action SUPPRESS

# Set permanent passwords
aws cognito-idp admin-set-user-password \
    --user-pool-id "${USER_POOL_ID}" \
    --username "testuser1" \
    --password "TestPassword123!" \
    --permanent

aws cognito-idp admin-set-user-password \
    --user-pool-id "${USER_POOL_ID}" \
    --username "testuser2" \
    --password "TestPassword123!" \
    --permanent
```

### 2. Validate Deployment

Test the GraphQL API endpoint:

```bash
# Get API endpoint from outputs
GRAPHQL_URL=$(aws cloudformation describe-stacks \
    --stack-name realtime-chat-app \
    --query 'Stacks[0].Outputs[?OutputKey==`GraphQLApiUrl`].OutputValue' \
    --output text)

echo "GraphQL API URL: ${GRAPHQL_URL}"
echo "Test the API in the AWS AppSync console"
```

## Testing the Chat Application

### 1. Authentication Test

```bash
# Authenticate test user
aws cognito-idp admin-initiate-auth \
    --user-pool-id "${USER_POOL_ID}" \
    --client-id "${USER_POOL_CLIENT_ID}" \
    --auth-flow ADMIN_NO_SRP_AUTH \
    --auth-parameters USERNAME=testuser1,PASSWORD=TestPassword123!
```

### 2. GraphQL Operations

Use the AWS AppSync console or a GraphQL client to test:

#### Create a Conversation
```graphql
mutation CreateConversation {
  createConversation(input: {
    name: "Test Chat Room"
    participants: ["testuser1", "testuser2"]
  }) {
    conversationId
    name
    participants
    createdAt
  }
}
```

#### Send a Message
```graphql
mutation SendMessage {
  sendMessage(input: {
    conversationId: "conversation-id-here"
    content: "Hello, World!"
    messageType: TEXT
  }) {
    messageId
    conversationId
    userId
    content
    createdAt
  }
}
```

#### Subscribe to Messages
```graphql
subscription OnMessageSent {
  onMessageSent(conversationId: "conversation-id-here") {
    messageId
    conversationId
    userId
    content
    createdAt
  }
}
```

## Monitoring and Logging

### CloudWatch Dashboards

Access monitoring through:
- AppSync API metrics and logs
- DynamoDB table metrics
- Lambda function logs and metrics
- Cognito authentication metrics

### Log Groups

The following CloudWatch log groups are created:
- `/aws/appsync/apis/{api-id}`
- `/aws/lambda/{function-name}`
- `/aws/cognito/userpools/{user-pool-id}`

### Alarms

Basic CloudWatch alarms are configured for:
- AppSync API errors
- DynamoDB throttling
- Lambda function errors

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name realtime-chat-app

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name realtime-chat-app
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the application
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Plan the destruction
terraform plan -destroy

# Destroy the infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure your AWS credentials have sufficient permissions for all required services.

2. **Resource Limits**: Check AWS service quotas if deployment fails due to limits.

3. **Region Availability**: Ensure all services are available in your chosen AWS region.

4. **VTL Resolver Errors**: Check CloudWatch logs for AppSync resolver execution errors.

### Debug Commands

```bash
# Check AppSync API status
aws appsync get-graphql-api --api-id YOUR_API_ID

# View DynamoDB table status
aws dynamodb describe-table --table-name YOUR_TABLE_NAME

# Check Cognito User Pool
aws cognito-idp describe-user-pool --user-pool-id YOUR_POOL_ID

# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/appsync/"
```

## Security Considerations

- **Authentication**: All API operations require valid Cognito JWT tokens
- **Authorization**: Users can only access conversations they participate in
- **Data Encryption**: DynamoDB encryption at rest is enabled
- **Transport Security**: All communications use HTTPS/WSS
- **IAM Roles**: Follow least privilege principle for all service roles

## Cost Optimization

- **DynamoDB**: Uses on-demand billing by default
- **AppSync**: Pay per operation and real-time subscription
- **Lambda**: Only charged for actual execution time
- **Cognito**: First 50,000 monthly active users are free

Monitor costs using AWS Cost Explorer and set up billing alerts.

## Customization

### Adding New Features

1. **File Uploads**: Integrate S3 for media sharing
2. **Push Notifications**: Add SNS for mobile notifications
3. **Message Search**: Implement OpenSearch for full-text search
4. **Analytics**: Add Kinesis for real-time analytics

### Schema Extensions

Modify the GraphQL schema in the respective IaC files to add:
- Message reactions
- Typing indicators
- Message threading
- User status updates

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../real-time-chat-applications-appsync-graphql.md)
2. Review AWS service documentation
3. Check CloudWatch logs for error details
4. Validate IAM permissions and resource quotas

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation and README
3. Validate security best practices
4. Test cleanup procedures
5. Update version numbers appropriately

## License

This infrastructure code is provided as-is for educational and development purposes. Ensure compliance with your organization's policies and AWS best practices.