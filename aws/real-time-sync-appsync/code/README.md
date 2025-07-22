# Infrastructure as Code for Real-time Data Synchronization with AWS AppSync

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Synchronizing Real-time Data with AWS AppSync".

## Solution Overview

This recipe implements a collaborative task management system using AWS AppSync for real-time GraphQL subscriptions, DynamoDB for data storage, and IAM for secure access control. The solution demonstrates how to build real-time collaborative applications where multiple users can create, update, and delete tasks while receiving immediate notifications of changes made by other users.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

- **AWS AppSync**: GraphQL API with real-time subscriptions
- **Amazon DynamoDB**: NoSQL database with streams enabled
- **IAM Roles**: Service roles for AppSync to access DynamoDB
- **CloudWatch**: Logging and monitoring for the GraphQL API

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AppSync (create APIs, data sources, resolvers)
  - DynamoDB (create tables, manage streams)
  - IAM (create roles and policies)
  - CloudWatch (access logs and metrics)
- For CDK deployments: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.0+
- Estimated cost: $10-15 for resources created (delete after testing)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name realtime-appsync-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ApiName,ParameterValue=my-realtime-api

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name realtime-appsync-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name realtime-appsync-stack \
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

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
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

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and display the API URL and key when complete
```

## Testing the Deployment

### Get API Details
```bash
# CloudFormation
aws cloudformation describe-stacks \
    --stack-name realtime-appsync-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`GraphQLApiUrl`].OutputValue' \
    --output text

# Terraform
terraform output -raw graphql_api_url

# CDK
cat outputs.json | jq -r '.RealtimeTasksStack.GraphQLApiUrl'
```

### Test GraphQL Operations
```bash
# Example: Create a task using AWS CLI
export API_ID="your-api-id"
export API_KEY="your-api-key"

# Create a test task
aws appsync post-graphql \
    --api-id $API_ID \
    --query 'mutation { createTask(input: { title: "Test Task", description: "Testing the API", priority: HIGH, assignedTo: "test@example.com" }) { id title status createdAt } }' \
    --auth-type API_KEY \
    --auth-config apiKey=$API_KEY

# List all tasks
aws appsync post-graphql \
    --api-id $API_ID \
    --query 'query { listTasks { items { id title status priority createdAt } } }' \
    --auth-type API_KEY \
    --auth-config apiKey=$API_KEY
```

### WebSocket Subscription Testing
For real-time subscription testing, use the AWS AppSync console or integrate with a client application using the AWS AppSync SDK.

## Configuration Options

### Environment Variables
Set these environment variables before deployment:

```bash
export AWS_REGION="us-east-1"              # AWS region for deployment
export API_NAME="my-realtime-tasks-api"    # Name for the AppSync API
export TABLE_NAME="my-tasks-table"         # Name for the DynamoDB table
export ENABLE_LOGGING="true"               # Enable CloudWatch logging
```

### Terraform Variables
Customize the deployment by modifying `terraform/terraform.tfvars`:

```hcl
api_name = "my-realtime-tasks-api"
table_name = "my-tasks-table"
enable_xray_tracing = true
enable_detailed_metrics = true
api_key_expires_days = 30
read_capacity_units = 5
write_capacity_units = 5
```

### CDK Context
For CDK deployments, customize in `cdk.json`:

```json
{
  "context": {
    "apiName": "my-realtime-tasks-api",
    "tableName": "my-tasks-table",
    "enableXRayTracing": true,
    "apiKeyExpiresDays": 30
  }
}
```

## Security Considerations

### Default Security Features
- IAM roles with least privilege access
- API key authentication for development/testing
- DynamoDB encryption at rest enabled
- CloudWatch logging for audit trails

### Production Recommendations
1. **Replace API Key Authentication**: Integrate with Amazon Cognito User Pools for production deployments
2. **Enable VPC Endpoints**: For private network access to DynamoDB
3. **Configure WAF**: Add AWS WAF for additional API protection
4. **Monitor Usage**: Set up CloudWatch alarms for unusual activity
5. **Rotate API Keys**: Implement regular API key rotation

### Sample Cognito Integration
```bash
# Create Cognito User Pool for production authentication
aws cognito-idp create-user-pool \
    --pool-name realtime-tasks-users \
    --policies PasswordPolicy='{MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=true}'
