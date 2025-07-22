#!/usr/bin/env python3
"""
AWS CDK Python Application for Microservices Orchestration with Step Functions

This CDK application deploys a complete microservices orchestration solution using:
- AWS Lambda functions for individual microservices
- AWS Step Functions for workflow orchestration
- Amazon EventBridge for event-driven triggers
- IAM roles with least privilege access

The architecture demonstrates serverless microservices patterns with parallel processing,
error handling, and retry mechanisms built into the Step Functions workflow.
"""

import os
from typing import Dict, Any

from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    CfnOutput,
    RemovalPolicy,
)
from aws_cdk import aws_lambda as _lambda
from aws_cdk import aws_stepfunctions as sfn
from aws_cdk import aws_stepfunctions_tasks as sfn_tasks
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as events_targets
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from constructs import Construct


class MicroservicesStepFunctionsStack(Stack):
    """
    CDK Stack for deploying a microservices orchestration solution using Step Functions.
    
    This stack creates:
    - 5 Lambda functions representing different microservices
    - A Step Functions state machine to orchestrate the workflow
    - EventBridge rule to trigger workflows from external events
    - IAM roles with appropriate permissions
    - CloudWatch logs for monitoring and debugging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create Lambda functions for microservices
        self.lambda_functions = self._create_lambda_functions()
        
        # Create Step Functions state machine
        self.state_machine = self._create_state_machine()
        
        # Create EventBridge rule for triggering workflows
        self._create_eventbridge_rule()
        
        # Create outputs for easy access to resources
        self._create_outputs()

    def _create_lambda_functions(self) -> Dict[str, _lambda.Function]:
        """
        Create Lambda functions for each microservice.
        
        Returns:
            Dictionary mapping service names to Lambda Function constructs
        """
        lambda_functions = {}
        
        # Create common IAM role for Lambda functions
        lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            description="Execution role for microservices Lambda functions"
        )

        # Define microservice configurations
        services = {
            "user-service": {
                "description": "Handles user validation and profile retrieval",
                "code": self._get_user_service_code()
            },
            "order-service": {
                "description": "Manages order creation and validation logic",
                "code": self._get_order_service_code()
            },
            "payment-service": {
                "description": "Handles payment processing and authorization",
                "code": self._get_payment_service_code()
            },
            "inventory-service": {
                "description": "Manages stock levels and reservation logic",
                "code": self._get_inventory_service_code()
            },
            "notification-service": {
                "description": "Handles customer communications and order confirmations",
                "code": self._get_notification_service_code()
            }
        }

        # Create Lambda function for each service
        for service_name, config in services.items():
            function = _lambda.Function(
                self, f"{service_name.replace('-', '').title()}Function",
                runtime=_lambda.Runtime.PYTHON_3_9,
                handler="index.lambda_handler",
                code=_lambda.Code.from_inline(config["code"]),
                role=lambda_role,
                timeout=Duration.seconds(30),
                description=config["description"],
                environment={
                    "SERVICE_NAME": service_name,
                    "LOG_LEVEL": "INFO"
                }
            )
            
            lambda_functions[service_name] = function

        return lambda_functions

    def _create_state_machine(self) -> sfn.StateMachine:
        """
        Create the Step Functions state machine for orchestrating microservices.
        
        Returns:
            Step Functions StateMachine construct
        """
        # Create log group for Step Functions execution history
        log_group = logs.LogGroup(
            self, "StepFunctionsLogGroup",
            log_group_name=f"/aws/stepfunctions/{self.stack_name}-workflow",
            removal_policy=RemovalPolicy.DESTROY,
            retention=logs.RetentionDays.ONE_WEEK
        )

        # Define the workflow states
        validate_input = sfn.Pass(
            self, "ValidateInput",
            comment="Validate input parameters"
        )

        # User service task with retry configuration
        get_user_data = sfn_tasks.LambdaInvoke(
            self, "GetUserData",
            lambda_function=self.lambda_functions["user-service"],
            payload_response_only=False,
            result_path="$.userResult",
            retry_on_service_exceptions=True
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(2),
            max_attempts=3,
            backoff_rate=2.0
        )

        # Parallel processing branch for order creation
        create_order = sfn_tasks.LambdaInvoke(
            self, "CreateOrder",
            lambda_function=self.lambda_functions["order-service"],
            payload=sfn.TaskInput.from_object({
                "orderData.$": "$.orderData",
                "userData.$": "$.userResult.Payload"
            }),
            payload_response_only=False
        )

        # Parallel processing branch for payment processing
        process_payment = sfn_tasks.LambdaInvoke(
            self, "ProcessPayment",
            lambda_function=self.lambda_functions["payment-service"],
            payload=sfn.TaskInput.from_object({
                "orderData.$": "$.orderData",
                "userData.$": "$.userResult.Payload"
            }),
            payload_response_only=False,
            retry_on_service_exceptions=True
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(1),
            max_attempts=2
        )

        # Parallel processing branch for inventory check
        check_inventory = sfn_tasks.LambdaInvoke(
            self, "CheckInventory",
            lambda_function=self.lambda_functions["inventory-service"],
            payload=sfn.TaskInput.from_object({
                "orderData.$": "$.orderData"
            }),
            payload_response_only=False
        )

        # Parallel state for concurrent processing
        process_order_and_payment = sfn.Parallel(
            self, "ProcessOrderAndPayment",
            comment="Process order, payment, and inventory concurrently"
        ).branch(create_order).branch(process_payment).branch(check_inventory)

        # Notification task
        send_notification = sfn_tasks.LambdaInvoke(
            self, "SendNotification",
            lambda_function=self.lambda_functions["notification-service"],
            payload=sfn.TaskInput.from_object({
                "userData.$": "$.userResult.Payload",
                "orderData.$": "$[0].Payload",
                "paymentData.$": "$[1].Payload",
                "inventoryData.$": "$[2].Payload"
            }),
            payload_response_only=False
        )

        # Define the workflow chain
        definition = validate_input.next(
            get_user_data.next(
                process_order_and_payment.next(send_notification)
            )
        )

        # Create IAM role for Step Functions
        state_machine_role = iam.Role(
            self, "StateMachineRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            description="Execution role for Step Functions state machine"
        )

        # Grant permissions to invoke Lambda functions
        for function in self.lambda_functions.values():
            function.grant_invoke(state_machine_role)

        # Grant permissions for CloudWatch logging
        log_group.grant_write(state_machine_role)

        # Create the state machine
        state_machine = sfn.StateMachine(
            self, "MicroservicesWorkflow",
            definition=definition,
            role=state_machine_role,
            timeout=Duration.minutes(15),
            comment="Microservices orchestration workflow with parallel processing",
            logs=sfn.LogOptions(
                destination=log_group,
                level=sfn.LogLevel.ALL,
                include_execution_data=True
            )
        )

        return state_machine

    def _create_eventbridge_rule(self) -> None:
        """Create EventBridge rule to trigger the Step Functions workflow."""
        # Create EventBridge rule
        rule = events.Rule(
            self, "WorkflowTriggerRule",
            description="Trigger microservices workflow on order submission events",
            event_pattern=events.EventPattern(
                source=["microservices.orders"],
                detail_type=["Order Submitted"]
            )
        )

        # Add Step Functions as target
        rule.add_target(
            events_targets.SfnStateMachine(
                machine=self.state_machine,
                input=events.RuleTargetInput.from_event_path("$.detail")
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self, "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="ARN of the Step Functions state machine"
        )

        CfnOutput(
            self, "StateMachineName",
            value=self.state_machine.state_machine_name,
            description="Name of the Step Functions state machine"
        )

        # Output Lambda function ARNs
        for service_name, function in self.lambda_functions.items():
            CfnOutput(
                self, f"{service_name.replace('-', '').title()}FunctionArn",
                value=function.function_arn,
                description=f"ARN of the {service_name} Lambda function"
            )

    def _get_user_service_code(self) -> str:
        """Return the Python code for the user service Lambda function."""
        return """
