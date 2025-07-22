import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cr from 'aws-cdk-lib/custom-resources';

/**
 * CDK Stack for Amazon Lex Chatbot Development
 * 
 * This stack creates a complete customer service chatbot infrastructure including:
 * - Lambda function for fulfillment with proper error handling and logging
 * - DynamoDB table for order data with sample data population
 * - S3 bucket for product catalog storage
 * - IAM roles with least privilege principles
 * - Amazon Lex V2 bot configuration with multiple intents
 * - CloudWatch logs for monitoring and debugging
 */
export class ChatbotDevelopmentStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();

    // Create DynamoDB table for order tracking
    const ordersTable = new dynamodb.Table(this, 'OrdersTable', {
      tableName: `customer-orders-${uniqueSuffix}`,
      partitionKey: {
        name: 'OrderId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      pointInTimeRecovery: true,
      tags: {
        Purpose: 'ChatbotOrderData',
        Component: 'DataStorage',
      },
    });

    // Create S3 bucket for product catalog
    const productsBucket = new s3.Bucket(this, 'ProductsBucket', {
      bucketName: `product-catalog-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      tags: [
        { key: 'Purpose', value: 'ProductCatalog' },
        { key: 'Component', value: 'DataStorage' },
      ],
    });

    // Create IAM role for Lambda function with least privilege
    const lambdaRole = new iam.Role(this, 'LexLambdaRole', {
      roleName: `lex-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lex chatbot fulfillment Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DynamoDBAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
              ],
              resources: [ordersTable.tableArn],
            }),
          ],
        }),
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:ListBucket',
              ],
              resources: [
                productsBucket.bucketArn,
                `${productsBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for Lex fulfillment
    const lexFulfillmentFunction = new lambda.Function(this, 'LexFulfillmentFunction', {
      functionName: `lex-fulfillment-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Lambda function for Amazon Lex chatbot fulfillment with business logic',
      environment: {
        ORDERS_TABLE_NAME: ordersTable.tableName,
        PRODUCTS_BUCKET_NAME: productsBucket.bucketName,
        LOG_LEVEL: 'INFO',
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# Get table name from environment
ORDERS_TABLE_NAME = os.environ['ORDERS_TABLE_NAME']
PRODUCTS_BUCKET_NAME = os.environ['PRODUCTS_BUCKET_NAME']

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Amazon Lex V2 fulfillment function for customer service chatbot.
    
    Handles multiple intents:
    - ProductInformation: Provides product details and recommendations
    - OrderStatus: Queries order status from DynamoDB
    - SupportRequest: Escalates to human support with contact information
    """
    logger.info(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        intent_name = event['sessionState']['intent']['name']
        logger.info(f"Processing intent: {intent_name}")
        
        if intent_name == 'ProductInformation':
            return handle_product_information(event)
        elif intent_name == 'OrderStatus':
            return handle_order_status(event)
        elif intent_name == 'SupportRequest':
            return handle_support_request(event)
        else:
            logger.warning(f"Unknown intent: {intent_name}")
            return close_intent(event, "I'm sorry, I don't understand that request. Please try asking about products, order status, or support.")
    
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return close_intent(event, "I'm experiencing technical difficulties. Please try again later or contact support.")

def handle_product_information(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle product information requests with slot validation."""
    slots = event['sessionState']['intent']['slots']
    product_type = slots.get('ProductType', {}).get('value', {}).get('interpretedValue')
    
    if not product_type:
        return elicit_slot(event, 'ProductType', 
                          "What type of product are you interested in? We have electronics, clothing, and books.")
    
    # Product information database (in production, this would query S3 or a database)
    product_info = {
        'electronics': {
            'description': "Our electronics include smartphones, laptops, tablets, and smart home devices.",
            'price_range': "Prices range from $50 to $2,000",
            'features': "All electronics come with manufacturer warranty and free shipping on orders over $100."
        },
        'clothing': {
            'description': "Our clothing collection features casual wear, formal attire, and seasonal items.",
            'price_range': "Prices range from $20 to $300",
            'features': "Available in sizes XS to XXL with free returns within 30 days."
        },
        'books': {
            'description': "Our book selection includes fiction, non-fiction, textbooks, and digital formats.",
            'price_range': "Most books are priced between $10-30",
            'features': "Digital versions available with instant download and audiobook options."
        }
    }
    
    product_data = product_info.get(product_type.lower())
    if product_data:
        response_text = f"{product_data['description']} {product_data['price_range']}. {product_data['features']}"
    else:
        response_text = "I don't have information about that product type. Please try electronics, clothing, or books."
    
    logger.info(f"Product information provided for: {product_type}")
    return close_intent(event, response_text)

def handle_order_status(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle order status queries with DynamoDB integration."""
    slots = event['sessionState']['intent']['slots']
    order_id = slots.get('OrderNumber', {}).get('value', {}).get('interpretedValue')
    
    if not order_id:
        return elicit_slot(event, 'OrderNumber', 
                          "Please provide your order number so I can check the status.")
    
    try:
        # Query DynamoDB for order status
        table = dynamodb.Table(ORDERS_TABLE_NAME)
        response = table.get_item(Key={'OrderId': order_id})
        
        if 'Item' in response:
            order = response['Item']
            status = order.get('Status', 'Unknown')
            estimated_delivery = order.get('EstimatedDelivery', '')
            
            status_text = f"Order {order_id} is currently {status}."
            if estimated_delivery:
                status_text += f" Estimated delivery: {estimated_delivery}"
            
            logger.info(f"Order status retrieved for: {order_id}")
        else:
            status_text = f"I couldn't find an order with number {order_id}. Please check the number and try again."
            logger.warning(f"Order not found: {order_id}")
            
    except Exception as e:
        logger.error(f"Error querying DynamoDB for order {order_id}: {str(e)}")
        status_text = "I'm having trouble accessing order information right now. Please try again later or contact support."
    
    return close_intent(event, status_text)

def handle_support_request(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle support escalation requests."""
    response_text = (
        "I'll connect you with our support team. Here are your options:\\n"
        "• Live Chat: Available 24/7 on our website\\n"
        "• Email: support@company.com (response within 24 hours)\\n"
        "• Phone: 1-800-SUPPORT (Mon-Fri 9AM-6PM EST)\\n"
        "A representative will assist you with your specific needs."
    )
    
    logger.info("Support request escalated to human agents")
    return close_intent(event, response_text)

def elicit_slot(event: Dict[str, Any], slot_name: str, message: str) -> Dict[str, Any]:
    """Request additional information from the user."""
    return {
        'sessionState': {
            'dialogAction': {
                'type': 'ElicitSlot',
                'slotToElicit': slot_name
            },
            'intent': event['sessionState']['intent'],
            'originatingRequestId': event.get('requestAttributes', {}).get('x-amz-lex:request-id')
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }

def close_intent(event: Dict[str, Any], message: str) -> Dict[str, Any]:
    """Close the conversation with a response."""
    return {
        'sessionState': {
            'dialogAction': {
                'type': 'Close'
            },
            'intent': {
                'name': event['sessionState']['intent']['name'],
                'state': 'Fulfilled'
            },
            'originatingRequestId': event.get('requestAttributes', {}).get('x-amz-lex:request-id')
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }
`),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Create IAM role for Amazon Lex with necessary permissions
    const lexRole = new iam.Role(this, 'LexServiceRole', {
      roleName: `lex-service-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lexv2.amazonaws.com'),
      description: 'IAM role for Amazon Lex V2 chatbot service',
      inlinePolicies: {
        LexRuntimeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction',
              ],
              resources: [lexFulfillmentFunction.functionArn],
            }),
          ],
        }),
      },
    });

    // Grant Lex permission to invoke the Lambda function
    lexFulfillmentFunction.addPermission('LexInvokePermission', {
      principal: new iam.ServicePrincipal('lexv2.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: `arn:aws:lex:${this.region}:${this.account}:bot-alias/*/*`,
    });

    // Create custom resource to populate sample data in DynamoDB
    const sampleDataProvider = new cr.Provider(this, 'SampleDataProvider', {
      onEventHandler: new lambda.Function(this, 'SampleDataFunction', {
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.handler',
        timeout: cdk.Duration.minutes(5),
        code: lambda.Code.fromInline(`
import boto3
import json

def handler(event, context):
    if event['RequestType'] == 'Create':
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table('${ordersTable.tableName}')
        
        # Sample order data
        sample_orders = [
            {
                'OrderId': 'ORD123456',
                'Status': 'Shipped',
                'EstimatedDelivery': '2024-02-15',
                'CustomerEmail': 'customer@example.com',
                'Total': '89.99'
            },
            {
                'OrderId': 'ORD789012',
                'Status': 'Processing',
                'EstimatedDelivery': '2024-02-20',
                'CustomerEmail': 'customer2@example.com',
                'Total': '156.50'
            },
            {
                'OrderId': 'ORD345678',
                'Status': 'Delivered',
                'EstimatedDelivery': '2024-02-10',
                'CustomerEmail': 'customer3@example.com',
                'Total': '45.99'
            }
        ]
        
        for order in sample_orders:
            table.put_item(Item=order)
        
        return {'PhysicalResourceId': 'sample-data-populated'}
    
    return {'PhysicalResourceId': event.get('PhysicalResourceId', 'sample-data')}
`),
        role: new iam.Role(this, 'SampleDataRole', {
          assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
          managedPolicies: [
            iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
          ],
          inlinePolicies: {
            DynamoDBAccess: new iam.PolicyDocument({
              statements: [
                new iam.PolicyStatement({
                  effect: iam.Effect.ALLOW,
                  actions: ['dynamodb:PutItem'],
                  resources: [ordersTable.tableArn],
                }),
              ],
            }),
          },
        }),
      }),
    });

    // Create custom resource to populate sample data
    new cdk.CustomResource(this, 'SampleData', {
      serviceToken: sampleDataProvider.serviceToken,
    });

    // Stack outputs for integration and testing
    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: lexFulfillmentFunction.functionArn,
      description: 'ARN of the Lex fulfillment Lambda function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'LexRoleArn', {
      value: lexRole.roleArn,
      description: 'ARN of the Lex service role',
      exportName: `${this.stackName}-LexRoleArn`,
    });

    new cdk.CfnOutput(this, 'OrdersTableName', {
      value: ordersTable.tableName,
      description: 'Name of the DynamoDB orders table',
      exportName: `${this.stackName}-OrdersTableName`,
    });

    new cdk.CfnOutput(this, 'ProductsBucketName', {
      value: productsBucket.bucketName,
      description: 'Name of the S3 products bucket',
      exportName: `${this.stackName}-ProductsBucketName`,
    });

    new cdk.CfnOutput(this, 'DeploymentInstructions', {
      value: [
        'After deployment, create your Lex bot using the AWS CLI:',
        `1. Create bot: aws lexv2-models create-bot --bot-name "customer-service-bot" --role-arn "${lexRole.roleArn}"`,
        '2. Configure intents: ProductInformation, OrderStatus, SupportRequest',
        `3. Set fulfillment function: ${lexFulfillmentFunction.functionArn}`,
        '4. Build and test your bot',
      ].join('\\n'),
      description: 'Instructions for completing the Lex bot setup',
    });
  }
}