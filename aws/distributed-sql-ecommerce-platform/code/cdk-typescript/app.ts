#!/usr/bin/env node
import 'source-map-support/register';
import { App, Stack, StackProps, Duration, RemovalPolicy, CfnOutput } from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { Construct } from 'constructs';

export interface GlobalEcommercePlatformStackProps extends StackProps {
  readonly dsqlClusterName?: string;
  readonly environment?: string;
}

export class GlobalEcommercePlatformStack extends Stack {
  constructor(scope: Construct, id: string, props?: GlobalEcommercePlatformStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const clusterName = props?.dsqlClusterName || `ecommerce-cluster-${randomSuffix}`;

    // Create IAM role for Lambda functions with Aurora DSQL access
    const lambdaRole = new iam.Role(this, 'EcommerceLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for e-commerce Lambda functions with Aurora DSQL access',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        AuroraDsqlAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dsql:DbConnect',
                'dsql:DbConnectAdmin',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for product operations
    const productFunction = new lambda.Function(this, 'ProductFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'product_handler.lambda_handler',
      role: lambdaRole,
      timeout: Duration.seconds(30),
      memorySize: 256,
      description: 'Lambda function for product CRUD operations with Aurora DSQL',
      environment: {
        DSQL_CLUSTER_NAME: clusterName,
      },
      code: lambda.Code.fromInline(`
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
                    'description': row[2]['stringValue'] if row[2]['stringValue'] else '',
                    'price': float(row[3]['stringValue']),
                    'stock_quantity': int(row[4]['longValue']),
                    'category': row[5]['stringValue'] if row[5]['stringValue'] else ''
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
                    {'name': 'p2', 'value': {'stringValue': body.get('description', '')}},
                    {'name': 'p3', 'value': {'stringValue': str(body['price'])}},
                    {'name': 'p4', 'value': {'longValue': body['stock_quantity']}},
                    {'name': 'p5', 'value': {'stringValue': body.get('category', '')}}
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
`),
    });

    // Create Lambda function for order processing
    const orderFunction = new lambda.Function(this, 'OrderFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'order_handler.lambda_handler',
      role: lambdaRole,
      timeout: Duration.seconds(30),
      memorySize: 256,
      description: 'Lambda function for order processing with Aurora DSQL transactions',
      environment: {
        DSQL_CLUSTER_NAME: clusterName,
      },
      code: lambda.Code.fromInline(`
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
                try:
                    dsql_client.rollback_transaction(
                        clusterName=os.environ['DSQL_CLUSTER_NAME'],
                        transactionId=transaction_id
                    )
                except:
                    pass
                raise e
                
    except Exception as e:
        return {
            'statusCode': 400,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
`),
    });

    // Create API Gateway
    const api = new apigateway.RestApi(this, 'EcommerceApi', {
      restApiName: `ecommerce-api-${randomSuffix}`,
      description: 'Global e-commerce API with Aurora DSQL backend',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      deployOptions: {
        stageName: 'prod',
        throttle: {
          rateLimit: 1000,
          burstLimit: 2000,
        },
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
    });

    // Create API resources and methods
    const productsResource = api.root.addResource('products');
    const ordersResource = api.root.addResource('orders');

    // Add Lambda integrations
    const productIntegration = new apigateway.LambdaIntegration(productFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
    });

    const orderIntegration = new apigateway.LambdaIntegration(orderFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
    });

    // Add methods to products resource
    productsResource.addMethod('GET', productIntegration);
    productsResource.addMethod('POST', productIntegration);

    // Add methods to orders resource
    ordersResource.addMethod('POST', orderIntegration);

    // Create CloudFront distribution for global delivery
    const distribution = new cloudfront.Distribution(this, 'EcommerceDistribution', {
      comment: 'Global e-commerce platform distribution',
      defaultBehavior: {
        origin: new origins.RestApiOrigin(api),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED, // For API responses
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
        compress: true,
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_ALL,
      enableLogging: true,
    });

    // Output important values
    new CfnOutput(this, 'DsqlClusterName', {
      value: clusterName,
      description: 'Aurora DSQL cluster name (must be created manually)',
      exportName: `${this.stackName}-DsqlClusterName`,
    });

    new CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiGatewayUrl`,
    });

    new CfnOutput(this, 'CloudFrontUrl', {
      value: `https://${distribution.distributionDomainName}`,
      description: 'CloudFront distribution URL for global access',
      exportName: `${this.stackName}-CloudFrontUrl`,
    });

    new CfnOutput(this, 'ProductFunctionName', {
      value: productFunction.functionName,
      description: 'Product Lambda function name',
      exportName: `${this.stackName}-ProductFunctionName`,
    });

    new CfnOutput(this, 'OrderFunctionName', {
      value: orderFunction.functionName,
      description: 'Order Lambda function name',
      exportName: `${this.stackName}-OrderFunctionName`,
    });

    new CfnOutput(this, 'LambdaRoleArn', {
      value: lambdaRole.roleArn,
      description: 'Lambda execution role ARN with Aurora DSQL access',
      exportName: `${this.stackName}-LambdaRoleArn`,
    });
  }
}

// CDK Application
const app = new App();

// Get deployment context
const environment = app.node.tryGetContext('environment') || 'development';
const dsqlClusterName = app.node.tryGetContext('dsqlClusterName');

// Create the main stack
new GlobalEcommercePlatformStack(app, 'GlobalEcommercePlatformStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Global E-commerce Platform with Aurora DSQL - serverless, distributed, and scalable',
  dsqlClusterName,
  environment,
  tags: {
    Project: 'GlobalEcommercePlatform',
    Environment: environment,
    ManagedBy: 'CDK',
    Recipe: 'global-ecommerce-platforms-aurora-dsql',
  },
});

app.synth();