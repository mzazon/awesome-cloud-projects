# Infrastructure as Code for Real-Time Apps with Amplify and AppSync

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Apps with Amplify and AppSync".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- Appropriate AWS permissions for:
  - AWS Amplify
  - AWS AppSync
  - Amazon Cognito
  - Amazon DynamoDB
  - AWS Lambda
  - AWS IAM
  - Amazon CloudWatch
- Git installed for repository management
- Estimated cost: $15-30/month for real-time API requests, DynamoDB operations, and Lambda executions

## Architecture Overview

This infrastructure deploys a complete real-time application platform including:

- **AWS Amplify**: Full-stack development platform with hosting
- **AWS AppSync**: Managed GraphQL API with real-time subscriptions
- **Amazon Cognito**: User authentication and authorization
- **Amazon DynamoDB**: NoSQL database with Global Secondary Indexes
- **AWS Lambda**: Serverless functions for custom business logic
- **Real-time Features**: WebSocket subscriptions, typing indicators, presence tracking

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name realtime-app-stack \
    --template-body file://cloudformation.yaml \
    --parameters file://parameters.json \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name realtime-app-stack \
    --region us-east-1

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name realtime-app-stack \
    --region us-east-1 \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --all

# View deployed resources
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --all

# View deployed resources
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
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

# Check deployment status
./scripts/status.sh
```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Name prefix for all resources (default: "realtime-app")
- `Environment`: Deployment environment (default: "dev")
- `UserPoolDomain`: Cognito User Pool domain prefix
- `EnableAPIKey`: Enable API key for public access (default: true)
- `DynamoDBBillingMode`: DynamoDB billing mode (default: "PAY_PER_REQUEST")

### CDK Configuration

Edit `cdk.json` to customize:

```json
{
  "app": "npx ts-node --prefer-ts-exts bin/realtime-app.ts",
  "context": {
    "projectName": "realtime-app",
    "environment": "dev",
    "enableApiKey": true,
    "enableDataStore": true
  }
}
```

### Terraform Variables

Customize in `terraform.tfvars`:

```hcl
project_name = "realtime-app"
environment  = "dev"
aws_region   = "us-east-1"

# DynamoDB settings
dynamodb_billing_mode = "PAY_PER_REQUEST"
dynamodb_read_capacity = 5
dynamodb_write_capacity = 5

# AppSync settings
enable_api_key = true
enable_datastore = true

# Cognito settings
user_pool_domain = "my-realtime-app"
```

## Deployment Outputs

After successful deployment, you'll receive:

- **AppSync GraphQL API URL**: For frontend application configuration
- **AppSync Real-time WebSocket URL**: For subscription connections
- **Cognito User Pool ID**: For user authentication
- **Cognito User Pool Client ID**: For application integration
- **DynamoDB Table Names**: For direct database access if needed
- **Lambda Function ARNs**: For monitoring and debugging

## Frontend Integration

### Configure Amplify in your React app:

```typescript
import { Amplify } from 'aws-amplify';

const awsConfig = {
  Auth: {
    region: 'us-east-1',
    userPoolId: 'OUTPUT_USER_POOL_ID',
    userPoolWebClientId: 'OUTPUT_USER_POOL_CLIENT_ID',
  },
  API: {
    GraphQL: {
      endpoint: 'OUTPUT_APPSYNC_GRAPHQL_URL',
      region: 'us-east-1',
      defaultAuthMode: 'userPool',
    },
  },
};

Amplify.configure(awsConfig);
```

### Install required dependencies:

```bash
npm install aws-amplify @aws-amplify/ui-react
npm install rxjs uuid date-fns
```

## Real-Time Features

The deployed infrastructure supports:

- **Real-time messaging**: Instant message delivery across clients
- **Typing indicators**: Live typing status updates
- **Presence tracking**: Online/offline user status
- **Message reactions**: Real-time emoji reactions
- **Conflict resolution**: Automatic data synchronization
- **Offline support**: Queue operations when offline

## Security Features

- **Authentication**: Cognito User Pool with MFA support
- **Authorization**: Fine-grained access control with user groups
- **API Security**: Rate limiting and request validation
- **Data Encryption**: Encryption at rest and in transit
- **IAM Roles**: Least privilege access patterns

## Monitoring and Observability

The infrastructure includes:

- **CloudWatch Logs**: Centralized logging for all services
- **CloudWatch Metrics**: Real-time performance monitoring
- **X-Ray Tracing**: Distributed tracing for troubleshooting
- **AppSync Metrics**: GraphQL operation and subscription monitoring
- **Custom Dashboards**: Pre-configured monitoring views

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name realtime-app-stack \
    --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name realtime-app-stack \
    --region us-east-1
```

### Using CDK

```bash
# Destroy all resources
cdk destroy --all

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Resource Limits**: Check AWS service limits for your region
3. **Name Conflicts**: Modify resource names if conflicts occur
4. **Subscription Limits**: Monitor AppSync subscription connection limits

### Debug Commands

```bash
# Check CloudFormation stack events
aws cloudformation describe-stack-events \
    --stack-name realtime-app-stack

# View AppSync API details
aws appsync list-graphql-apis

# Check DynamoDB table status
aws dynamodb describe-table --table-name YourTableName

# Monitor Lambda function logs
aws logs tail /aws/lambda/your-function-name --follow
```

### Resource Verification

```bash
# Verify all resources are created
aws cloudformation list-stack-resources \
    --stack-name realtime-app-stack

# Test GraphQL API connectivity
curl -X POST \
    -H "Content-Type: application/json" \
    -H "x-api-key: YOUR_API_KEY" \
    -d '{"query": "{ __schema { types { name } } }"}' \
    YOUR_GRAPHQL_ENDPOINT
```

## Customization

### Adding New Message Types

1. Update the GraphQL schema in your IaC templates
2. Add corresponding DynamoDB attributes
3. Update Lambda resolvers for new message handling
4. Deploy changes using your chosen IaC tool

### Scaling Configuration

- **DynamoDB**: Adjust read/write capacity or use auto-scaling
- **Lambda**: Configure reserved concurrency if needed
- **AppSync**: Monitor subscription connection limits
- **Cognito**: Review user pool limits for your use case

## Cost Optimization

- **DynamoDB**: Use on-demand billing for unpredictable workloads
- **Lambda**: Optimize function memory and timeout settings
- **AppSync**: Monitor subscription message counts
- **CloudWatch**: Set up log retention policies

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Verify your AWS permissions and service limits
4. Check CloudFormation/CDK/Terraform logs for specific errors

## Additional Resources

- [AWS Amplify Documentation](https://docs.amplify.aws/)
- [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/)
- [Amazon Cognito Documentation](https://docs.aws.amazon.com/cognito/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)