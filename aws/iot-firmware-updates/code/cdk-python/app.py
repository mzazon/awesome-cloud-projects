#!/usr/bin/env python3
"""
CDK Python Application for IoT Firmware Updates with Device Management Jobs

This CDK application creates the infrastructure needed for managing over-the-air (OTA)
firmware updates for IoT devices using AWS IoT Device Management Jobs. The solution
includes firmware storage, code signing, job orchestration, and monitoring capabilities.

Architecture Components:
- S3 bucket for secure firmware storage and distribution
- AWS IoT Thing Types and Thing Groups for device organization
- AWS Signer for firmware code signing and verification
- Lambda functions for job management and orchestration
- IAM roles and policies for secure service interactions
- CloudWatch monitoring and logging
- SNS notifications for update status alerts
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_iot as iot,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
    aws_sns as sns,
    aws_signer as signer,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct
from typing import Dict, Any, List


class IoTFirmwareUpdatesStack(Stack):
    """
    CDK Stack for IoT Firmware Updates with Device Management Jobs
    
    This stack creates all the necessary infrastructure for managing
    over-the-air firmware updates for IoT device fleets.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for firmware storage
        self._create_firmware_storage()
        
        # Create IAM roles for services
        self._create_iam_roles()
        
        # Create IoT resources (Thing Types, Groups, Policies)
        self._create_iot_resources()
        
        # Create code signing resources
        self._create_code_signing()
        
        # Create Lambda functions for job management
        self._create_lambda_functions()
        
        # Create monitoring and alerting
        self._create_monitoring()
        
        # Create CloudFormation outputs
        self._create_outputs()

    def _create_firmware_storage(self) -> None:
        """Create S3 bucket for secure firmware storage and distribution."""
        
        # Main firmware storage bucket
        self.firmware_bucket = s3.Bucket(
            self,
            "FirmwareBucket",
            bucket_name=f"iot-firmware-updates-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="FirmwareLifecycle",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(90),
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                )
            ],
            cors=[
                s3.CorsRule(
                    allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.HEAD],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    max_age=3600,
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for IoT Jobs and Lambda functions."""
        
        # IAM role for IoT Jobs to access S3 firmware
        self.iot_jobs_role = iam.Role(
            self,
            "IoTJobsRole",
            role_name=f"IoTJobsRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com"),
            description="Role for IoT Jobs to access firmware files in S3",
            inline_policies={
                "S3FirmwareAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectVersion",
                                "s3:GetBucketLocation",
                            ],
                            resources=[
                                self.firmware_bucket.bucket_arn,
                                self.firmware_bucket.arn_for_objects("*"),
                            ],
                        )
                    ]
                )
            },
        )

        # IAM role for Lambda functions
        self.lambda_execution_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"FirmwareUpdateLambdaRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Lambda functions managing firmware updates",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "FirmwareUpdatePermissions": iam.PolicyDocument(
                    statements=[
                        # IoT permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "iot:CreateJob",
                                "iot:DescribeJob",
                                "iot:ListJobs",
                                "iot:UpdateJob",
                                "iot:CancelJob",
                                "iot:DeleteJob",
                                "iot:ListJobExecutionsForJob",
                                "iot:ListJobExecutionsForThing",
                                "iot:DescribeJobExecution",
                                "iot:CreateThingGroup",
                                "iot:DescribeThingGroup",
                                "iot:ListThingGroups",
                                "iot:ListThingsInThingGroup",
                            ],
                            resources=["*"],
                        ),
                        # S3 permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket",
                                "s3:GetBucketLocation",
                            ],
                            resources=[
                                self.firmware_bucket.bucket_arn,
                                self.firmware_bucket.arn_for_objects("*"),
                            ],
                        ),
                        # Signer permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "signer:StartSigningJob",
                                "signer:DescribeSigningJob",
                                "signer:ListSigningJobs",
                                "signer:GetSigningProfile",
                            ],
                            resources=["*"],
                        ),
                        # CloudWatch permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "cloudwatch:PutMetricData",
                            ],
                            resources=["*"],
                        ),
                    ]
                )
            },
        )

    def _create_iot_resources(self) -> None:
        """Create IoT Thing Types, Thing Groups, and Policies."""
        
        # Create IoT Thing Type for firmware update capable devices
        self.device_thing_type = iot.CfnThingType(
            self,
            "FirmwareUpdateDeviceType",
            thing_type_name=f"FirmwareUpdateDevice-{self.stack_name}",
            thing_type_properties={
                "description": "IoT devices capable of receiving firmware updates",
                "searchableAttributes": ["firmwareVersion", "deviceModel", "lastUpdate"],
            },
        )

        # Create Thing Group for device fleet management
        self.device_thing_group = iot.CfnThingGroup(
            self,
            "FirmwareUpdateGroup",
            thing_group_name=f"FirmwareUpdateGroup-{self.stack_name}",
            thing_group_properties={
                "description": "Group of devices for firmware update management",
                "attributes": {
                    "managedBy": "FirmwareUpdateSystem",
                    "updatePolicy": "graduated-rollout",
                },
            },
        )

        # Create IoT Policy for device permissions
        device_policy_document: Dict[str, Any] = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["iot:Connect"],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:client/${{iot:Connection.Thing.ThingName}}",
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Publish"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/start-next",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/update",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/get",
                    ],
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Subscribe"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/notify-next",
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/start-next/accepted",
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/start-next/rejected",
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/update/accepted",
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/update/rejected",
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/get/accepted",
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/get/rejected",
                    ],
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Receive"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/notify-next",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/start-next/accepted",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/start-next/rejected",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/update/accepted",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/update/rejected",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/get/accepted",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/jobs/*/get/rejected",
                    ],
                },
            ],
        }

        self.device_policy = iot.CfnPolicy(
            self,
            "FirmwareUpdateDevicePolicy",
            policy_name=f"FirmwareUpdateDevicePolicy-{self.stack_name}",
            policy_document=device_policy_document,
        )

    def _create_code_signing(self) -> None:
        """Create AWS Signer resources for firmware code signing."""
        
        # Create signing profile for firmware packages
        self.signing_profile = signer.CfnSigningProfile(
            self,
            "FirmwareSigningProfile",
            platform_id="AmazonFreeRTOS-TI-CC3220SF",
            signature_validity_period={
                "value": 365,
                "type": "Days",
            },
            tags=[
                cdk.CfnTag(key="Purpose", value="IoTFirmwareSigning"),
                cdk.CfnTag(key="Environment", value=self.stack_name),
            ],
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for firmware update job management."""
        
        # Firmware Update Manager Lambda
        self.firmware_manager_function = lambda_.Function(
            self,
            "FirmwareUpdateManager",
            function_name=f"firmware-update-manager-{self.stack_name}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_firmware_manager_code()),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=self.lambda_execution_role,
            environment={
                "FIRMWARE_BUCKET": self.firmware_bucket.bucket_name,
                "IOT_JOBS_ROLE_ARN": self.iot_jobs_role.role_arn,
                "SIGNING_PROFILE_NAME": self.signing_profile.attr_profile_name,
                "THING_GROUP_NAME": self.device_thing_group.thing_group_name,
                "AWS_ACCOUNT_ID": self.account,
                "AWS_REGION": self.region,
            },
            description="Manages IoT firmware update jobs and orchestration",
            log_retention=logs.RetentionDays.ONE_MONTH,
        )

        # Job Status Monitor Lambda
        self.job_monitor_function = lambda_.Function(
            self,
            "JobStatusMonitor",
            function_name=f"job-status-monitor-{self.stack_name}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_job_monitor_code()),
            timeout=Duration.minutes(3),
            memory_size=128,
            role=self.lambda_execution_role,
            environment={
                "CLOUDWATCH_NAMESPACE": "IoT/FirmwareUpdates",
                "SNS_TOPIC_ARN": "",  # Will be updated after SNS topic creation
            },
            description="Monitors job status and publishes metrics",
            log_retention=logs.RetentionDays.ONE_MONTH,
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and SNS notifications."""
        
        # SNS topic for firmware update notifications
        self.notification_topic = sns.Topic(
            self,
            "FirmwareUpdateNotifications",
            topic_name=f"firmware-update-notifications-{self.stack_name}",
            display_name="IoT Firmware Update Notifications",
            description="Notifications for firmware update job status changes",
        )

        # Update Lambda environment variable with SNS topic ARN
        self.job_monitor_function.add_environment(
            "SNS_TOPIC_ARN", self.notification_topic.topic_arn
        )

        # Grant SNS publish permissions to Lambda
        self.notification_topic.grant_publish(self.job_monitor_function)

        # CloudWatch Dashboard for monitoring
        dashboard = cloudwatch.Dashboard(
            self,
            "FirmwareUpdateDashboard",
            dashboard_name=f"IoT-Firmware-Updates-{self.stack_name}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Job Execution Status",
                        left=[
                            cloudwatch.Metric(
                                namespace="IoT/FirmwareUpdates",
                                metric_name="JobsCompleted",
                                statistic="Sum",
                            ),
                            cloudwatch.Metric(
                                namespace="IoT/FirmwareUpdates",
                                metric_name="JobsFailed",
                                statistic="Sum",
                            ),
                            cloudwatch.Metric(
                                namespace="IoT/FirmwareUpdates",
                                metric_name="JobsInProgress",
                                statistic="Sum",
                            ),
                        ],
                        width=12,
                    ),
                    cloudwatch.LogQueryWidget(
                        title="Recent Firmware Update Logs",
                        log_groups=[
                            self.firmware_manager_function.log_group,
                            self.job_monitor_function.log_group,
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "sort @timestamp desc",
                            "limit 100",
                        ],
                        width=12,
                    ),
                ]
            ],
        )

        # CloudWatch Alarms
        job_failure_alarm = cloudwatch.Alarm(
            self,
            "JobFailureAlarm",
            alarm_name=f"firmware-update-job-failures-{self.stack_name}",
            alarm_description="Alarm when firmware update jobs fail",
            metric=cloudwatch.Metric(
                namespace="IoT/FirmwareUpdates",
                metric_name="JobsFailed",
                statistic="Sum",
            ),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )

        job_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self,
            "FirmwareBucketName",
            value=self.firmware_bucket.bucket_name,
            description="S3 bucket name for firmware storage",
            export_name=f"{self.stack_name}-FirmwareBucketName",
        )

        CfnOutput(
            self,
            "IoTJobsRoleArn",
            value=self.iot_jobs_role.role_arn,
            description="IAM role ARN for IoT Jobs",
            export_name=f"{self.stack_name}-IoTJobsRoleArn",
        )

        CfnOutput(
            self,
            "ThingGroupName",
            value=self.device_thing_group.thing_group_name,
            description="IoT Thing Group name for device management",
            export_name=f"{self.stack_name}-ThingGroupName",
        )

        CfnOutput(
            self,
            "ThingTypeName",
            value=self.device_thing_type.thing_type_name,
            description="IoT Thing Type name for devices",
            export_name=f"{self.stack_name}-ThingTypeName",
        )

        CfnOutput(
            self,
            "DevicePolicyName",
            value=self.device_policy.policy_name,
            description="IoT Policy name for devices",
            export_name=f"{self.stack_name}-DevicePolicyName",
        )

        CfnOutput(
            self,
            "SigningProfileName",
            value=self.signing_profile.attr_profile_name,
            description="AWS Signer profile name for firmware signing",
            export_name=f"{self.stack_name}-SigningProfileName",
        )

        CfnOutput(
            self,
            "FirmwareManagerFunctionName",
            value=self.firmware_manager_function.function_name,
            description="Lambda function name for firmware update management",
            export_name=f"{self.stack_name}-FirmwareManagerFunctionName",
        )

        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications",
            export_name=f"{self.stack_name}-NotificationTopicArn",
        )

    def _get_firmware_manager_code(self) -> str:
        """Return the Lambda function code for firmware update management."""
        return '''
import json
import boto3
import uuid
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
iot_client = boto3.client('iot')
s3_client = boto3.client('s3')
signer_client = boto3.client('signer')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Main Lambda handler for firmware update management.
    
    Supported actions:
    - create_job: Create a new firmware update job
    - check_job_status: Check the status of an existing job
    - cancel_job: Cancel an existing job
    - list_jobs: List all jobs
    """
    try:
        action = event.get('action')
        logger.info(f"Processing action: {action}")
        
        if action == 'create_job':
            return create_firmware_job(event)
        elif action == 'check_job_status':
            return check_job_status(event)
        elif action == 'cancel_job':
            return cancel_job(event)
        elif action == 'list_jobs':
            return list_jobs(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid action',
                    'supported_actions': ['create_job', 'check_job_status', 'cancel_job', 'list_jobs']
                })
            }
            
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_firmware_job(event: Dict[str, Any]) -> Dict[str, Any]:
    """Create a new firmware update job."""
    try:
        # Extract required parameters
        firmware_version = event['firmware_version']
        thing_group = event.get('thing_group', os.environ['THING_GROUP_NAME'])
        s3_bucket = event.get('s3_bucket', os.environ['FIRMWARE_BUCKET'])
        s3_key = event['s3_key']
        
        # Optional parameters with defaults
        rollout_rate = event.get('rollout_rate', 10)
        abort_threshold = event.get('abort_threshold', 20.0)
        timeout_minutes = event.get('timeout_minutes', 60)
        
        # Get firmware metadata
        firmware_size = get_object_size(s3_bucket, s3_key)
        firmware_checksum = get_object_checksum(s3_bucket, s3_key)
        
        # Create job document
        job_document = {
            "operation": "firmware_update",
            "firmware": {
                "version": firmware_version,
                "url": f"https://{s3_bucket}.s3.amazonaws.com/{s3_key}",
                "size": firmware_size,
                "checksum": firmware_checksum
            },
            "steps": [
                "download_firmware",
                "verify_signature", 
                "backup_current_firmware",
                "install_firmware",
                "verify_installation",
                "report_status"
            ],
            "timeout": timeout_minutes * 60,
            "retry_attempts": 3
        }
        
        # Generate unique job ID
        job_id = f"firmware-update-{firmware_version}-{uuid.uuid4().hex[:8]}"
        
        # Create the job with advanced configuration
        response = iot_client.create_job(
            jobId=job_id,
            targets=[f"arn:aws:iot:{os.environ['AWS_REGION']}:{os.environ['AWS_ACCOUNT_ID']}:thinggroup/{thing_group}"],
            document=json.dumps(job_document),
            description=f"Firmware update to version {firmware_version}",
            targetSelection='SNAPSHOT',
            jobExecutionsRolloutConfig={
                'maximumPerMinute': rollout_rate,
                'exponentialRate': {
                    'baseRatePerMinute': max(1, rollout_rate // 2),
                    'incrementFactor': 2.0,
                    'rateIncreaseCriteria': {
                        'numberOfNotifiedThings': rollout_rate,
                        'numberOfSucceededThings': max(1, rollout_rate // 2)
                    }
                }
            },
            abortConfig={
                'criteriaList': [
                    {
                        'failureType': 'FAILED',
                        'action': 'CANCEL',
                        'thresholdPercentage': abort_threshold,
                        'minNumberOfExecutedThings': 5
                    },
                    {
                        'failureType': 'TIMED_OUT',
                        'action': 'CANCEL',
                        'thresholdPercentage': 10.0,
                        'minNumberOfExecutedThings': 3
                    }
                ]
            },
            timeoutConfig={
                'inProgressTimeoutInMinutes': timeout_minutes
            }
        )
        
        # Publish metrics
        publish_metric('JobsCreated', 1, {'JobId': job_id, 'FirmwareVersion': firmware_version})
        
        logger.info(f"Created firmware update job: {job_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'job_arn': response['jobArn'],
                'firmware_version': firmware_version,
                'target_group': thing_group,
                'message': 'Firmware update job created successfully'
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating job: {str(e)}")
        publish_metric('JobCreationErrors', 1)
        raise

def check_job_status(event: Dict[str, Any]) -> Dict[str, Any]:
    """Check the status of an existing job."""
    try:
        job_id = event['job_id']
        
        # Get job details
        job_response = iot_client.describe_job(jobId=job_id)
        job_executions = iot_client.list_job_executions_for_job(jobId=job_id)
        
        job_status = job_response['job']['status']
        process_details = job_response['job']['jobProcessDetails']
        
        # Publish status metrics
        publish_metric('JobStatusCheck', 1, {'JobId': job_id, 'Status': job_status})
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'status': job_status,
                'process_details': process_details,
                'execution_summary': {
                    'queued': process_details.get('numberOfQueuedThings', 0),
                    'in_progress': process_details.get('numberOfInProgressThings', 0),
                    'succeeded': process_details.get('numberOfSucceededThings', 0),
                    'failed': process_details.get('numberOfFailedThings', 0),
                    'canceled': process_details.get('numberOfCanceledThings', 0),
                    'rejected': process_details.get('numberOfRejectedThings', 0),
                    'removed': process_details.get('numberOfRemovedThings', 0),
                    'timed_out': process_details.get('numberOfTimedOutThings', 0)
                },
                'executions': job_executions['executionSummaries'][:10]  # Limit to first 10
            })
        }
        
    except Exception as e:
        logger.error(f"Error checking job status: {str(e)}")
        raise

