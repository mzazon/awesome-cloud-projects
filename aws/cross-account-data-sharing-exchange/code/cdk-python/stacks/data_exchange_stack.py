"""
CDK Stack for AWS Data Exchange Cross-Account Data Sharing.

This stack creates the complete infrastructure for sharing data assets
across AWS accounts using AWS Data Exchange, including S3 buckets,
IAM roles, Lambda functions, and monitoring resources.
"""

from typing import Dict, Any
import os
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_s3_assets as s3_assets,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct


class DataExchangeStack(Stack):
    """
    CDK Stack for AWS Data Exchange cross-account data sharing infrastructure.
    
    This stack creates:
    - S3 buckets for data storage
    - IAM roles for Data Exchange operations
    - Lambda functions for automation and notifications
    - EventBridge rules for event-driven automation
    - CloudWatch monitoring and alerting
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get configuration parameters
        self.subscriber_account_id = self.node.try_get_context("subscriber_account_id") or "123456789012"
        self.environment_name = self.node.try_get_context("environment") or "prod"
        
        # Create S3 bucket for data provider
        self.data_bucket = self._create_data_bucket()
        
        # Create IAM role for Data Exchange
        self.data_exchange_role = self._create_data_exchange_role()
        
        # Create Lambda functions
        self.notification_function = self._create_notification_function()
        self.update_function = self._create_update_function()
        
        # Create EventBridge rules
        self._create_event_rules()
        
        # Create monitoring resources
        self._create_monitoring()
        
        # Create outputs
        self._create_outputs()

    def _create_data_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing data assets."""
        bucket = s3.Bucket(
            self,
            "DataProviderBucket",
            bucket_name=f"data-exchange-provider-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
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
            ],
            removal_policy=RemovalPolicy.RETAIN,
        )
        
        return bucket

    def _create_data_exchange_role(self) -> iam.Role:
        """Create IAM role for AWS Data Exchange operations."""
        role = iam.Role(
            self,
            "DataExchangeProviderRole",
            role_name="DataExchangeProviderRole",
            assumed_by=iam.ServicePrincipal("dataexchange.amazonaws.com"),
            description="IAM role for AWS Data Exchange provider operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSDataExchangeProviderFullAccess")
            ],
        )
        
        # Add inline policy for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:PutObjectAcl",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation",
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*",
                ],
            )
        )
        
        return role

    def _create_notification_function(self) -> _lambda.Function:
        """Create Lambda function for handling Data Exchange notifications."""
        # Create Lambda function
        function = _lambda.Function(
            self,
            "NotificationFunction",
            function_name="DataExchangeNotificationHandler",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_notification_lambda_code()),
            timeout=Duration.minutes(5),
            description="Handles Data Exchange events and sends notifications",
            environment={
                "ENVIRONMENT": self.environment_name,
                "DATA_BUCKET": self.data_bucket.bucket_name,
            },
        )
        
        # Grant permissions
        function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )
        
        # Optional: Add SNS permissions if SNS topic ARN is provided
        sns_topic_arn = self.node.try_get_context("sns_topic_arn")
        if sns_topic_arn:
            function.add_environment("SNS_TOPIC_ARN", sns_topic_arn)
            function.add_to_role_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sns:Publish"],
                    resources=[sns_topic_arn],
                )
            )
        
        return function

    def _create_update_function(self) -> _lambda.Function:
        """Create Lambda function for automated data updates."""
        function = _lambda.Function(
            self,
            "UpdateFunction",
            function_name="DataExchangeAutoUpdate",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_update_lambda_code()),
            timeout=Duration.minutes(10),
            description="Automatically updates data sets with new revisions",
            environment={
                "ENVIRONMENT": self.environment_name,
                "DATA_BUCKET": self.data_bucket.bucket_name,
            },
        )
        
        # Grant Data Exchange permissions
        function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dataexchange:CreateRevision",
                    "dataexchange:CreateJob",
                    "dataexchange:GetJob",
                    "dataexchange:ListJobs",
                    "dataexchange:UpdateRevision",
                ],
                resources=["*"],
            )
        )
        
        # Grant S3 permissions
        self.data_bucket.grant_read_write(function)
        
        return function

    def _create_event_rules(self) -> None:
        """Create EventBridge rules for automation."""
        # Rule for Data Exchange events
        data_exchange_rule = events.Rule(
            self,
            "DataExchangeEventRule",
            rule_name="DataExchangeEventRule",
            description="Captures Data Exchange events for notifications",
            event_pattern=events.EventPattern(
                source=["aws.dataexchange"],
                detail_type=["Data Exchange Asset Import State Change"],
            ),
        )
        
        # Add Lambda target
        data_exchange_rule.add_target(
            targets.LambdaFunction(self.notification_function)
        )
        
        # Rule for scheduled updates (daily)
        schedule_rule = events.Rule(
            self,
            "ScheduleRule",
            rule_name="DataExchangeAutoUpdateSchedule",
            description="Triggers daily data updates for Data Exchange",
            schedule=events.Schedule.rate(Duration.hours(24)),
        )
        
        # Add Lambda target with input
        schedule_rule.add_target(
            targets.LambdaFunction(
                self.update_function,
                event=events.RuleTargetInput.from_object({
                    "bucket_name": self.data_bucket.bucket_name,
                    "dataset_id": "TO_BE_REPLACED",  # Will be updated after dataset creation
                }),
            )
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alerting resources."""
        # Create log group for Data Exchange operations
        log_group = logs.LogGroup(
            self,
            "DataExchangeLogGroup",
            log_group_name="/aws/dataexchange/operations",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create custom metric for Lambda errors
        error_metric = cloudwatch.Metric(
            namespace="CustomMetrics",
            metric_name="DataExchangeLambdaErrors",
            statistic="Sum",
        )
        
        # Create alarm for Lambda errors
        error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name="DataExchangeLambdaErrors",
            alarm_description="Alert when Data Exchange Lambda functions encounter errors",
            metric=error_metric,
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket for data assets",
            export_name=f"{self.stack_name}-DataBucketName",
        )
        
        CfnOutput(
            self,
            "DataExchangeRoleArn",
            value=self.data_exchange_role.role_arn,
            description="ARN of the IAM role for Data Exchange operations",
            export_name=f"{self.stack_name}-DataExchangeRoleArn",
        )
        
        CfnOutput(
            self,
            "NotificationFunctionArn",
            value=self.notification_function.function_arn,
            description="ARN of the notification Lambda function",
            export_name=f"{self.stack_name}-NotificationFunctionArn",
        )
        
        CfnOutput(
            self,
            "UpdateFunctionArn",
            value=self.update_function.function_arn,
            description="ARN of the update Lambda function",
            export_name=f"{self.stack_name}-UpdateFunctionArn",
        )
        
        CfnOutput(
            self,
            "SubscriberAccountId",
            value=self.subscriber_account_id,
            description="AWS Account ID for data subscriber",
            export_name=f"{self.stack_name}-SubscriberAccountId",
        )

    def _get_notification_lambda_code(self) -> str:
        """Get the Lambda function code for notifications."""
        return '''
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Handle Data Exchange events and send notifications.
    
    This function processes EventBridge events from AWS Data Exchange
    and sends notifications via SNS if configured.
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    try:
        # Extract event details
        detail = event.get('detail', {})
        event_name = detail.get('eventName', 'Unknown')
        dataset_id = detail.get('dataSetId', 'Unknown')
        source = event.get('source', 'aws.dataexchange')
        
        # Create notification message
        message = f"""
AWS Data Exchange Event Notification

Event: {event_name}
Source: {source}
Dataset ID: {dataset_id}
Timestamp: {event.get('time', datetime.utcnow().isoformat())}
Environment: {os.environ.get('ENVIRONMENT', 'Unknown')}

Event Details:
{json.dumps(detail, indent=2)}
        """
        
        # Send SNS notification if topic ARN is configured
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if sns_topic_arn:
            sns = boto3.client('sns')
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject=f'Data Exchange Event: {event_name}'
            )
            print(f"Sent SNS notification to {sns_topic_arn}")
        else:
            print("No SNS topic configured, logging event only")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'event_name': event_name,
                'dataset_id': dataset_id
            })
        }
        
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process event'
            })
        }
'''

    def _get_update_lambda_code(self) -> str:
        """Get the Lambda function code for automated updates."""
        return '''
import json
import boto3
import csv
import random
from datetime import datetime, timedelta
from io import StringIO

def lambda_handler(event, context):
    """
    Automatically update data sets with new revisions.
    
    This function generates new sample data, uploads it to S3,
    and creates new revisions in AWS Data Exchange.
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    try:
        # Extract parameters
        dataset_id = event.get('dataset_id')
        bucket_name = event.get('bucket_name', os.environ.get('DATA_BUCKET'))
        
        if not dataset_id or not bucket_name:
            raise ValueError("Missing required parameters: dataset_id or bucket_name")
        
        # Initialize AWS clients
        dataexchange = boto3.client('dataexchange')
        s3 = boto3.client('s3')
        
        # Generate updated sample data
        current_date = datetime.now().strftime('%Y-%m-%d')
        csv_data = generate_sample_data(current_date)
        
        # Upload updated data to S3
        s3_key = f'analytics-data/customer-analytics-{current_date}.csv'
        s3.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=csv_data,
            ContentType='text/csv'
        )
        print(f"Uploaded data to s3://{bucket_name}/{s3_key}")
        
        # Create new revision
        revision_response = dataexchange.create_revision(
            DataSetId=dataset_id,
            Comment=f'Automated update - {current_date}'
        )
        revision_id = revision_response['Id']
        print(f"Created revision: {revision_id}")
        
        # Import new assets
        import_job = dataexchange.create_job(
            Type='IMPORT_ASSETS_FROM_S3',
            Details={
                'ImportAssetsFromS3JobDetails': {
                    'DataSetId': dataset_id,
                    'RevisionId': revision_id,
                    'AssetSources': [
                        {
                            'Bucket': bucket_name,
                            'Key': s3_key
                        }
                    ]
                }
            }
        )
        
        import_job_id = import_job['Id']
        print(f"Started import job: {import_job_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data update completed successfully',
                'revision_id': revision_id,
                'import_job_id': import_job_id,
                's3_key': s3_key
            })
        }
        
    except Exception as e:
        print(f"Error updating data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to update data'
            })
        }

def generate_sample_data(date_str):
    """Generate sample CSV data for the given date."""
    categories = ['electronics', 'books', 'clothing', 'home', 'sports']
    regions = ['us-east', 'us-west', 'eu-central', 'asia-pacific']
    
    # Create CSV data
    output = StringIO()
    writer = csv.writer(output)
    
    # Write header
    writer.writerow(['customer_id', 'purchase_date', 'amount', 'category', 'region'])
    
    # Generate 10 random records
    for i in range(1, 11):
        customer_id = f'C{i:03d}'
        amount = round(random.uniform(25.0, 500.0), 2)
        category = random.choice(categories)
        region = random.choice(regions)
        
        writer.writerow([customer_id, date_str, amount, category, region])
    
    return output.getvalue()
'''