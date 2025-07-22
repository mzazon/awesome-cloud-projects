# Global E-commerce Platform with Aurora DSQL - CDK Python

This CDK Python application deploys a globally distributed e-commerce platform using Amazon Aurora DSQL, AWS Lambda, API Gateway, and CloudFront.

## Architecture

The solution creates:

- **Aurora DSQL Cluster**: Distributed SQL database with multi-region active-active capabilities
- **Lambda Functions**: Serverless compute for product and order processing
- **API Gateway**: REST API with proper CORS configuration
- **CloudFront Distribution**: Global content delivery network
- **IAM Roles**: Secure access control with least-privilege permissions
- **CloudWatch Logs**: Centralized logging for monitoring and debugging

## Prerequisites

1. **AWS Account**: With appropriate permissions for Aurora DSQL, Lambda, API Gateway, CloudFront, and IAM
2. **AWS CLI**: Installed and configured with appropriate credentials
3. **Python**: Version 3.8 or higher
4. **Node.js**: Version 18 or higher (required for CDK)
5. **AWS CDK**: Version 2.167.0 or higher

```bash
# Install AWS CDK if not already installed
npm install -g aws-cdk@latest

# Verify CDK installation
cdk --version
```

## Setup and Installation

1. **Clone or navigate to the project directory**:
   ```bash
   cd aws/global-ecommerce-platforms-aurora-dsql/code/cdk-python/
   ```

2. **Create a virtual environment** (recommended):
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure environment variables**:
   ```bash
   export AWS_REGION=$(aws configure get region)
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export DSQL_CLUSTER_NAME="ecommerce-cluster-$(date +%s)"
   ```

## Deployment

### Step 1: Bootstrap CDK (first time only)

```bash
cdk bootstrap aws://${AWS_ACCOUNT_ID}/${AWS_REGION}
```

### Step 2: Create Aurora DSQL Cluster

The CDK application assumes an Aurora DSQL cluster exists. Create one first:

```bash
# Create Aurora DSQL cluster
aws dsql create-cluster \
    --cluster-name ${DSQL_CLUSTER_NAME} \
    --region ${AWS_REGION} \
    --deletion-protection-enabled

# Wait for cluster to be active
aws dsql wait cluster-available \
    --cluster-name ${DSQL_CLUSTER_NAME} \
    --region ${AWS_REGION}

echo "Aurora DSQL cluster '${DSQL_CLUSTER_NAME}' is ready"
```

### Step 3: Create Database Schema

```bash
# Create database schema file
cat > ecommerce-schema.sql << 'EOF'
-- Create core e-commerce tables
CREATE TABLE customers (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    category VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(customer_id),
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
    order_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(order_id),
    product_id UUID NOT NULL REFERENCES products(product_id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_products_category ON products(category);

-- Insert sample data
INSERT INTO customers (email, first_name, last_name) VALUES
('john.doe@example.com', 'John', 'Doe'),
('jane.smith@example.com', 'Jane', 'Smith'),
('alice.johnson@example.com', 'Alice', 'Johnson');

INSERT INTO products (name, description, price, stock_quantity, category) VALUES
('Wireless Headphones', 'High-quality wireless headphones with noise cancellation', 199.99, 100, 'Electronics'),
('Coffee Mug', 'Ceramic coffee mug with temperature retention', 12.99, 500, 'Home'),
('Laptop Stand', 'Adjustable laptop stand for ergonomic work setup', 49.99, 50, 'Electronics'),
('Bluetooth Speaker', 'Portable Bluetooth speaker with 12-hour battery', 89.99, 75, 'Electronics'),
('Desk Lamp', 'LED desk lamp with adjustable brightness', 34.99, 30, 'Home');
EOF

# Execute schema creation
aws dsql execute-statement \
    --cluster-name ${DSQL_CLUSTER_NAME} \
    --database postgres \
    --statement "$(cat ecommerce-schema.sql)" \
    --region ${AWS_REGION}

echo "Database schema created successfully"
```

### Step 4: Deploy CDK Stack

```bash
# Synthesize the CDK stack (optional - to review generated CloudFormation)
cdk synth --context dsql_cluster_name=${DSQL_CLUSTER_NAME}

# Deploy the stack
cdk deploy --context dsql_cluster_name=${DSQL_CLUSTER_NAME} --require-approval never
```

### Step 5: Get Deployment Outputs

```bash
# Get API Gateway URL
API_URL=$(aws cloudformation describe-stacks \
    --stack-name GlobalEcommerceAuroraDsqlStack \
    --query 'Stacks[0].Outputs[?OutputKey==`EcommerceApiEndpoint`].OutputValue' \
    --output text)

# Get CloudFront distribution URL
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
    --stack-name GlobalEcommerceAuroraDsqlStack \
    --query 'Stacks[0].Outputs[?OutputKey==`EcommerceDistributionDomainName`].OutputValue' \
    --output text)

echo "API Gateway URL: ${API_URL}"
echo "CloudFront URL: https://${CLOUDFRONT_URL}"
```

## Testing the Deployment

### Test Product Endpoints

```bash
# List all products
curl -X GET "${API_URL}/products" \
    -H "Content-Type: application/json"

# Create a new product
curl -X POST "${API_URL}/products" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Test Product",
        "description": "A test product created via API",
        "price": 29.99,
        "stock_quantity": 10,
        "category": "Test"
    }'
```

### Test Order Processing

