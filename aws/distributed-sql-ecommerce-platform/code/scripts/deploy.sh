#!/bin/bash

# Deploy script for Global E-commerce Platform with Aurora DSQL
# This script deploys a complete e-commerce platform using Aurora DSQL, API Gateway, Lambda, and CloudFront

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI and credentials
validate_aws_setup() {
    log_info "Validating AWS setup..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Test AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials are not configured. Please run 'aws configure' or set up AWS credentials."
        exit 1
    fi
    
    log_success "AWS setup validated"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Required commands
    local required_commands=("aws" "jq" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "$cmd is required but not installed."
            exit 1
        fi
    done
    
    # Check AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log_error "AWS_REGION is not set. Please set it as an environment variable or configure AWS CLI."
            exit 1
        fi
    fi
    
    log_info "Using AWS Region: $AWS_REGION"
    
    # Check if Aurora DSQL is available in region
    local supported_regions=("us-east-1" "us-east-2" "us-west-2" "eu-west-1" "eu-west-2" "eu-west-3" "ap-northeast-1" "ap-southeast-1" "ap-southeast-2")
    if [[ ! " ${supported_regions[@]} " =~ " $AWS_REGION " ]]; then
        log_warning "Aurora DSQL may not be available in region $AWS_REGION"
        log_warning "Supported regions: ${supported_regions[*]}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Prerequisites validated"
}

# Function to setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Generate unique suffix for resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
    fi
    
    export DSQL_CLUSTER_NAME="ecommerce-cluster-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="ecommerce-lambda-role-${RANDOM_SUFFIX}"
    export LAMBDA_POLICY_NAME="aurora-dsql-access-${RANDOM_SUFFIX}"
    export PRODUCTS_LAMBDA_NAME="ecommerce-products-${RANDOM_SUFFIX}"
    export ORDERS_LAMBDA_NAME="ecommerce-orders-${RANDOM_SUFFIX}"
    export API_NAME="ecommerce-api-${RANDOM_SUFFIX}"
    export DISTRIBUTION_NAME="ecommerce-cdn-${RANDOM_SUFFIX}"
    
    log_info "Resource suffix: $RANDOM_SUFFIX"
    log_success "Environment variables configured"
}

# Function to create IAM resources
create_iam_resources() {
    log_info "Creating IAM resources..."
    
    # Create Lambda execution role
    log_info "Creating Lambda execution role..."
    aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "lambda.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags Key=Project,Value=EcommerceAuroraDSQL Key=Environment,Value=Demo
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create Aurora DSQL access policy
    log_info "Creating Aurora DSQL access policy..."
    aws iam create-policy \
        --policy-name "$LAMBDA_POLICY_NAME" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "dsql:DbConnect",
                        "dsql:DbConnectAdmin"
                    ],
                    "Resource": "*"
                }
            ]
        }' \
        --tags Key=Project,Value=EcommerceAuroraDSQL Key=Environment,Value=Demo
    
    # Attach Aurora DSQL policy to Lambda role
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}"
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    log_success "IAM resources created"
}

