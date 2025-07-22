#!/usr/bin/env python3
"""
CDK Python application for Saga Pattern with Step Functions for Distributed Transactions.

This application deploys a complete saga orchestration pattern using AWS Step Functions
to coordinate distributed transactions across multiple microservices including order
processing, inventory management, payment processing, and notifications.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_lambda as _lambda,
    aws_dynamodb as dynamodb,
    aws_sns as sns,
    aws_apigateway as apigateway,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct
import json


class SagaPatternStack(Stack):
    """
    Stack for implementing Saga Pattern with Step Functions for distributed transactions.
    
    This stack creates:
    - DynamoDB tables for orders, inventory, and payments
    - Lambda functions for business services and compensation actions
    - Step Functions state machine for saga orchestration
    - SNS topic for notifications
    - API Gateway for transaction initiation
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create DynamoDB tables
        self.create_dynamodb_tables()
        
        # Create SNS topic for notifications
        self.create_sns_topic()
        
        # Create Lambda functions
        self.create_lambda_functions()
        
        # Create Step Functions state machine
        self.create_step_functions_state_machine()
        
        # Create API Gateway
        self.create_api_gateway()
        
        # Create outputs
        self.create_outputs()

    def create_dynamodb_tables(self) -> None:
        """Create DynamoDB tables for orders, inventory, and payments."""
        
        # Orders table
        self.orders_table = dynamodb.Table(
            self, "OrdersTable",
            table_name=f"saga-orders-{self.stack_name}",
            partition_key=dynamodb.Attribute(
                name="orderId", 
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Inventory table
        self.inventory_table = dynamodb.Table(
            self, "InventoryTable",
            table_name=f"saga-inventory-{self.stack_name}",
            partition_key=dynamodb.Attribute(
                name="productId", 
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )
        
        # Payments table
        self.payments_table = dynamodb.Table(
            self, "PaymentsTable",
            table_name=f"saga-payments-{self.stack_name}",
            partition_key=dynamodb.Attribute(
                name="paymentId", 
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )

        # Populate sample inventory data
        self.populate_sample_inventory()

    def populate_sample_inventory(self) -> None:
        """Populate inventory table with sample data using custom resource."""
        
        # Create Lambda function for populating inventory
        populate_inventory_function = _lambda.Function(
            self, "PopulateInventoryFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.handler",
            code=_lambda.Code.from_inline('''
import boto3
import json
import cfnresponse

def handler(event, context):
    try:
        if event['RequestType'] == 'Create':
            dynamodb = boto3.resource('dynamodb')
            table = dynamodb.Table(event['ResourceProperties']['TableName'])
            
            # Sample inventory items
            items = [
                {
                    'productId': 'laptop-001',
                    'quantity': 10,
                    'price': 999.99,
                    'reserved': 0
                },
                {
                    'productId': 'phone-002',
                    'quantity': 25,
                    'price': 599.99,
                    'reserved': 0
                }
            ]
            
            for item in items:
                table.put_item(Item=item)
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        else:
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
            '''),
            timeout=Duration.seconds(60),
        )
        
        # Grant permissions to access DynamoDB
        self.inventory_table.grant_write_data(populate_inventory_function)
        
        # Create custom resource
        cdk.CustomResource(
            self, "PopulateInventoryCustomResource",
            service_token=populate_inventory_function.function_arn,
            properties={
                "TableName": self.inventory_table.table_name
            }
        )

    def create_sns_topic(self) -> None:
        """Create SNS topic for notifications."""
        
        self.notification_topic = sns.Topic(
            self, "NotificationTopic",
            topic_name=f"saga-notifications-{self.stack_name}",
            display_name="Saga Pattern Notifications"
        )

    def create_lambda_functions(self) -> None:
        """Create Lambda functions for business services and compensation actions."""
        
        # Common Lambda environment variables
        common_env = {
            "ORDERS_TABLE": self.orders_table.table_name,
            "INVENTORY_TABLE": self.inventory_table.table_name,
            "PAYMENTS_TABLE": self.payments_table.table_name,
            "NOTIFICATION_TOPIC": self.notification_topic.topic_arn,
        }
        
        # Order Service Lambda
        self.order_service_function = _lambda.Function(
            self, "OrderServiceFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="order_service.lambda_handler",
            code=_lambda.Code.from_asset("lambda"),
            timeout=Duration.seconds(30),
            environment=common_env,
            retry_attempts=0,
        )
        
        # Inventory Service Lambda
        self.inventory_service_function = _lambda.Function(
            self, "InventoryServiceFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="inventory_service.lambda_handler",
            code=_lambda.Code.from_asset("lambda"),
            timeout=Duration.seconds(30),
            environment=common_env,
            retry_attempts=0,
        )
        
        # Payment Service Lambda
        self.payment_service_function = _lambda.Function(
            self, "PaymentServiceFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="payment_service.lambda_handler",
            code=_lambda.Code.from_asset("lambda"),
            timeout=Duration.seconds(30),
            environment=common_env,
            retry_attempts=0,
        )
        
        # Notification Service Lambda
        self.notification_service_function = _lambda.Function(
            self, "NotificationServiceFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="notification_service.lambda_handler",
            code=_lambda.Code.from_asset("lambda"),
            timeout=Duration.seconds(30),
            environment=common_env,
            retry_attempts=0,
        )
        
        # Compensation Lambda Functions
        self.cancel_order_function = _lambda.Function(
            self, "CancelOrderFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="cancel_order.lambda_handler",
            code=_lambda.Code.from_asset("lambda"),
            timeout=Duration.seconds(30),
            environment=common_env,
            retry_attempts=0,
        )
        
        self.revert_inventory_function = _lambda.Function(
            self, "RevertInventoryFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="revert_inventory.lambda_handler",
            code=_lambda.Code.from_asset("lambda"),
            timeout=Duration.seconds(30),
            environment=common_env,
            retry_attempts=0,
        )
        
        self.refund_payment_function = _lambda.Function(
            self, "RefundPaymentFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="refund_payment.lambda_handler",
            code=_lambda.Code.from_asset("lambda"),
            timeout=Duration.seconds(30),
            environment=common_env,
            retry_attempts=0,
        )
        
        # Grant permissions to Lambda functions
        self.grant_lambda_permissions()

    def grant_lambda_permissions(self) -> None:
        """Grant necessary permissions to Lambda functions."""
        
        # List of all Lambda functions
        lambda_functions = [
            self.order_service_function,
            self.inventory_service_function,
            self.payment_service_function,
            self.notification_service_function,
            self.cancel_order_function,
            self.revert_inventory_function,
            self.refund_payment_function,
        ]
        
        # Grant DynamoDB permissions
        for func in lambda_functions:
            self.orders_table.grant_read_write_data(func)
            self.inventory_table.grant_read_write_data(func)
            self.payments_table.grant_read_write_data(func)
            self.notification_topic.grant_publish(func)

    def create_step_functions_state_machine(self) -> None:
        """Create Step Functions state machine for saga orchestration."""
        
        # Create CloudWatch log group for Step Functions
        log_group = logs.LogGroup(
            self, "SagaLogGroup",
            log_group_name=f"/aws/stepfunctions/saga-{self.stack_name}",
            removal_policy=RemovalPolicy.DESTROY,
            retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Define state machine tasks
        place_order_task = sfn_tasks.LambdaInvoke(
            self, "PlaceOrderTask",
            lambda_function=self.order_service_function,
            payload=sfn.TaskInput.from_object({
                "tableName": self.orders_table.table_name,
                "customerId.$": "$.customerId",
                "productId.$": "$.productId",
                "quantity.$": "$.quantity"
            }),
            result_path="$.orderResult",
            retry_on_service_exceptions=True,
        )
        
        reserve_inventory_task = sfn_tasks.LambdaInvoke(
            self, "ReserveInventoryTask",
            lambda_function=self.inventory_service_function,
            payload=sfn.TaskInput.from_object({
                "tableName": self.inventory_table.table_name,
                "productId.$": "$.productId",
                "quantity.$": "$.quantity"
            }),
            result_path="$.inventoryResult",
            retry_on_service_exceptions=True,
        )
        
        process_payment_task = sfn_tasks.LambdaInvoke(
            self, "ProcessPaymentTask",
            lambda_function=self.payment_service_function,
            payload=sfn.TaskInput.from_object({
                "tableName": self.payments_table.table_name,
                "orderId.$": "$.orderResult.Payload.orderId",
                "customerId.$": "$.customerId",
                "amount.$": "$.amount"
            }),
            result_path="$.paymentResult",
            retry_on_service_exceptions=True,
        )
        
        send_success_notification_task = sfn_tasks.LambdaInvoke(
            self, "SendSuccessNotificationTask",
            lambda_function=self.notification_service_function,
            payload=sfn.TaskInput.from_object({
                "topicArn": self.notification_topic.topic_arn,
                "subject": "Order Completed Successfully",
                "message": {
                    "orderId.$": "$.orderResult.Payload.orderId",
                    "customerId.$": "$.customerId",
                    "status": "SUCCESS",
                    "details": "Your order has been processed successfully"
                }
            }),
            result_path="$.notificationResult",
        )
        
        # Compensation tasks
        cancel_order_task = sfn_tasks.LambdaInvoke(
            self, "CancelOrderTask",
            lambda_function=self.cancel_order_function,
            payload=sfn.TaskInput.from_object({
                "tableName": self.orders_table.table_name,
                "orderId.$": "$.orderResult.Payload.orderId"
            }),
            result_path="$.cancelResult",
        )
        
        revert_inventory_task = sfn_tasks.LambdaInvoke(
            self, "RevertInventoryTask",
            lambda_function=self.revert_inventory_function,
            payload=sfn.TaskInput.from_object({
                "tableName": self.inventory_table.table_name,
                "productId.$": "$.productId",
                "quantity.$": "$.quantity"
            }),
            result_path="$.revertResult",
        )
        
        refund_payment_task = sfn_tasks.LambdaInvoke(
            self, "RefundPaymentTask",
            lambda_function=self.refund_payment_function,
            payload=sfn.TaskInput.from_object({
                "tableName": self.payments_table.table_name,
                "paymentId.$": "$.paymentResult.Payload.paymentId",
                "orderId.$": "$.orderResult.Payload.orderId",
                "customerId.$": "$.customerId",
                "amount.$": "$.amount"
            }),
            result_path="$.refundResult",
        )
        
        send_failure_notification_task = sfn_tasks.LambdaInvoke(
            self, "SendFailureNotificationTask",
            lambda_function=self.notification_service_function,
            payload=sfn.TaskInput.from_object({
                "topicArn": self.notification_topic.topic_arn,
                "subject": "Order Processing Failed",
                "message": {
                    "orderId.$": "$.orderResult.Payload.orderId",
                    "customerId.$": "$.customerId",
                    "status": "FAILED",
                    "details": "Your order could not be processed and has been cancelled"
                }
            }),
            result_path="$.notificationResult",
        )
        
        send_order_failed_notification_task = sfn_tasks.LambdaInvoke(
            self, "SendOrderFailedNotificationTask",
            lambda_function=self.notification_service_function,
            payload=sfn.TaskInput.from_object({
                "topicArn": self.notification_topic.topic_arn,
                "subject": "Order Creation Failed",
                "message": {
                    "customerId.$": "$.customerId",
                    "status": "FAILED",
                    "details": "Order creation failed"
                }
            }),
            result_path="$.notificationResult",
        )
        
        # Define end states
        success_state = sfn.Pass(
            self, "Success",
            result=sfn.Result.from_object({
                "status": "SUCCESS",
                "message": "Transaction completed successfully"
            })
        )
        
        transaction_failed_state = sfn.Pass(
            self, "TransactionFailed",
            result=sfn.Result.from_object({
                "status": "FAILED",
                "message": "Transaction failed and compensations completed"
            })
        )
        
        compensation_failed_state = sfn.Pass(
            self, "CompensationFailed",
            result=sfn.Result.from_object({
                "status": "COMPENSATION_FAILED",
                "message": "Transaction failed and compensation actions also failed"
            })
        )
        
        # Define choice conditions
        check_order_status = sfn.Choice(
            self, "CheckOrderStatus"
        ).when(
            sfn.Condition.string_equals("$.orderResult.Payload.status", "ORDER_PLACED"),
            reserve_inventory_task
        ).otherwise(
            send_order_failed_notification_task.next(transaction_failed_state)
        )
        
        check_inventory_status = sfn.Choice(
            self, "CheckInventoryStatus"
        ).when(
            sfn.Condition.string_equals("$.inventoryResult.Payload.status", "INVENTORY_RESERVED"),
            process_payment_task
        ).otherwise(
            cancel_order_task.next(send_failure_notification_task).next(transaction_failed_state)
        )
        
        check_payment_status = sfn.Choice(
            self, "CheckPaymentStatus"
        ).when(
            sfn.Condition.string_equals("$.paymentResult.Payload.status", "PAYMENT_COMPLETED"),
            send_success_notification_task.next(success_state)
        ).otherwise(
            revert_inventory_task.next(cancel_order_task).next(refund_payment_task).next(send_failure_notification_task).next(transaction_failed_state)
        )
        
        # Add error handling for compensation failures
        cancel_order_task.add_catch(
            compensation_failed_state,
            errors=["States.ALL"],
            result_path="$.compensationError"
        )
        
        revert_inventory_task.add_catch(
            compensation_failed_state,
            errors=["States.ALL"],
            result_path="$.compensationError"
        )
        
        refund_payment_task.add_catch(
            compensation_failed_state,
            errors=["States.ALL"],
            result_path="$.compensationError"
        )
        
        # Build the state machine definition
        definition = place_order_task.next(check_order_status).next(
            reserve_inventory_task.next(check_inventory_status).next(
                process_payment_task.next(check_payment_status)
            )
        )
        
        # Add error handling for main flow
        place_order_task.add_catch(
            send_order_failed_notification_task.next(transaction_failed_state),
            errors=["States.ALL"],
            result_path="$.error"
        )
        
        reserve_inventory_task.add_catch(
            cancel_order_task.next(send_failure_notification_task).next(transaction_failed_state),
            errors=["States.ALL"],
            result_path="$.error"
        )
        
        process_payment_task.add_catch(
            revert_inventory_task.next(cancel_order_task).next(refund_payment_task).next(send_failure_notification_task).next(transaction_failed_state),
            errors=["States.ALL"],
            result_path="$.error"
        )
        
        # Create the state machine
        self.saga_state_machine = sfn.StateMachine(
            self, "SagaStateMachine",
            state_machine_name=f"saga-orchestrator-{self.stack_name}",
            definition=definition,
            timeout=Duration.minutes(5),
            logs=sfn.LogOptions(
                destination=log_group,
                level=sfn.LogLevel.ALL,
                include_execution_data=True
            )
        )

    def create_api_gateway(self) -> None:
        """Create API Gateway for saga transaction initiation."""
        
        # Create REST API
        self.api = apigateway.RestApi(
            self, "SagaApi",
            rest_api_name=f"saga-api-{self.stack_name}",
            description="API for initiating saga transactions",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            )
        )
        
        # Create IAM role for API Gateway to invoke Step Functions
        api_gateway_role = iam.Role(
            self, "ApiGatewayRole",
            assumed_by=iam.ServicePrincipal("apigateway.amazonaws.com"),
            inline_policies={
                "StepFunctionsAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            actions=["states:StartExecution"],
                            resources=[self.saga_state_machine.state_machine_arn]
                        )
                    ]
                )
            }
        )
        
        # Create orders resource
        orders_resource = self.api.root.add_resource("orders")
        
        # Create Step Functions integration
        step_functions_integration = apigateway.AwsIntegration(
            service="states",
            action="StartExecution",
            options=apigateway.IntegrationOptions(
                credentials_role=api_gateway_role,
                request_templates={
                    "application/json": json.dumps({
                        "stateMachineArn": self.saga_state_machine.state_machine_arn,
                        "input": "$util.escapeJavaScript($input.body)"
                    })
                },
                integration_responses=[
                    apigateway.IntegrationResponse(
                        status_code="200",
                        response_templates={
                            "application/json": json.dumps({
                                "executionArn": "$input.path('$.executionArn')",
                                "startDate": "$input.path('$.startDate')"
                            })
                        }
                    )
                ]
            )
        )
        
        # Add POST method to orders resource
        orders_resource.add_method(
            "POST",
            step_functions_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    }
                )
            ]
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        
        CfnOutput(
            self, "ApiEndpoint",
            value=self.api.url,
            description="API Gateway endpoint URL"
        )
        
        CfnOutput(
            self, "StateMachineArn",
            value=self.saga_state_machine.state_machine_arn,
            description="Step Functions state machine ARN"
        )
        
        CfnOutput(
            self, "OrdersTableName",
            value=self.orders_table.table_name,
            description="Orders DynamoDB table name"
        )
        
        CfnOutput(
            self, "InventoryTableName",
            value=self.inventory_table.table_name,
            description="Inventory DynamoDB table name"
        )
        
        CfnOutput(
            self, "PaymentsTableName",
            value=self.payments_table.table_name,
            description="Payments DynamoDB table name"
        )
        
        CfnOutput(
            self, "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS notification topic ARN"
        )


# CDK App
app = cdk.App()

# Create stack
saga_stack = SagaPatternStack(
    app, "SagaPatternStack",
    description="Saga Pattern with Step Functions for Distributed Transactions",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

# Add tags
cdk.Tags.of(saga_stack).add("Project", "SagaPattern")
cdk.Tags.of(saga_stack).add("Environment", "Demo")

app.synth()