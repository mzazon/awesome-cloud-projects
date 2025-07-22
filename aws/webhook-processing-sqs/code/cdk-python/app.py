#!/usr/bin/env python3
"""
CDK Python application for webhook processing system with API Gateway and SQS.

This application creates a complete webhook processing infrastructure including:
- API Gateway REST API for webhook ingestion
- SQS queue with dead letter queue for message buffering
- Lambda function for webhook processing
- DynamoDB table for webhook history
- CloudWatch alarms for monitoring
- IAM roles and policies for secure service integration

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_apigateway as apigw,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_lambda_event_sources as event_sources,
    aws_logs as logs,
    aws_sqs as sqs,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_sns as sns,
)
from constructs import Construct


class WebhookProcessingStack(Stack):
    """
    CDK Stack for webhook processing system using API Gateway, SQS, and Lambda.
    
    This stack implements a serverless, scalable webhook processing system that:
    - Receives webhooks via API Gateway
    - Queues messages in SQS for reliable processing
    - Processes webhooks asynchronously with Lambda
    - Stores webhook history in DynamoDB
    - Provides monitoring and alerting via CloudWatch
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        self.resource_suffix = self.node.try_get_context("resource_suffix") or "dev"
        
        # Create DynamoDB table for webhook history
        self.webhook_table = self._create_webhook_table()
        
        # Create SQS queues (DLQ first, then main queue)
        self.dead_letter_queue = self._create_dead_letter_queue()
        self.webhook_queue = self._create_webhook_queue()
        
        # Create Lambda function for webhook processing
        self.webhook_processor = self._create_webhook_processor()
        
        # Create API Gateway for webhook ingestion
        self.api_gateway = self._create_api_gateway()
        
        # Create CloudWatch alarms for monitoring
        self._create_monitoring_alarms()
        
        # Create stack outputs
        self._create_outputs()

    def _create_webhook_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing webhook processing history.
        
        Returns:
            DynamoDB table with composite primary key for efficient querying
        """
        table = dynamodb.Table(
            self, "WebhookHistoryTable",
            table_name=f"webhook-history-{self.resource_suffix}",
            partition_key=dynamodb.Attribute(
                name="webhook_id",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )
        
        # Add global secondary index for querying by webhook type
        table.add_global_secondary_index(
            index_name="webhook-type-index",
            partition_key=dynamodb.Attribute(
                name="webhook_type",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING
            )
        )
        
        # Tag the table for resource management
        cdk.Tags.of(table).add("Purpose", "WebhookProcessing")
        cdk.Tags.of(table).add("Environment", self.resource_suffix)
        
        return table

    def _create_dead_letter_queue(self) -> sqs.Queue:
        """
        Create SQS dead letter queue for failed webhook processing.
        
        Returns:
            SQS queue configured for dead letter message handling
        """
        dlq = sqs.Queue(
            self, "WebhookDeadLetterQueue",
            queue_name=f"webhook-dlq-{self.resource_suffix}",
            retention_period=Duration.days(14),
            visibility_timeout=Duration.seconds(60)
        )
        
        # Tag the queue for resource management
        cdk.Tags.of(dlq).add("Purpose", "WebhookProcessingDLQ")
        cdk.Tags.of(dlq).add("Environment", self.resource_suffix)
        
        return dlq

    def _create_webhook_queue(self) -> sqs.Queue:
        """
        Create primary SQS queue for webhook message buffering.
        
        Returns:
            SQS queue with dead letter queue configuration
        """
        queue = sqs.Queue(
            self, "WebhookProcessingQueue",
            queue_name=f"webhook-processing-queue-{self.resource_suffix}",
            retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            )
        )
        
        # Tag the queue for resource management
        cdk.Tags.of(queue).add("Purpose", "WebhookProcessing")
        cdk.Tags.of(queue).add("Environment", self.resource_suffix)
        
        return queue

    def _create_webhook_processor(self) -> lambda_.Function:
        """
        Create Lambda function for processing webhook messages.
        
        Returns:
            Lambda function with appropriate IAM permissions and event source mapping
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "WebhookProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Grant DynamoDB permissions
        self.webhook_table.grant_read_write_data(lambda_role)
        
        # Grant SQS permissions
        self.webhook_queue.grant_consume_messages(lambda_role)
        
        # Create Lambda function
        webhook_function = lambda_.Function(
            self, "WebhookProcessor",
            function_name=f"webhook-processor-{self.resource_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="webhook_processor.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "WEBHOOK_TABLE_NAME": self.webhook_table.table_name,
                "DLQ_NAME": self.dead_letter_queue.queue_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Processes webhook messages from SQS queue"
        )
        
        # Create event source mapping for SQS
        webhook_function.add_event_source(
            event_sources.SqsEventSource(
                self.webhook_queue,
                batch_size=10,
                max_batching_window=Duration.seconds(5)
            )
        )
        
        # Tag the function for resource management
        cdk.Tags.of(webhook_function).add("Purpose", "WebhookProcessing")
        cdk.Tags.of(webhook_function).add("Environment", self.resource_suffix)
        
        return webhook_function

    def _create_api_gateway(self) -> apigw.RestApi:
        """
        Create API Gateway REST API for webhook ingestion.
        
        Returns:
            API Gateway with direct SQS integration
        """
        # Create API Gateway execution role
        api_role = iam.Role(
            self, "ApiGatewaySqsRole",
            assumed_by=iam.ServicePrincipal("apigateway.amazonaws.com")
        )
        
        # Grant SQS permissions to API Gateway
        self.webhook_queue.grant_send_messages(api_role)
        
        # Create REST API
        api = apigw.RestApi(
            self, "WebhookApi",
            rest_api_name=f"webhook-api-{self.resource_suffix}",
            description="REST API for webhook processing system",
            endpoint_configuration=apigw.EndpointConfiguration(
                types=[apigw.EndpointType.REGIONAL]
            ),
            deploy_options=apigw.StageOptions(
                stage_name="prod",
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
                logging_level=apigw.MethodLoggingLevel.INFO,
                data_trace_enabled=True
            )
        )
        
        # Create /webhooks resource
        webhooks_resource = api.root.add_resource("webhooks")
        
        # Create SQS integration
        sqs_integration = apigw.AwsIntegration(
            service="sqs",
            path=f"{self.account}/{self.webhook_queue.queue_name}",
            integration_http_method="POST",
            options=apigw.IntegrationOptions(
                credentials_role=api_role,
                request_parameters={
                    "integration.request.header.Content-Type": "'application/x-www-form-urlencoded'"
                },
                request_templates={
                    "application/json": 'Action=SendMessage&MessageBody=$util.urlEncode(\'{"source_ip":"$context.identity.sourceIp","timestamp":"$context.requestTime","body":$input.json(\'$\')}\')'
                },
                integration_responses=[
                    apigw.IntegrationResponse(
                        status_code="200",
                        response_templates={
                            "application/json": '{"message": "Webhook received and queued for processing", "requestId": "$context.requestId"}'
                        }
                    )
                ]
            )
        )
        
        # Add POST method to /webhooks
        webhooks_resource.add_method(
            "POST",
            sqs_integration,
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigw.Model.EMPTY_MODEL
                    }
                )
            ]
        )
        
        # Tag the API for resource management
        cdk.Tags.of(api).add("Purpose", "WebhookProcessing")
        cdk.Tags.of(api).add("Environment", self.resource_suffix)
        
        return api

    def _create_monitoring_alarms(self) -> None:
        """
        Create CloudWatch alarms for monitoring webhook processing system.
        """
        # Create SNS topic for alarm notifications
        alarm_topic = sns.Topic(
            self, "WebhookAlarmsNotification",
            topic_name=f"webhook-alarms-{self.resource_suffix}",
            display_name="Webhook Processing Alarms"
        )
        
        # Alarm for dead letter queue messages
        dlq_alarm = cloudwatch.Alarm(
            self, "DeadLetterQueueAlarm",
            alarm_name=f"webhook-dlq-messages-{self.resource_suffix}",
            alarm_description="Alert when messages appear in webhook dead letter queue",
            metric=self.dead_letter_queue.metric_approximate_number_of_visible_messages(),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )
        
        # Alarm for Lambda function errors
        lambda_error_alarm = cloudwatch.Alarm(
            self, "LambdaErrorAlarm",
            alarm_name=f"webhook-lambda-errors-{self.resource_suffix}",
            alarm_description="Alert on Lambda function errors",
            metric=self.webhook_processor.metric_errors(),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        
        # Alarm for API Gateway 4XX errors
        api_error_alarm = cloudwatch.Alarm(
            self, "ApiGateway4xxAlarm",
            alarm_name=f"webhook-api-4xx-errors-{self.resource_suffix}",
            alarm_description="Alert on API Gateway 4XX errors",
            metric=self.api_gateway.metric_client_error(),
            threshold=10,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        
        # Add SNS actions to alarms
        dlq_alarm.add_alarm_action(cw_actions.SnsAction(alarm_topic))
        lambda_error_alarm.add_alarm_action(cw_actions.SnsAction(alarm_topic))
        api_error_alarm.add_alarm_action(cw_actions.SnsAction(alarm_topic))

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        cdk.CfnOutput(
            self, "WebhookEndpointUrl",
            value=f"{self.api_gateway.url}webhooks",
            description="URL endpoint for webhook submissions"
        )
        
        cdk.CfnOutput(
            self, "WebhookTableName",
            value=self.webhook_table.table_name,
            description="DynamoDB table name for webhook history"
        )
        
        cdk.CfnOutput(
            self, "WebhookQueueName",
            value=self.webhook_queue.queue_name,
            description="SQS queue name for webhook processing"
        )
        
        cdk.CfnOutput(
            self, "WebhookProcessorName",
            value=self.webhook_processor.function_name,
            description="Lambda function name for webhook processing"
        )
        
        cdk.CfnOutput(
            self, "DeadLetterQueueName",
            value=self.dead_letter_queue.queue_name,
            description="SQS dead letter queue name for failed messages"
        )

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for webhook processing.
        
        Returns:
            Python code string for the Lambda function
        """
        return """
import json
import boto3
import uuid
import os
from datetime import datetime
import logging
from typing import Dict, Any, List

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['WEBHOOK_TABLE_NAME'])


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process webhook messages from SQS queue.
    
    Args:
        event: SQS event containing webhook messages
        context: Lambda context object
        
    Returns:
        Response indicating processing status
    """
    try:
        processed_count = 0
        failed_count = 0
        
        # Process each SQS record
        for record in event['Records']:
            try:
                # Parse the webhook payload
                webhook_body = json.loads(record['body'])
                
                # Generate unique webhook ID
                webhook_id = str(uuid.uuid4())
                timestamp = datetime.utcnow().isoformat()
                
                # Extract webhook metadata
                source_ip = webhook_body.get('source_ip', 'unknown')
                webhook_type = webhook_body.get('body', {}).get('type', 'unknown')
                
                # Process the webhook
                processed_data = process_webhook(webhook_body.get('body', {}))
                
                # Store in DynamoDB
                table.put_item(
                    Item={
                        'webhook_id': webhook_id,
                        'timestamp': timestamp,
                        'source_ip': source_ip,
                        'webhook_type': webhook_type,
                        'raw_payload': json.dumps(webhook_body),
                        'processed_data': json.dumps(processed_data),
                        'status': 'processed',
                        'message_id': record.get('messageId', 'unknown')
                    }
                )
                
                logger.info(f"Processed webhook {webhook_id} of type {webhook_type}")
                processed_count += 1
                
            except Exception as e:
                logger.error(f"Error processing individual webhook: {str(e)}")
                failed_count += 1
                # Continue processing other messages in the batch
                continue
        
        logger.info(f"Batch processing complete. Processed: {processed_count}, Failed: {failed_count}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Webhook batch processed',
                'processed_count': processed_count,
                'failed_count': failed_count
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing webhook batch: {str(e)}")
        raise


def process_webhook(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process individual webhook payload.
    
    Args:
        payload: Webhook payload data
        
    Returns:
        Processed webhook data
    """
    try:
        processed = {
            'processed_at': datetime.utcnow().isoformat(),
            'payload_size': len(json.dumps(payload)),
            'contains_sensitive_data': check_sensitive_data(payload),
            'webhook_version': payload.get('version', 'unknown'),
            'event_type': payload.get('type', 'unknown')
        }
        
        # Add business logic specific processing here
        if payload.get('type') == 'payment.completed':
            processed['payment_amount'] = payload.get('amount', 0)
            processed['currency'] = payload.get('currency', 'USD')
            processed['payment_processed'] = True
            
        elif payload.get('type') == 'user.created':
            processed['user_id'] = payload.get('user_id', 'unknown')
            processed['user_processed'] = True
            
        return processed
        
    except Exception as e:
        logger.error(f"Error in webhook processing: {str(e)}")
        return {
            'processed_at': datetime.utcnow().isoformat(),
            'error': str(e),
            'status': 'processing_failed'
        }


def check_sensitive_data(payload: Dict[str, Any]) -> bool:
    """
    Check if webhook payload contains sensitive data.
    
    Args:
        payload: Webhook payload to check
        
    Returns:
        True if sensitive data is detected, False otherwise
    """
    try:
        sensitive_keys = [
            'credit_card', 'creditcard', 'cc_number',
            'ssn', 'social_security',
            'password', 'passwd', 'secret',
            'api_key', 'apikey', 'token',
            'private_key', 'privatekey'
        ]
        
        payload_str = json.dumps(payload).lower()
        
        for key in sensitive_keys:
            if key in payload_str:
                logger.warning(f"Sensitive data detected: {key}")
                return True
                
        return False
        
    except Exception as e:
        logger.error(f"Error checking sensitive data: {str(e)}")
        return False
"""


def create_app() -> cdk.App:
    """
    Create and configure the CDK application.
    
    Returns:
        Configured CDK application
    """
    app = cdk.App()
    
    # Create the webhook processing stack
    WebhookProcessingStack(
        app, 
        "WebhookProcessingStack",
        env=cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION')
        ),
        description="Webhook processing system with API Gateway, SQS, and Lambda"
    )
    
    return app


if __name__ == "__main__":
    app = create_app()
    app.synth()