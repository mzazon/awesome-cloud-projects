#!/usr/bin/env python3
"""
Real-Time Collaborative Task Management with Aurora DSQL and EventBridge

This CDK application deploys a serverless task management system using:
- Aurora DSQL for multi-region distributed database
- EventBridge for event-driven architecture
- Lambda for serverless task processing
- CloudWatch for monitoring and logging

Architecture:
- Multi-region Aurora DSQL cluster for strong consistency
- EventBridge custom bus for task event routing
- Lambda functions for task processing in multiple regions
- CloudWatch for comprehensive monitoring
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    aws_dsql as dsql,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
)
from typing import Dict, List, Optional
from constructs import Construct


class TaskManagementStack(Stack):
    """
    Main stack for the real-time collaborative task management system.
    
    Creates a complete serverless architecture with Aurora DSQL, EventBridge,
    and Lambda functions across multiple regions for high availability.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        primary_region: str = "us-east-1",
        secondary_region: str = "us-west-2",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store regions for multi-region deployment
        self.primary_region = primary_region
        self.secondary_region = secondary_region

        # Create Aurora DSQL multi-region cluster
        self._create_dsql_cluster()

        # Create EventBridge custom bus
        self._create_event_bus()

        # Create IAM role for Lambda functions
        self._create_lambda_execution_role()

        # Create Lambda function for task processing
        self._create_task_processor_lambda()

        # Create EventBridge rules and targets
        self._create_eventbridge_rules()

        # Create CloudWatch monitoring
        self._create_monitoring()

        # Create outputs
        self._create_outputs()

    def _create_dsql_cluster(self) -> None:
        """
        Create Aurora DSQL multi-region cluster for distributed task storage.
        
        Aurora DSQL provides active-active multi-region capabilities with
        strong consistency and automatic scaling.
        """
        # Generate unique cluster name
        cluster_suffix = self.node.try_get_context("cluster_suffix") or "001"
        
        # Primary cluster
        self.dsql_primary_cluster = dsql.CfnCluster(
            self,
            "DSQLPrimaryCluster",
            cluster_identifier=f"task-mgmt-cluster-primary-{cluster_suffix}",
            engine="aurora-dsql",
            database_name="task_management",
            deletion_protection=False,  # Set to True for production
            backup_retention_period=7,
            preferred_backup_window="03:00-04:00",
            preferred_maintenance_window="sun:04:00-sun:05:00",
            tags=[
                cdk.CfnTag(key="Environment", value="development"),
                cdk.CfnTag(key="Application", value="TaskManagement"),
                cdk.CfnTag(key="Region", value="primary")
            ]
        )

        # Note: Secondary cluster would be created in a separate stack
        # deployed to the secondary region due to CDK's single-region limitation
        # For this demonstration, we'll create the configuration template

    def _create_event_bus(self) -> None:
        """
        Create custom EventBridge bus for task management events.
        
        Provides isolated event routing for task operations with
        flexible filtering and targeting capabilities.
        """
        self.event_bus = events.EventBus(
            self,
            "TaskEventBus",
            event_bus_name="task-events-bus",
            description="Custom event bus for task management events"
        )

        # Create event source mapping for task events
        self.task_event_source = events.CfnEventSourceMapping(
            self,
            "TaskEventSource",
            event_source_name="task.management"
        )

    def _create_lambda_execution_role(self) -> None:
        """
        Create IAM role with necessary permissions for Lambda functions.
        
        Follows principle of least privilege while enabling required
        service integrations for Aurora DSQL, EventBridge, and CloudWatch.
        """
        self.lambda_role = iam.Role(
            self,
            "TaskProcessorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for task processor Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add Aurora DSQL permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dsql:DescribeCluster",
                    "dsql:Execute",
                    "dsql:BatchExecute",
                    "dsql:Connect"
                ],
                resources=["*"]  # Restrict to specific cluster ARNs in production
            )
        )

        # Add EventBridge permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "events:PutEvents",
                    "events:DescribeEventBus"
                ],
                resources=[
                    self.event_bus.event_bus_arn,
                    f"arn:aws:events:*:{self.account}:event-bus/*"
                ]
            )
        )

        # Add CloudWatch permissions for enhanced monitoring
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]
            )
        )

    def _create_task_processor_lambda(self) -> None:
        """
        Create Lambda function for processing task operations.
        
        Handles both EventBridge events and direct API requests with
        Aurora DSQL integration for data persistence.
        """
        # Create Lambda function
        self.task_processor = lambda_.Function(
            self,
            "TaskProcessorFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="task_processor.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=512,
            description="Processes task management events and API requests",
            environment={
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
                "DSQL_ENDPOINT": self.dsql_primary_cluster.attr_endpoint,
                "DB_NAME": "task_management",
                "AWS_REGION": self.region
            },
            reserved_concurrent_executions=100,  # Limit concurrency for cost control
        )

        # Create log group with retention
        logs.LogGroup(
            self,
            "TaskProcessorLogGroup",
            log_group_name=f"/aws/lambda/{self.task_processor.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

    def _create_eventbridge_rules(self) -> None:
        """
        Create EventBridge rules for routing task events to Lambda function.
        
        Enables event-driven architecture with automatic scaling and
        fault tolerance for task processing operations.
        """
        # Rule for task creation events
        self.task_creation_rule = events.Rule(
            self,
            "TaskCreationRule",
            event_bus=self.event_bus,
            rule_name="task-creation-processing",
            description="Routes task creation events to processor",
            event_pattern=events.EventPattern(
                source=["task.management"],
                detail_type=["Task Created"],
                detail={
                    "eventType": ["task.created"]
                }
            ),
            enabled=True
        )

        # Rule for task update events
        self.task_update_rule = events.Rule(
            self,
            "TaskUpdateRule",
            event_bus=self.event_bus,
            rule_name="task-update-processing",
            description="Routes task update events to processor",
            event_pattern=events.EventPattern(
                source=["task.management"],
                detail_type=["Task Updated"],
                detail={
                    "eventType": ["task.updated"]
                }
            ),
            enabled=True
        )

        # Rule for task completion events
        self.task_completion_rule = events.Rule(
            self,
            "TaskCompletionRule",
            event_bus=self.event_bus,
            rule_name="task-completion-processing",
            description="Routes task completion events to processor",
            event_pattern=events.EventPattern(
                source=["task.management"],
                detail_type=["Task Completed"],
                detail={
                    "eventType": ["task.completed"]
                }
            ),
            enabled=True
        )

        # Add Lambda targets to rules
        for rule in [self.task_creation_rule, self.task_update_rule, self.task_completion_rule]:
            rule.add_target(
                targets.LambdaFunction(
                    self.task_processor,
                    retry_attempts=3,
                    max_event_age=Duration.hours(2)
                )
            )

    def _create_monitoring(self) -> None:
        """
        Create CloudWatch alarms and dashboard for system monitoring.
        
        Provides comprehensive observability for Lambda functions,
        EventBridge events, and overall system health.
        """
        # Create CloudWatch alarms
        self.lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"{self.task_processor.function_name}-errors",
            alarm_description="Monitor Lambda function errors",
            metric=self.task_processor.metric_errors(
                period=Duration.minutes(5),
                statistic=cloudwatch.Statistic.SUM
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        self.lambda_duration_alarm = cloudwatch.Alarm(
            self,
            "LambdaDurationAlarm",
            alarm_name=f"{self.task_processor.function_name}-duration",
            alarm_description="Monitor Lambda function duration",
            metric=self.task_processor.metric_duration(
                period=Duration.minutes(5),
                statistic=cloudwatch.Statistic.AVERAGE
            ),
            threshold=30000,  # 30 seconds
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "TaskManagementDashboard",
            dashboard_name="TaskManagementSystem",
            period_override=cloudwatch.PeriodOverride.AUTO
        )

        # Add widgets to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                width=12,
                height=6,
                left=[
                    self.task_processor.metric_invocations(
                        label="Invocations",
                        color=cloudwatch.Color.BLUE
                    ),
                    self.task_processor.metric_errors(
                        label="Errors",
                        color=cloudwatch.Color.RED
                    ),
                    self.task_processor.metric_throttles(
                        label="Throttles",
                        color=cloudwatch.Color.ORANGE
                    )
                ]
            ),
            cloudwatch.GraphWidget(
                title="Lambda Duration and Memory",
                width=12,
                height=6,
                left=[
                    self.task_processor.metric_duration(
                        label="Duration (ms)",
                        color=cloudwatch.Color.GREEN
                    )
                ]
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "DSQLClusterEndpoint",
            value=self.dsql_primary_cluster.attr_endpoint,
            description="Aurora DSQL primary cluster endpoint",
            export_name=f"{self.stack_name}-dsql-endpoint"
        )

        CfnOutput(
            self,
            "EventBusArn",
            value=self.event_bus.event_bus_arn,
            description="Task management EventBridge bus ARN",
            export_name=f"{self.stack_name}-event-bus-arn"
        )

        CfnOutput(
            self,
            "TaskProcessorFunctionArn",
            value=self.task_processor.function_arn,
            description="Task processor Lambda function ARN",
            export_name=f"{self.stack_name}-lambda-arn"
        )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for monitoring",
            export_name=f"{self.stack_name}-dashboard-url"
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code for task processing.
        
        This is a simplified version for CDK deployment. In production,
        consider using Lambda layers or external deployment packages.
        """
        return """
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
events_client = boto3.client('events')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    \"\"\"
    Main Lambda handler for task processing operations.
    
    Processes both EventBridge events and direct API requests,
    handling task creation, updates, and completion with proper
    error handling and monitoring integration.
    \"\"\"
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Process EventBridge event
        if 'source' in event and event['source'] == 'task.management':
            return process_task_event(event)
        
        # Process direct API invocation
        return process_api_request(event)
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        
        # Publish custom CloudWatch metric for errors
        publish_metric('TaskProcessingErrors', 1)
        
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': str(e),
                'message': 'Internal server error during task processing'
            })
        }