def cancel_job(event: Dict[str, Any]) -> Dict[str, Any]:
    """Cancel an existing job."""
    try:
        job_id = event['job_id']
        reason = event.get('reason', 'USER_INITIATED')
        comment = event.get('comment', 'Job cancelled by user request')
        
        iot_client.cancel_job(
            jobId=job_id,
            reasonCode=reason,
            comment=comment
        )
        
        # Publish metrics
        publish_metric('JobsCancelled', 1, {'JobId': job_id})
        
        logger.info(f"Cancelled job: {job_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'message': 'Job cancelled successfully'
            })
        }
        
    except Exception as e:
        logger.error(f"Error cancelling job: {str(e)}")
        raise

def list_jobs(event: Dict[str, Any]) -> Dict[str, Any]:
    """List jobs with optional filtering."""
    try:
        status = event.get('status')  # Optional status filter
        max_results = min(event.get('max_results', 50), 100)  # Cap at 100
        
        list_kwargs = {
            'maxResults': max_results
        }
        
        if status:
            list_kwargs['status'] = status
            
        response = iot_client.list_jobs(**list_kwargs)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'jobs': response['jobs'],
                'next_token': response.get('nextToken'),
                'total_count': len(response['jobs'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error listing jobs: {str(e)}")
        raise

def get_object_size(bucket: str, key: str) -> int:
    """Get the size of an S3 object."""
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response['ContentLength']
    except Exception as e:
        logger.warning(f"Could not get object size for {key}: {str(e)}")
        return 0

def get_object_checksum(bucket: str, key: str) -> str:
    """Get the ETag/checksum of an S3 object."""
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response.get('ETag', '').replace('"', '')
    except Exception as e:
        logger.warning(f"Could not get object checksum for {key}: {str(e)}")
        return ''

def publish_metric(metric_name: str, value: float, dimensions: Optional[Dict[str, str]] = None) -> None:
    """Publish a custom metric to CloudWatch."""
    try:
        metric_data = {
            'MetricName': metric_name,
            'Value': value,
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        }
        
        if dimensions:
            metric_data['Dimensions'] = [
                {'Name': k, 'Value': v} for k, v in dimensions.items()
            ]
        
        cloudwatch.put_metric_data(
            Namespace='IoT/FirmwareUpdates',
            MetricData=[metric_data]
        )
    except Exception as e:
        logger.warning(f"Could not publish metric {metric_name}: {str(e)}")

import os
'''

    def _get_job_monitor_code(self) -> str:
        """Return the Lambda function code for job status monitoring."""
        return '''
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
iot_client = boto3.client('iot')
sns_client = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Monitor job status and publish metrics/notifications.
    
    This function can be triggered by:
    - CloudWatch Events (scheduled monitoring)
    - IoT Rules (job status changes)
    - Manual invocation with job IDs
    """
    try:
        # Check if this is a scheduled monitoring run
        if event.get('source') == 'aws.events':
            return monitor_all_active_jobs()
        
        # Check if specific job IDs were provided
        job_ids = event.get('job_ids', [])
        if job_ids:
            return monitor_specific_jobs(job_ids)
            
        # Check if this is an IoT Rule trigger
        if 'jobId' in event:
            return handle_job_status_change(event)
            
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'No valid trigger found'})
        }
        
    except Exception as e:
        logger.error(f"Error in job monitor: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def monitor_all_active_jobs() -> Dict[str, Any]:
    """Monitor all active firmware update jobs."""
    try:
        # Get all in-progress jobs
        active_jobs = []
        for status in ['IN_PROGRESS', 'QUEUED']:
            response = iot_client.list_jobs(status=status, maxResults=50)
            active_jobs.extend(response['jobs'])
        
        metrics_published = 0
        notifications_sent = 0
        
        for job in active_jobs:
            job_id = job['jobId']
            
            # Get detailed job information
            job_details = iot_client.describe_job(jobId=job_id)
            process_details = job_details['job']['jobProcessDetails']
            
            # Publish metrics for this job
            publish_job_metrics(job_id, process_details)
            metrics_published += 1
            
            # Check if notification is needed
            if should_send_notification(job_details):
                send_job_notification(job_details)
                notifications_sent += 1
        
        logger.info(f"Monitored {len(active_jobs)} active jobs, published {metrics_published} metrics, sent {notifications_sent} notifications")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'monitored_jobs': len(active_jobs),
                'metrics_published': metrics_published,
                'notifications_sent': notifications_sent
            })
        }
        
    except Exception as e:
        logger.error(f"Error monitoring active jobs: {str(e)}")
        raise

def monitor_specific_jobs(job_ids: List[str]) -> Dict[str, Any]:
    """Monitor specific job IDs."""
    try:
        results = []
        
        for job_id in job_ids:
            try:
                job_details = iot_client.describe_job(jobId=job_id)
                process_details = job_details['job']['jobProcessDetails']
                
                # Publish metrics
                publish_job_metrics(job_id, process_details)
                
                # Check for notifications
                if should_send_notification(job_details):
                    send_job_notification(job_details)
                
                results.append({
                    'job_id': job_id,
                    'status': job_details['job']['status'],
                    'monitored': True
                })
                
            except Exception as e:
                logger.error(f"Error monitoring job {job_id}: {str(e)}")
                results.append({
                    'job_id': job_id,
                    'status': 'ERROR',
                    'error': str(e)
                })
        
        return {
            'statusCode': 200,
            'body': json.dumps({'results': results})
        }
        
    except Exception as e:
        logger.error(f"Error monitoring specific jobs: {str(e)}")
        raise

def handle_job_status_change(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle job status change events from IoT Rules."""
    try:
        job_id = event['jobId']
        status = event.get('status')
        
        logger.info(f"Handling status change for job {job_id}: {status}")
        
        # Get full job details
        job_details = iot_client.describe_job(jobId=job_id)
        
        # Publish metrics
        publish_job_metrics(job_id, job_details['job']['jobProcessDetails'])
        
        # Send notification for status change
        send_job_notification(job_details, status_change=True)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'status': status,
                'processed': True
            })
        }
        
    except Exception as e:
        logger.error(f"Error handling job status change: {str(e)}")
        raise