# Function to create Aurora DSQL cluster
create_aurora_dsql_cluster() {
    log_info "Creating Aurora DSQL cluster..."
    
    aws dsql create-cluster \
        --cluster-name "$DSQL_CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --deletion-protection-enabled \
        --tags Key=Project,Value=EcommerceAuroraDSQL Key=Environment,Value=Demo
    
    log_info "Waiting for Aurora DSQL cluster to be available..."
    aws dsql wait cluster-available \
        --cluster-name "$DSQL_CLUSTER_NAME" \
        --region "$AWS_REGION"
    
    export DSQL_ENDPOINT=$(aws dsql describe-cluster \
        --cluster-name "$DSQL_CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'Cluster.ClusterEndpoint' \
        --output text)
    
    log_success "Aurora DSQL cluster created: $DSQL_ENDPOINT"
}

# Function to create database schema
create_database_schema() {
    log_info "Creating database schema..."
    
    # Create schema file
    cat > /tmp/ecommerce-schema.sql << 'EOF'
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
('jane.smith@example.com', 'Jane', 'Smith');

INSERT INTO products (name, description, price, stock_quantity, category) VALUES
('Wireless Headphones', 'High-quality wireless headphones', 199.99, 100, 'Electronics'),
('Coffee Mug', 'Ceramic coffee mug', 12.99, 500, 'Home'),
('Laptop Stand', 'Adjustable laptop stand', 49.99, 50, 'Electronics');
EOF
    
    # Execute schema creation
    aws dsql execute-statement \
        --cluster-name "$DSQL_CLUSTER_NAME" \
        --database postgres \
        --statement "$(cat /tmp/ecommerce-schema.sql)" \
        --region "$AWS_REGION"
    
    # Clean up temp file
    rm -f /tmp/ecommerce-schema.sql
    
    log_success "Database schema created with sample data"
}

# Function to create Lambda functions
create_lambda_functions() {
    log_info "Creating Lambda functions..."
    
    # Create working directory
    mkdir -p /tmp/lambda-package
    cd /tmp/lambda-package
    
    # Create product handler
    cat > product-handler.py << 'EOF'
import json
import boto3
import os
from decimal import Decimal

# Initialize Aurora DSQL client
dsql_client = boto3.client('dsql')

def lambda_handler(event, context):
    try:
        http_method = event['httpMethod']
        
        if http_method == 'GET':
            # Get all products
            response = dsql_client.execute_statement(
                clusterName=os.environ['DSQL_CLUSTER_NAME'],
                database='postgres',
                statement="""
                    SELECT product_id, name, description, price, stock_quantity, category
                    FROM products
                    ORDER BY created_at DESC
                """
            )
            
            products = []
            for row in response.get('records', []):
                products.append({
                    'product_id': row[0]['stringValue'],
                    'name': row[1]['stringValue'],
                    'description': row[2]['stringValue'],
                    'price': float(row[3]['stringValue']),
                    'stock_quantity': int(row[4]['longValue']),
                    'category': row[5]['stringValue']
                })
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(products)
            }
        
        elif http_method == 'POST':
            # Create new product
            body = json.loads(event['body'])
            
            response = dsql_client.execute_statement(
                clusterName=os.environ['DSQL_CLUSTER_NAME'],
                database='postgres',
                statement="""
                    INSERT INTO products (name, description, price, stock_quantity, category)
                    VALUES ($1, $2, $3, $4, $5)
                    RETURNING product_id
                """,
                parameters=[
                    {'name': 'p1', 'value': {'stringValue': body['name']}},
                    {'name': 'p2', 'value': {'stringValue': body['description']}},
                    {'name': 'p3', 'value': {'stringValue': str(body['price'])}},
                    {'name': 'p4', 'value': {'longValue': body['stock_quantity']}},
                    {'name': 'p5', 'value': {'stringValue': body['category']}}
                ]
            )
            
            product_id = response['records'][0][0]['stringValue']
            
            return {
                'statusCode': 201,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'product_id': product_id})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment package for products
    zip -r product-handler.zip product-handler.py
    
    # Deploy products Lambda function
    aws lambda create-function \
        --function-name "$PRODUCTS_LAMBDA_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler product-handler.lambda_handler \
        --zip-file fileb://product-handler.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{DSQL_CLUSTER_NAME=${DSQL_CLUSTER_NAME}}" \
        --tags Project=EcommerceAuroraDSQL,Environment=Demo
    
    log_success "Products Lambda function deployed"
    
    # Create order handler
    cat > order-handler.py << 'EOF'
import json
import boto3
import os
from decimal import Decimal

# Initialize Aurora DSQL client
dsql_client = boto3.client('dsql')

