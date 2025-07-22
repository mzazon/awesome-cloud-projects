# CDK Python: GraphQL APIs with AWS AppSync

This directory contains a complete AWS CDK Python application that deploys a production-ready GraphQL API using AWS AppSync, DynamoDB, and Amazon Cognito for authentication.

## Architecture Overview

The CDK application creates the following AWS resources:

- **AWS AppSync GraphQL API** - Fully managed GraphQL service with real-time subscriptions
- **DynamoDB Table** - NoSQL database for storing blog posts with Global Secondary Index
- **Amazon Cognito User Pool** - User authentication and authorization
- **IAM Roles & Policies** - Secure access control following least privilege principle
- **CloudWatch Logs** - API request logging and monitoring
- **API Keys** - Development and testing access

## Features

### GraphQL API Capabilities
- **Queries**: Get individual posts, list all posts, list posts by author
- **Mutations**: Create, update, and delete blog posts
- **Subscriptions**: Real-time updates for create, update, and delete operations
- **Authentication**: Cognito User Pool integration with API key fallback
- **Authorization**: Field-level access control and user-based permissions

### Data Management
- **DynamoDB Table**: Optimized for blog post storage with efficient access patterns
- **Global Secondary Index**: Fast author-based queries with timestamp sorting
- **Automatic Timestamps**: CreatedAt and UpdatedAt fields managed automatically
- **Pagination Support**: Efficient data retrieval with cursor-based pagination

### Security & Monitoring
- **Authentication**: Multiple auth methods (Cognito User Pool, API Key)
- **Authorization**: User-based access control for mutations
- **Encryption**: Data encrypted at rest and in transit
- **Logging**: Comprehensive CloudWatch logging with X-Ray tracing
- **IAM Policies**: Least privilege access for all resources

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **AWS CDK** installed globally (`npm install -g aws-cdk`)
3. **Python 3.8+** installed on your system
4. **Node.js** (required for CDK CLI)
5. **Git** (for version control)

### Required AWS Permissions

Your AWS credentials must have permissions for:
- AppSync (create APIs, data sources, resolvers)
- DynamoDB (create tables, indexes)
- Cognito (create user pools, clients)
- IAM (create roles, policies)
- CloudWatch Logs (create log groups)
- CloudFormation (create/update stacks)

## Installation & Setup

### 1. Create Virtual Environment

```bash
# Create virtual environment
python3 -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate
```

### 2. Install Dependencies

```bash
# Install CDK dependencies
pip install -r requirements.txt

# Verify CDK installation
cdk --version
```

### 3. Bootstrap CDK (First Time Only)

```bash
# Bootstrap CDK in your AWS account/region
cdk bootstrap

# Optional: Bootstrap with specific profile
cdk bootstrap --profile your-aws-profile
```

### 4. Configure Environment Variables

```bash
# Set AWS region (optional, defaults to us-east-1)
export CDK_DEFAULT_REGION=us-east-1

# Set AWS account ID (optional, auto-detected)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
```

## Deployment

### Deploy the Stack

```bash
# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the stack
cdk deploy

# Deploy with automatic approval (skip confirmation prompts)
cdk deploy --require-approval never
```

### Deployment Output

After successful deployment, you'll see output similar to:

```
 ✅  GraphQLAppSyncStack

✨  Deployment time: 150.32s

Outputs:
GraphQLAppSyncStack.GraphQLApiId = abcdef123456
GraphQLAppSyncStack.GraphQLApiUrl = https://abcdef123456.appsync-api.us-east-1.amazonaws.com/graphql
GraphQLAppSyncStack.GraphQLApiKey = da2-abcdef123456
GraphQLAppSyncStack.UserPoolId = us-east-1_ABC123DEF
GraphQLAppSyncStack.UserPoolClientId = abcdef123456
GraphQLAppSyncStack.DynamoDBTableName = BlogPosts-abcdef12
GraphQLAppSyncStack.RealtimeUrl = https://abcdef123456.appsync-realtime-api.us-east-1.amazonaws.com/graphql
```

## Testing the API

### Using AWS AppSync Console

1. Navigate to the AWS AppSync console
2. Select your API (blog-api-*)
3. Go to the "Queries" tab
4. Use the built-in GraphQL explorer to test queries

### Example GraphQL Operations

#### Create a Blog Post
```graphql
mutation CreatePost {
  createBlogPost(input: {
    title: "My First Post"
    content: "This is the content of my first blog post"
    tags: ["technology", "aws", "graphql"]
    published: true
  }) {
    id
    title
    author
    createdAt
    tags
  }
}
```

#### List All Posts
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
    nextToken
  }
}
```

#### Subscribe to New Posts
```graphql
subscription OnNewPost {
  onCreateBlogPost {
    id
    title
    author
    createdAt
  }
}
```

### Using Python Client

Create a test script to interact with your API:

```python
import boto3
import json
import requests

# Use the outputs from CDK deployment
API_URL = "https://your-api-id.appsync-api.us-east-1.amazonaws.com/graphql"
API_KEY = "your-api-key"

def graphql_request(query, variables=None):
    headers = {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY
    }
    
    payload = {'query': query}
    if variables:
        payload['variables'] = variables
    
    response = requests.post(API_URL, json=payload, headers=headers)
    return response.json()

# Test query
query = """
query {
  listBlogPosts(limit: 5) {
    items {
      id
      title
      author
      createdAt
    }
  }
}
"""

result = graphql_request(query)
print(json.dumps(result, indent=2))
```

## User Management

### Create Test Users

```bash
# Get User Pool ID from stack outputs
USER_POOL_ID="us-east-1_ABC123DEF"

