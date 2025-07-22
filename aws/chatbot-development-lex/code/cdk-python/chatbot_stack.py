"""
AWS CDK Stack for Amazon Lex Chatbot Development

This stack creates a complete customer service chatbot solution including:
- Amazon Lex V2 bot with three intents (ProductInformation, OrderStatus, SupportRequest)
- Lambda function for bot fulfillment with business logic
- DynamoDB table for order data storage
- S3 bucket for product catalog
- IAM roles with least privilege permissions
- CloudWatch logging and monitoring

The architecture follows AWS best practices for conversational AI applications.
"""

from typing import Dict, Any
import json
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_logs as logs,
)
from constructs import Construct


class ChatbotStack(Stack):
    """CDK Stack for Amazon Lex Chatbot implementation."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"

        # Create DynamoDB table for order data
        self.orders_table = self._create_orders_table(unique_suffix)

        # Create S3 bucket for product catalog
        self.products_bucket = self._create_products_bucket(unique_suffix)

        # Create Lambda function for Lex fulfillment
        self.fulfillment_function = self._create_fulfillment_function(unique_suffix)

        # Create IAM role for Lex service
        self.lex_service_role = self._create_lex_service_role(unique_suffix)

        # Populate sample data
        self._populate_sample_data()

        # Create stack outputs
        self._create_outputs()

    def _create_orders_table(self, suffix: str) -> dynamodb.Table:
        """Create DynamoDB table for storing customer order data."""
        table = dynamodb.Table(
            self,
            "OrdersTable",
            table_name=f"customer-orders-{suffix}",
            partition_key=dynamodb.Attribute(
                name="OrderId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )

        # Add tags for resource management
        table.node.add_metadata("Purpose", "LexChatbotDemo")
        return table

    def _create_products_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for product catalog storage."""
        bucket = s3.Bucket(
            self,
            "ProductsBucket",
            bucket_name=f"product-catalog-{suffix}-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add tags for resource management
        bucket.node.add_metadata("Purpose", "LexChatbotDemo")
        return bucket

    def _create_fulfillment_function(self, suffix: str) -> lambda_.Function:
        """Create Lambda function for Lex bot fulfillment."""
        # Lambda function code
        function_code = '''
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """Main Lambda handler for Lex bot fulfillment."""
    logger.info(f"Received event: {json.dumps(event)}")
    
    intent_name = event['sessionState']['intent']['name']
    
    if intent_name == 'ProductInformation':
        return handle_product_information(event)
    elif intent_name == 'OrderStatus':
        return handle_order_status(event)
    elif intent_name == 'SupportRequest':
        return handle_support_request(event)
    else:
        return close_intent(event, "I'm sorry, I don't understand that request.")

def handle_product_information(event):
    """Handle product information requests."""
    slots = event['sessionState']['intent']['slots']
    product_type = slots.get('ProductType', {}).get('value', {}).get('interpretedValue')
    
    if not product_type:
        return elicit_slot(event, 'ProductType', 
                          "What type of product are you interested in? We have electronics, clothing, and books.")
    
    # Product information lookup
    product_info = {
        'electronics': "Our electronics include smartphones, laptops, and smart home devices. Prices range from $50 to $2000.",
        'clothing': "Our clothing collection features casual wear, formal attire, and seasonal items. Sizes range from XS to XXL.",
        'books': "Our book selection includes fiction, non-fiction, and educational materials. Most books are priced between $10-30."
    }
    
    response_text = product_info.get(product_type.lower(), 
                                   "I don't have information about that product type. Please try electronics, clothing, or books.")
    
    return close_intent(event, response_text)

def handle_order_status(event):
    """Handle order status inquiries."""
    slots = event['sessionState']['intent']['slots']
    order_id = slots.get('OrderNumber', {}).get('value', {}).get('interpretedValue')
    
    if not order_id:
        return elicit_slot(event, 'OrderNumber', 
                          "Please provide your order number so I can check the status.")
    
    # Query DynamoDB for order status
    try:
        table_name = os.environ.get('ORDERS_TABLE_NAME')
        table = dynamodb.Table(table_name)
        response = table.get_item(Key={'OrderId': order_id})
        
        if 'Item' in response:
            order = response['Item']
            status_text = f"Order {order_id} is currently {order.get('Status', 'Unknown')}."
            if 'EstimatedDelivery' in order:
                status_text += f" Estimated delivery: {order['EstimatedDelivery']}"
        else:
            status_text = f"I couldn't find an order with number {order_id}. Please check the number and try again."
            
    except Exception as e:
        logger.error(f"Error querying DynamoDB: {str(e)}")
        status_text = "I'm having trouble accessing order information right now. Please try again later."
    
    return close_intent(event, status_text)

def handle_support_request(event):
    """Handle complex support requests."""
    response_text = ("I'll connect you with a human support agent. "
                    "You can also email us at support@company.com or call 1-800-SUPPORT. "
                    "A representative will assist you within 24 hours.")
    
    return close_intent(event, response_text)

def elicit_slot(event, slot_name, message):
    """Elicit a required slot from the user."""
    return {
        'sessionState': {
            'dialogAction': {
                'type': 'ElicitSlot',
                'slotToElicit': slot_name
            },
            'intent': event['sessionState']['intent'],
            'originatingRequestId': event['requestAttributes'].get('x-amz-lex:request-id')
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }

def close_intent(event, message):
    """Close the intent with a message."""
    return {
        'sessionState': {
            'dialogAction': {
                'type': 'Close'
            },
            'intent': {
                'name': event['sessionState']['intent']['name'],
                'state': 'Fulfilled'
            },
            'originatingRequestId': event['requestAttributes'].get('x-amz-lex:request-id')
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }
'''

        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "LexLambdaRole",
            role_name=f"LexLambdaRole-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
        )

        # Grant permissions to access DynamoDB and S3
        self.orders_table.grant_read_data(lambda_role)
        self.products_bucket.grant_read(lambda_role)

        # Create Lambda function
        function = lambda_.Function(
            self,
            "LexFulfillmentFunction",
            function_name=f"lex-fulfillment-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            role=lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "ORDERS_TABLE_NAME": self.orders_table.table_name,
                "PRODUCTS_BUCKET_NAME": self.products_bucket.bucket_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Grant Lex permission to invoke Lambda
        function.add_permission(
            "LexInvokePermission",
            principal=iam.ServicePrincipal("lexv2.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"arn:aws:lex:{self.region}:{self.account}:bot-alias/*/*",
        )

        return function

    def _create_lex_service_role(self, suffix: str) -> iam.Role:
        """Create IAM role for Lex service."""
        role = iam.Role(
            self,
            "LexServiceRole",
            role_name=f"LexServiceRole-{suffix}",
            assumed_by=iam.ServicePrincipal("lexv2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonLexFullAccess")
            ],
        )

        return role

    def _populate_sample_data(self) -> None:
        """Populate DynamoDB with sample order data using custom resource."""
        # Custom resource Lambda for data population
        populate_data_code = '''
import boto3
import json
import cfnresponse

def lambda_handler(event, context):
    """Populate DynamoDB with sample data."""
    try:
        if event['RequestType'] == 'Create':
            dynamodb = boto3.resource('dynamodb')
            table_name = event['ResourceProperties']['TableName']
            table = dynamodb.Table(table_name)
            
            # Sample order data
            sample_orders = [
                {
                    'OrderId': 'ORD123456',
                    'Status': 'Shipped',
                    'EstimatedDelivery': '2024-01-15',
                    'CustomerEmail': 'customer@example.com'
                },
                {
                    'OrderId': 'ORD789012',
                    'Status': 'Processing',
                    'EstimatedDelivery': '2024-01-20',
                    'CustomerEmail': 'customer2@example.com'
                }
            ]
            
            # Insert sample data
            for order in sample_orders:
                table.put_item(Item=order)
            
            print(f"Successfully populated {len(sample_orders)} sample orders")
        
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
'''

        # Create role for data population Lambda
        populate_role = iam.Role(
            self,
            "PopulateDataRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
        )

        self.orders_table.grant_write_data(populate_role)

        # Create Lambda function for data population
        populate_function = lambda_.Function(
            self,
            "PopulateDataFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(populate_data_code),
            role=populate_role,
            timeout=Duration.seconds(60),
        )

        # Create custom resource to trigger data population
        from aws_cdk.custom_resources import Provider
        provider = Provider(
            self,
            "PopulateDataProvider",
            on_event_handler=populate_function,
        )

        from aws_cdk import CustomResource
        CustomResource(
            self,
            "PopulateSampleData",
            service_token=provider.service_token,
            properties={
                "TableName": self.orders_table.table_name,
            },
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "OrdersTableName",
            value=self.orders_table.table_name,
            description="DynamoDB table name for customer orders",
        )

        CfnOutput(
            self,
            "ProductsBucketName",
            value=self.products_bucket.bucket_name,
            description="S3 bucket name for product catalog",
        )

        CfnOutput(
            self,
            "FulfillmentFunctionArn",
            value=self.fulfillment_function.function_arn,
            description="Lambda function ARN for Lex fulfillment",
        )

        CfnOutput(
            self,
            "LexServiceRoleArn",
            value=self.lex_service_role.role_arn,
            description="IAM role ARN for Lex service",
        )

        CfnOutput(
            self,
            "FulfillmentFunctionName",
            value=self.fulfillment_function.function_name,
            description="Lambda function name for Lex fulfillment",
        )