def lambda_handler(event, context):
    try:
        http_method = event['httpMethod']
        
        if http_method == 'POST':
            # Process new order
            body = json.loads(event['body'])
            customer_id = body['customer_id']
            items = body['items']
            
            # Start transaction
            transaction_id = dsql_client.begin_transaction(
                clusterName=os.environ['DSQL_CLUSTER_NAME'],
                database='postgres'
            )['transactionId']
            
            try:
                # Create order record
                order_response = dsql_client.execute_statement(
                    clusterName=os.environ['DSQL_CLUSTER_NAME'],
                    database='postgres',
                    transactionId=transaction_id,
                    statement="""
                        INSERT INTO orders (customer_id, total_amount, status)
                        VALUES ($1, $2, $3)
                        RETURNING order_id
                    """,
                    parameters=[
                        {'name': 'p1', 'value': {'stringValue': customer_id}},
                        {'name': 'p2', 'value': {'stringValue': '0.00'}},
                        {'name': 'p3', 'value': {'stringValue': 'processing'}}
                    ]
                )
                
                order_id = order_response['records'][0][0]['stringValue']
                total_amount = Decimal('0.00')
                
                # Process each item
                for item in items:
                    product_id = item['product_id']
                    quantity = item['quantity']
                    
                    # Check stock and get price
                    stock_response = dsql_client.execute_statement(
                        clusterName=os.environ['DSQL_CLUSTER_NAME'],
                        database='postgres',
                        transactionId=transaction_id,
                        statement="""
                            SELECT price, stock_quantity
                            FROM products
                            WHERE product_id = $1
                        """,
                        parameters=[
                            {'name': 'p1', 'value': {'stringValue': product_id}}
                        ]
                    )
                    
                    if not stock_response['records']:
                        raise Exception(f"Product {product_id} not found")
                    
                    price = Decimal(stock_response['records'][0][0]['stringValue'])
                    stock = int(stock_response['records'][0][1]['longValue'])
                    
                    if stock < quantity:
                        raise Exception(f"Insufficient stock for product {product_id}")
                    
                    # Update inventory
                    dsql_client.execute_statement(
                        clusterName=os.environ['DSQL_CLUSTER_NAME'],
                        database='postgres',
                        transactionId=transaction_id,
                        statement="""
                            UPDATE products
                            SET stock_quantity = stock_quantity - $1
                            WHERE product_id = $2
                        """,
                        parameters=[
                            {'name': 'p1', 'value': {'longValue': quantity}},
                            {'name': 'p2', 'value': {'stringValue': product_id}}
                        ]
                    )
                    
                    # Add order item
                    dsql_client.execute_statement(
                        clusterName=os.environ['DSQL_CLUSTER_NAME'],
                        database='postgres',
                        transactionId=transaction_id,
                        statement="""
                            INSERT INTO order_items (order_id, product_id, quantity, unit_price)
                            VALUES ($1, $2, $3, $4)
                        """,
                        parameters=[
                            {'name': 'p1', 'value': {'stringValue': order_id}},
                            {'name': 'p2', 'value': {'stringValue': product_id}},
                            {'name': 'p3', 'value': {'longValue': quantity}},
                            {'name': 'p4', 'value': {'stringValue': str(price)}}
                        ]
                    )
                    
                    total_amount += price * quantity
                
                # Update order total
                dsql_client.execute_statement(
                    clusterName=os.environ['DSQL_CLUSTER_NAME'],
                    database='postgres',
                    transactionId=transaction_id,
                    statement="""
                        UPDATE orders
                        SET total_amount = $1, status = $2
                        WHERE order_id = $3
                    """,
                    parameters=[
                        {'name': 'p1', 'value': {'stringValue': str(total_amount)}},
                        {'name': 'p2', 'value': {'stringValue': 'completed'}},
                        {'name': 'p3', 'value': {'stringValue': order_id}}
                    ]
                )
                
                # Commit transaction
                dsql_client.commit_transaction(
                    clusterName=os.environ['DSQL_CLUSTER_NAME'],
                    transactionId=transaction_id
                )
                
                return {
                    'statusCode': 201,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'order_id': order_id,
                        'total_amount': float(total_amount)
                    })
                }
                
            except Exception as e:
                # Rollback transaction
                dsql_client.rollback_transaction(
                    clusterName=os.environ['DSQL_CLUSTER_NAME'],
                    transactionId=transaction_id
                )
                raise e
                
    except Exception as e:
        return {
            'statusCode': 400,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment package for orders
    zip -r order-handler.zip order-handler.py
    
    # Deploy orders Lambda function
    aws lambda create-function \
        --function-name "$ORDERS_LAMBDA_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler order-handler.lambda_handler \
        --zip-file fileb://order-handler.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{DSQL_CLUSTER_NAME=${DSQL_CLUSTER_NAME}}" \
        --tags Project=EcommerceAuroraDSQL,Environment=Demo
    
    log_success "Orders Lambda function deployed"
    
    # Clean up
    cd - >/dev/null
    rm -rf /tmp/lambda-package
}

