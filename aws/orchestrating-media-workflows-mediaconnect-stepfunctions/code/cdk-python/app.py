#!/usr/bin/env python3
"""
AWS CDK Python application for orchestrating real-time media workflows 
with AWS Elemental MediaConnect and Step Functions.

This application creates:
- MediaConnect flow for reliable video transport
- Step Functions state machine for workflow orchestration  
- Lambda functions for stream monitoring and alerting
- CloudWatch alarms and dashboard for monitoring
- SNS topic for notifications
- EventBridge rules for automated workflow execution
"""

import os
import random
import string
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    CfnResource,
    Tags,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_stepfunctions as stepfunctions,
    aws_stepfunctions_tasks as stepfunctions_tasks,
)
from constructs import Construct


class MediaWorkflowStackProps:
    """Properties for the MediaWorkflowStack."""
    
    def __init__(
        self,
        flow_name: Optional[str] = None,
        notification_email: Optional[str] = None,
        source_whitelist_cidr: Optional[str] = None,
        primary_output_destination: Optional[str] = None,
        backup_output_destination: Optional[str] = None,
        packet_loss_threshold: Optional[float] = None,
        jitter_threshold: Optional[float] = None,
        **kwargs
    ) -> None:
        """Initialize MediaWorkflowStackProps.
        
        Args:
            flow_name: Flow name for MediaConnect flow
            notification_email: Email address for SNS notifications
            source_whitelist_cidr: Source IP whitelist for MediaConnect flow
            primary_output_destination: Primary output destination IP
            backup_output_destination: Backup output destination IP
            packet_loss_threshold: Packet loss threshold percentage (default: 0.1)
            jitter_threshold: Jitter threshold in milliseconds (default: 50)
            **kwargs: Additional stack properties
        """
        self.flow_name = flow_name
        self.notification_email = notification_email
        self.source_whitelist_cidr = source_whitelist_cidr
        self.primary_output_destination = primary_output_destination
        self.backup_output_destination = backup_output_destination
        self.packet_loss_threshold = packet_loss_threshold
        self.jitter_threshold = jitter_threshold
        self.stack_props = kwargs


