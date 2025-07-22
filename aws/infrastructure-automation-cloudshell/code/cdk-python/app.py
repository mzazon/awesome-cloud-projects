#!/usr/bin/env python3
"""
CDK Application for Infrastructure Automation with CloudShell PowerShell

This CDK application creates the infrastructure for automating infrastructure management
using AWS CloudShell PowerShell scripts integrated with Systems Manager, Lambda, and CloudWatch.
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    aws_sns as sns,
    aws_ssm as ssm,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    CfnParameter
)
import json


class InfrastructureAutomationStack(Stack):
    """
    Stack for infrastructure automation using CloudShell PowerShell and Systems Manager
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        environment_suffix = CfnParameter(
            self, "EnvironmentSuffix",
            type="String",
            description="Suffix to append to resource names for uniqueness",
            default="dev",
            allowed_pattern="^[a-z0-9-]*$",
            constraint_description="Must contain only lowercase letters, numbers, and hyphens"
        )

        # Create IAM role for automation execution
        automation_role = self._create_automation_role(environment_suffix.value_as_string)

        # Create CloudWatch Log Group for automation logs
        log_group = self._create_log_group(environment_suffix.value_as_string)

        # Create SNS topic for notifications
        notification_topic = self._create_notification_topic(environment_suffix.value_as_string)

        # Create Systems Manager automation document
        automation_document = self._create_automation_document(
            automation_role,
            log_group,
            environment_suffix.value_as_string
        )

        # Create Lambda function for automation orchestration
        lambda_function = self._create_lambda_function(
            automation_role,
            automation_document,
            environment_suffix.value_as_string
        )

        # Create EventBridge rule for scheduled execution
        schedule_rule = self._create_schedule_rule(
            lambda_function,
            environment_suffix.value_as_string
        )

        # Create CloudWatch monitoring resources
        self._create_monitoring(
            lambda_function,
            notification_topic,
            environment_suffix.value_as_string
        )

        # Outputs
        CfnOutput(
            self, "AutomationRoleArn",
            value=automation_role.role_arn,
            description="ARN of the IAM role for automation execution"
        )

        CfnOutput(
            self, "AutomationDocumentName",
            value=automation_document.name,
            description="Name of the Systems Manager automation document"
        )

        CfnOutput(
            self, "LambdaFunctionArn",
            value=lambda_function.function_arn,
            description="ARN of the Lambda function for automation orchestration"
        )

        CfnOutput(
            self, "LogGroupName",
            value=log_group.log_group_name,
            description="Name of the CloudWatch Log Group for automation logs"
        )

        CfnOutput(
            self, "NotificationTopicArn",
            value=notification_topic.topic_arn,
            description="ARN of the SNS topic for notifications"
        )

        CfnOutput(
            self, "ScheduleRuleName",
            value=schedule_rule.rule_name,
            description="Name of the EventBridge rule for scheduled execution"
        )

    def _create_automation_role(self, suffix: str) -> iam.Role:
        """
        Create IAM role for automation execution with necessary permissions
        """
        role = iam.Role(
            self, "AutomationRole",
            role_name=f"InfraAutomationRole-{suffix}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("lambda.amazonaws.com"),
                iam.ServicePrincipal("ssm.amazonaws.com")
            ),
            description="Role for infrastructure automation using CloudShell PowerShell",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                # Note: In production, use custom policies with least privilege
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSNSFullAccess")
            ]
        )

        # Add custom policy for specific automation needs
        custom_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeInstances",
                        "ec2:DescribeInstanceStatus",
                        "s3:ListAllMyBuckets",
                        "s3:GetBucketEncryption",
                        "s3:GetBucketVersioning",
                        "s3:GetBucketLogging",
                        "rds:DescribeDBInstances",
                        "rds:DescribeDBClusters",
                        "iam:ListRoles",
                        "iam:ListPolicies"
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            "aws:RequestedRegion": self.region
                        }
                    }
                )
            ]
        )

        role.attach_inline_policy(
            iam.Policy(
                self, "AutomationCustomPolicy",
                document=custom_policy
            )
        )

        return role

    def _create_log_group(self, suffix: str) -> logs.LogGroup:
        """
        Create CloudWatch Log Group for automation logs
        """
        log_group = logs.LogGroup(
            self, "AutomationLogGroup",
            log_group_name="/aws/automation/infrastructure-health",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        return log_group

    def _create_notification_topic(self, suffix: str) -> sns.Topic:
        """
        Create SNS topic for automation notifications
        """
        topic = sns.Topic(
            self, "AutomationNotificationTopic",
            topic_name=f"automation-alerts-{suffix}",
            display_name="Infrastructure Automation Alerts",
            description="SNS topic for infrastructure automation notifications"
        )

        return topic

    def _create_automation_document(
        self, 
        automation_role: iam.Role, 
        log_group: logs.LogGroup,
        suffix: str
    ) -> ssm.CfnDocument:
        """
        Create Systems Manager automation document for PowerShell script execution
        """
        # PowerShell script content for infrastructure health check
        powershell_script = '''
param(
    [string]$Region = $env:AWS_REGION,
    [string]$LogGroup = "/aws/automation/infrastructure-health"
)

# Import required AWS modules
Import-Module AWS.Tools.EC2
Import-Module AWS.Tools.S3
Import-Module AWS.Tools.CloudWatchLogs

# Function to write structured logs
function Write-AutomationLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    $logEntry = @{
        timestamp = $timestamp
        level = $Level
        message = $Message
        region = $Region
    } | ConvertTo-Json -Compress
    
    Write-Host $logEntry
    
    try {
        # Create log stream if it doesn't exist
        $logStreamName = "health-check-$(Get-Date -Format 'yyyy-MM-dd')"
        New-CWLLogStream -LogGroupName $LogGroup -LogStreamName $logStreamName -ErrorAction SilentlyContinue
        
        # Send to CloudWatch Logs
        Write-CWLLogEvent -LogGroupName $LogGroup -LogStreamName $logStreamName -LogEvent @{
            Message = $logEntry
            Timestamp = [DateTimeOffset]::UtcNow
        }
    } catch {
        Write-Host "Failed to write to CloudWatch Logs: $($_.Exception.Message)"
    }
}

# Check EC2 instance health
function Test-EC2Health {
    Write-AutomationLog "Starting EC2 health assessment"
    try {
        $instances = Get-EC2Instance -Region $Region
        $healthReport = @()
        
        foreach ($reservation in $instances) {
            foreach ($instance in $reservation.Instances) {
                $healthStatus = @{
                    InstanceId = $instance.InstanceId
                    State = $instance.State.Name
                    Type = $instance.InstanceType
                    LaunchTime = $instance.LaunchTime
                    PublicIP = $instance.PublicIpAddress
                    PrivateIP = $instance.PrivateIpAddress
                    SecurityGroups = ($instance.SecurityGroups | ForEach-Object { $_.GroupName }) -join ","
                }
                $healthReport += $healthStatus
            }
        }
        
        Write-AutomationLog "Found $($healthReport.Count) EC2 instances"
        return $healthReport
    } catch {
        Write-AutomationLog "EC2 health check failed: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Check S3 bucket compliance
function Test-S3Compliance {
    Write-AutomationLog "Starting S3 compliance assessment"
    try {
        $buckets = Get-S3Bucket -Region $Region
        $complianceReport = @()
        
        foreach ($bucket in $buckets) {
            try {
                $encryption = Get-S3BucketEncryption -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
                $versioning = Get-S3BucketVersioning -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
                $logging = Get-S3BucketLogging -BucketName $bucket.BucketName -ErrorAction SilentlyContinue
                
                $complianceStatus = @{
                    BucketName = $bucket.BucketName
                    CreationDate = $bucket.CreationDate
                    EncryptionEnabled = $null -ne $encryption
                    VersioningEnabled = $versioning.Status -eq "Enabled"
                    LoggingEnabled = $null -ne $logging.LoggingEnabled
                }
                $complianceReport += $complianceStatus
            } catch {
                Write-AutomationLog "Failed to assess bucket $($bucket.BucketName): $($_.Exception.Message)" "WARNING"
            }
        }
        
        Write-AutomationLog "Assessed $($complianceReport.Count) S3 buckets"
        return $complianceReport
    } catch {
        Write-AutomationLog "S3 compliance check failed: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Main execution
try {
    Write-AutomationLog "Infrastructure health check started"
    
    $ec2Health = Test-EC2Health
    $s3Compliance = Test-S3Compliance
    
    $report = @{
        Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        Region = $Region
        EC2Health = $ec2Health
        S3Compliance = $s3Compliance
        Summary = @{
            EC2InstanceCount = $ec2Health.Count
            S3BucketCount = $s3Compliance.Count
            HealthyInstances = ($ec2Health | Where-Object { $_.State -eq "running" }).Count
            CompliantBuckets = ($s3Compliance | Where-Object { $_.EncryptionEnabled -and $_.VersioningEnabled }).Count
        }
    }
    
    $reportJson = $report | ConvertTo-Json -Depth 10
    Write-AutomationLog "Health check completed successfully"
    Write-AutomationLog ($report.Summary | ConvertTo-Json)
    
    # Return the report for Systems Manager output
    $reportJson
    
} catch {
    Write-AutomationLog "Health check failed: $($_.Exception.Message)" "ERROR"
    throw
}
'''

        document_content = {
            "schemaVersion": "0.3",
            "description": "Infrastructure Health Check Automation using PowerShell",
            "assumeRole": automation_role.role_arn,
            "parameters": {
                "Region": {
                    "type": "String",
                    "description": "AWS Region for health check",
                    "default": self.region
                },
                "LogGroupName": {
                    "type": "String",
                    "description": "CloudWatch Log Group for automation logs",
                    "default": log_group.log_group_name
                }
            },
            "mainSteps": [
                {
                    "name": "CreateLogGroup",
                    "action": "aws:executeAwsApi",
                    "description": "Ensure CloudWatch Log Group exists",
                    "inputs": {
                        "Service": "logs",
                        "Api": "CreateLogGroup",
                        "logGroupName": "{{ LogGroupName }}"
                    },
                    "onFailure": "Continue"
                },
                {
                    "name": "ExecuteHealthCheck",
                    "action": "aws:executeScript",
                    "description": "Execute PowerShell infrastructure health check",
                    "inputs": {
                        "Runtime": "PowerShell Core 6.0",
                        "Script": powershell_script,
                        "InputPayload": {
                            "Region": "{{ Region }}",
                            "LogGroup": "{{ LogGroupName }}"
                        }
                    }
                }
            ],
            "outputs": [
                "ExecuteHealthCheck.Payload"
            ]
        }

        automation_document = ssm.CfnDocument(
            self, "AutomationDocument",
            name=f"InfrastructureHealthCheck-{suffix}",
            document_type="Automation",
            document_format="JSON",
            content=document_content,
            tags=[
                {
                    "key": "Purpose",
                    "value": "Infrastructure Automation"
                },
                {
                    "key": "Environment",
                    "value": suffix
                }
            ]
        )

        return automation_document

    def _create_lambda_function(
        self, 
        automation_role: iam.Role, 
        automation_document: ssm.CfnDocument,
        suffix: str
    ) -> lambda_.Function:
        """
        Create Lambda function for automation orchestration
        """
        lambda_code = '''
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to orchestrate infrastructure automation
    """
    ssm = boto3.client('ssm')
    cloudwatch = boto3.client('cloudwatch')
    
    automation_document = os.environ['AUTOMATION_DOCUMENT_NAME']
    region = os.environ.get('AWS_REGION', 'us-east-1')
    
    logger.info(f"Starting automation execution for document: {automation_document}")
    
    try:
        # Execute automation document
        response = ssm.start_automation_execution(
            DocumentName=automation_document,
            Parameters={
                'Region': [region],
                'LogGroupName': ['/aws/automation/infrastructure-health']
            }
        )
        
        execution_id = response['AutomationExecutionId']
        logger.info(f"Automation execution started with ID: {execution_id}")
        
        # Send custom metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Automation',
            MetricData=[
                {
                    'MetricName': 'AutomationExecutions',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'DocumentName',
                            'Value': automation_document
                        }
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Automation started successfully',
                'executionId': execution_id,
                'timestamp': datetime.utcnow().isoformat(),
                'documentName': automation_document
            })
        }
        
    except Exception as e:
        logger.error(f"Automation execution failed: {str(e)}")
        
        # Send error metric
        try:
            cloudwatch.put_metric_data(
                Namespace='Infrastructure/Automation',
                MetricData=[
                    {
                        'MetricName': 'AutomationErrors',
                        'Value': 1,
                        'Unit': 'Count'
                    }
                ]
            )
        except Exception as metric_error:
            logger.error(f"Failed to send error metric: {str(metric_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
'''

        lambda_function = lambda_.Function(
            self, "AutomationLambdaFunction",
            function_name=f"InfrastructureAutomation-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=automation_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "AUTOMATION_DOCUMENT_NAME": automation_document.name
            },
            description="Lambda function for orchestrating infrastructure automation"
        )

        return lambda_function

    def _create_schedule_rule(
        self, 
        lambda_function: lambda_.Function,
        suffix: str
    ) -> events.Rule:
        """
        Create EventBridge rule for scheduled automation execution
        """
        schedule_rule = events.Rule(
            self, "AutomationScheduleRule",
            rule_name=f"InfrastructureHealthSchedule-{suffix}",
            description="Daily infrastructure health check at 6 AM UTC",
            schedule=events.Schedule.cron(
                minute="0",
                hour="6",
                day="*",
                month="*",
                year="*"
            ),
            enabled=True
        )

        # Add Lambda function as target
        schedule_rule.add_target(
            targets.LambdaFunction(
                lambda_function,
                retry_attempts=2
            )
        )

        return schedule_rule

    def _create_monitoring(
        self, 
        lambda_function: lambda_.Function,
        notification_topic: sns.Topic,
        suffix: str
    ) -> None:
        """
        Create CloudWatch monitoring and alerting resources
        """
        # CloudWatch Alarm for automation errors
        error_alarm = cloudwatch.Alarm(
            self, "AutomationErrorAlarm",
            alarm_name=f"InfrastructureAutomationErrors-{suffix}",
            alarm_description="Alert on infrastructure automation errors",
            metric=cloudwatch.Metric(
                namespace="Infrastructure/Automation",
                metric_name="AutomationErrors",
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            period=Duration.minutes(5),
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )

        # Add SNS action to alarm
        error_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(notification_topic)
        )

        # CloudWatch Dashboard for monitoring
        dashboard = cloudwatch.Dashboard(
            self, "AutomationDashboard",
            dashboard_name=f"InfrastructureAutomation-{suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Infrastructure Automation Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="Infrastructure/Automation",
                                metric_name="AutomationExecutions",
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="Infrastructure/Automation",
                                metric_name="AutomationErrors",
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Automation Logs",
                        log_groups=[logs.LogGroup.from_log_group_name(
                            self, "ImportedLogGroup",
                            "/aws/automation/infrastructure-health"
                        )],
                        query_lines=[
                            "fields @timestamp, level, message",
                            "sort @timestamp desc",
                            "limit 100"
                        ],
                        width=24
                    )
                ]
            ]
        )


app = cdk.App()

# Get environment configuration
env_config = cdk.Environment(
    account=app.node.try_get_context("account") or "123456789012",  # Default account ID
    region=app.node.try_get_context("region") or "us-east-1"       # Default region
)

InfrastructureAutomationStack(
    app, 
    "InfrastructureAutomationStack",
    env=env_config,
    description="Infrastructure for Infrastructure Automation with CloudShell PowerShell"
)

app.synth()