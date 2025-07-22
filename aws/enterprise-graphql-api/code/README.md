# Infrastructure as Code for Enterprise GraphQL API Architecture

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise GraphQL API Architecture".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive GraphQL API ecosystem using:
- AWS AppSync for managed GraphQL API with real-time subscriptions
- DynamoDB tables for transactional data with Global Secondary Indexes
- OpenSearch Service for advanced search capabilities
- Lambda functions for custom business logic
- Cognito User Pool for authentication and authorization
- IAM roles and policies for secure access control

## Prerequisites

- AWS CLI v2 installed and configured (`aws --version` to verify)
- Appropriate AWS permissions for creating:
  - AppSync APIs and resolvers
  - DynamoDB tables and indexes
  - OpenSearch domains
  - Lambda functions and layers
  - Cognito User Pools
  - IAM roles and policies
- Advanced understanding of GraphQL concepts
- Node.js 18+ (for CDK TypeScript implementation)
- Python 3.9+ (for CDK Python implementation)
- Terraform 1.0+ (for Terraform implementation)

### Cost Considerations

- **Development**: $50-150/month (includes OpenSearch t3.small.search instance at ~$15/month)
- **Production**: Costs scale with usage; consider reserved instances for OpenSearch
- **Key cost drivers**: OpenSearch domain, Lambda invocations, DynamoDB requests, data transfer

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete stack
aws cloudformation create-stack \
    --stack-name graphql-appsync-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=ecommerce-api

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name graphql-appsync-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint
aws cloudformation describe-stacks \
    --stack-name graphql-appsync-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`GraphQLEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
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

# View stack information
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
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

# The script will output:
# - GraphQL API endpoint
# - Real-time endpoint
# - API key for testing
# - Cognito User Pool details
```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Base name for all resources (default: ecommerce-api)
- `Environment`: Environment name (default: dev)
- `OpenSearchInstanceType`: Instance type for OpenSearch (default: t3.small.search)
- `DynamoDBBillingMode`: Billing mode for DynamoDB tables (default: PAY_PER_REQUEST)

### CDK Configuration

Both CDK implementations support these context variables:
- `projectName`: Base name for resources
- `environment`: Environment identifier
- `openSearchInstanceType`: OpenSearch instance type
- `enableEnhancedMonitoring`: Enable detailed monitoring (default: true)

### Terraform Variables

- `project_name`: Base name for all resources
- `aws_region`: AWS region for deployment
- `environment`: Environment name
- `opensearch_instance_type`: OpenSearch instance type
- `enable_xray_tracing`: Enable AWS X-Ray tracing

## Testing the Deployment

After deployment, test your GraphQL API:

### Using API Key Authentication

```bash
# Get API key from outputs
API_KEY=$(aws appsync list-api-keys --api-id <API_ID> --query 'apiKeys[0].id' --output text)

# Test query
curl -X POST \
    -H "Content-Type: application/json" \
    -H "x-api-key: $API_KEY" \
    -d '{
        "query": "query GetProduct($productId: ID!) { getProduct(productId: $productId) { productId name price category } }",
        "variables": { "productId": "prod-001" }
    }' \
    <GRAPHQL_ENDPOINT>
```

### Using AppSync Console

1. Navigate to AWS AppSync Console
2. Select your API
3. Use the Query explorer for interactive testing
4. Test subscriptions for real-time functionality

### Sample Queries

