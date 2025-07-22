#!/usr/bin/env python3
"""
Global E-commerce Platforms with Aurora DSQL CDK Application

This CDK application deploys a globally distributed e-commerce platform using:
- Aurora DSQL for distributed database
- Lambda functions for serverless compute
- API Gateway for REST API endpoints
- CloudFront for global content delivery
- IAM roles and policies for secure access
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Tags,
    Duration,
    RemovalPolicy,
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_apigateway as apigateway
from aws_cdk import aws_cloudfront as cloudfront
from aws_cdk import aws_cloudfront_origins as origins
from aws_cdk import aws_logs as logs
from constructs import Construct


class GlobalEcommerceAuroraDsqlStack(Stack):
    """
    CDK Stack for Global E-commerce Platform with Aurora DSQL
    
    This stack creates:
    - IAM roles and policies for Lambda functions
    - Lambda functions for product and order operations
    - API Gateway REST API with proper integrations
    - CloudFront distribution for global delivery
    - CloudWatch log groups for monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        dsql_cluster_name: str,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.dsql_cluster_name = dsql_cluster_name

        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()

        # Create Lambda functions
        self.product_function = self._create_product_lambda()
        self.order_function = self._create_order_lambda()

        # Create API Gateway
        self.api = self._create_api_gateway()

        # Create CloudFront distribution
        self.cloudfront_distribution = self._create_cloudfront_distribution()

        # Add stack tags
        self._add_stack_tags()

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with necessary permissions
        
        Returns:
            iam.Role: IAM role with Aurora DSQL and CloudWatch permissions
        """
        lambda_role = iam.Role(
            self,
            "EcommerceLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for e-commerce Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add Aurora DSQL permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dsql:DbConnect",
                    "dsql:DbConnectAdmin",
                    "dsql:ExecuteStatement",
                    "dsql:BeginTransaction",
                    "dsql:CommitTransaction",
                    "dsql:RollbackTransaction",
                ],
                resources=["*"],  # DSQL resources are not specific to clusters
                sid="AuroraDSQLPermissions",
            )
        )

        return lambda_role

    def _create_product_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for product operations (GET and POST)
        
        Returns:
            lambda_.Function: Lambda function for product management
        """
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "ProductLambdaLogGroup",
            log_group_name="/aws/lambda/ecommerce-products",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Lambda function code
        product_code = '''
import json
import boto3
import os
from decimal import Decimal
from typing import Dict, Any, List

# Initialize Aurora DSQL client
dsql_client = boto3.client('dsql')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for product operations
    
    Supports:
    - GET /products - List all products
    - POST /products - Create new product
    """
    try:
        http_method = event.get('httpMethod', 'GET')
        
        if http_method == 'GET':
            return get_products()
        elif http_method == 'POST':
            return create_product(event)
        else:
            return {
                'statusCode': 405,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Method not allowed'})
            }
            
    except Exception as e:
        print(f"Error in product handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def get_products() -> Dict[str, Any]:
    """Get all products from the database"""
    response = dsql_client.execute_statement(
        clusterName=os.environ['DSQL_CLUSTER_NAME'],
        database='postgres',
        statement="""
            SELECT product_id, name, description, price, stock_quantity, category,
                   created_at, updated_at
            FROM products
            ORDER BY created_at DESC
        """
    )
    
    products = []
    for row in response.get('records', []):
        products.append({
            'product_id': row[0].get('stringValue', ''),
            'name': row[1].get('stringValue', ''),
            'description': row[2].get('stringValue', ''),
            'price': float(row[3].get('stringValue', '0')),
            'stock_quantity': int(row[4].get('longValue', 0)),
            'category': row[5].get('stringValue', ''),
            'created_at': row[6].get('stringValue', ''),
            'updated_at': row[7].get('stringValue', '')
        })
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        },
        'body': json.dumps(products, default=str)
    }

def create_product(event: Dict[str, Any]) -> Dict[str, Any]:
    """Create a new product"""
    try:
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        required_fields = ['name', 'description', 'price', 'stock_quantity', 'category']
        for field in required_fields:
            if field not in body:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({'error': f'Missing required field: {field}'})
                }
        
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
                {'name': 'p4', 'value': {'longValue': int(body['stock_quantity'])}},
                {'name': 'p5', 'value': {'stringValue': body['category']}}
            ]
        )
        
        product_id = response['records'][0][0]['stringValue']
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps({
                'product_id': product_id,
                'message': 'Product created successfully'
            })
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
        '''

        function = lambda_.Function(
            self,
            "ProductFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(product_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            description="Lambda function for product operations (GET/POST)",
            environment={
                "DSQL_CLUSTER_NAME": self.dsql_cluster_name,
                "LOG_LEVEL": "INFO"
            },
            log_group=log_group,
        )

        return function

    def _create_order_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for order operations with transaction support
        
        Returns:
            lambda_.Function: Lambda function for order processing
        """
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "OrderLambdaLogGroup",
            log_group_name="/aws/lambda/ecommerce-orders",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Lambda function code
        order_code = '''
import json
import boto3
import os
from decimal import Decimal
from typing import Dict, Any, List

# Initialize Aurora DSQL client
dsql_client = boto3.client('dsql')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for order operations
    
    Supports:
    - POST /orders - Create new order with inventory management
    """
    try:
        http_method = event.get('httpMethod', 'POST')
        
        if http_method == 'POST':
            return create_order(event)
        else:
            return {
                'statusCode': 405,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Method not allowed'})
            }
            
    except Exception as e:
        print(f"Error in order handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def create_order(event: Dict[str, Any]) -> Dict[str, Any]:
    """Create a new order with transaction support"""
    transaction_id = None
    
    try:
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        if 'customer_id' not in body or 'items' not in body:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Missing customer_id or items'})
            }
        
        customer_id = body['customer_id']
        items = body['items']
        
        if not items:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Order must contain at least one item'})
            }
        
        # Start transaction
        transaction_response = dsql_client.begin_transaction(
            clusterName=os.environ['DSQL_CLUSTER_NAME'],
            database='postgres'
        )
        transaction_id = transaction_response['transactionId']
        
        # Verify customer exists
        customer_check = dsql_client.execute_statement(
            clusterName=os.environ['DSQL_CLUSTER_NAME'],
            database='postgres',
            transactionId=transaction_id,
            statement="SELECT customer_id FROM customers WHERE customer_id = $1",
            parameters=[
                {'name': 'p1', 'value': {'stringValue': customer_id}}
            ]
        )
        
        if not customer_check.get('records'):
            raise Exception(f"Customer {customer_id} not found")
        
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
            if 'product_id' not in item or 'quantity' not in item:
                raise Exception("Each item must have product_id and quantity")
            
            product_id = item['product_id']
            quantity = int(item['quantity'])
            
            if quantity <= 0:
                raise Exception(f"Invalid quantity {quantity} for product {product_id}")
            
            # Check stock and get price
            stock_response = dsql_client.execute_statement(
                clusterName=os.environ['DSQL_CLUSTER_NAME'],
                database='postgres',
                transactionId=transaction_id,
                statement="""
                    SELECT price, stock_quantity, name
                    FROM products
                    WHERE product_id = $1
                """,
                parameters=[
                    {'name': 'p1', 'value': {'stringValue': product_id}}
                ]
            )
            
            if not stock_response.get('records'):
                raise Exception(f"Product {product_id} not found")
            
            record = stock_response['records'][0]
            price = Decimal(record[0]['stringValue'])
            stock = int(record[1]['longValue'])
            product_name = record[2]['stringValue']
            
            if stock < quantity:
                raise Exception(f"Insufficient stock for {product_name}. Available: {stock}, Requested: {quantity}")
            
            # Update inventory
            dsql_client.execute_statement(
                clusterName=os.environ['DSQL_CLUSTER_NAME'],
                database='postgres',
                transactionId=transaction_id,
                statement="""
                    UPDATE products
                    SET stock_quantity = stock_quantity - $1,
                        updated_at = CURRENT_TIMESTAMP
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
        
        # Update order total and status
        dsql_client.execute_statement(
            clusterName=os.environ['DSQL_CLUSTER_NAME'],
            database='postgres',
            transactionId=transaction_id,
            statement="""
                UPDATE orders
                SET total_amount = $1, status = $2, updated_at = CURRENT_TIMESTAMP
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
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps({
                'order_id': order_id,
                'total_amount': float(total_amount),
                'status': 'completed',
                'message': 'Order created successfully'
            })
        }
        
    except Exception as e:
        # Rollback transaction if it exists
        if transaction_id:
            try:
                dsql_client.rollback_transaction(
                    clusterName=os.environ['DSQL_CLUSTER_NAME'],
                    transactionId=transaction_id
                )
            except Exception as rollback_error:
                print(f"Error rolling back transaction: {str(rollback_error)}")
        
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
        '''

        function = lambda_.Function(
            self,
            "OrderFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(order_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=512,
            description="Lambda function for order processing with transaction support",
            environment={
                "DSQL_CLUSTER_NAME": self.dsql_cluster_name,
                "LOG_LEVEL": "INFO"
            },
            log_group=log_group,
        )

        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway REST API with Lambda integrations
        
        Returns:
            apigateway.RestApi: Configured API Gateway with product and order endpoints
        """
        # Create REST API
        api = apigateway.RestApi(
            self,
            "EcommerceApi",
            rest_api_name="Global E-commerce API",
            description="REST API for global e-commerce platform with Aurora DSQL",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
            ),
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=["GET", "POST", "OPTIONS"],
                allow_headers=["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key"]
            )
        )

        # Create products resource
        products_resource = api.root.add_resource("products")
        
        # Add GET method for products
        products_resource.add_method(
            "GET",
            apigateway.LambdaIntegration(
                handler=self.product_function,
                proxy=True,
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    }
                )
            ]
        )

        # Add POST method for products
        products_resource.add_method(
            "POST",
            apigateway.LambdaIntegration(
                handler=self.product_function,
                proxy=True,
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="201",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    }
                )
            ]
        )

        # Create orders resource
        orders_resource = api.root.add_resource("orders")
        
        # Add POST method for orders
        orders_resource.add_method(
            "POST",
            apigateway.LambdaIntegration(
                handler=self.order_function,
                proxy=True,
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="201",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    }
                )
            ]
        )

        return api

    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """
        Create CloudFront distribution for global API delivery
        
        Returns:
            cloudfront.Distribution: CloudFront distribution with API Gateway origin
        """
        # Create origin for API Gateway
        api_origin = origins.RestApiOrigin(self.api)

        # Create CloudFront distribution
        distribution = cloudfront.Distribution(
            self,
            "EcommerceDistribution",
            default_behavior=cloudfront.BehaviorOptions(
                origin=api_origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_DISABLED,  # API responses shouldn't be cached
                origin_request_policy=cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
                compress=True,
            ),
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,  # US, Canada, Europe
            comment="Global E-commerce API Distribution",
            enabled=True,
        )

        return distribution

    def _add_stack_tags(self) -> None:
        """Add common tags to all resources in the stack"""
        Tags.of(self).add("Application", "Global E-commerce Platform")
        Tags.of(self).add("Component", "Backend Infrastructure")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Database", "Aurora DSQL")


class GlobalEcommerceAuroraDsqlApp(cdk.App):
    """CDK Application for Global E-commerce Platform"""

    def __init__(self) -> None:
        super().__init__()

        # Get environment variables or use defaults
        dsql_cluster_name = self.node.try_get_context("dsql_cluster_name")
        if not dsql_cluster_name:
            dsql_cluster_name = os.environ.get("DSQL_CLUSTER_NAME", "ecommerce-cluster")

        # Create stack
        GlobalEcommerceAuroraDsqlStack(
            self,
            "GlobalEcommerceAuroraDsqlStack",
            dsql_cluster_name=dsql_cluster_name,
            description="Global E-commerce Platform with Aurora DSQL, Lambda, API Gateway, and CloudFront",
            env=cdk.Environment(
                account=os.getenv("CDK_DEFAULT_ACCOUNT"),
                region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = GlobalEcommerceAuroraDsqlApp()
    app.synth()