import json
import random

def lambda_handler(event, context):
    \"\"\"
    User service Lambda function - handles user validation and profile retrieval.
    
    Args:
        event: Input event containing userId
        context: Lambda runtime context
        
    Returns:
        User data including profile and credit score information
    \"\"\"
    user_id = event.get('userId')
    
    # Simulate user validation
    if not user_id:
        raise Exception("User ID is required")
    
    # Mock user data with randomized credit score
    user_data = {
        'userId': user_id,
        'email': f'user{user_id}@example.com',
        'status': 'active',
        'creditScore': random.randint(600, 850),
        'membershipLevel': random.choice(['bronze', 'silver', 'gold', 'platinum'])
    }
    
    print(f"User validation successful for user: {user_id}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(user_data)
    }
"""

    def _get_order_service_code(self) -> str:
        """Return the Python code for the order service Lambda function."""
        return """
import json
import uuid
import datetime

def lambda_handler(event, context):
    \"\"\"
    Order service Lambda function - manages order creation and validation.
    
    Args:
        event: Input event containing orderData and userData
        context: Lambda runtime context
        
    Returns:
        Created order with unique ID and calculated total
    \"\"\"
    order_data = event.get('orderData', {})
    user_data = event.get('userData', {})
    
    # Validate order requirements
    if not order_data.get('items'):
        raise Exception("Order items are required")
    
    # Calculate order total
    total = sum(item.get('price', 0) * item.get('quantity', 1) for item in order_data.get('items', []))
    
    # Create order object
    order = {
        'orderId': str(uuid.uuid4()),
        'userId': user_data.get('userId'),
        'items': order_data.get('items'),
        'total': round(total, 2),
        'status': 'pending',
        'created': datetime.datetime.utcnow().isoformat(),
        'currency': 'USD'
    }
    
    print(f"Order created: {order['orderId']} for user: {user_data.get('userId')} with total: ${total}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(order)
    }
