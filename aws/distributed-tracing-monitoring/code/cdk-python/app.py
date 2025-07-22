#!/usr/bin/env python3
"""
AWS CDK Application for Infrastructure Monitoring with AWS X-Ray

This CDK application deploys a complete serverless infrastructure monitoring solution
using AWS X-Ray for distributed tracing, including:
- API Gateway with X-Ray tracing
- Lambda functions with X-Ray instrumentation
- DynamoDB table with X-Ray tracing
- Custom sampling rules and filter groups
- CloudWatch dashboard and alarms
- Automated trace analysis

Author: AWS CDK Team
Version: 1.0
"""

import os
from aws_cdk import App, Environment
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_lambda as _lambda,
    aws_apigateway as apigateway,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_xray as xray,
    aws_cloudwatch as cloudwatch,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
)


class XRayMonitoringStack(Stack):
    """
    CDK Stack for Infrastructure Monitoring with AWS X-Ray
    
    This stack creates a comprehensive distributed tracing solution using AWS X-Ray
    to monitor serverless applications with full observability capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create DynamoDB table with X-Ray tracing enabled
        self.orders_table = self._create_dynamodb_table()
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda functions with X-Ray tracing
        self.order_processor = self._create_order_processor_function()
        self.inventory_manager = self._create_inventory_manager_function()
        self.trace_analyzer = self._create_trace_analyzer_function()
        
        # Create API Gateway with X-Ray tracing
        self.api = self._create_api_gateway()
        
        # Create X-Ray resources
        self._create_xray_sampling_rules()
        self._create_xray_filter_groups()
        
        # Create CloudWatch dashboard and alarms
        self._create_cloudwatch_dashboard()
        self._create_cloudwatch_alarms()
        
        # Create EventBridge rule for automated trace analysis
        self._create_eventbridge_rule()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """Create DynamoDB table for storing order data with X-Ray tracing."""
        table = dynamodb.Table(
            self, "OrdersTable",
            table_name=f"{self.stack_name}-orders",
            partition_key=dynamodb.Attribute(
                name="orderId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=5,
            write_capacity=5,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )
        
        # Add tags
        table.node.default_child.add_metadata("Project", self.stack_name)
        
        return table

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with necessary permissions."""
        role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"{self.stack_name}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSXRayDaemonWriteAccess"
                ),
            ],
        )
        
        # Add DynamoDB permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                ],
                resources=[self.orders_table.table_arn],
            )
        )
        
        # Add X-Ray permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "xray:GetTraceSummaries",
                    "xray:BatchGetTraces",
                    "xray:GetServiceGraph",
                ],
                resources=["*"],
            )
        )
        
        # Add CloudWatch permissions for custom metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_order_processor_function(self) -> _lambda.Function:
        """Create Lambda function for processing orders with X-Ray instrumentation."""
        function = _lambda.Function(
            self, "OrderProcessorFunction",
            function_name=f"{self.stack_name}-order-processor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_order_processor_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            tracing=_lambda.Tracing.ACTIVE,
            environment={
                "ORDERS_TABLE": self.orders_table.table_name,
                "_X_AMZN_TRACE_ID": "",  # Enable X-Ray tracing
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        return function

    def _create_inventory_manager_function(self) -> _lambda.Function:
        """Create Lambda function for inventory management with X-Ray instrumentation."""
        function = _lambda.Function(
            self, "InventoryManagerFunction",
            function_name=f"{self.stack_name}-inventory-manager",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_inventory_manager_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            tracing=_lambda.Tracing.ACTIVE,
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        return function

    def _create_trace_analyzer_function(self) -> _lambda.Function:
        """Create Lambda function for automated trace analysis."""
        function = _lambda.Function(
            self, "TraceAnalyzerFunction",
            function_name=f"{self.stack_name}-trace-analyzer",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_trace_analyzer_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """Create API Gateway with X-Ray tracing enabled."""
        api = apigateway.RestApi(
            self, "XRayMonitoringAPI",
            rest_api_name=f"{self.stack_name}-api",
            description="API for X-Ray monitoring demonstration",
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                tracing_enabled=True,
                metrics_enabled=True,
                logging_level=apigateway.MethodLoggingLevel.INFO,
            ),
        )
        
        # Create orders resource
        orders_resource = api.root.add_resource("orders")
        
        # Create POST method for orders
        orders_integration = apigateway.LambdaIntegration(
            self.order_processor,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'",
                    },
                )
            ],
        )
        
        orders_resource.add_method(
            "POST",
            orders_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True,
                    },
                )
            ],
        )
        
        # Add CORS
        orders_resource.add_cors_preflight(
            allow_origins=["*"],
            allow_methods=["POST", "OPTIONS"],
            allow_headers=["Content-Type", "X-Amz-Date", "Authorization"],
        )
        
        return api

    def _create_xray_sampling_rules(self) -> None:
        """Create custom X-Ray sampling rules for optimized trace collection."""
        # High priority sampling rule
        xray.CfnSamplingRule(
            self, "HighPrioritySamplingRule",
            sampling_rule=xray.CfnSamplingRule.SamplingRuleProperty(
                rule_name="high-priority-requests",
                resource_arn="*",
                priority=100,
                fixed_rate=1.0,
                reservoir_size=10,
                service_name="order-processor",
                service_type="*",
                host="*",
                http_method="*",
                url_path="*",
                version=1,
            ),
        )
        
        # Error traces sampling rule
        xray.CfnSamplingRule(
            self, "ErrorTracesSamplingRule",
            sampling_rule=xray.CfnSamplingRule.SamplingRuleProperty(
                rule_name="error-traces",
                resource_arn="*",
                priority=50,
                fixed_rate=1.0,
                reservoir_size=5,
                service_name="*",
                service_type="*",
                host="*",
                http_method="*",
                url_path="*",
                version=1,
            ),
        )

    def _create_xray_filter_groups(self) -> None:
        """Create X-Ray filter groups for organized trace analysis."""
        # High latency requests filter group
        xray.CfnGroup(
            self, "HighLatencyGroup",
            group_name="high-latency-requests",
            filter_expression="responsetime > 2",
        )
        
        # Error traces filter group
        xray.CfnGroup(
            self, "ErrorTracesGroup",
            group_name="error-traces",
            filter_expression="error = true OR fault = true",
        )
        
        # Order processor service filter group
        xray.CfnGroup(
            self, "OrderProcessorGroup",
            group_name="order-processor-service",
            filter_expression='service("order-processor")',
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for X-Ray metrics visualization."""
        dashboard = cloudwatch.Dashboard(
            self, "XRayDashboard",
            dashboard_name=f"{self.stack_name}-xray-monitoring",
        )
        
        # X-Ray metrics widget
        xray_widget = cloudwatch.GraphWidget(
            title="X-Ray Trace Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/X-Ray",
                    metric_name="TracesReceived",
                    statistic="Sum",
                ),
                cloudwatch.Metric(
                    namespace="AWS/X-Ray",
                    metric_name="TracesScanned",
                    statistic="Sum",
                ),
                cloudwatch.Metric(
                    namespace="AWS/X-Ray",
                    metric_name="LatencyHigh",
                    statistic="Sum",
                ),
            ],
            width=12,
            height=6,
        )
        
        # Lambda metrics widget
        lambda_widget = cloudwatch.GraphWidget(
            title="Lambda Function Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Duration",
                    dimensions_map={
                        "FunctionName": self.order_processor.function_name,
                    },
                    statistic="Average",
                ),
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Errors",
                    dimensions_map={
                        "FunctionName": self.order_processor.function_name,
                    },
                    statistic="Sum",
                ),
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Throttles",
                    dimensions_map={
                        "FunctionName": self.order_processor.function_name,
                    },
                    statistic="Sum",
                ),
            ],
            width=12,
            height=6,
        )
        
        # Custom metrics widget
        custom_widget = cloudwatch.GraphWidget(
            title="Custom X-Ray Analysis Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="XRay/Analysis",
                    metric_name="TotalTraces",
                    statistic="Sum",
                ),
                cloudwatch.Metric(
                    namespace="XRay/Analysis",
                    metric_name="ErrorTraces",
                    statistic="Sum",
                ),
                cloudwatch.Metric(
                    namespace="XRay/Analysis",
                    metric_name="HighLatencyTraces",
                    statistic="Sum",
                ),
            ],
            width=12,
            height=6,
        )
        
        dashboard.add_widgets(xray_widget)
        dashboard.add_widgets(lambda_widget)
        dashboard.add_widgets(custom_widget)

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for performance monitoring."""
        # High error rate alarm
        cloudwatch.Alarm(
            self, "HighErrorRateAlarm",
            alarm_name=f"{self.stack_name}-high-error-rate",
            alarm_description="High error rate detected in X-Ray traces",
            metric=cloudwatch.Metric(
                namespace="XRay/Analysis",
                metric_name="ErrorTraces",
                statistic="Sum",
            ),
            threshold=5,
            evaluation_periods=2,
            period=Duration.minutes(5),
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        # High latency alarm
        cloudwatch.Alarm(
            self, "HighLatencyAlarm",
            alarm_name=f"{self.stack_name}-high-latency",
            alarm_description="High latency detected in X-Ray traces",
            metric=cloudwatch.Metric(
                namespace="XRay/Analysis",
                metric_name="HighLatencyTraces",
                statistic="Sum",
            ),
            threshold=3,
            evaluation_periods=1,
            period=Duration.minutes(5),
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

    def _create_eventbridge_rule(self) -> None:
        """Create EventBridge rule for automated trace analysis."""
        rule = events.Rule(
            self, "TraceAnalysisRule",
            rule_name=f"{self.stack_name}-trace-analysis",
            description="Trigger automated trace analysis every hour",
            schedule=events.Schedule.rate(Duration.hours(1)),
        )
        
        rule.add_target(targets.LambdaFunction(self.trace_analyzer))

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "APIEndpoint",
            value=self.api.url,
            description="API Gateway endpoint URL",
        )
        
        CfnOutput(
            self, "OrdersTableName",
            value=self.orders_table.table_name,
            description="DynamoDB table name for orders",
        )
        
        CfnOutput(
            self, "OrderProcessorFunctionName",
            value=self.order_processor.function_name,
            description="Order processor Lambda function name",
        )
        
        CfnOutput(
            self, "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.stack_name}-xray-monitoring",
            description="CloudWatch dashboard URL",
        )
        
        CfnOutput(
            self, "XRayConsoleURL",
            value=f"https://{self.region}.console.aws.amazon.com/xray/home?region={self.region}#/service-map",
            description="X-Ray service map console URL",
        )

    def _get_order_processor_code(self) -> str:
        """Return the Lambda function code for order processing."""
        return '''
import json
import boto3
import uuid
from datetime import datetime
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
import os

# Patch AWS SDK calls for X-Ray tracing
patch_all()

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['ORDERS_TABLE'])

@xray_recorder.capture('process_order')
def lambda_handler(event, context):
    try:
        # Add custom annotations for filtering
        xray_recorder.put_annotation('service', 'order-processor')
        xray_recorder.put_annotation('operation', 'create_order')
        
        # Extract order details
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        
        order_id = str(uuid.uuid4())
        order_data = {
            'orderId': order_id,
            'customerId': body.get('customerId'),
            'productId': body.get('productId'),
            'quantity': body.get('quantity', 1),
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'pending'
        }
        
        # Add custom metadata
        xray_recorder.put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': body.get('customerId'),
            'product_id': body.get('productId')
        })
        
        # Store order in DynamoDB
        with xray_recorder.in_subsegment('dynamodb_put_item'):
            table.put_item(Item=order_data)
        
        # Simulate calling inventory service
        inventory_response = check_inventory(body.get('productId'))
        
        # Simulate calling notification service
        notification_response = send_notification(order_id, body.get('customerId'))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'orderId': order_id,
                'status': 'processed',
                'inventory': inventory_response,
                'notification': notification_response
            })
        }
        
    except Exception as e:
        xray_recorder.put_annotation('error', str(e))
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

@xray_recorder.capture('check_inventory')
def check_inventory(product_id):
    # Simulate inventory check with artificial delay
    import time
    time.sleep(0.1)
    
    xray_recorder.put_annotation('inventory_check', 'completed')
    return {'status': 'available', 'quantity': 100}

@xray_recorder.capture('send_notification')
def send_notification(order_id, customer_id):
    # Simulate notification sending
    import time
    time.sleep(0.05)
    
    xray_recorder.put_annotation('notification_sent', 'true')
    return {'status': 'sent', 'channel': 'email'}
'''

    def _get_inventory_manager_code(self) -> str:
        """Return the Lambda function code for inventory management."""
        return '''
import json
import boto3
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
import time

# Patch AWS SDK calls for X-Ray tracing
patch_all()

@xray_recorder.capture('inventory_manager')
def lambda_handler(event, context):
    try:
        xray_recorder.put_annotation('service', 'inventory-manager')
        xray_recorder.put_annotation('operation', 'update_inventory')
        
        # Simulate inventory processing
        with xray_recorder.in_subsegment('inventory_validation'):
            product_id = event.get('productId')
            quantity = event.get('quantity', 1)
            
            # Simulate database lookup
            time.sleep(0.1)
            
            xray_recorder.put_metadata('inventory_check', {
                'product_id': product_id,
                'requested_quantity': quantity,
                'available_quantity': 100
            })
        
        # Simulate inventory update
        with xray_recorder.in_subsegment('inventory_update'):
            time.sleep(0.05)
            xray_recorder.put_annotation('inventory_updated', 'true')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'productId': product_id,
                'status': 'reserved',
                'availableQuantity': 100 - quantity
            })
        }
        
    except Exception as e:
        xray_recorder.put_annotation('error', str(e))
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

    def _get_trace_analyzer_code(self) -> str:
        """Return the Lambda function code for automated trace analysis."""
        return '''
import json
import boto3
from datetime import datetime, timedelta

xray_client = boto3.client('xray')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Get traces from last hour
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        # Get trace summaries
        response = xray_client.get_trace_summaries(
            TimeRangeType='TimeStamp',
            StartTime=start_time,
            EndTime=end_time,
            FilterExpression='service("order-processor")'
        )
        
        # Analyze traces
        total_traces = len(response['TraceSummaries'])
        error_traces = len([t for t in response['TraceSummaries'] if t.get('IsError')])
        high_latency_traces = len([t for t in response['TraceSummaries'] if t.get('ResponseTime', 0) > 2])
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='XRay/Analysis',
            MetricData=[
                {
                    'MetricName': 'TotalTraces',
                    'Value': total_traces,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'ErrorTraces',
                    'Value': error_traces,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'HighLatencyTraces',
                    'Value': high_latency_traces,
                    'Unit': 'Count'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'total_traces': total_traces,
                'error_traces': error_traces,
                'high_latency_traces': high_latency_traces
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get environment settings
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION"),
    )
    
    # Create the stack
    XRayMonitoringStack(
        app,
        "XRayMonitoringStack",
        env=env,
        description="Infrastructure Monitoring with AWS X-Ray - CDK Python Implementation",
    )
    
    app.synth()


if __name__ == "__main__":
    main()