# Create a test user
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username testuser@example.com \
  --user-attributes Name=email,Value=testuser@example.com \
  --temporary-password "TempPass123!" \
  --message-action SUPPRESS

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username testuser@example.com \
  --password "BlogUser123!" \
  --permanent
```

## Customization

### Modify the Schema

Edit `schema.graphql` to add new fields or operations:

```graphql
# Add new fields to BlogPost type
type BlogPost {
    id: ID!
    title: String!
    content: String!
    author: String!
    createdAt: AWSDateTime!
    updatedAt: AWSDateTime!
    tags: [String]
    published: Boolean!
    # New fields
    category: String
    viewCount: Int
    featured: Boolean
}
```

### Add New Resolvers

Modify `app.py` to add new resolver functions:

```python
def _create_custom_resolvers(self, data_source):
    # Add custom resolver logic
    data_source.create_resolver(
        "customResolver",
        type_name="Query",
        field_name="customField",
        request_mapping_template=appsync.MappingTemplate.from_string("""
        # Custom VTL mapping template
        """),
        response_mapping_template=appsync.MappingTemplate.from_string("""
        # Custom response mapping
        """),
    )
```

### Environment-Specific Configuration

Create different configurations for environments:

```python
# In app.py
import os

environment = os.getenv('ENVIRONMENT', 'dev')

if environment == 'prod':
    # Production configuration
    removal_policy = RemovalPolicy.RETAIN
    log_retention = logs.RetentionDays.ONE_MONTH
else:
    # Development configuration
    removal_policy = RemovalPolicy.DESTROY
    log_retention = logs.RetentionDays.ONE_WEEK
```

## Monitoring & Debugging

### CloudWatch Logs

Monitor API requests and errors:

```bash
# View AppSync logs
aws logs describe-log-groups --log-group-name-prefix "/aws/appsync/apis"

# Tail logs in real-time
aws logs tail /aws/appsync/apis/your-api-id --follow
```

### X-Ray Tracing

The API includes X-Ray tracing for performance monitoring:

1. Navigate to AWS X-Ray console
2. View service maps and traces
3. Analyze performance bottlenecks

### CloudWatch Metrics

Monitor key metrics:
- Request count
- Error rate
- Latency
- Resolver execution time

## Security Best Practices

### Authentication Flow

1. **Cognito User Pool**: Primary authentication method
2. **API Key**: Fallback for development/testing
3. **IAM Roles**: Service-to-service communication

### Authorization Rules

- **Public**: `listBlogPosts` (published posts only)
- **Authenticated**: `createBlogPost`, `getBlogPost`
- **Owner**: `updateBlogPost`, `deleteBlogPost` (author-restricted)

### Data Protection

- **Encryption at Rest**: DynamoDB encryption enabled
- **Encryption in Transit**: HTTPS/WSS for all communications
- **Access Logging**: All API requests logged to CloudWatch

## Troubleshooting

### Common Issues

1. **Schema Validation Errors**
   - Check GraphQL schema syntax
   - Verify field types and directives

2. **Resolver Errors**
   - Review VTL mapping templates
   - Check DynamoDB table structure

3. **Authentication Issues**
   - Verify Cognito User Pool configuration
   - Check API key validity

4. **Permission Errors**
   - Review IAM policies
   - Ensure service roles have required permissions

### Debug Commands

```bash
# Check stack status
cdk ls

# View differences before deployment
cdk diff

# View synthesized CloudFormation template
cdk synth

# Check for security issues
cdk doctor
```

## Cleanup

### Destroy the Stack

```bash
# Destroy all resources
cdk destroy

# Destroy with automatic approval
cdk destroy --force
```

### Manual Cleanup

If automatic cleanup fails:

```bash
# Delete AppSync API
aws appsync delete-graphql-api --api-id your-api-id

# Delete DynamoDB table
aws dynamodb delete-table --table-name BlogPosts-suffix

# Delete Cognito User Pool
aws cognito-idp delete-user-pool --user-pool-id your-pool-id
```

## Cost Considerations

### Pricing Factors

- **AppSync**: $4.00 per million requests
- **DynamoDB**: $0.25 per million read/write units
- **Cognito**: $0.0055 per MAU (Monthly Active User)
- **CloudWatch**: $0.50 per million API requests logged

### Cost Optimization

1. **DynamoDB**: Consider on-demand billing for variable workloads
2. **AppSync**: Use caching to reduce downstream requests
3. **Cognito**: Monitor MAU usage and optimize user flows
4. **CloudWatch**: Adjust log retention periods

## Additional Resources

### Documentation
- [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/)
- [GraphQL Specification](https://spec.graphql.org/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)

### Tools
- [GraphQL Playground](https://github.com/graphql/graphql-playground)
- [AWS AppSync Client SDK](https://docs.aws.amazon.com/appsync/latest/devguide/building-a-client-app.html)
- [AWS Amplify](https://aws.amazon.com/amplify/) (for frontend integration)

### Community
- [AWS AppSync GitHub](https://github.com/aws/aws-appsync-community)
- [GraphQL Community](https://graphql.org/community/)
- [AWS CDK Community](https://github.com/aws/aws-cdk)

## Support

For issues with this CDK application:

1. Check the troubleshooting section above
2. Review AWS CloudFormation events in the AWS Console
3. Examine CloudWatch logs for detailed error messages
4. Refer to the original recipe documentation
5. Consult AWS documentation for specific services

## Contributing

To contribute improvements to this CDK application:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This CDK application is provided as-is under the MIT License. See the LICENSE file for details.

---

**Note**: This CDK application is designed for educational and demonstration purposes. For production use, consider additional security hardening, monitoring, and compliance requirements specific to your organization.