def publish_job_metrics(job_id: str, process_details: Dict[str, Any]) -> None:
    """Publish CloudWatch metrics for a job."""
    try:
        metrics = [
            ('JobsQueued', process_details.get('numberOfQueuedThings', 0)),
            ('JobsInProgress', process_details.get('numberOfInProgressThings', 0)),
            ('JobsSucceeded', process_details.get('numberOfSucceededThings', 0)),
            ('JobsFailed', process_details.get('numberOfFailedThings', 0)),
            ('JobsCancelled', process_details.get('numberOfCanceledThings', 0)),
            ('JobsRejected', process_details.get('numberOfRejectedThings', 0)),
            ('JobsTimedOut', process_details.get('numberOfTimedOutThings', 0)),
        ]
        
        metric_data = []
        for metric_name, value in metrics:
            if value > 0:  # Only publish non-zero metrics
                metric_data.append({
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow(),
                    'Dimensions': [
                        {'Name': 'JobId', 'Value': job_id}
                    ]
                })
        
        if metric_data:
            cloudwatch.put_metric_data(
                Namespace=os.environ['CLOUDWATCH_NAMESPACE'],
                MetricData=metric_data
            )
            
    except Exception as e:
        logger.warning(f"Could not publish metrics for job {job_id}: {str(e)}")