```graphql
# List products by category
query ListElectronics {
  listProductsByCategory(category: "electronics", limit: 5) {
    items {
      productId
      name
      price
      inStock
      rating
      reviewCount
    }
    nextToken
  }
}

# Create a new product (requires authentication)
mutation CreateProduct {
  createProduct(input: {
    name: "Wireless Mouse"
    description: "Ergonomic wireless mouse"
    price: 29.99
    category: "electronics"
    tags: ["wireless", "computer", "accessory"]
  }) {
    productId
    name
    createdAt
  }
}

# Subscribe to new products
subscription OnNewProduct {
  onCreateProduct {
    productId
    name
    category
    price
  }
}
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

- **CloudWatch Logs**: API request/response logging
- **X-Ray Tracing**: Distributed tracing for performance analysis
- **CloudWatch Metrics**: API performance and error metrics
- **Custom Dashboards**: Pre-configured monitoring dashboards

### Key Metrics to Monitor

- GraphQL request latency
- DynamoDB throttling events
- Lambda function errors and duration
- OpenSearch cluster health
- API authentication failures

## Security Features

The implementation includes enterprise-grade security:

- **Multi-factor Authentication**: Cognito User Pools with MFA support
- **Fine-grained Authorization**: GraphQL directive-based access control
- **Encryption**: Data encrypted at rest and in transit
- **VPC Integration**: Optional VPC deployment for network isolation
- **WAF Integration**: Web Application Firewall for API protection

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this removes all resources)
aws cloudformation delete-stack --stack-name graphql-appsync-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name graphql-appsync-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Script includes confirmation prompts for safety
```

## Customization

### Adding New GraphQL Operations

1. **Update Schema**: Modify the GraphQL schema file
2. **Create Resolvers**: Add VTL templates for new operations
3. **Update IAM Policies**: Ensure proper permissions for new data sources
4. **Test Operations**: Validate new functionality in AppSync console

### Integrating Additional Data Sources

1. **Lambda Data Sources**: For external API integrations
2. **HTTP Data Sources**: For REST API endpoints
3. **RDS Data Sources**: For relational database integration
4. **ElasticSearch**: For advanced search capabilities

### Environment-Specific Configurations

Use parameter files or environment variables to customize deployments:

```bash
# CloudFormation with parameters file
aws cloudformation create-stack \
    --stack-name graphql-appsync-prod \
    --template-body file://cloudformation.yaml \
    --parameters file://prod-parameters.json

# Terraform with variable files
terraform apply -var-file="prod.tfvars"
```

## Troubleshooting

### Common Issues

1. **OpenSearch Domain Creation Timeout**
   - OpenSearch domains take 15-20 minutes to create
   - Check domain status in AWS Console

2. **Lambda Function Timeout**
   - Increase memory allocation (affects CPU)
   - Optimize function code for performance

3. **DynamoDB Throttling**
   - Switch to provisioned capacity for predictable workloads
   - Implement exponential backoff in application code

4. **GraphQL Schema Validation Errors**
   - Validate schema syntax before deployment
   - Check for unsupported directives or types

### Debugging Tools

- **AppSync Query Logs**: Enable field-level logging
- **X-Ray Service Map**: Visualize request flows
- **CloudWatch Insights**: Query structured logs
- **AWS CLI**: Validate resource configurations

## Performance Optimization

### Caching Strategies

- **Resolver-level Caching**: Configure TTL per resolver
- **Full Request Caching**: Cache complete GraphQL responses
- **DynamoDB DAX**: In-memory acceleration for hot data

### DynamoDB Optimization

- **Efficient Access Patterns**: Use GSIs for query optimization
- **Hot Partitioning**: Distribute data across partitions
- **Item Size**: Keep items under 400KB for optimal performance

### Lambda Optimization

- **Memory Allocation**: Right-size for CPU requirements
- **Connection Pooling**: Reuse database connections
- **Cold Start Mitigation**: Use provisioned concurrency for critical functions

## Support

- **AWS Documentation**: [AppSync Developer Guide](https://docs.aws.amazon.com/appsync/latest/devguide/)
- **GraphQL Specification**: [GraphQL.org](https://graphql.org/)
- **Community Support**: AWS Developer Forums
- **Professional Support**: AWS Support Plans

For issues specific to this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## Next Steps

After successful deployment, consider these enhancements:

1. **Mobile Integration**: Use AWS Amplify for React Native/Flutter apps
2. **Advanced Analytics**: Implement real-time analytics with Kinesis
3. **Multi-Region Deployment**: Extend to multiple AWS regions
4. **DevOps Integration**: Automate deployment with CI/CD pipelines
5. **Cost Optimization**: Implement reserved capacity for predictable workloads