"""

    def _get_payment_service_code(self) -> str:
        """Return the Python code for the payment service Lambda function."""
        return """
import json
import random

def lambda_handler(event, context):
    \"\"\"
    Payment service Lambda function - handles payment processing and authorization.
    
    Args:
        event: Input event containing orderData and userData
        context: Lambda runtime context
        
    Returns:
        Payment transaction result with authorization details
    \"\"\"
    order_data = event.get('orderData', {})
    user_data = event.get('userData', {})
    
    order_total = order_data.get('total', 0)
    credit_score = user_data.get('creditScore', 600)
    
    # Simulate payment validation based on business rules
    if order_total > 1000 and credit_score < 650:
        raise Exception("Payment declined: Insufficient credit rating for high-value transaction")
    
    # Simulate random payment gateway failures (10% failure rate)
    if random.random() < 0.1:
        raise Exception("Payment gateway timeout - please retry")
    
    # Generate payment result
    payment_result = {
        'transactionId': f"txn_{random.randint(100000, 999999)}",
        'amount': order_total,
        'status': 'authorized',
        'method': 'credit_card',
        'authCode': f"AUTH{random.randint(10000, 99999)}",
        'timestamp': json.dumps(datetime.datetime.utcnow(), default=str)
    }
    
    print(f"Payment processed: {payment_result['transactionId']} for amount: ${order_total}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(payment_result)
    }
"""

    def _get_inventory_service_code(self) -> str:
        """Return the Python code for the inventory service Lambda function."""
        return """
import json
import random

def lambda_handler(event, context):
    \"\"\"
    Inventory service Lambda function - manages stock levels and reservations.
    
    Args:
        event: Input event containing orderData
        context: Lambda runtime context
        
    Returns:
        Inventory reservation results for ordered items
    \"\"\"
    order_data = event.get('orderData', {})
    
    items = order_data.get('items', [])
    inventory_results = []
    
    for item in items:
        product_id = item.get('productId')
        requested_qty = item.get('quantity', 1)
        
        # Simulate inventory check with random availability
        available_qty = random.randint(0, 100)
        
        if available_qty >= requested_qty:
            inventory_results.append({
                'productId': product_id,
                'status': 'reserved',
                'quantity': requested_qty,
                'availableQuantity': available_qty,
                'reservationId': f"RES{random.randint(100000, 999999)}"
            })
            print(f"Inventory reserved: {requested_qty} units of {product_id}")
        else:
            raise Exception(f"Insufficient inventory for product {product_id}: {available_qty} available, {requested_qty} requested")
    
    result = {
        'reservations': inventory_results,
        'status': 'confirmed',
        'totalItemsReserved': len(inventory_results)
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(result)
    }
"""

    def _get_notification_service_code(self) -> str:
        """Return the Python code for the notification service Lambda function."""
        return """
import json

def lambda_handler(event, context):
    \"\"\"
    Notification service Lambda function - handles customer communications.
    
    Args:
        event: Input event containing userData, orderData, and paymentData
        context: Lambda runtime context
        
    Returns:
        Notification delivery confirmation
    \"\"\"
    user_data = event.get('userData', {})
    order_data = event.get('orderData', {})
    payment_data = event.get('paymentData', {})
    inventory_data = event.get('inventoryData', {})
    
    # Extract notification details
    user_email = user_data.get('email', 'unknown@example.com')
    order_id = order_data.get('orderId', 'UNKNOWN')
    order_total = order_data.get('total', 0)
    transaction_id = payment_data.get('transactionId', 'UNKNOWN')
    items_count = len(order_data.get('items', []))
    
    # Create comprehensive notification message
    notification = {
        'to': user_email,
        'subject': f"Order Confirmation #{order_id[:8]}",
        'message': f"Thank you for your order! Your order for ${order_total} ({items_count} items) has been confirmed. Transaction ID: {transaction_id}. You will receive shipping updates via email.",
        'type': 'order_confirmation',
        'status': 'sent',
        'metadata': {
            'orderId': order_id,
            'transactionId': transaction_id,
            'itemsCount': items_count,
            'total': order_total
        }
    }
    
    # In a real implementation, this would integrate with SES, SNS, or other notification services
    print(f"Order confirmation notification sent to {user_email} for order {order_id}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(notification)
    }
"""


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get deployment configuration from environment or use defaults
    stack_name = os.environ.get('CDK_STACK_NAME', 'MicroservicesStepFunctionsStack')
    
    # Create the stack
    MicroservicesStepFunctionsStack(
        app, stack_name,
        description="Microservices orchestration with AWS Step Functions, Lambda, and EventBridge",
        env={
            'account': os.environ.get('CDK_DEFAULT_ACCOUNT'),
            'region': os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()