```

## Monitoring and Observability

### CloudWatch Metrics
Monitor these key metrics:
- `ActiveConnections`: Number of active WebSocket connections
- `ConnectSuccess`: Successful connection rate
- `4xxError` and `5xxError`: Error rates
- `Latency`: API response times

### CloudWatch Logs
Access logs at:
- `/aws/appsync/apis/{api-id}`: AppSync request/response logs
- `/aws/lambda/{function-name}`: Lambda resolver logs (if using Lambda resolvers)

### Sample CloudWatch Query
```bash
# Get error logs from the last hour
aws logs filter-log-events \
    --log-group-name "/aws/appsync/apis/${API_ID}" \
    --start-time $(date -d '1 hour ago' +%s)000 \
    --filter-pattern "ERROR"
```

## Troubleshooting

### Common Issues

1. **Schema Upload Failures**
   ```bash
   # Check schema syntax
   aws appsync get-introspection-schema \
       --api-id $API_ID \
       --format SDL
   ```

2. **Resolver Errors**
   ```bash
   # Check resolver mapping templates
   aws appsync get-resolver \
       --api-id $API_ID \
       --type-name Mutation \
       --field-name createTask
   ```

3. **DynamoDB Access Issues**
   ```bash
   # Verify IAM role permissions
   aws iam get-role-policy \
       --role-name appsync-tasks-role \
       --policy-name DynamoDBAccess
   ```

4. **Subscription Connection Issues**
   - Verify WebSocket endpoint URL
   - Check API key validity and permissions
   - Review CloudWatch logs for connection errors

### Debugging Commands
```bash
# Test DynamoDB table access
aws dynamodb describe-table --table-name $TABLE_NAME

# Check AppSync API status
aws appsync get-graphql-api --api-id $API_ID

# Validate IAM role
aws sts assume-role \
    --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
    --role-session-name test-session
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack and all resources
aws cloudformation delete-stack \
    --stack-name realtime-appsync-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name realtime-appsync-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup Verification
```bash
# Verify AppSync API deletion
aws appsync list-graphql-apis \
    --query 'graphqlApis[?name==`realtime-tasks-api`]'

# Verify DynamoDB table deletion
aws dynamodb list-tables \
    --query 'TableNames[?contains(@, `tasks`)]'

# Verify IAM role deletion
aws iam list-roles \
    --query 'Roles[?contains(RoleName, `appsync-tasks-role`)]'
```

## Performance Optimization

### Scaling Considerations
- **DynamoDB**: Configure auto-scaling for read/write capacity
- **AppSync**: Monitor connection limits (default: 100,000 concurrent connections)
- **CloudWatch**: Set up alarms for high latency or error rates

### Cost Optimization
- **DynamoDB**: Use on-demand billing for unpredictable workloads
- **AppSync**: Monitor request and subscription usage
- **CloudWatch**: Configure log retention periods appropriately

## Support and Documentation

### Official Documentation
- [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/latest/devguide/)
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/latest/developerguide/)
- [GraphQL Subscriptions in AppSync](https://docs.aws.amazon.com/appsync/latest/devguide/real-time-data.html)

### Additional Resources
- [AWS AppSync Schema Design Best Practices](https://docs.aws.amazon.com/appsync/latest/devguide/designing-your-schema.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [GraphQL Best Practices](https://graphql.org/learn/best-practices/)

### Community Support
- [AWS AppSync GitHub](https://github.com/aws/aws-appsync-community)
- [AWS Developer Forums](https://forums.aws.amazon.com/forum.jspa?forumID=250)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/aws-appsync)

## Next Steps

After successful deployment, consider these enhancements:

1. **Add Authentication**: Integrate with Amazon Cognito User Pools
2. **Implement Caching**: Enable AppSync caching for improved performance
3. **Add Analytics**: Integrate with Amazon Pinpoint for user analytics
4. **Build Client Apps**: Use AWS AppSync SDKs for web, mobile, and desktop applications
5. **Add Data Validation**: Implement custom resolvers with AWS Lambda for complex business logic

For issues with this infrastructure code, refer to the original recipe documentation or the AWS documentation links provided above.