def process_task_event(event: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Process task management events from EventBridge.\"\"\"
    detail = event.get('detail', {})
    event_type = detail.get('eventType')
    
    logger.info(f"Processing task event: {event_type}")
    
    if event_type == 'task.created':
        return handle_task_created(detail)
    elif event_type == 'task.updated':
        return handle_task_updated(detail)
    elif event_type == 'task.completed':
        return handle_task_completed(detail)
    else:
        logger.warning(f"Unknown event type: {event_type}")
        return {
            'statusCode': 400,
            'body': json.dumps({'error': f'Unknown event type: {event_type}'})
        }

def handle_task_created(detail: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Handle task creation events with database persistence.\"\"\"
    task_data = detail.get('taskData', {})
    
    # Simulate database insertion (replace with actual Aurora DSQL connection)
    task_id = simulate_task_creation(task_data)
    
    # Publish success metric
    publish_metric('TasksCreated', 1)
    
    # Publish notification event
    publish_task_notification('task.created', task_id, task_data)
    
    logger.info(f"Task created successfully with ID: {task_id}")
    return {
        'statusCode': 200,
        'body': json.dumps({
            'task_id': task_id,
            'message': 'Task created successfully'
        })
    }

def handle_task_updated(detail: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Handle task update events with change tracking.\"\"\"
    task_id = detail.get('taskId')
    updates = detail.get('updates', {})
    updated_by = detail.get('updatedBy')
    
    # Simulate database update (replace with actual Aurora DSQL connection)
    simulate_task_update(task_id, updates, updated_by)
    
    # Publish success metric
    publish_metric('TasksUpdated', 1)
    
    # Publish notification event
    publish_task_notification('task.updated', task_id, updates)
    
    logger.info(f"Task {task_id} updated successfully")
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Task updated successfully'})
    }

def handle_task_completed(detail: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Handle task completion events.\"\"\"
    task_id = detail.get('taskId')
    completed_by = detail.get('completedBy')
    
    # Simulate database update (replace with actual Aurora DSQL connection)
    simulate_task_completion(task_id, completed_by)
    
    # Publish success metric
    publish_metric('TasksCompleted', 1)
    
    # Publish notification event
    publish_task_notification('task.completed', task_id, {'completed_by': completed_by})
    
    logger.info(f"Task {task_id} completed by {completed_by}")
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Task completed successfully'})
    }

def process_api_request(event: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Process direct API requests for task operations.\"\"\"
    method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    logger.info(f"Processing API request: {method} {path}")
    
    if method == 'GET' and path == '/tasks':
        return get_all_tasks()
    elif method == 'POST' and path == '/tasks':
        body = json.loads(event.get('body', '{}'))
        return create_task_api(body)
    elif method == 'PUT' and '/tasks/' in path:
        task_id = path.split('/')[-1]
        body = json.loads(event.get('body', '{}'))
        return update_task_api(task_id, body)
    else:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Endpoint not found'})
        }

def get_all_tasks() -> Dict[str, Any]:
    \"\"\"Retrieve all tasks from database.\"\"\"
    # Simulate database query (replace with actual Aurora DSQL connection)
    tasks = simulate_get_tasks()
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'tasks': tasks})
    }