def should_send_notification(job_details: Dict[str, Any]) -> bool:
    """Determine if a notification should be sent for this job."""
    try:
        status = job_details['job']['status']
        process_details = job_details['job']['jobProcessDetails']
        
        # Send notification for completed, failed, or cancelled jobs
        if status in ['COMPLETED', 'CANCELLED']:
            return True
            
        # Send notification if failure rate is high
        total_things = process_details.get('numberOfQueuedThings', 0) + process_details.get('numberOfInProgressThings', 0) + process_details.get('numberOfSucceededThings', 0) + process_details.get('numberOfFailedThings', 0)
        failed_things = process_details.get('numberOfFailedThings', 0)
        
        if total_things > 10 and failed_things / total_things > 0.2:  # >20% failure rate
            return True
            
        return False
        
    except Exception as e:
        logger.warning(f"Error determining notification need: {str(e)}")
        return False

def send_job_notification(job_details: Dict[str, Any], status_change: bool = False) -> None:
    """Send SNS notification for job status."""
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if not sns_topic_arn:
            logger.warning("No SNS topic ARN configured")
            return
            
        job = job_details['job']
        job_id = job['jobId']
        status = job['status']
        process_details = job['jobProcessDetails']
        
        # Calculate success rate
        total_things = sum([
            process_details.get('numberOfQueuedThings', 0),
            process_details.get('numberOfInProgressThings', 0),
            process_details.get('numberOfSucceededThings', 0),
            process_details.get('numberOfFailedThings', 0),
            process_details.get('numberOfCanceledThings', 0),
            process_details.get('numberOfRejectedThings', 0),
            process_details.get('numberOfTimedOutThings', 0)
        ])
        
        succeeded_things = process_details.get('numberOfSucceededThings', 0)
        success_rate = (succeeded_things / total_things * 100) if total_things > 0 else 0
        
        # Create notification message
        subject = f"IoT Firmware Update Job {status}: {job_id}"
        
        message = f"""
Firmware Update Job Status Update

Job ID: {job_id}
Status: {status}
Description: {job.get('description', 'N/A')}

Execution Summary:
- Total Devices: {total_things}
- Succeeded: {succeeded_things} ({success_rate:.1f}%)
- Failed: {process_details.get('numberOfFailedThings', 0)}
- In Progress: {process_details.get('numberOfInProgressThings', 0)}
- Queued: {process_details.get('numberOfQueuedThings', 0)}
- Cancelled: {process_details.get('numberOfCanceledThings', 0)}
- Rejected: {process_details.get('numberOfRejectedThings', 0)}
- Timed Out: {process_details.get('numberOfTimedOutThings', 0)}

Created: {job.get('createdAt', 'N/A')}
Last Updated: {job.get('lastUpdatedAt', 'N/A')}

AWS Console: https://console.aws.amazon.com/iot/home#/jobs/{job_id}
"""
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject=subject,
            Message=message
        )
        
        logger.info(f"Sent notification for job {job_id}")
        
    except Exception as e:
        logger.warning(f"Could not send notification: {str(e)}")

import os
'''


class IoTFirmwareUpdatesApp(cdk.App):
    """CDK Application for IoT Firmware Updates."""

    def __init__(self) -> None:
        super().__init__()

        # Create the main stack
        IoTFirmwareUpdatesStack(
            self,
            "IoTFirmwareUpdatesStack",
            description="Infrastructure for IoT firmware updates with device management jobs",
            env=cdk.Environment(
                account=self.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=self.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION"),
            ),
        )


if __name__ == "__main__":
    import os
    app = IoTFirmwareUpdatesApp()
    app.synth()