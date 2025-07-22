# Terraform Infrastructure for AWS AppSync GraphQL API

This Terraform configuration creates a complete GraphQL API infrastructure using AWS AppSync, DynamoDB, and Cognito User Pools. The setup includes real-time subscriptions, authentication, and authorization for a blog platform.

## Architecture Overview

The infrastructure includes:

- **AWS AppSync GraphQL API** - Fully managed GraphQL service with real-time subscriptions
- **DynamoDB Table** - NoSQL database for blog posts with Global Secondary Index
- **Cognito User Pool** - User authentication and authorization
- **IAM Roles and Policies** - Service permissions and security
- **VTL Resolvers** - Data transformation logic for GraphQL operations

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Terraform** >= 1.0 installed
3. **AWS credentials** configured with the following permissions:
   - AppSync full access
   - DynamoDB full access
   - Cognito Identity Provider full access
   - IAM role and policy management
   - CloudWatch Logs access

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review the Plan

```bash
terraform plan
```

### 3. Deploy the Infrastructure

```bash
terraform apply
```

### 4. Get the Outputs

```bash
terraform output
```

## Configuration Options

### Basic Configuration

The following variables can be customized in `terraform.tfvars`:

```hcl
# Basic settings
api_name        = "my-blog-api"
table_name      = "MyBlogPosts"
user_pool_name  = "MyBlogUserPool"
environment     = "dev"

# Enable API key authentication for testing
enable_api_key_auth = true

# Create a test user
create_test_user = true
test_username    = "testuser@example.com"
test_password    = "MySecurePassword123!"

# Resource tags
tags = {
  Environment = "development"
  Project     = "my-blog-api"
  Owner       = "my-team"
}
```

### Advanced Configuration

For production deployments, consider these additional settings:

```hcl
# DynamoDB configuration
dynamodb_billing_mode = "PAY_PER_REQUEST"  # or "PROVISIONED"
enable_encryption     = true
enable_point_in_time_recovery = true

# AppSync configuration
log_level            = "ERROR"  # or "ALL" for debugging
enable_xray_tracing = true

# Security settings
enable_api_key_auth = false  # Disable for production
introspection_enabled = false  # Disable for production
```

## File Structure

```
terraform/
├── main.tf                 # Main infrastructure resources
├── variables.tf            # Input variables and validation
├── outputs.tf             # Output values
├── versions.tf            # Provider version constraints
├── schema.graphql         # GraphQL schema definition
├── templates/             # VTL resolver templates
│   ├── response.vtl
│   ├── list_blog_posts_request.vtl
│   ├── list_response.vtl
│   ├── list_by_author_request.vtl
│   ├── create_blog_post_request.vtl
│   ├── update_blog_post_request.vtl
│   └── delete_blog_post_request.vtl
└── README.md              # This file
```

## GraphQL Schema

The API supports the following operations:

### Queries
- `getBlogPost(id: ID!)` - Get a single blog post
- `listBlogPosts(limit: Int, nextToken: String)` - List all blog posts with pagination
- `listBlogPostsByAuthor(author: String!, limit: Int, nextToken: String)` - List posts by author

### Mutations
- `createBlogPost(input: CreateBlogPostInput!)` - Create a new blog post
- `updateBlogPost(input: UpdateBlogPostInput!)` - Update an existing post (author only)
- `deleteBlogPost(id: ID!)` - Delete a blog post (author only)

### Subscriptions
- `onCreateBlogPost` - Real-time notifications for new posts
- `onUpdateBlogPost` - Real-time notifications for updated posts
- `onDeleteBlogPost` - Real-time notifications for deleted posts

## Authentication and Authorization

The API supports two authentication methods:

1. **Cognito User Pool** (Primary)
   - JWT token-based authentication
   - User registration and login
   - Author-based authorization for mutations

2. **API Key** (Optional, for testing)
   - Simple API key authentication
   - Useful for development and testing

## Testing the API

After deployment, you can test the API using:

### 1. AWS AppSync Console

Navigate to the AppSync console and use the built-in query editor:

```
https://console.aws.amazon.com/appsync/home?region=<region>#/apis/<api-id>/v1/home
```

### 2. GraphQL Playground

Use the GraphQL endpoint from the Terraform outputs:

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

### 3. curl Command

```bash
# Get the API key and endpoint from Terraform outputs
API_KEY=$(terraform output -raw api_key)
ENDPOINT=$(terraform output -raw graphql_endpoint)

# Test query
curl -X POST $ENDPOINT \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"query": "query { __typename }"}'
```

## Security Best Practices

### For Production Deployments

1. **Disable API Key Authentication**:
   ```hcl
   enable_api_key_auth = false
   ```

2. **Disable GraphQL Introspection**:
   ```hcl
   introspection_enabled = false
   ```

3. **Enable Encryption and Backup**:
   ```hcl
   enable_encryption = true
   enable_point_in_time_recovery = true
   ```

4. **Use Appropriate Logging**:
   ```hcl
   log_level = "ERROR"
   ```

5. **Enable X-Ray Tracing**:
   ```hcl
   enable_xray_tracing = true
   ```

### Access Control

- **Author-based Authorization**: Users can only update/delete their own blog posts
- **Authenticated Operations**: Create, update, and delete operations require authentication
- **Public Reads**: List and get operations can be made public if needed

## Cost Optimization

### DynamoDB

- Use `PAY_PER_REQUEST` billing mode for unpredictable workloads
- Use `PROVISIONED` billing mode for predictable workloads
- Enable auto-scaling for provisioned capacity

### AppSync

- Costs are based on query and data modification operations
- Real-time subscriptions incur additional costs
- Consider caching to reduce database operations

### Cognito

- Costs are based on monthly active users (MAU)
- First 50,000 MAU per month are free

## Monitoring and Debugging

### CloudWatch Metrics

Monitor the following metrics:

- **AppSync**: Request count, latency, errors
- **DynamoDB**: Read/write capacity, throttles
- **Cognito**: Sign-up, sign-in success rates

### CloudWatch Logs

Enable detailed logging for debugging:

```hcl
log_level = "ALL"
```

### X-Ray Tracing

Enable distributed tracing:

```hcl
enable_xray_tracing = true
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure IAM roles have correct permissions
   - Check trust relationships

2. **Schema Validation Errors**
   - Validate GraphQL schema syntax
   - Ensure resolver field names match schema

3. **Authentication Failures**
   - Check Cognito User Pool configuration
   - Verify JWT token format

4. **DynamoDB Throttling**
   - Increase provisioned capacity
   - Consider switching to on-demand billing

### Useful Commands

```bash
# Check Terraform state
terraform show

# Refresh state
terraform refresh

# Import existing resources
terraform import aws_appsync_graphql_api.blog_api <api-id>

# Validate configuration
terraform validate

# Format code
terraform fmt
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all data in DynamoDB and cannot be undone.

## Contributing

When modifying this infrastructure:

1. Follow Terraform best practices
2. Update documentation
3. Test changes in a development environment
4. Validate with `terraform validate`
5. Format code with `terraform fmt`

## Support

For issues with this infrastructure:

1. Check the [AWS AppSync documentation](https://docs.aws.amazon.com/appsync/)
2. Review [Terraform AWS provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. Check AWS service limits and quotas
4. Review CloudWatch logs and metrics

## License

This code is provided as-is for educational and reference purposes. Please review and modify according to your specific requirements and security policies.