def create_task_api(task_data: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Create new task via API.\"\"\"
    task_id = simulate_task_creation(task_data)
    
    # Publish creation event
    publish_task_notification('task.created', task_id, task_data)
    
    return {
        'statusCode': 201,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'task_id': task_id,
            'message': 'Task created successfully'
        })
    }

def update_task_api(task_id: str, updates: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Update existing task via API.\"\"\"
    simulate_task_update(task_id, updates, 'api_user')
    
    # Publish update event
    publish_task_notification('task.updated', task_id, updates)
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'message': 'Task updated successfully'})
    }

def publish_task_notification(event_type: str, task_id: str, data: Dict[str, Any]) -> None:
    \"\"\"Publish task notification to EventBridge.\"\"\"
    try:
        events_client.put_events(
            Entries=[
                {
                    'Source': 'task.management.notifications',
                    'DetailType': 'Task Notification',
                    'Detail': json.dumps({
                        'eventType': event_type,
                        'taskId': task_id,
                        'data': data,
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        logger.info(f"Published notification for {event_type}: {task_id}")
    except Exception as e:
        logger.error(f"Failed to publish notification: {str(e)}")

def publish_metric(metric_name: str, value: float, unit: str = 'Count') -> None:
    \"\"\"Publish custom CloudWatch metric.\"\"\"
    try:
        cloudwatch.put_metric_data(
            Namespace='TaskManagement',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': unit,
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        logger.error(f"Failed to publish metric {metric_name}: {str(e)}")

# Simulation functions (replace with actual Aurora DSQL operations)
def simulate_task_creation(task_data: Dict[str, Any]) -> str:
    \"\"\"Simulate task creation in database.\"\"\"
    import uuid
    task_id = str(uuid.uuid4())
    logger.info(f"Simulated task creation: {task_id}")
    return task_id

def simulate_task_update(task_id: str, updates: Dict[str, Any], updated_by: str) -> None:
    \"\"\"Simulate task update in database.\"\"\"
    logger.info(f"Simulated task update: {task_id} by {updated_by}")

def simulate_task_completion(task_id: str, completed_by: str) -> None:
    \"\"\"Simulate task completion in database.\"\"\"
    logger.info(f"Simulated task completion: {task_id} by {completed_by}")

def simulate_get_tasks() -> list:
    \"\"\"Simulate retrieving tasks from database.\"\"\"
    return [
        {
            'id': '1',
            'title': 'Sample Task',
            'status': 'pending',
            'created_at': datetime.utcnow().isoformat()
        }
    ]
"""


class TaskManagementApp(cdk.App):
    """
    CDK Application for the Real-Time Collaborative Task Management System.
    
    This application creates the complete infrastructure needed for a
    serverless, multi-region task management system with real-time
    collaboration capabilities.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from context or use defaults
        primary_region = self.node.try_get_context("primary_region") or "us-east-1"
        secondary_region = self.node.try_get_context("secondary_region") or "us-west-2"
        environment_name = self.node.try_get_context("environment") or "dev"

        # Create primary stack
        primary_stack = TaskManagementStack(
            self,
            f"TaskManagementStack-{environment_name}",
            primary_region=primary_region,
            secondary_region=secondary_region,
            description=f"Real-time collaborative task management system ({environment_name})",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=primary_region
            )
        )

        # Add tags to all resources
        cdk.Tags.of(primary_stack).add("Project", "TaskManagement")
        cdk.Tags.of(primary_stack).add("Environment", environment_name)
        cdk.Tags.of(primary_stack).add("ManagedBy", "CDK")


# Initialize the CDK application
app = TaskManagementApp()
app.synth()