# Function to create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway..."
    
    # Create REST API
    export API_ID=$(aws apigateway create-rest-api \
        --name "$API_NAME" \
        --description "E-commerce API with Aurora DSQL" \
        --query 'id' --output text)
    
    # Get root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[0].id' --output text)
    
    # Create products resource
    export PRODUCTS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ROOT_RESOURCE_ID" \
        --path-part products \
        --query 'id' --output text)
    
    # Create orders resource
    export ORDERS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ROOT_RESOURCE_ID" \
        --path-part orders \
        --query 'id' --output text)
    
    # Get Lambda function ARNs
    export PRODUCTS_LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$PRODUCTS_LAMBDA_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    export ORDERS_LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$ORDERS_LAMBDA_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    log_success "API Gateway resources created"
}

# Function to configure API Gateway methods
configure_api_methods() {
    log_info "Configuring API Gateway methods..."
    
    # Add GET method for products
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$PRODUCTS_RESOURCE_ID" \
        --http-method GET \
        --authorization-type NONE
    
    # Add POST method for products
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$PRODUCTS_RESOURCE_ID" \
        --http-method POST \
        --authorization-type NONE
    
    # Add POST method for orders
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$ORDERS_RESOURCE_ID" \
        --http-method POST \
        --authorization-type NONE
    
    # Configure Lambda integrations
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$PRODUCTS_RESOURCE_ID" \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${PRODUCTS_LAMBDA_ARN}/invocations"
    
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$PRODUCTS_RESOURCE_ID" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${PRODUCTS_LAMBDA_ARN}/invocations"
    
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$ORDERS_RESOURCE_ID" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${ORDERS_LAMBDA_ARN}/invocations"
    
    # Grant API Gateway permissions to invoke Lambda functions
    aws lambda add-permission \
        --function-name "$PRODUCTS_LAMBDA_NAME" \
        --statement-id apigateway-invoke-products \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
    
    aws lambda add-permission \
        --function-name "$ORDERS_LAMBDA_NAME" \
        --statement-id apigateway-invoke-orders \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
    
    # Deploy API to prod stage
    aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name prod
    
    export API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    log_success "API Gateway deployed at: $API_URL"
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    log_info "Creating CloudFront distribution..."
    
    # Create CloudFront distribution configuration
    cat > /tmp/cloudfront-config.json << EOF
{
    "CallerReference": "ecommerce-${RANDOM_SUFFIX}-$(date +%s)",
    "Comment": "E-commerce API distribution",
    "DefaultCacheBehavior": {
        "TargetOriginId": "api-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {
                "Forward": "all"
            },
            "Headers": {
                "Quantity": 4,
                "Items": ["Authorization", "Content-Type", "Accept", "Origin"]
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 0
    },
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "api-origin",
                "DomainName": "${API_ID}.execute-api.${AWS_REGION}.amazonaws.com",
                "OriginPath": "/prod",
                "CustomOriginConfig": {
                    "HTTPPort": 443,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only"
                }
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_All"
}
EOF
    
    # Create CloudFront distribution
    export DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/cloudfront-config.json \
        --query 'Distribution.Id' --output text)
    
    # Get CloudFront domain name
    export CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'Distribution.DomainName' --output text)
    
    # Clean up temp file
    rm -f /tmp/cloudfront-config.json
    
    log_success "CloudFront distribution created: $CLOUDFRONT_DOMAIN"
    log_warning "CloudFront distribution is deploying (this may take 10-15 minutes)"
}

