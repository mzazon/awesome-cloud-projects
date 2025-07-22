#!/usr/bin/env python3
"""
Business Process Automation with Step Functions CDK Application

This CDK application deploys a complete business process automation solution
using AWS Step Functions, Lambda, SQS, SNS, and API Gateway. The solution
demonstrates workflow orchestration with human approval patterns, error handling,
and integration with multiple AWS services.

Architecture Components:
- Step Functions state machine for workflow orchestration
- Lambda function for business logic processing
- SQS queue for task completion logging
- SNS topic for notifications and human approvals
- API Gateway for human approval callbacks
- IAM roles with least privilege permissions

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_sqs as sqs,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_apigateway as apigateway,
    aws_logs as logs,
)
from constructs import Construct


class BusinessProcessAutomationStack(Stack):
    """
    CDK Stack for Business Process Automation with Step Functions.
    
    This stack creates a complete workflow automation solution including:
    - Lambda function for business logic processing
    - SQS queue for completed task logging
    - SNS topic for notifications and human approvals
    - Step Functions state machine for workflow orchestration
    - API Gateway for human approval callbacks
    - Appropriate IAM roles and permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters for customization
        self.business_process_prefix = self.node.try_get_context("business_process_prefix") or "business-process"
        self.notification_email = self.node.try_get_context("notification_email") or "user@example.com"
        
        # Create Lambda function for business logic processing
        self.processor_function = self._create_processor_function()
        
        # Create SQS queue for task completion logging
        self.completion_queue = self._create_completion_queue()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create Step Functions state machine
        self.state_machine = self._create_state_machine()
        
        # Create API Gateway for human approvals
        self.approval_api = self._create_approval_api()
        
        # Create CloudWatch log group for state machine
        self.state_machine_logs = self._create_log_group()
        
        # Output important resource information
        self._create_outputs()

    def _create_processor_function(self) -> _lambda.Function:
        """
        Create Lambda function for business logic processing.
        
        This function handles the core business logic processing within
        the Step Functions workflow, including data validation,
        business rule execution, and result generation.
        
        Returns:
            _lambda.Function: The configured Lambda function
        """
        # Create Lambda execution role with necessary permissions
        lambda_role = iam.Role(
            self, "ProcessorFunctionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Lambda function code
        function_code = '''
import json
import boto3
import time
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process business logic for workflow automation.
    
    Args:
        event: Input event containing process data
        context: Lambda runtime context
        
    Returns:
        dict: Processing result with status and metadata
    """
    try:
        logger.info(f"Processing business logic for event: {json.dumps(event)}")
        
        # Extract business process data
        process_data = event.get('processData', {})
        process_type = process_data.get('type', 'unknown')
        process_id = process_data.get('processId', 'unknown')
        
        # Simulate business logic processing time
        processing_time = min(process_data.get('processingTime', 2), 25)  # Cap at 25 seconds
        logger.info(f"Simulating {processing_time} seconds of processing for {process_type}")
        time.sleep(processing_time)
        
        # Generate processing result based on business rules
        result = {
            'processId': process_id,
            'processType': process_type,
            'status': 'processed',
            'timestamp': datetime.utcnow().isoformat(),
            'result': f"Successfully processed {process_type} business process",
            'metadata': {
                'processingDuration': processing_time,
                'processedBy': 'automated-system',
                'validationStatus': 'passed'
            }
        }
        
        logger.info(f"Processing completed successfully: {json.dumps(result)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result),
            'processResult': result
        }
        
    except Exception as e:
        logger.error(f"Error processing business logic: {str(e)}")
        raise Exception(f"Business processing failed: {str(e)}")
'''

        return _lambda.Function(
            self, "ProcessorFunction",
            function_name=f"{self.business_process_prefix}-processor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(function_code),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            description="Business logic processor for workflow automation",
            environment={
                "LOG_LEVEL": "INFO",
                "BUSINESS_PROCESS_PREFIX": self.business_process_prefix
            }
        )

    def _create_completion_queue(self) -> sqs.Queue:
        """
        Create SQS queue for task completion logging.
        
        This queue receives completion messages from the Step Functions
        workflow, providing durable storage for audit logs and enabling
        integration with downstream business systems.
        
        Returns:
            sqs.Queue: The configured SQS queue
        """
        # Create dead letter queue for failed messages
        dlq = sqs.Queue(
            self, "CompletionQueueDLQ",
            queue_name=f"{self.business_process_prefix}-completion-dlq",
            retention_period=Duration.days(14)
        )

        return sqs.Queue(
            self, "CompletionQueue",
            queue_name=f"{self.business_process_prefix}-completion",
            visibility_timeout=Duration.minutes(5),
            retention_period=Duration.days(14),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=dlq
            )
        )

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for notifications and human approvals.
        
        This topic handles both automated notifications and human
        approval workflows using the Step Functions callback pattern.
        
        Returns:
            sns.Topic: The configured SNS topic
        """
        topic = sns.Topic(
            self, "NotificationTopic",
            topic_name=f"{self.business_process_prefix}-notifications",
            display_name="Business Process Notifications",
            description="Notifications for business process automation workflows"
        )

        # Add email subscription for notifications
        if self.notification_email and self.notification_email != "user@example.com":
            topic.add_subscription(
                sns_subscriptions.EmailSubscription(self.notification_email)
            )

        return topic

    def _create_state_machine(self) -> sfn.StateMachine:
        """
        Create Step Functions state machine for workflow orchestration.
        
        This state machine implements the complete business process automation
        workflow including validation, processing, human approval, notifications,
        and completion logging with comprehensive error handling.
        
        Returns:
            sfn.StateMachine: The configured state machine
        """
        # Create execution role for Step Functions
        state_machine_role = iam.Role(
            self, "StateMachineRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            description="Execution role for business process automation state machine"
        )

        # Grant permissions to invoke Lambda function
        self.processor_function.grant_invoke(state_machine_role)
        
        # Grant permissions to publish to SNS topic
        self.notification_topic.grant_publish(state_machine_role)
        
        # Grant permissions to send messages to SQS queue
        self.completion_queue.grant_send_messages(state_machine_role)

        # Grant CloudWatch Logs permissions
        state_machine_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]
            )
        )

        # Define state machine workflow
        
        # Input validation state
        validate_input = sfn.Pass(
            self, "ValidateInput",
            comment="Validate and prepare input data for processing",
            parameters={
                "processData.$": "$.processData",
                "validationResult": "Input validated successfully",
                "validationTimestamp.$": "$$.State.EnteredTime"
            }
        )

        # Business logic processing state
        process_business_logic = sfn_tasks.LambdaInvoke(
            self, "ProcessBusinessLogic",
            lambda_function=self.processor_function,
            comment="Execute core business logic processing",
            retry_on_service_exceptions=True,
            payload_response_only=True
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(5),
            max_attempts=3,
            backoff_rate=2.0
        ).add_catch(
            errors=["States.ALL"],
            handler=self._create_processing_failed_state()
        )

        # Human approval state using callback pattern
        human_approval = sfn_tasks.SnsPublish(
            self, "HumanApprovalRequired",
            topic=self.notification_topic,
            message=sfn.TaskInput.from_object({
                "processId": sfn.JsonPath.string_at("$.processResult.processId"),
                "processType": sfn.JsonPath.string_at("$.processResult.processType"),
                "approvalRequired": "Please approve this business process",
                "approvalUrl": f"https://{self.approval_api.rest_api_id if hasattr(self, 'approval_api') else 'API_GATEWAY_ID'}.execute-api.{self.region}.amazonaws.com/prod/approval",
                "taskToken": sfn.JsonPath.task_token
            }),
            subject="Business Process Approval Required",
            comment="Request human approval with callback token",
            integration_pattern=sfn.IntegrationPattern.WAIT_FOR_TASK_TOKEN,
            heartbeat=Duration.hours(1),
            timeout=Duration.hours(24)
        )

        # Completion notification state
        send_completion_notification = sfn_tasks.SnsPublish(
            self, "SendCompletionNotification",
            topic=self.notification_topic,
            message=sfn.TaskInput.from_object({
                "processId": sfn.JsonPath.string_at("$.processResult.processId"),
                "status": "completed",
                "message": "Business process completed successfully",
                "completionTime": sfn.JsonPath.string_at("$$.State.EnteredTime")
            }),
            subject="Business Process Completed",
            comment="Notify stakeholders of successful completion"
        )

        # Log completion to SQS queue
        log_to_queue = sfn_tasks.SqsSendMessage(
            self, "LogToQueue",
            queue=self.completion_queue,
            message_body=sfn.TaskInput.from_object({
                "processId": sfn.JsonPath.string_at("$.processResult.processId"),
                "completionTime": sfn.JsonPath.string_at("$$.State.EnteredTime"),
                "status": "completed",
                "executionArn": sfn.JsonPath.string_at("$$.Execution.Name"),
                "auditTrail": {
                    "validatedAt": sfn.JsonPath.string_at("$.validationTimestamp"),
                    "processedAt": sfn.JsonPath.string_at("$.processResult.timestamp"),
                    "approvedAt": sfn.JsonPath.string_at("$$.State.EnteredTime")
                }
            }),
            comment="Log process completion for audit and downstream processing"
        )

        # Define workflow chain
        definition = validate_input.next(
            process_business_logic.next(
                human_approval.next(
                    send_completion_notification.next(log_to_queue)
                )
            )
        )

        return sfn.StateMachine(
            self, "BusinessProcessStateMachine",
            state_machine_name=f"{self.business_process_prefix}-workflow",
            definition=definition,
            role=state_machine_role,
            timeout=Duration.hours(24),
            comment="Business process automation workflow with human approval"
        )

    def _create_processing_failed_state(self) -> sfn.State:
        """
        Create error handling state for processing failures.
        
        Returns:
            sfn.State: Error notification state
        """
        return sfn_tasks.SnsPublish(
            self, "ProcessingFailed",
            topic=self.notification_topic,
            message=sfn.TaskInput.from_object({
                "error": "Business process failed",
                "details": sfn.JsonPath.string_at("$.Error"),
                "executionArn": sfn.JsonPath.string_at("$$.Execution.Name"),
                "failureTime": sfn.JsonPath.string_at("$$.State.EnteredTime")
            }),
            subject="Business Process Failed",
            comment="Notify stakeholders of processing failure"
        )

    def _create_approval_api(self) -> apigateway.RestApi:
        """
        Create API Gateway for human approval callbacks.
        
        This API provides endpoints for stakeholders to submit approval
        decisions that resume paused Step Functions executions.
        
        Returns:
            apigateway.RestApi: The configured API Gateway
        """
        # Create Lambda function for handling approval callbacks
        approval_handler_code = '''
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    """
    Handle human approval callbacks from API Gateway.
    
    Args:
        event: API Gateway event containing approval decision
        context: Lambda runtime context
        
    Returns:
        dict: API Gateway response
    """
    try:
        # Parse request body
        if event.get('body'):
            body = json.loads(event['body'])
        else:
            body = event
            
        task_token = body.get('taskToken')
        approved = body.get('approved', False)
        approver = body.get('approver', 'unknown')
        comments = body.get('comments', '')
        
        if not task_token:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing taskToken'})
            }
        
        # Prepare approval result
        approval_result = {
            'approved': approved,
            'approver': approver,
            'approvalTime': json.dumps(datetime.utcnow(), default=str),
            'comments': comments
        }
        
        # Send task success to Step Functions
        if approved:
            stepfunctions.send_task_success(
                taskToken=task_token,
                output=json.dumps(approval_result)
            )
            logger.info(f"Approval granted by {approver}")
        else:
            stepfunctions.send_task_failure(
                taskToken=task_token,
                error='ApprovalDenied',
                cause=f'Process denied by {approver}: {comments}'
            )
            logger.info(f"Approval denied by {approver}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Approval processed successfully',
                'approved': approved
            }),
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        }
        
    except Exception as e:
        logger.error(f"Error processing approval: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

        # Create approval handler Lambda function
        approval_handler = _lambda.Function(
            self, "ApprovalHandler",
            function_name=f"{self.business_process_prefix}-approval-handler",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(approval_handler_code),
            timeout=Duration.seconds(30),
            description="Handle human approval callbacks for Step Functions"
        )

        # Grant permission to send task success/failure to Step Functions
        approval_handler.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "states:SendTaskSuccess",
                    "states:SendTaskFailure"
                ],
                resources=["*"]
            )
        )

        # Create API Gateway
        api = apigateway.RestApi(
            self, "ApprovalApi",
            rest_api_name=f"{self.business_process_prefix}-approval-api",
            description="API for business process approval callbacks",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            )
        )

        # Create approval resource and method
        approval_resource = api.root.add_resource("approval")
        approval_integration = apigateway.LambdaIntegration(approval_handler)
        
        approval_resource.add_method(
            "POST",
            approval_integration,
            method_responses=[
                apigateway.MethodResponse(status_code="200"),
                apigateway.MethodResponse(status_code="400"),
                apigateway.MethodResponse(status_code="500")
            ]
        )

        return api

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for Step Functions execution logs.
        
        Returns:
            logs.LogGroup: The configured log group
        """
        return logs.LogGroup(
            self, "StateMachineLogGroup",
            log_group_name=f"/aws/stepfunctions/{self.business_process_prefix}-workflow",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self, "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="ARN of the business process automation state machine",
            export_name=f"{self.stack_name}-StateMachineArn"
        )

        CfnOutput(
            self, "ProcessorFunctionArn",
            value=self.processor_function.function_arn,
            description="ARN of the business logic processor Lambda function",
            export_name=f"{self.stack_name}-ProcessorFunctionArn"
        )

        CfnOutput(
            self, "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for notifications",
            export_name=f"{self.stack_name}-NotificationTopicArn"
        )

        CfnOutput(
            self, "CompletionQueueUrl",
            value=self.completion_queue.queue_url,
            description="URL of the SQS queue for completion logging",
            export_name=f"{self.stack_name}-CompletionQueueUrl"
        )

        CfnOutput(
            self, "ApprovalApiUrl",
            value=self.approval_api.url,
            description="URL of the API Gateway for human approvals",
            export_name=f"{self.stack_name}-ApprovalApiUrl"
        )

        CfnOutput(
            self, "ApprovalEndpoint",
            value=f"{self.approval_api.url}approval",
            description="Complete endpoint URL for approval submissions",
            export_name=f"{self.stack_name}-ApprovalEndpoint"
        )


class BusinessProcessAutomationApp(cdk.App):
    """
    CDK Application for Business Process Automation.
    
    This application creates a comprehensive business process automation
    solution using AWS Step Functions and related services.
    """

    def __init__(self):
        super().__init__()

        # Environment configuration
        env = cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
        )

        # Create the main stack
        BusinessProcessAutomationStack(
            self, "BusinessProcessAutomationStack",
            env=env,
            description="Business Process Automation with Step Functions, Lambda, SQS, SNS, and API Gateway"
        )


# Application entry point
if __name__ == "__main__":
    app = BusinessProcessAutomationApp()
    app.synth()