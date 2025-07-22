# Infrastructure as Code for Global E-commerce with Distributed SQL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Global E-commerce with Distributed SQL".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a globally distributed e-commerce platform using:

- **Aurora DSQL**: Serverless, distributed SQL database with multi-region capabilities
- **API Gateway**: REST API endpoints for product and order management
- **Lambda**: Serverless compute for business logic
- **CloudFront**: Global content delivery network for reduced latency
- **IAM**: Secure access control and service permissions

## Prerequisites

- AWS CLI installed and configured (v2.0 or later)
- Appropriate AWS permissions for:
  - Aurora DSQL cluster management
  - API Gateway creation and configuration
  - Lambda function deployment
  - CloudFront distribution management
  - IAM role and policy creation
- Basic knowledge of SQL, REST APIs, and serverless architectures
- Understanding of e-commerce transaction patterns

## Cost Considerations

**Estimated monthly costs for development environment:**
- Aurora DSQL: $50-150 (scales with usage)
- Lambda: $10-50 (based on request volume)
- API Gateway: $5-25 (per million requests)
- CloudFront: $10-30 (data transfer and requests)
- **Total: $200-400/month** (scales with actual usage)

> **Warning**: These are development estimates. Production costs will vary based on traffic patterns, data storage, and geographic distribution.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name ecommerce-aurora-dsql-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ClusterName,ParameterValue=ecommerce-cluster \
        ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name ecommerce-aurora-dsql-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint
aws cloudformation describe-stacks \
    --stack-name ecommerce-aurora-dsql-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
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

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack information
cdk list
cdk diff
```

### Using Terraform

```bash
# Navigate to Terraform directory
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

# Check deployment status
# The script will provide endpoint URLs and resource identifiers
```

## Testing the Deployment

Once deployed, test your e-commerce platform:

### 1. Test Product API

```bash
# Set your API endpoint (replace with actual endpoint)
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/prod"

# Get all products
curl -X GET "${API_ENDPOINT}/products" \
    -H "Content-Type: application/json"

# Create a new product
curl -X POST "${API_ENDPOINT}/products" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Wireless Headphones Pro",
        "description": "Premium wireless headphones with noise cancellation",
        "price": 299.99,
        "stock_quantity": 50,
        "category": "Electronics"
    }'
```

### 2. Test Order Processing

```bash
# Create an order (replace customer_id and product_id with actual values)
curl -X POST "${API_ENDPOINT}/orders" \
    -H "Content-Type: application/json" \
    -d '{
        "customer_id": "your-customer-uuid",
        "items": [
            {
                "product_id": "your-product-uuid",
                "quantity": 2
            }
        ]
    }'
```

### 3. Test Global Performance

```bash
# Test CloudFront global distribution
CLOUDFRONT_DOMAIN="your-distribution.cloudfront.net"

curl -X GET "https://${CLOUDFRONT_DOMAIN}/products" \
    -H "Content-Type: application/json" \
    -w "Response time: %{time_total}s\n"
```

## Configuration

### Environment Variables

The following environment variables can be set to customize deployment:

```bash
export AWS_REGION=us-east-1
export CLUSTER_NAME=ecommerce-cluster-prod
export ENVIRONMENT=production
export API_STAGE=prod
```

### Customization Options

Each IaC implementation supports customization through variables:

- **Cluster Name**: Aurora DSQL cluster identifier
- **Environment**: Deployment environment (dev, staging, prod)
- **API Stage**: API Gateway deployment stage
- **Lambda Memory**: Memory allocation for Lambda functions
- **CloudFront Price Class**: Global distribution scope

Refer to the variable definitions in each implementation directory for complete customization options.

## Multi-Region Deployment

For true global distribution, consider deploying in multiple regions:

1. **Primary Region**: us-east-1 (North Virginia)
2. **Secondary Regions**: eu-west-1 (Ireland), ap-northeast-1 (Tokyo)

> **Note**: Aurora DSQL automatically handles multi-region synchronization within the same region set. Cross-region-set deployments require separate clusters with application-level synchronization.

## Monitoring and Observability

After deployment, monitor your platform:

```bash
# CloudWatch Metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DSQL \
    --metric-name DatabaseConnections \
    --dimensions Name=ClusterName,Value=your-cluster-name \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 300 \
    --statistics Average

