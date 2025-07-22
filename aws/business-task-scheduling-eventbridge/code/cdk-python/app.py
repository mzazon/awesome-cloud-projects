#!/usr/bin/env python3
"""
AWS CDK Python application for automated business task scheduling.

This application creates infrastructure for automated business workflows using:
- EventBridge Scheduler for flexible scheduling
- Lambda functions for task processing
- S3 bucket for report storage
- SNS topic for notifications
- IAM roles with least privilege access
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_s3 as s3,
    aws_sns as sns,
    aws_iam as iam,
    aws_scheduler as scheduler,
    aws_logs as logs,
)
from constructs import Construct


class BusinessTaskSchedulingStack(Stack):
    """
    CDK Stack for automated business task scheduling infrastructure.
    
    Creates a complete serverless automation system with EventBridge Scheduler,
    Lambda functions, S3 storage, and SNS notifications for business workflows.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "dev"
        
        # Create S3 bucket for report storage
        self.reports_bucket = self._create_s3_bucket(unique_suffix)
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_sns_topic(unique_suffix)
        
        # Create Lambda function for business task processing
        self.task_processor_function = self._create_lambda_function(unique_suffix)
        
        # Create IAM role for EventBridge Scheduler
        self.scheduler_role = self._create_scheduler_role()
        
        # Create EventBridge schedules
        self._create_schedules()
        
        # Create schedule group for organization
        self._create_schedule_group()
        
        # Output important ARNs
        self._create_outputs()

    def _create_s3_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for storing generated reports and processed data.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self,
            "ReportsBucket",
            bucket_name=f"business-automation-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ReportArchiving",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )
        
        # Add tags for cost tracking
        cdk.Tags.of(bucket).add("Environment", "Production")
        cdk.Tags.of(bucket).add("Department", "Operations")
        cdk.Tags.of(bucket).add("Application", "BusinessAutomation")
        
        return bucket

    def _create_sns_topic(self, unique_suffix: str) -> sns.Topic:
        """
        Create SNS topic for business notifications.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            SNS Topic construct
        """
        topic = sns.Topic(
            self,
            "NotificationTopic",
            topic_name=f"business-notifications-{unique_suffix}",
            display_name="Business Automation Notifications",
            fifo=False
        )
        
        # Add email subscription (can be configured via context)
        email = self.node.try_get_context("notification_email")
        if email:
            topic.add_subscription(
                sns.Subscription(
                    self,
                    "EmailSubscription",
                    topic=topic,
                    endpoint=email,
                    protocol=sns.SubscriptionProtocol.EMAIL
                )
            )
        
        return topic

    def _create_lambda_function(self, unique_suffix: str) -> _lambda.Function:
        """
        Create Lambda function for processing business tasks.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            Lambda Function construct
        """
        # Create IAM role for Lambda with minimal permissions
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"lambda-execution-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Grant S3 permissions
        self.reports_bucket.grant_read_write(lambda_role)
        
        # Grant SNS publish permissions
        self.notification_topic.grant_publish(lambda_role)
        
        # Create Lambda function
        function = _lambda.Function(
            self,
            "TaskProcessorFunction",
            function_name=f"business-task-processor-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="business_task_processor.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=lambda_role,
            environment={
                "BUCKET_NAME": self.reports_bucket.bucket_name,
                "TOPIC_ARN": self.notification_topic.topic_arn,
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            description="Processes automated business tasks including report generation, data processing, and notifications"
        )
        
        return function

    def _create_scheduler_role(self) -> iam.Role:
        """
        Create IAM role for EventBridge Scheduler with minimal permissions.
        
        Returns:
            IAM Role construct for EventBridge Scheduler
        """
        role = iam.Role(
            self,
            "SchedulerExecutionRole",
            assumed_by=iam.ServicePrincipal("scheduler.amazonaws.com"),
            inline_policies={
                "LambdaInvokePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["lambda:InvokeFunction"],
                            resources=[self.task_processor_function.function_arn]
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_schedules(self) -> None:
        """Create EventBridge schedules for different business automation tasks."""
        
        # Daily report schedule (9 AM ET)
        scheduler.Schedule(
            self,
            "DailyReportSchedule",
            schedule_name="daily-report-schedule",
            schedule=scheduler.ScheduleExpression.cron(
                minute="0",
                hour="13",  # 9 AM ET = 13 UTC
                day="*",
                month="*",
                week_day="*"
            ),
            target=scheduler.ScheduleTargetConfig(
                arn=self.task_processor_function.function_arn,
                role_arn=self.scheduler_role.role_arn,
                input='{"task_type": "report"}'
            ),
            description="Daily business report generation at 9 AM ET",
            flexible_time_window=scheduler.FlexibleTimeWindow.off()
        )
        
        # Hourly data processing schedule
        scheduler.Schedule(
            self,
            "HourlyDataProcessing",
            schedule_name="hourly-data-processing",
            schedule=scheduler.ScheduleExpression.rate(Duration.hours(1)),
            target=scheduler.ScheduleTargetConfig(
                arn=self.task_processor_function.function_arn,
                role_arn=self.scheduler_role.role_arn,
                input='{"task_type": "data_processing"}'
            ),
            description="Hourly business data processing",
            flexible_time_window=scheduler.FlexibleTimeWindow.off()
        )
        
        # Weekly notification schedule (Monday 10 AM ET)
        scheduler.Schedule(
            self,
            "WeeklyNotificationSchedule",
            schedule_name="weekly-notification-schedule",
            schedule=scheduler.ScheduleExpression.cron(
                minute="0",
                hour="14",  # 10 AM ET = 14 UTC
                day="*",
                month="*",
                week_day="MON"
            ),
            target=scheduler.ScheduleTargetConfig(
                arn=self.task_processor_function.function_arn,
                role_arn=self.scheduler_role.role_arn,
                input='{"task_type": "notification"}'
            ),
            description="Weekly business status notifications every Monday at 10 AM ET",
            flexible_time_window=scheduler.FlexibleTimeWindow.off()
        )

    def _create_schedule_group(self) -> None:
        """Create schedule group for organizing business automation schedules."""
        scheduler.ScheduleGroup(
            self,
            "BusinessAutomationGroup",
            schedule_group_name="business-automation-group"
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource ARNs."""
        cdk.CfnOutput(
            self,
            "BucketName",
            value=self.reports_bucket.bucket_name,
            description="S3 bucket name for reports storage"
        )
        
        cdk.CfnOutput(
            self,
            "TopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications"
        )
        
        cdk.CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.task_processor_function.function_arn,
            description="Lambda function ARN for business task processing"
        )

    def _get_lambda_code(self) -> str:
        """
        Return the inline Lambda function code for business task processing.
        
        Returns:
            Python code as string for Lambda function
        """
        return '''
import json
import boto3
import datetime
from io import StringIO
import csv
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing business automation tasks.
    
    Args:
        event: Event data containing task_type
        context: Lambda runtime context
        
    Returns:
        dict: Response with status and result
    """
    try:
        # Get task type from event
        task_type = event.get('task_type', 'report')
        bucket_name = os.environ['BUCKET_NAME']
        topic_arn = os.environ['TOPIC_ARN']
        
        logger.info(f"Processing task type: {task_type}")
        
        if task_type == 'report':
            result = generate_daily_report(bucket_name)
        elif task_type == 'data_processing':
            result = process_business_data(bucket_name)
        elif task_type == 'notification':
            result = send_business_notification(topic_arn)
        else:
            result = f"Unknown task type: {task_type}"
            logger.warning(result)
        
        # Send success notification
        sns.publish(
            TopicArn=topic_arn,
            Message=f"Business task completed successfully: {result}",
            Subject=f"Task Completion - {task_type}"
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Task completed successfully',
                'result': result,
                'timestamp': datetime.datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Task failed: {str(e)}")
        
        # Send failure notification
        try:
            sns.publish(
                TopicArn=topic_arn,
                Message=f"Business task failed: {str(e)}",
                Subject=f"Task Failure - {task_type}"
            )
        except Exception as sns_error:
            logger.error(f"Failed to send failure notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.datetime.now().isoformat()
            })
        }

def generate_daily_report(bucket_name):
    """Generate sample business report and upload to S3."""
    # Generate sample business report data
    report_data = [
        ['Date', 'Revenue', 'Orders', 'Customers'],
        [datetime.datetime.now().strftime('%Y-%m-%d'), '12500', '45', '38'],
        [(datetime.datetime.now() - datetime.timedelta(days=1)).strftime('%Y-%m-%d'), '15800', '52', '41']
    ]
    
    # Convert to CSV
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    writer.writerows(report_data)
    
    # Upload to S3
    report_key = f"reports/daily-report-{datetime.datetime.now().strftime('%Y%m%d')}.csv"
    s3.put_object(
        Bucket=bucket_name,
        Key=report_key,
        Body=csv_buffer.getvalue(),
        ContentType='text/csv',
        ServerSideEncryption='AES256'
    )
    
    logger.info(f"Daily report generated: {report_key}")
    return f"Daily report generated: {report_key}"

def process_business_data(bucket_name):
    """Simulate data processing and save results to S3."""
    # Simulate data processing
    processed_data = {
        'processed_at': datetime.datetime.now().isoformat(),
        'records_processed': 150,
        'success_rate': 98.5,
        'errors': 2,
        'processing_time_seconds': 45.2
    }
    
    # Save processed data to S3
    data_key = f"processed-data/batch-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    s3.put_object(
        Bucket=bucket_name,
        Key=data_key,
        Body=json.dumps(processed_data, indent=2),
        ContentType='application/json',
        ServerSideEncryption='AES256'
    )
    
    logger.info(f"Data processing completed: {data_key}")
    return f"Data processing completed: {data_key}"

def send_business_notification(topic_arn):
    """Send business status notification via SNS."""
    message = (
        f"Business automation system status check completed at "
        f"{datetime.datetime.now().isoformat()}\\n\\n"
        f"System Status: Operational\\n"
        f"Last Check: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
        f"All scheduled tasks running normally."
    )
    
    sns.publish(
        TopicArn=topic_arn,
        Message=message,
        Subject="Business Automation Status Update"
    )
    
    logger.info("Business notification sent successfully")
    return "Business notification sent successfully"
'''


app = cdk.App()

# Get stack configuration from context
env = cdk.Environment(
    account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
    region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
)

# Create the stack
BusinessTaskSchedulingStack(
    app,
    "BusinessTaskSchedulingStack",
    env=env,
    description="Automated business task scheduling with EventBridge Scheduler and Lambda"
)

app.synth()