class MediaWorkflowStack(Stack):
    """
    AWS CDK Stack for orchestrating real-time media workflows with 
    AWS Elemental MediaConnect and Step Functions.
    
    This stack creates:
    - MediaConnect flow for reliable video transport
    - Step Functions state machine for workflow orchestration
    - Lambda functions for stream monitoring and alerting
    - CloudWatch alarms and dashboard for monitoring
    - SNS topic for notifications
    - EventBridge rules for automated workflow execution
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        props: Optional[MediaWorkflowStackProps] = None,
        **kwargs
    ) -> None:
        """Initialize MediaWorkflowStack.
        
        Args:
            scope: The scope in which this construct is defined
            construct_id: The scoped construct ID
            props: Stack configuration properties
            **kwargs: Additional stack properties
        """
        # Merge stack properties
        if props and props.stack_props:
            kwargs.update(props.stack_props)
        
        super().__init__(scope, construct_id, **kwargs)

        # Extract properties with defaults
        if props is None:
            props = MediaWorkflowStackProps()
            
        flow_name = props.flow_name or f"live-stream-{self._generate_random_suffix()}"
        notification_email = props.notification_email or "your-email@example.com"
        source_whitelist_cidr = props.source_whitelist_cidr or "0.0.0.0/0"
        primary_output_destination = props.primary_output_destination or "10.0.0.100"
        backup_output_destination = props.backup_output_destination or "10.0.0.101"
        packet_loss_threshold = props.packet_loss_threshold or 0.1
        jitter_threshold = props.jitter_threshold or 50

        # Create S3 bucket for Lambda deployment packages
        lambda_bucket = s3.Bucket(
            self, "LambdaCodeBucket",
            bucket_name=f"lambda-code-{self._generate_random_suffix()}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="CleanupOldVersions",
                    expiration=Duration.days(30)
                )
            ]
        )

        # Create SNS Topic for media alerts
        alerts_topic = sns.Topic(
            self, "MediaAlertsTopic",
            topic_name=f"media-alerts-{self._generate_random_suffix()}",
            display_name="Media Workflow Alerts"
        )

        # Add email subscription to SNS topic
        alerts_topic.add_subscription(
            sns_subscriptions.EmailSubscription(notification_email)
        )

        # Create IAM role for Lambda functions
        lambda_role = iam.Role(
            self, "MediaLambdaRole",
            role_name=f"media-lambda-role-{self._generate_random_suffix()}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "MediaConnectAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "mediaconnect:DescribeFlow",
                                "mediaconnect:ListFlows",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:GetMetricData",
                                "sns:Publish"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Create stream monitor Lambda function
        stream_monitor_function = lambda_.Function(
            self, "StreamMonitorFunction",
            function_name=f"stream-monitor-{self._generate_random_suffix()}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_stream_monitor_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=lambda_role,
            environment={
                "SNS_TOPIC_ARN": alerts_topic.topic_arn,
                "PACKET_LOSS_THRESHOLD": str(packet_loss_threshold),
                "JITTER_THRESHOLD": str(jitter_threshold)
            },
            description="Monitors MediaConnect flow health metrics and detects quality issues"
        )

        # Create alert handler Lambda function
        alert_handler_function = lambda_.Function(
            self, "AlertHandlerFunction",
            function_name=f"alert-handler-{self._generate_random_suffix()}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_alert_handler_code()),
            timeout=Duration.seconds(30),
            memory_size=128,
            role=lambda_role,
            environment={
                "SNS_TOPIC_ARN": alerts_topic.topic_arn
            },
            description="Formats and sends notifications for MediaConnect flow issues"
        )

        # Grant SNS publish permissions to Lambda functions
        alerts_topic.grant_publish(stream_monitor_function)
        alerts_topic.grant_publish(alert_handler_function)

        # Create IAM role for Step Functions
        step_functions_role = iam.Role(
            self, "MediaStepFunctionsRole",
            role_name=f"media-sf-role-{self._generate_random_suffix()}",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            inline_policies={
                "StepFunctionsExecutionPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "lambda:InvokeFunction",
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Create Step Functions state machine
        monitor_stream_task = stepfunctions_tasks.LambdaInvoke(
            self, "MonitorStreamTask",
            lambda_function=stream_monitor_function,
            payload_response_only=True,
            result_path="$.monitoring_result"
        )

        send_alert_task = stepfunctions_tasks.LambdaInvoke(
            self, "SendAlertTask",
            lambda_function=alert_handler_function,
            payload_response_only=True
        )

        healthy_flow_pass = stepfunctions.Pass(
            self, "HealthyFlow",
            result=stepfunctions.Result.from_string("Flow is healthy - no action required")
        )

        # Define the workflow
        definition = monitor_stream_task.next(
            stepfunctions.Choice(self, "EvaluateHealth")
            .when(
                stepfunctions.Condition.boolean_equals("$.monitoring_result.healthy", False),
                send_alert_task
            )
            .otherwise(healthy_flow_pass)
        )

        # Create log group for Step Functions
        state_machine_log_group = logs.LogGroup(
            self, "StateMachineLogGroup",
            log_group_name=f"/aws/stepfunctions/media-workflow-{self._generate_random_suffix()}",
            removal_policy=RemovalPolicy.DESTROY
        )

        state_machine = stepfunctions.StateMachine(
            self, "MediaWorkflowStateMachine",
            state_machine_name=f"media-workflow-{self._generate_random_suffix()}",
            state_machine_type=stepfunctions.StateMachineType.EXPRESS,
            definition=definition,
            role=step_functions_role,
            logs=stepfunctions.LogOptions(
                destination=state_machine_log_group,
                level=stepfunctions.LogLevel.ERROR,
                include_execution_data=False
            )
        )

        # Create MediaConnect flow using custom resource (L1 construct)
        mediaconnect_flow = CfnResource(
            self, "MediaConnectFlow",
            type="AWS::MediaConnect::Flow",
            properties={
                "Name": flow_name,
                "AvailabilityZone": f"{self.region}a",
                "Source": {
                    "Name": "PrimarySource",
                    "Description": "Primary live stream source",
                    "Protocol": "rtp",
                    "WhitelistCidr": source_whitelist_cidr,
                    "IngestPort": 5000
                },
                "Outputs": [
                    {
                        "Name": "PrimaryOutput",
                        "Description": "Primary stream output",
                        "Protocol": "rtp",
                        "Destination": primary_output_destination,
                        "Port": 5001
                    },
                    {
                        "Name": "BackupOutput",
                        "Description": "Backup stream output",
                        "Protocol": "rtp",
                        "Destination": backup_output_destination,
                        "Port": 5002
                    }
                ]
            }
        )

        # Create CloudWatch alarms for stream health monitoring
        packet_loss_alarm = cloudwatch.Alarm(
            self, "PacketLossAlarm",
            alarm_name=f"{flow_name}-packet-loss",
            alarm_description="Triggers when packet loss exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaConnect",
                metric_name="SourcePacketLossPercent",
                dimensions_map={
                    "FlowARN": mediaconnect_flow.ref
                },
                statistic="Maximum",
                period=Duration.minutes(5)
            ),
            threshold=packet_loss_threshold,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            datapoints_to_alarm=1,
            evaluation_periods=1
        )

        jitter_alarm = cloudwatch.Alarm(
            self, "JitterAlarm",
            alarm_name=f"{flow_name}-jitter",
            alarm_description="Triggers when jitter exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaConnect",
                metric_name="SourceJitter",
                dimensions_map={
                    "FlowARN": mediaconnect_flow.ref
                },
                statistic="Maximum",
                period=Duration.minutes(5)
            ),
            threshold=jitter_threshold,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            datapoints_to_alarm=2,
            evaluation_periods=2
        )

        workflow_trigger_alarm = cloudwatch.Alarm(
            self, "WorkflowTriggerAlarm",
            alarm_name=f"{flow_name}-workflow-trigger",
            alarm_description="Triggers media monitoring workflow",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaConnect",
                metric_name="SourcePacketLossPercent",
                dimensions_map={
                    "FlowARN": mediaconnect_flow.ref
                },
                statistic="Average",
                period=Duration.minutes(1)
            ),
            threshold=0.05,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            datapoints_to_alarm=1,
            evaluation_periods=1
        )

        # Add SNS notification actions to alarms
        packet_loss_alarm.add_alarm_action(cloudwatch_actions.SnsAction(alerts_topic))
        jitter_alarm.add_alarm_action(cloudwatch_actions.SnsAction(alerts_topic))

        # Create EventBridge rule for automated workflow execution
        alarm_rule = events.Rule(
            self, "AlarmRule",
            rule_name=f"{flow_name}-alarm-rule",
            description="Triggers workflow on MediaConnect alarm",
            event_pattern=events.EventPattern(
                source=["aws.cloudwatch"],
                detail_type=["CloudWatch Alarm State Change"],
                detail={
                    "alarmName": [workflow_trigger_alarm.alarm_name],
                    "state": {
                        "value": ["ALARM"]
                    }
                }
            )
        )

        # Add Step Functions as target for EventBridge rule
        alarm_rule.add_target(
            events_targets.SfnStateMachine(
                state_machine,
                input=events.RuleTargetInput.from_object({
                    "flow_arn": mediaconnect_flow.ref
                })
            )
        )

        # Create CloudWatch Dashboard for visualization
        dashboard = cloudwatch.Dashboard(
            self, "MediaDashboard",
            dashboard_name=f"{flow_name}-monitoring"
        )

        # Add widgets to dashboard
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Stream Health Metrics",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/MediaConnect",
                        metric_name="SourcePacketLossPercent",
                        dimensions_map={
                            "FlowARN": mediaconnect_flow.ref
                        },
                        statistic="Maximum",
                        period=Duration.minutes(5)
                    )
                ],
                right=[
                    cloudwatch.Metric(
                        namespace="AWS/MediaConnect",
                        metric_name="SourceJitter",
                        dimensions_map={
                            "FlowARN": mediaconnect_flow.ref
                        },
                        statistic="Average",
                        period=Duration.minutes(5)
                    )
                ]
            ),
            cloudwatch.GraphWidget(
                title="Stream Performance",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/MediaConnect",
                        metric_name="SourceBitrate",
                        dimensions_map={
                            "FlowARN": mediaconnect_flow.ref
                        },
                        statistic="Average",
                        period=Duration.minutes(5)
                    )
                ],
                right=[
                    cloudwatch.Metric(
                        namespace="AWS/MediaConnect",
                        metric_name="SourceUptime",
                        dimensions_map={
                            "FlowARN": mediaconnect_flow.ref
                        },
                        statistic="Maximum",
                        period=Duration.minutes(5)
                    )
                ]
            )
        )

        # Store public properties
        self.flow_arn = mediaconnect_flow.ref
        self.state_machine_arn = state_machine.state_machine_arn
        self.sns_topic_arn = alerts_topic.topic_arn

        # Create CloudFormation outputs
        CfnOutput(
            self, "MediaConnectFlowArn",
            description="ARN of the MediaConnect flow",
            value=self.flow_arn,
            export_name=f"{self.stack_name}-FlowArn"
        )

        CfnOutput(
            self, "StepFunctionsStateMachineArn",
            description="ARN of the Step Functions state machine",
            value=self.state_machine_arn,
            export_name=f"{self.stack_name}-StateMachineArn"
        )

        CfnOutput(
            self, "SNSTopicArn",
            description="ARN of the SNS topic for alerts",
            value=self.sns_topic_arn,
            export_name=f"{self.stack_name}-SNSTopicArn"
        )

        CfnOutput(
            self, "DashboardURL",
            description="URL of the CloudWatch dashboard",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={flow_name}-monitoring"
        )

        CfnOutput(
            self, "StreamMonitorLambdaArn",
            description="ARN of the stream monitor Lambda function",
            value=stream_monitor_function.function_arn
        )

        CfnOutput(
            self, "AlertHandlerLambdaArn",
            description="ARN of the alert handler Lambda function",
            value=alert_handler_function.function_arn
        )

        # Add tags to all resources
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Purpose", "MediaWorkflow")
        Tags.of(self).add("Application", "MediaConnect-StepFunctions")

    def _generate_random_suffix(self) -> str:
        """Generate a random suffix for resource names.
        
        Returns:
            Random 6-character string
        """
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

    def _get_stream_monitor_code(self) -> str:
        """Get the Python code for the stream monitor Lambda function.
        
        Returns:
            Python code as string
        """
        return '''
import json
import boto3
import os
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
mediaconnect = boto3.client('mediaconnect')

def lambda_handler(event, context):
    try:
        flow_arn = event['flow_arn']
        packet_loss_threshold = float(os.environ.get('PACKET_LOSS_THRESHOLD', '0.1'))
        jitter_threshold = float(os.environ.get('JITTER_THRESHOLD', '50'))
        
        # Get flow details
        flow = mediaconnect.describe_flow(FlowArn=flow_arn)
        flow_name = flow['Flow']['Name']
        
        # Query CloudWatch metrics for the last 5 minutes
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Check source packet loss
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourcePacketLossPercent',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # Analyze metrics
        issues = []
        if response['Datapoints']:
            latest = sorted(response['Datapoints'], 
                           key=lambda x: x['Timestamp'])[-1]
            if latest['Maximum'] > packet_loss_threshold:
                issues.append({
                    'metric': 'PacketLoss',
                    'value': latest['Maximum'],
                    'threshold': packet_loss_threshold,
                    'severity': 'HIGH'
                })
        
        # Check source jitter
        jitter_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourceJitter',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if jitter_response['Datapoints']:
            latest_jitter = sorted(jitter_response['Datapoints'], 
                                 key=lambda x: x['Timestamp'])[-1]
            if latest_jitter['Maximum'] > jitter_threshold:
                issues.append({
                    'metric': 'Jitter',
                    'value': latest_jitter['Maximum'],
                    'threshold': jitter_threshold,
                    'severity': 'MEDIUM'
                })
        
        return {
            'statusCode': 200,
            'flow_name': flow_name,
            'flow_arn': flow_arn,
            'timestamp': end_time.isoformat(),
            'issues': issues,
            'healthy': len(issues) == 0
        }
        
    except Exception as e:
        print(f"Error monitoring stream: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'healthy': False
        }
'''

    def _get_alert_handler_code(self) -> str:
        """Get the Python code for the alert handler Lambda function.
        
        Returns:
            Python code as string
        """
        return '''
import json
import boto3
import os

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        # Extract monitoring results
        monitoring_result = event
        
        if not monitoring_result.get('healthy', True):
            # Construct alert message
            subject = f"MediaConnect Alert: {monitoring_result.get('flow_name', 'Unknown Flow')}"
            
            message_lines = [
                f"Flow: {monitoring_result.get('flow_name', 'Unknown')}",
                f"Time: {monitoring_result.get('timestamp', 'Unknown')}",
                f"Status: UNHEALTHY",
                "",
                "Issues Detected:"
            ]
            
            for issue in monitoring_result.get('issues', []):
                message_lines.append(
                    f"- {issue['metric']}: {issue['value']:.2f} "
                    f"(threshold: {issue['threshold']}) "
                    f"[{issue['severity']}]"
                )
            
            message_lines.extend([
                "",
                "Recommended Actions:",
                "1. Check source encoder stability",
                "2. Verify network connectivity",
                "3. Review CloudWatch dashboard for detailed metrics",
                f"4. Access flow in console: https://console.aws.amazon.com/mediaconnect/home?region={context.invoked_function_arn.split(':')[3]}#/flows"
            ])
            
            message = "\\n".join(message_lines)
            
            # Send SNS notification
            response = sns.publish(
                TopicArn=sns_topic_arn,
                Subject=subject,
                Message=message
            )
            
            return {
                'statusCode': 200,
                'notification_sent': True,
                'message_id': response['MessageId']
            }
        
        return {
            'statusCode': 200,
            'notification_sent': False,
            'reason': 'Flow is healthy'
        }
        
    except Exception as e:
        print(f"Error handling alert: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'notification_sent': False
        }
'''


def main() -> None:
    """CDK Application entry point."""
    app = cdk.App()

    # Get configuration from context or environment variables
    config = MediaWorkflowStackProps(
        flow_name=app.node.try_get_context("flowName") or os.environ.get("FLOW_NAME"),
        notification_email=(
            app.node.try_get_context("notificationEmail") 
            or os.environ.get("NOTIFICATION_EMAIL") 
            or "your-email@example.com"
        ),
        source_whitelist_cidr=(
            app.node.try_get_context("sourceWhitelistCidr") 
            or os.environ.get("SOURCE_WHITELIST_CIDR") 
            or "0.0.0.0/0"
        ),
        primary_output_destination=(
            app.node.try_get_context("primaryOutputDestination") 
            or os.environ.get("PRIMARY_OUTPUT_DESTINATION") 
            or "10.0.0.100"
        ),
        backup_output_destination=(
            app.node.try_get_context("backupOutputDestination") 
            or os.environ.get("BACKUP_OUTPUT_DESTINATION") 
            or "10.0.0.101"
        ),
        packet_loss_threshold=float(
            app.node.try_get_context("packetLossThreshold") 
            or os.environ.get("PACKET_LOSS_THRESHOLD") 
            or "0.1"
        ),
        jitter_threshold=float(
            app.node.try_get_context("jitterThreshold") 
            or os.environ.get("JITTER_THRESHOLD") 
            or "50"
        ),
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION") or "us-east-1"
        ),
        description=(
            "Media workflow stack for orchestrating real-time media workflows "
            "with AWS Elemental MediaConnect and Step Functions"
        ),
        tags={
            "Application": "MediaWorkflow",
            "Environment": "Production",
            "Purpose": "MediaStreaming"
        }
    )

    # Create the media workflow stack
    MediaWorkflowStack(app, "MediaWorkflowStack", config)

    # Synthesize the CDK app
    app.synth()


if __name__ == "__main__":
    main()