# Lambda Function Logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/ecommerce

# API Gateway Access Logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/apigateway
```

## Security Considerations

This implementation includes several security best practices:

- **IAM Roles**: Least privilege access for all services
- **API Gateway**: HTTPS-only endpoints with request validation
- **Aurora DSQL**: Encrypted connections and IAM database authentication
- **Lambda**: VPC configuration and security groups (when applicable)
- **CloudFront**: SSL/TLS certificates and security headers

### Additional Security Hardening

For production deployments, consider:

1. **API Authentication**: Implement Cognito User Pools or custom authorizers
2. **WAF Integration**: Add AWS WAF rules for API protection
3. **VPC Configuration**: Deploy Lambda functions in private subnets
4. **Secrets Management**: Use AWS Secrets Manager for database credentials
5. **Audit Logging**: Enable CloudTrail for all API calls

## Troubleshooting

### Common Issues

1. **Aurora DSQL Connection Failures**
   ```bash
   # Check cluster status
   aws dsql describe-cluster --cluster-name your-cluster-name
   
   # Verify IAM permissions
   aws sts get-caller-identity
   ```

2. **Lambda Function Errors**
   ```bash
   # View function logs
   aws logs tail /aws/lambda/your-function-name --follow
   
   # Check function configuration
   aws lambda get-function --function-name your-function-name
   ```

3. **API Gateway 5xx Errors**
   ```bash
   # Enable CloudWatch logging for API Gateway
   aws apigateway get-stage --rest-api-id your-api-id --stage-name prod
   
   # Check execution logs
   aws logs tail /aws/apigateway/your-api-id --follow
   ```

### Performance Optimization

- Monitor Lambda cold start times and consider provisioned concurrency
- Implement API Gateway caching for frequently accessed data
- Use Aurora DSQL connection pooling in Lambda functions
- Optimize CloudFront cache behaviors for your API patterns

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ecommerce-aurora-dsql-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name ecommerce-aurora-dsql-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy

# Deactivate virtual environment (if used)
deactivate
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

> **Warning**: Cleanup operations will permanently delete all resources including databases and stored data. Ensure you have proper backups before proceeding.

## Advanced Features

### Extending the Platform

1. **Real-time Inventory Updates**: Integrate with EventBridge for inventory change notifications
2. **Advanced Analytics**: Add Amazon QuickSight dashboards for business intelligence
3. **Machine Learning**: Implement Amazon Personalize for product recommendations
4. **Event-Driven Architecture**: Use Step Functions for complex order workflows
5. **Multi-tenant Support**: Extend the data model for SaaS e-commerce platforms

### Integration Examples

```bash
# Add EventBridge rule for inventory notifications
aws events put-rule \
    --name inventory-updates \
    --event-pattern '{
        "source": ["ecommerce.inventory"],
        "detail-type": ["Stock Level Changed"]
    }'

# Create CloudWatch dashboard
aws cloudwatch put-dashboard \
    --dashboard-name ecommerce-metrics \
    --dashboard-body file://dashboard-config.json
```

## Support and Resources

- **AWS Aurora DSQL Documentation**: https://docs.aws.amazon.com/aurora-dsql/
- **API Gateway Best Practices**: https://docs.aws.amazon.com/apigateway/latest/developerguide/best-practices.html
- **Lambda Performance Optimization**: https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html
- **CloudFront Configuration Guide**: https://docs.aws.amazon.com/cloudfront/latest/developerguide/

For issues with this infrastructure code, refer to the original recipe documentation or AWS support channels.

## License

This infrastructure code is provided as-is under the MIT License. See individual component licenses for specific terms and conditions.