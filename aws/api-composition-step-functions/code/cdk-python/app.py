#!/usr/bin/env python3
"""
CDK Python application for API Composition with Step Functions and API Gateway.

This application creates a comprehensive serverless solution that demonstrates
API composition patterns using AWS Step Functions and API Gateway to orchestrate
multiple microservices.
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_apigateway as apigateway,
    aws_lambda as _lambda,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class ApiCompositionStack(Stack):
    """
    Stack that implements API composition using Step Functions and API Gateway.
    
    This stack creates:
    - DynamoDB tables for orders and audit logging
    - Lambda functions representing microservices
    - Step Functions state machine for workflow orchestration
    - API Gateway with direct integrations
    - IAM roles with least privilege permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create DynamoDB tables
        self._create_dynamodb_tables()
        
        # Create Lambda functions for microservices
        self._create_lambda_functions()
        
        # Create Step Functions state machine
        self._create_step_functions_workflow()
        
        # Create API Gateway
        self._create_api_gateway()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_tables(self) -> None:
        """Create DynamoDB tables for orders and audit logging."""
        
        # Orders table
        self.orders_table = dynamodb.Table(
            self, "OrdersTable",
            table_name=f"{self.stack_name}-orders",
            partition_key=dynamodb.Attribute(
                name="orderId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
        )

        # Audit table
        self.audit_table = dynamodb.Table(
            self, "AuditTable",
            table_name=f"{self.stack_name}-audit",
            partition_key=dynamodb.Attribute(
                name="auditId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
        )

        # Add GSI for audit table to query by orderId
        self.audit_table.add_global_secondary_index(
            index_name="orderIdIndex",
            partition_key=dynamodb.Attribute(
                name="orderId",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions representing microservices."""
        
        # User service Lambda function
        self.user_service_function = _lambda.Function(
            self, "UserServiceFunction",
            function_name=f"{self.stack_name}-user-service",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import random

def lambda_handler(event, context):
    \"\"\"Mock user validation service.\"\"\"
    user_id = event.get('userId', '')
    
    # Mock user validation
    if not user_id or len(user_id) < 3:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'valid': False,
                'error': 'Invalid user ID'
            })
        }
    
    # Simulate user data retrieval
    user_data = {
        'valid': True,
        'userId': user_id,
        'name': f'User {user_id}',
        'email': f'{user_id}@example.com',
        'creditLimit': random.randint(1000, 5000)
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(user_data)
    }
            """),
            timeout=Duration.seconds(30),
            memory_size=128,
            tracing=_lambda.Tracing.ACTIVE,
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Inventory service Lambda function
        self.inventory_service_function = _lambda.Function(
            self, "InventoryServiceFunction",
            function_name=f"{self.stack_name}-inventory-service",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import random

def lambda_handler(event, context):
    \"\"\"Mock inventory management service.\"\"\"
    items = event.get('items', [])
    
    inventory_status = []
    for item in items:
        available = random.randint(0, 100)
        requested = item.get('quantity', 0)
        
        inventory_status.append({
            'productId': item.get('productId'),
            'requested': requested,
            'available': available,
            'sufficient': available >= requested,
            'price': random.randint(10, 500)
        })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'inventoryStatus': inventory_status,
            'allItemsAvailable': all(item['sufficient'] for item in inventory_status)
        })
    }
            """),
            timeout=Duration.seconds(30),
            memory_size=128,
            tracing=_lambda.Tracing.ACTIVE,
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Payment service Lambda function
        self.payment_service_function = _lambda.Function(
            self, "PaymentServiceFunction",
            function_name=f"{self.stack_name}-payment-service",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import random

def lambda_handler(event, context):
    \"\"\"Mock payment processing service.\"\"\"
    order_total = event.get('orderTotal', 0)
    user_id = event.get('userId', '')
    
    # Simulate payment processing
    success_rate = 0.9  # 90% success rate for demo
    payment_successful = random.random() < success_rate
    
    if payment_successful:
        return {
            'statusCode': 200,
            'body': json.dumps({
                'paymentSuccessful': True,
                'transactionId': f'txn-{random.randint(10000, 99999)}',
                'amount': order_total,
                'userId': user_id
            })
        }
    else:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'paymentSuccessful': False,
                'error': 'Payment processing failed'
            })
        }
            """),
            timeout=Duration.seconds(30),
            memory_size=128,
            tracing=_lambda.Tracing.ACTIVE,
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

    def _create_step_functions_workflow(self) -> None:
        """Create Step Functions state machine for order processing workflow."""
        
        # Create IAM role for Step Functions
        self.step_functions_role = iam.Role(
            self, "StepFunctionsRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaRole")
            ]
        )

        # Grant permissions to access DynamoDB tables
        self.orders_table.grant_read_write_data(self.step_functions_role)
        self.audit_table.grant_read_write_data(self.step_functions_role)

        # Grant permissions to invoke Lambda functions
        self.user_service_function.grant_invoke(self.step_functions_role)
        self.inventory_service_function.grant_invoke(self.step_functions_role)
        self.payment_service_function.grant_invoke(self.step_functions_role)

        # Define state machine tasks
        validate_user_task = sfn_tasks.LambdaInvoke(
            self, "ValidateUser",
            lambda_function=self.user_service_function,
            payload=sfn.TaskInput.from_object({
                "userId": sfn.JsonPath.string_at("$.userId")
            }),
            result_path="$.userValidation",
            retry_on_service_exceptions=True
        )

        check_inventory_task = sfn_tasks.LambdaInvoke(
            self, "CheckInventory",
            lambda_function=self.inventory_service_function,
            payload=sfn.TaskInput.from_object({
                "items": sfn.JsonPath.string_at("$.items")
            }),
            result_path="$.inventoryCheck",
            retry_on_service_exceptions=True
        )

        process_payment_task = sfn_tasks.LambdaInvoke(
            self, "ProcessPayment",
            lambda_function=self.payment_service_function,
            payload=sfn.TaskInput.from_object({
                "orderTotal": sfn.JsonPath.number_at("$.orderTotal"),
                "userId": sfn.JsonPath.string_at("$.userId")
            }),
            result_path="$.paymentResult",
            retry_on_service_exceptions=True
        )

        save_order_task = sfn_tasks.DynamoPutItem(
            self, "SaveOrder",
            table=self.orders_table,
            item={
                "orderId": sfn_tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$.orderId")
                ),
                "userId": sfn_tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$.userId")
                ),
                "status": sfn_tasks.DynamoAttributeValue.from_string("processing"),
                "orderTotal": sfn_tasks.DynamoAttributeValue.from_number(
                    sfn.JsonPath.number_at("$.orderTotal")
                ),
                "timestamp": sfn_tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$$.State.EnteredTime")
                )
            },
            result_path="$.orderSaved"
        )

        log_audit_task = sfn_tasks.DynamoPutItem(
            self, "LogAudit",
            table=self.audit_table,
            item={
                "auditId": sfn_tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$$.Execution.Name")
                ),
                "orderId": sfn_tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$.orderId")
                ),
                "action": sfn_tasks.DynamoAttributeValue.from_string("order_created"),
                "timestamp": sfn_tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$$.State.EnteredTime")
                )
            },
            result_path="$.auditLogged"
        )

        # Define success and failure states
        order_successful = sfn.Pass(
            self, "OrderSuccessful",
            parameters={
                "orderId": sfn.JsonPath.string_at("$.orderId"),
                "status": "completed",
                "message": "Order processed successfully"
            }
        )

        order_failed = sfn.Pass(
            self, "OrderFailed",
            parameters={
                "orderId": sfn.JsonPath.string_at("$.orderId"),
                "status": "failed",
                "message": "Order processing failed"
            }
        )

        # Define choice conditions
        user_valid_choice = sfn.Choice(self, "IsUserValid")
        user_valid_choice.when(
            sfn.Condition.string_matches(
                "$.userValidation.Payload.body", "*\"valid\":true*"
            ),
            check_inventory_task
        ).otherwise(order_failed)

        inventory_available_choice = sfn.Choice(self, "IsInventoryAvailable")
        inventory_available_choice.when(
            sfn.Condition.string_matches(
                "$.inventoryCheck.Payload.body", "*\"allItemsAvailable\":true*"
            ),
            process_payment_task
        ).otherwise(order_failed)

        payment_successful_choice = sfn.Choice(self, "IsPaymentSuccessful")
        payment_successful_choice.when(
            sfn.Condition.string_matches(
                "$.paymentResult.Payload.body", "*\"paymentSuccessful\":true*"
            ),
            sfn.Parallel(self, "ParallelProcessing")
            .branch(save_order_task)
            .branch(log_audit_task)
            .next(order_successful)
        ).otherwise(order_failed)

        # Define the workflow
        definition = validate_user_task \
            .next(user_valid_choice) \
            .next(inventory_available_choice) \
            .next(payment_successful_choice)

        # Create state machine
        self.state_machine = sfn.StateMachine(
            self, "OrderProcessingStateMachine",
            state_machine_name=f"{self.stack_name}-order-processing",
            definition=definition,
            role=self.step_functions_role,
            tracing_enabled=True,
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self, "StateMachineLogGroup",
                    log_group_name=f"/aws/stepfunctions/{self.stack_name}-order-processing",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY
                ),
                level=sfn.LogLevel.ALL
            )
        )

    def _create_api_gateway(self) -> None:
        """Create API Gateway with Step Functions and DynamoDB integrations."""
        
        # Create API Gateway
        self.api = apigateway.RestApi(
            self, "CompositionApi",
            rest_api_name=f"{self.stack_name}-composition-api",
            description="API Composition with Step Functions",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization"]
            ),
            deploy=True,
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                tracing_enabled=True,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            )
        )

        # Create IAM role for API Gateway to access AWS services
        self.api_gateway_role = iam.Role(
            self, "ApiGatewayRole",
            assumed_by=iam.ServicePrincipal("apigateway.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSStepFunctionsFullAccess")
            ]
        )

        # Grant API Gateway permissions to read from DynamoDB
        self.orders_table.grant_read_data(self.api_gateway_role)

        # Create orders resource
        orders_resource = self.api.root.add_resource("orders")

        # Create POST method for order creation (Step Functions integration)
        orders_resource.add_method(
            "POST",
            apigateway.AwsIntegration(
                service="states",
                action="StartExecution",
                integration_http_method="POST",
                options=apigateway.IntegrationOptions(
                    credentials_role=self.api_gateway_role,
                    request_templates={
                        "application/json": f'''{{
                            "input": "$util.escapeJavaScript($input.json('$$'))",
                            "stateMachineArn": "{self.state_machine.state_machine_arn}"
                        }}'''
                    },
                    integration_responses=[
                        apigateway.IntegrationResponse(
                            status_code="200",
                            response_templates={
                                "application/json": '''{{
                                    "executionArn": "$input.json('$.executionArn')",
                                    "message": "Order processing started"
                                }}'''
                            }
                        )
                    ]
                )
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

        # Create order ID resource for status checking
        order_id_resource = orders_resource.add_resource("{orderId}")
        status_resource = order_id_resource.add_resource("status")

        # Create GET method for order status (DynamoDB integration)
        status_resource.add_method(
            "GET",
            apigateway.AwsIntegration(
                service="dynamodb",
                action="GetItem",
                integration_http_method="POST",
                options=apigateway.IntegrationOptions(
                    credentials_role=self.api_gateway_role,
                    request_templates={
                        "application/json": f'''{{
                            "TableName": "{self.orders_table.table_name}",
                            "Key": {{
                                "orderId": {{
                                    "S": "$input.params('orderId')"
                                }}
                            }}
                        }}'''
                    },
                    integration_responses=[
                        apigateway.IntegrationResponse(
                            status_code="200",
                            response_templates={
                                "application/json": '''{{
                                    "orderId": "$input.json('$.Item.orderId.S')",
                                    "status": "$input.json('$.Item.status.S')",
                                    "orderTotal": "$input.json('$.Item.orderTotal.N')",
                                    "timestamp": "$input.json('$.Item.timestamp.S')"
                                }}'''
                            }
                        )
                    ]
                )
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    }
                )
            ],
            request_parameters={
                "method.request.path.orderId": True
            }
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        cdk.CfnOutput(
            self, "ApiEndpoint",
            value=self.api.url,
            description="API Gateway endpoint URL"
        )

        cdk.CfnOutput(
            self, "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="Step Functions state machine ARN"
        )

        cdk.CfnOutput(
            self, "OrdersTableName",
            value=self.orders_table.table_name,
            description="DynamoDB orders table name"
        )

        cdk.CfnOutput(
            self, "AuditTableName",
            value=self.audit_table.table_name,
            description="DynamoDB audit table name"
        )

        cdk.CfnOutput(
            self, "UserServiceFunctionName",
            value=self.user_service_function.function_name,
            description="User service Lambda function name"
        )

        cdk.CfnOutput(
            self, "InventoryServiceFunctionName",
            value=self.inventory_service_function.function_name,
            description="Inventory service Lambda function name"
        )

        cdk.CfnOutput(
            self, "PaymentServiceFunctionName",
            value=self.payment_service_function.function_name,
            description="Payment service Lambda function name"
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get environment configuration
    env = cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    )
    
    # Create the stack
    ApiCompositionStack(
        app, "ApiCompositionStack",
        env=env,
        description="API Composition with Step Functions and API Gateway"
    )
    
    app.synth()


if __name__ == "__main__":
    main()