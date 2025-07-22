#!/usr/bin/env python3
"""
Customer Service Chatbot CDK Application

This CDK application deploys a complete customer service chatbot solution using:
- Amazon Lex V2 for conversational AI
- AWS Lambda for backend processing and fulfillment
- Amazon DynamoDB for customer data storage
- IAM roles and policies for secure access

Author: AWS Recipe Generator
Version: 1.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Tags
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_dynamodb as dynamodb
from aws_cdk import aws_lexv2 as lex
from constructs import Construct


class CustomerServiceChatbotStack(Stack):
    """
    CDK Stack for Customer Service Chatbot solution using Amazon Lex V2.
    
    This stack creates:
    - DynamoDB table for customer data
    - Lambda function for intent fulfillment
    - Amazon Lex V2 bot with intents and slots
    - IAM roles and policies for secure operations
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.bot_name = "CustomerServiceBot"
        self.lambda_function_name = "lex-fulfillment-function"
        self.dynamodb_table_name = "customer-data"

        # Create DynamoDB table for customer data
        self.customer_table = self._create_dynamodb_table()

        # Create Lambda function for Lex fulfillment
        self.fulfillment_lambda = self._create_lambda_function()

        # Create IAM role for Amazon Lex
        self.lex_service_role = self._create_lex_service_role()

        # Create Amazon Lex V2 bot
        self.lex_bot = self._create_lex_bot()

        # Create bot locale configuration
        self.bot_locale = self._create_bot_locale()

        # Create custom slot types
        self.slot_types = self._create_slot_types()

        # Create bot intents
        self.intents = self._create_bot_intents()

        # Add slots to intents
        self._create_intent_slots()

        # Configure Lambda permissions for Lex
        self._configure_lambda_permissions()

        # Add sample customer data
        self._populate_sample_data()

        # Create stack outputs
        self._create_outputs()

        # Add resource tags
        self._tag_resources()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing customer data.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "CustomerDataTable",
            table_name=self.dynamodb_table_name,
            partition_key=dynamodb.Attribute(
                name="CustomerId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            point_in_time_recovery=True,
            deletion_protection=False  # For demo cleanup
        )

        # Add tags to the table
        Tags.of(table).add("Project", "LexCustomerService")
        Tags.of(table).add("Component", "DataStorage")

        return table

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for Lex intent fulfillment.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self, "LexLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add DynamoDB permissions to Lambda role
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                    "dynamodb:BatchGetItem"
                ],
                resources=[self.customer_table.table_arn]
            )
        )

        # Define Lambda function code
        lambda_code = '''
import json
import boto3
import os
import logging
from typing import Dict, Any, Optional

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['DYNAMODB_TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for Amazon Lex V2 intent fulfillment.
    
    Args:
        event: Lex V2 event containing intent information
        context: Lambda context object
        
    Returns:
        Lex V2 response with fulfillment result
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    intent_name = event['sessionState']['intent']['name']
    slots = event['sessionState']['intent']['slots']
    
    if intent_name == 'OrderStatus':
        return handle_order_status(event, slots)
    elif intent_name == 'BillingInquiry':
        return handle_billing_inquiry(event, slots)
    elif intent_name == 'ProductInfo':
        return handle_product_info(event, slots)
    else:
        return close_intent(
            event, 
            'Fulfilled', 
            'I can help you with order status, billing questions, or product information.'
        )

def handle_order_status(event: Dict[str, Any], slots: Dict[str, Any]) -> Dict[str, Any]:
    """Handle order status inquiries."""
    customer_id = get_slot_value(slots, 'CustomerId')
    
    if not customer_id:
        return elicit_slot(
            event, 
            'CustomerId', 
            'Could you please provide your customer ID to check your order status?'
        )
    
    try:
        response = table.get_item(Key={'CustomerId': customer_id})
        if 'Item' in response:
            item = response['Item']
            message = f"Hi {item['Name']}! Your last order {item['LastOrderId']} is currently {item['LastOrderStatus']}."
        else:
            message = f"I couldn't find a customer with ID {customer_id}. Please check your customer ID."
        
        return close_intent(event, 'Fulfilled', message)
    except Exception as e:
        logger.error(f"Error retrieving order status: {str(e)}")
        return close_intent(
            event, 
            'Failed', 
            'Sorry, I encountered an error checking your order status. Please try again later.'
        )

def handle_billing_inquiry(event: Dict[str, Any], slots: Dict[str, Any]) -> Dict[str, Any]:
    """Handle billing and account balance inquiries."""
    customer_id = get_slot_value(slots, 'CustomerId')
    
    if not customer_id:
        return elicit_slot(
            event, 
            'CustomerId', 
            'Could you please provide your customer ID to check your account balance?'
        )
    
    try:
        response = table.get_item(Key={'CustomerId': customer_id})
        if 'Item' in response:
            item = response['Item']
            balance = float(item['AccountBalance'])
            message = f"Hi {item['Name']}! Your current account balance is ${balance:.2f}."
        else:
            message = f"I couldn't find a customer with ID {customer_id}. Please check your customer ID."
        
        return close_intent(event, 'Fulfilled', message)
    except Exception as e:
        logger.error(f"Error retrieving billing info: {str(e)}")
        return close_intent(
            event, 
            'Failed', 
            'Sorry, I encountered an error checking your account. Please try again later.'
        )

def handle_product_info(event: Dict[str, Any], slots: Dict[str, Any]) -> Dict[str, Any]:
    """Handle product information requests."""
    product_name = get_slot_value(slots, 'ProductName')
    
    if not product_name:
        return elicit_slot(
            event, 
            'ProductName', 
            'What product would you like information about?'
        )
    
    # Simple product info responses (in real implementation, query product database)
    product_info = {
        'laptop': 'Our laptops feature high-performance processors and long battery life, starting at $899.',
        'smartphone': 'Our smartphones offer premium cameras and 5G connectivity, starting at $699.',
        'tablet': 'Our tablets are perfect for productivity and entertainment, starting at $399.'
    }
    
    product_lower = product_name.lower()
    if product_lower in product_info:
        message = product_info[product_lower]
    else:
        message = f"I don't have specific information about {product_name}. Please contact our sales team for detailed product information."
    
    return close_intent(event, 'Fulfilled', message)

def get_slot_value(slots: Dict[str, Any], slot_name: str) -> Optional[str]:
    """Extract slot value from Lex V2 slots structure."""
    slot = slots.get(slot_name, {})
    if slot and 'value' in slot and 'interpretedValue' in slot['value']:
        return slot['value']['interpretedValue']
    return None

def elicit_slot(event: Dict[str, Any], slot_to_elicit: str, message: str) -> Dict[str, Any]:
    """Create Lex V2 response to elicit a specific slot."""
    return {
        'sessionState': {
            'sessionAttributes': event['sessionState'].get('sessionAttributes', {}),
            'dialogAction': {
                'type': 'ElicitSlot',
                'slotToElicit': slot_to_elicit
            },
            'intent': event['sessionState']['intent']
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }

def close_intent(event: Dict[str, Any], fulfillment_state: str, message: str) -> Dict[str, Any]:
    """Create Lex V2 response to close an intent."""
    return {
        'sessionState': {
            'sessionAttributes': event['sessionState'].get('sessionAttributes', {}),
            'dialogAction': {
                'type': 'Close'
            },
            'intent': {
                'name': event['sessionState']['intent']['name'],
                'state': fulfillment_state
            }
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }
        '''

        # Create Lambda function
        function = lambda_.Function(
            self, "LexFulfillmentLambda",
            function_name=self.lambda_function_name,
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "DYNAMODB_TABLE_NAME": self.customer_table.table_name
            },
            description="Lambda function for Amazon Lex V2 customer service bot fulfillment"
        )

        # Add tags to the function
        Tags.of(function).add("Project", "LexCustomerService")
        Tags.of(function).add("Component", "Fulfillment")

        return function

    def _create_lex_service_role(self) -> iam.Role:
        """
        Create IAM service role for Amazon Lex.
        
        Returns:
            iam.Role: The created IAM role for Lex
        """
        role = iam.Role(
            self, "LexServiceRole",
            assumed_by=iam.ServicePrincipal("lexv2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonLexV2BotPolicy")
            ]
        )

        # Add tags to the role
        Tags.of(role).add("Project", "LexCustomerService")
        Tags.of(role).add("Component", "BotService")

        return role

    def _create_lex_bot(self) -> lex.CfnBot:
        """
        Create Amazon Lex V2 bot.
        
        Returns:
            lex.CfnBot: The created Lex bot
        """
        bot = lex.CfnBot(
            self, "CustomerServiceBot",
            bot_name=self.bot_name,
            description="Customer service chatbot for handling common inquiries",
            role_arn=self.lex_service_role.role_arn,
            data_privacy={
                "childDirected": False
            },
            idle_session_ttl_in_seconds=600,
            bot_tags=[
                {
                    "key": "Project",
                    "value": "LexCustomerService"
                },
                {
                    "key": "Component", 
                    "value": "ConversationalAI"
                }
            ]
        )

        return bot

    def _create_bot_locale(self) -> lex.CfnBotVersion:
        """
        Create bot locale configuration for English (US).
        
        Returns:
            lex.CfnBotVersion: The created bot locale
        """
        # Create bot locale
        locale = lex.CfnBotVersion(
            self, "BotLocale",
            bot_id=self.lex_bot.attr_bot_id,
            locale_id="en_US",
            description="English US locale for customer service bot",
            nlu_intent_confidence_threshold=0.40,
            voice_settings={
                "voiceId": "Joanna"
            }
        )

        # Add dependency on bot
        locale.add_dependency(self.lex_bot)

        return locale

    def _create_slot_types(self) -> Dict[str, lex.CfnSlotType]:
        """
        Create custom slot types for the bot.
        
        Returns:
            Dict[str, lex.CfnSlotType]: Dictionary of created slot types
        """
        slot_types = {}

        # Create CustomerId slot type
        customer_id_slot = lex.CfnSlotType(
            self, "CustomerIdSlotType",
            bot_id=self.lex_bot.attr_bot_id,
            bot_version="DRAFT",
            locale_id="en_US",
            slot_type_name="CustomerId",
            description="Customer identification numbers",
            slot_type_values=[
                {
                    "sampleValue": {"value": "12345"},
                    "synonyms": []
                },
                {
                    "sampleValue": {"value": "67890"},
                    "synonyms": []
                }
            ],
            value_selection_strategy="ORIGINAL_VALUE"
        )
        customer_id_slot.add_dependency(self.lex_bot)
        slot_types["CustomerId"] = customer_id_slot

        # Create ProductName slot type
        product_name_slot = lex.CfnSlotType(
            self, "ProductNameSlotType",
            bot_id=self.lex_bot.attr_bot_id,
            bot_version="DRAFT",
            locale_id="en_US",
            slot_type_name="ProductName",
            description="Product names for inquiries",
            slot_type_values=[
                {
                    "sampleValue": {"value": "laptop"},
                    "synonyms": [{"value": "computer"}, {"value": "notebook"}]
                },
                {
                    "sampleValue": {"value": "smartphone"},
                    "synonyms": [{"value": "phone"}, {"value": "mobile"}]
                },
                {
                    "sampleValue": {"value": "tablet"},
                    "synonyms": [{"value": "ipad"}]
                }
            ],
            value_selection_strategy="TOP_RESOLUTION"
        )
        product_name_slot.add_dependency(self.lex_bot)
        slot_types["ProductName"] = product_name_slot

        return slot_types

    def _create_bot_intents(self) -> Dict[str, lex.CfnIntent]:
        """
        Create bot intents for customer service scenarios.
        
        Returns:
            Dict[str, lex.CfnIntent]: Dictionary of created intents
        """
        intents = {}

        # Create OrderStatus intent
        order_status_intent = lex.CfnIntent(
            self, "OrderStatusIntent",
            bot_id=self.lex_bot.attr_bot_id,
            bot_version="DRAFT",
            locale_id="en_US",
            intent_name="OrderStatus",
            description="Handle order status inquiries",
            sample_utterances=[
                {"utterance": "What is my order status"},
                {"utterance": "Check my order"},
                {"utterance": "Where is my order"},
                {"utterance": "Track my order {CustomerId}"},
                {"utterance": "Order status for {CustomerId}"},
                {"utterance": "My customer ID is {CustomerId}"}
            ],
            fulfillment_code_hook={
                "enabled": True,
                "fulfillmentUpdatesSpecification": {
                    "active": False
                }
            }
        )
        order_status_intent.add_dependency(self.lex_bot)
        intents["OrderStatus"] = order_status_intent

        # Create BillingInquiry intent
        billing_inquiry_intent = lex.CfnIntent(
            self, "BillingInquiryIntent",
            bot_id=self.lex_bot.attr_bot_id,
            bot_version="DRAFT",
            locale_id="en_US",
            intent_name="BillingInquiry",
            description="Handle billing and account balance inquiries",
            sample_utterances=[
                {"utterance": "What is my account balance"},
                {"utterance": "Check my balance"},
                {"utterance": "How much do I owe"},
                {"utterance": "Billing information for {CustomerId}"},
                {"utterance": "Account balance for customer {CustomerId}"},
                {"utterance": "My balance please"}
            ],
            fulfillment_code_hook={
                "enabled": True,
                "fulfillmentUpdatesSpecification": {
                    "active": False
                }
            }
        )
        billing_inquiry_intent.add_dependency(self.lex_bot)
        intents["BillingInquiry"] = billing_inquiry_intent

        # Create ProductInfo intent
        product_info_intent = lex.CfnIntent(
            self, "ProductInfoIntent",
            bot_id=self.lex_bot.attr_bot_id,
            bot_version="DRAFT",
            locale_id="en_US",
            intent_name="ProductInfo",
            description="Handle product information requests",
            sample_utterances=[
                {"utterance": "Tell me about {ProductName}"},
                {"utterance": "Product information for {ProductName}"},
                {"utterance": "What can you tell me about {ProductName}"},
                {"utterance": "I want to know about {ProductName}"},
                {"utterance": "Details about your {ProductName}"}
            ],
            fulfillment_code_hook={
                "enabled": True,
                "fulfillmentUpdatesSpecification": {
                    "active": False
                }
            }
        )
        product_info_intent.add_dependency(self.lex_bot)
        intents["ProductInfo"] = product_info_intent

        return intents

    def _create_intent_slots(self) -> None:
        """Create slots for each intent."""
        # Add CustomerId slot to OrderStatus intent
        order_customer_slot = lex.CfnSlot(
            self, "OrderStatusCustomerIdSlot",
            bot_id=self.lex_bot.attr_bot_id,
            bot_version="DRAFT",
            locale_id="en_US",
            intent_id=self.intents["OrderStatus"].attr_intent_id,
            slot_name="CustomerId",
            description="Customer identification number",
            slot_type_id=self.slot_types["CustomerId"].attr_slot_type_id,
            value_elicitation_setting={
                "slotConstraint": "Required",
                "promptSpecification": {
                    "messageGroups": [
                        {
                            "message": {
                                "plainTextMessage": {
                                    "value": "Could you please provide your customer ID?"
                                }
                            }
                        }
                    ],
                    "maxRetries": 2
                }
            }
        )
        order_customer_slot.add_dependency(self.intents["OrderStatus"])
        order_customer_slot.add_dependency(self.slot_types["CustomerId"])

        # Add CustomerId slot to BillingInquiry intent
        billing_customer_slot = lex.CfnSlot(
            self, "BillingInquiryCustomerIdSlot",
            bot_id=self.lex_bot.attr_bot_id,
            bot_version="DRAFT",
            locale_id="en_US",
            intent_id=self.intents["BillingInquiry"].attr_intent_id,
            slot_name="CustomerId",
            description="Customer identification number for billing",
            slot_type_id=self.slot_types["CustomerId"].attr_slot_type_id,
            value_elicitation_setting={
                "slotConstraint": "Required",
                "promptSpecification": {
                    "messageGroups": [
                        {
                            "message": {
                                "plainTextMessage": {
                                    "value": "Please provide your customer ID to check your account balance."
                                }
                            }
                        }
                    ],
                    "maxRetries": 2
                }
            }
        )
        billing_customer_slot.add_dependency(self.intents["BillingInquiry"])
        billing_customer_slot.add_dependency(self.slot_types["CustomerId"])

        # Add ProductName slot to ProductInfo intent
        product_name_slot = lex.CfnSlot(
            self, "ProductInfoProductNameSlot",
            bot_id=self.lex_bot.attr_bot_id,
            bot_version="DRAFT",
            locale_id="en_US",
            intent_id=self.intents["ProductInfo"].attr_intent_id,
            slot_name="ProductName",
            description="Product name for information request",
            slot_type_id=self.slot_types["ProductName"].attr_slot_type_id,
            value_elicitation_setting={
                "slotConstraint": "Required",
                "promptSpecification": {
                    "messageGroups": [
                        {
                            "message": {
                                "plainTextMessage": {
                                    "value": "What product would you like information about?"
                                }
                            }
                        }
                    ],
                    "maxRetries": 2
                }
            }
        )
        product_name_slot.add_dependency(self.intents["ProductInfo"])
        product_name_slot.add_dependency(self.slot_types["ProductName"])

    def _configure_lambda_permissions(self) -> None:
        """Configure Lambda permissions for Lex to invoke the function."""
        self.fulfillment_lambda.add_permission(
            "LexInvokePermission",
            principal=iam.ServicePrincipal("lexv2.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"arn:aws:lex:{self.region}:{self.account}:bot/{self.lex_bot.attr_bot_id}"
        )

    def _populate_sample_data(self) -> None:
        """Add sample customer data to DynamoDB table."""
        # Sample data will be added via custom resource
        from aws_cdk import custom_resources as cr

        # Create sample data
        sample_customers = [
            {
                "CustomerId": "12345",
                "Name": "John Smith",
                "Email": "john.smith@example.com",
                "LastOrderId": "ORD-789",
                "LastOrderStatus": "Shipped",
                "AccountBalance": "156.78"
            },
            {
                "CustomerId": "67890",
                "Name": "Jane Doe",
                "Email": "jane.doe@example.com",
                "LastOrderId": "ORD-456",
                "LastOrderStatus": "Processing",
                "AccountBalance": "89.23"
            }
        ]

        # Create custom resource to populate data
        populate_data = cr.AwsCustomResource(
            self, "PopulateSampleData",
            on_create=cr.AwsSdkCall(
                service="DynamoDB",
                action="batchWriteItem",
                parameters={
                    "RequestItems": {
                        self.customer_table.table_name: [
                            {
                                "PutRequest": {
                                    "Item": {
                                        "CustomerId": {"S": customer["CustomerId"]},
                                        "Name": {"S": customer["Name"]},
                                        "Email": {"S": customer["Email"]},
                                        "LastOrderId": {"S": customer["LastOrderId"]},
                                        "LastOrderStatus": {"S": customer["LastOrderStatus"]},
                                        "AccountBalance": {"N": customer["AccountBalance"]}
                                    }
                                }
                            }
                            for customer in sample_customers
                        ]
                    }
                },
                physical_resource_id=cr.PhysicalResourceId.of("SampleDataPopulation")
            ),
            policy=cr.AwsCustomResourcePolicy.from_statements([
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["dynamodb:BatchWriteItem"],
                    resources=[self.customer_table.table_arn]
                )
            ])
        )

        populate_data.node.add_dependency(self.customer_table)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "BotId",
            value=self.lex_bot.attr_bot_id,
            description="Amazon Lex Bot ID",
            export_name=f"{self.stack_name}-BotId"
        )

        CfnOutput(
            self, "BotName",
            value=self.bot_name,
            description="Amazon Lex Bot Name",
            export_name=f"{self.stack_name}-BotName"
        )

        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.fulfillment_lambda.function_arn,
            description="Lambda function ARN for Lex fulfillment",
            export_name=f"{self.stack_name}-LambdaFunctionArn"
        )

        CfnOutput(
            self, "DynamoDBTableName",
            value=self.customer_table.table_name,
            description="DynamoDB table name for customer data",
            export_name=f"{self.stack_name}-DynamoDBTableName"
        )

        CfnOutput(
            self, "TestInstructions",
            value=(
                f"Test the bot using: aws lexv2-runtime recognize-text "
                f"--bot-id {self.lex_bot.attr_bot_id} "
                f"--bot-alias-id TSTALIASID "
                f"--locale-id en_US "
                f"--session-id test-session "
                f"--text 'What is my order status for customer 12345?'"
            ),
            description="Instructions for testing the bot"
        )

    def _tag_resources(self) -> None:
        """Add consistent tags to all resources in the stack."""
        Tags.of(self).add("Project", "LexCustomerService")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("Owner", "CDK-Recipe")
        Tags.of(self).add("CostCenter", "Engineering")


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )

    # Create the stack
    CustomerServiceChatbotStack(
        app, 
        "CustomerServiceChatbotStack",
        env=env,
        description="Customer Service Chatbot solution using Amazon Lex V2, Lambda, and DynamoDB",
        tags={
            "Project": "LexCustomerService",
            "Component": "Infrastructure"
        }
    )

    app.synth()


if __name__ == "__main__":
    main()