```bash
# Get a customer ID for testing
CUSTOMER_ID=$(aws dsql execute-statement \
    --cluster-name ${DSQL_CLUSTER_NAME} \
    --database postgres \
    --statement "SELECT customer_id FROM customers LIMIT 1" \
    --query 'records[0][0].stringValue' \
    --output text)

# Get a product ID for testing
PRODUCT_ID=$(aws dsql execute-statement \
    --cluster-name ${DSQL_CLUSTER_NAME} \
    --database postgres \
    --statement "SELECT product_id FROM products LIMIT 1" \
    --query 'records[0][0].stringValue' \
    --output text)

# Create an order
curl -X POST "${API_URL}/orders" \
    -H "Content-Type: application/json" \
    -d "{
        \"customer_id\": \"${CUSTOMER_ID}\",
        \"items\": [
            {
                \"product_id\": \"${PRODUCT_ID}\",
                \"quantity\": 2
            }
        ]
    }"
```

### Test CloudFront Distribution

```bash
# Test via CloudFront (may take 5-10 minutes to propagate)
curl -X GET "https://${CLOUDFRONT_URL}/products" \
    -H "Content-Type: application/json" \
    -w "Response Time: %{time_total}s\n"
```

## Monitoring and Logs

### View Lambda Logs

```bash
# Product function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/GlobalEcommerceAuroraDsql"

# Tail product function logs
aws logs tail /aws/lambda/ecommerce-products --follow

# Tail order function logs
aws logs tail /aws/lambda/ecommerce-orders --follow
```

### View API Gateway Logs

```bash
# API Gateway execution logs
aws logs tail /aws/apigateway/GlobalEcommerceAuroraDsqlStack-EcommerceApi --follow
```

## Configuration Options

You can customize the deployment by modifying the `cdk.json` file or passing context variables:

```bash
# Deploy with custom configuration
cdk deploy \
    --context dsql_cluster_name=my-cluster \
    --context lambda_memory_size_products=512 \
    --context lambda_timeout_seconds=90 \
    --context api_throttle_rate_limit=2000
```

Available configuration options:

- `dsql_cluster_name`: Name of the Aurora DSQL cluster
- `enable_monitoring`: Enable enhanced monitoring (default: true)
- `lambda_memory_size_products`: Memory size for products Lambda (default: 256)
- `lambda_memory_size_orders`: Memory size for orders Lambda (default: 512)
- `lambda_timeout_seconds`: Lambda timeout in seconds (default: 60)
- `api_throttle_rate_limit`: API Gateway throttle rate limit (default: 1000)
- `api_throttle_burst_limit`: API Gateway throttle burst limit (default: 2000)
- `cloudfront_price_class`: CloudFront price class (default: PriceClass_100)
- `log_retention_days`: CloudWatch log retention in days (default: 7)

## Cleanup

To avoid ongoing charges, clean up the resources:

```bash
# Destroy the CDK stack
cdk destroy --context dsql_cluster_name=${DSQL_CLUSTER_NAME}

# Delete the Aurora DSQL cluster
aws dsql delete-cluster --cluster-name ${DSQL_CLUSTER_NAME}

# Clean up local files
rm -f ecommerce-schema.sql
```

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Error**: Make sure you've bootstrapped CDK in your region
2. **Aurora DSQL Access**: Ensure your AWS credentials have Aurora DSQL permissions
3. **Lambda Timeout**: Increase timeout if experiencing timeouts with large orders
4. **API Gateway 5XX Errors**: Check Lambda function logs for detailed error messages
5. **CloudFront Cache**: Remember that CloudFront may cache responses; use cache invalidation if needed

### Debug Commands

```bash
# Check CDK stack status
aws cloudformation describe-stacks --stack-name GlobalEcommerceAuroraDsqlStack

# Check Aurora DSQL cluster status
aws dsql describe-cluster --cluster-name ${DSQL_CLUSTER_NAME}

# Test Lambda function directly
aws lambda invoke \
    --function-name GlobalEcommerceAuroraDsqlStack-ProductFunction-XXXX \
    --payload '{"httpMethod":"GET","path":"/products"}' \
    response.json && cat response.json

# Check API Gateway deployment
aws apigateway get-deployments --rest-api-id $(aws apigateway get-rest-apis \
    --query 'items[?name==`Global E-commerce API`].id' --output text)
```

## Development

### Local Development Setup

```bash
# Install development dependencies
pip install -r requirements.txt[dev]

# Run type checking
mypy app.py

# Format code
black app.py

# Run linting
flake8 app.py
```

### Running Tests

```bash
# Install test dependencies
pip install pytest pytest-cov moto[all]

# Run tests (when test files are added)
pytest tests/ -v --cov=app
```

## Security Considerations

- The Lambda functions use least-privilege IAM permissions
- API Gateway endpoints use CORS configuration for web access
- Aurora DSQL uses AWS IAM for authentication
- CloudFront enforces HTTPS connections
- All resources are tagged for compliance and cost tracking

For production deployments, consider:
- Adding API Gateway authorizers
- Implementing AWS WAF rules
- Using AWS Secrets Manager for sensitive configuration
- Adding VPC endpoints for private communication
- Enabling AWS CloudTrail for audit logging

## Support

For issues related to this CDK application:
1. Check the CloudWatch logs for detailed error messages
2. Verify Aurora DSQL cluster is active and accessible
3. Ensure all required AWS permissions are in place
4. Review the CDK documentation: https://docs.aws.amazon.com/cdk/

For Aurora DSQL specific issues, refer to the [Aurora DSQL User Guide](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/what-is-aurora-dsql.html).