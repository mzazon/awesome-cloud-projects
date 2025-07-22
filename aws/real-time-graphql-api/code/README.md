# Infrastructure as Code for Real-Time GraphQL API with AppSync

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time GraphQL API with AppSync".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Appropriate AWS permissions for creating:
  - AWS AppSync APIs
  - DynamoDB tables
  - Amazon Cognito User Pools
  - IAM roles and policies
- Estimated cost: $5-15/month for development workloads

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name appsync-graphql-api \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ApiName,ParameterValue=MyBlogAPI \
                 ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name appsync-graphql-api \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name appsync-graphql-api \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python (AWS)

```bash
# Set up virtual environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
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
./scripts/deploy.sh --status
```

## Architecture Overview

This infrastructure creates:

- **AWS AppSync GraphQL API** with Cognito User Pool authentication
- **DynamoDB table** with Global Secondary Index for blog posts
- **Amazon Cognito User Pool** for user authentication
- **IAM roles and policies** for secure service integration
- **GraphQL schema** with queries, mutations, and subscriptions
- **VTL resolvers** for data transformation
- **Test user** for validation

## Configuration Options

### CloudFormation Parameters

- `ApiName`: Name for the AppSync API (default: BlogAPI)
- `Environment`: Environment name (dev/staging/prod)
- `TableName`: DynamoDB table name (optional)
- `UserPoolName`: Cognito User Pool name (optional)

### CDK Context Variables

```json
{
  "apiName": "MyBlogAPI",
  "environment": "development",
  "enableApiKey": true,
  "enableCognito": true
}
```

### Terraform Variables

```hcl
variable "api_name" {
  description = "Name for the AppSync API"
  type        = string
  default     = "BlogAPI"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
```

## Testing Your Deployment

### Get API Information

```bash
# CloudFormation
aws cloudformation describe-stacks \
    --stack-name appsync-graphql-api \
    --query 'Stacks[0].Outputs'

# CDK
cdk list --long

# Terraform
terraform output
```

### Test GraphQL Operations

1. **Navigate to AppSync Console**:
   - Go to AWS AppSync in the AWS Console
   - Select your API
   - Use the Queries tab to test operations

2. **Example Query**:
   ```graphql
   query ListPosts {
     listBlogPosts(limit: 10) {
       items {
         id
         title
         author
         createdAt
         published
       }
     }
   }
   ```

3. **Example Mutation**:
   ```graphql
   mutation CreatePost($input: CreateBlogPostInput!) {
     createBlogPost(input: $input) {
       id
       title
       content
       author
       createdAt
     }
   }
   ```

4. **Example Subscription**:
   ```graphql
   subscription OnCreatePost {
     onCreateBlogPost {
       id
       title
       author
       createdAt
     }
   }
   ```

### Authentication Testing

1. **Get Cognito User Pool details** from stack outputs
2. **Create a test user** in the Cognito console
3. **Use the AppSync console** to test authenticated operations
4. **Try API key authentication** for development testing

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name appsync-graphql-api

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name appsync-graphql-api \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Schema Modifications

To modify the GraphQL schema:

1. **CloudFormation**: Update the schema in the `AppSyncSchema` resource
2. **CDK**: Modify the schema file in `assets/schema.graphql`
3. **Terraform**: Update the schema in `graphql_api.tf`
4. **Scripts**: Edit the schema creation in `deploy.sh`

### Adding New Resolvers

To add new resolvers:

1. Define new resolver templates (request/response mapping)
2. Add resolver resources to your IaC
3. Update the GraphQL schema with new fields
4. Test new operations in the AppSync console

### Security Enhancements

Consider these security improvements:

- Enable AWS WAF for API protection
- Implement field-level authorization
- Add request/response logging
- Configure API caching
- Enable X-Ray tracing

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics:

- `4XXError`: Client errors
- `5XXError`: Server errors
- `Latency`: Response time
- `ConnectedDevice`: WebSocket connections

### Logging

Enable these logging options:

- **Field-level logging**: Track individual field resolution
- **Request-level logging**: Monitor complete request lifecycle
- **CloudTrail**: Track API configuration changes

### Alarms

Set up CloudWatch alarms for:

- High error rates (>5% 4XX/5XX errors)
- High latency (>1000ms average)
- Failed resolver executions

## Troubleshooting

### Common Issues

1. **Schema validation errors**:
   - Check GraphQL schema syntax
   - Verify all required fields are defined
   - Ensure proper type definitions

2. **Resolver errors**:
   - Validate VTL mapping templates
   - Check IAM permissions for data sources
   - Verify DynamoDB table structure

3. **Authentication issues**:
   - Confirm Cognito User Pool configuration
   - Check JWT token validity
   - Verify API key permissions

4. **Permission errors**:
   - Review IAM roles and policies
   - Check service role trust relationships
   - Verify least privilege access

### Debugging Steps

1. **Check CloudWatch logs** for detailed error messages
2. **Use AppSync console** to test operations interactively
3. **Validate DynamoDB** table structure and data
4. **Test authentication** with known good credentials
5. **Review IAM policies** for proper permissions

## Performance Optimization

### Caching

- Enable **API-level caching** for frequently accessed data
- Configure **resolver-level caching** for expensive operations
- Set appropriate **TTL values** based on data freshness requirements

### Query Optimization

- Use **specific field selection** to minimize data transfer
- Implement **pagination** for large result sets
- Consider **batch operations** for multiple related requests

### Real-time Optimization

- Limit **subscription complexity** to essential fields
- Use **subscription filters** to reduce unnecessary notifications
- Monitor **WebSocket connection** counts and limits

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for architectural guidance
2. **AWS Documentation**: Check [AWS AppSync documentation](https://docs.aws.amazon.com/appsync/)
3. **Provider Documentation**: 
   - [CloudFormation AppSync resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_AppSync.html)
   - [CDK AppSync constructs](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_appsync-readme.html)
   - [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appsync_graphql_api)
4. **Community Resources**: AWS forums and Stack Overflow for specific implementation questions

## Additional Resources

- [GraphQL Best Practices](https://graphql.org/learn/best-practices/)
- [AppSync Security Best Practices](https://docs.aws.amazon.com/appsync/latest/devguide/security-best-practices.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [Cognito User Pool Best Practices](https://docs.aws.amazon.com/cognito/latest/developerguide/managing-security.html)