# Function to save deployment info
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > /tmp/deployment-info.json << EOF
{
    "deployment_id": "ecommerce-aurora-dsql-${RANDOM_SUFFIX}",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "region": "${AWS_REGION}",
    "resources": {
        "aurora_dsql_cluster": "${DSQL_CLUSTER_NAME}",
        "lambda_role": "${LAMBDA_ROLE_NAME}",
        "lambda_policy": "${LAMBDA_POLICY_NAME}",
        "products_lambda": "${PRODUCTS_LAMBDA_NAME}",
        "orders_lambda": "${ORDERS_LAMBDA_NAME}",
        "api_gateway": "${API_ID}",
        "cloudfront_distribution": "${DISTRIBUTION_ID}"
    },
    "endpoints": {
        "api_url": "${API_URL}",
        "cloudfront_domain": "https://${CLOUDFRONT_DOMAIN}",
        "dsql_endpoint": "${DSQL_ENDPOINT}"
    }
}
EOF
    
    cp /tmp/deployment-info.json ./ecommerce-deployment-${RANDOM_SUFFIX}.json
    
    log_success "Deployment information saved to ecommerce-deployment-${RANDOM_SUFFIX}.json"
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    # Test Aurora DSQL cluster
    local cluster_status=$(aws dsql describe-cluster \
        --cluster-name "$DSQL_CLUSTER_NAME" \
        --query 'Cluster.Status' --output text)
    
    if [[ "$cluster_status" == "ACTIVE" ]]; then
        log_success "Aurora DSQL cluster is active"
    else
        log_warning "Aurora DSQL cluster status: $cluster_status"
    fi
    
    # Test API endpoints
    log_info "Testing API endpoints..."
    
    # Test GET products (with retry)
    local max_retries=3
    local retry_count=0
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -s -f -X GET "$API_URL/products" -H "Content-Type: application/json" >/dev/null; then
            log_success "Products API endpoint is responding"
            break
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_info "API not ready, retrying in 10 seconds... ($retry_count/$max_retries)"
                sleep 10
            else
                log_warning "Products API endpoint test failed after $max_retries attempts"
            fi
        fi
    done
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    echo
    echo "=================================="
    echo "  DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo
    log_info "Aurora DSQL Cluster: $DSQL_CLUSTER_NAME"
    log_info "API Gateway URL: $API_URL"
    log_info "CloudFront Domain: https://$CLOUDFRONT_DOMAIN"
    echo
    log_info "Test your deployment:"
    echo "  # Get products"
    echo "  curl -X GET '$API_URL/products'"
    echo
    echo "  # Create a product"
    echo "  curl -X POST '$API_URL/products' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"name\":\"Test Product\",\"description\":\"Test\",\"price\":29.99,\"stock_quantity\":10,\"category\":\"Test\"}'"
    echo
    log_info "Deployment info saved to: ecommerce-deployment-${RANDOM_SUFFIX}.json"
    log_warning "CloudFront distribution may take 10-15 minutes to be fully deployed"
    echo
}

# Main deployment function
main() {
    log_info "Starting Global E-commerce Platform deployment with Aurora DSQL"
    
    # Run all deployment steps
    validate_aws_setup
    check_prerequisites
    setup_environment
    create_iam_resources
    create_aurora_dsql_cluster
    create_database_schema
    create_lambda_functions
    create_api_gateway
    configure_api_methods
    create_cloudfront_distribution
    save_deployment_info
    run_validation_tests
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Run destroy.sh to clean up any created resources."; exit 1' INT TERM

# Run main function
main "$@"