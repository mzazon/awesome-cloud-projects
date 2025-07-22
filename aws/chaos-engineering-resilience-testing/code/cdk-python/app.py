#!/usr/bin/env python3
"""
AWS CDK Python Application for Chaos Engineering with FIS and EventBridge

This CDK application deploys a complete chaos engineering solution using AWS Fault Injection Service
(FIS) integrated with EventBridge for automated scheduling and monitoring. The infrastructure
includes CloudWatch alarms for safety mechanisms, SNS notifications, and monitoring dashboards.

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    CfnOutput,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_scheduler as scheduler,
    aws_fis as fis
)
from constructs import Construct
import json
from typing import Dict, Any, Optional


class ChaosEngineeringStack(Stack):
    """
    AWS CDK Stack for implementing chaos engineering testing with FIS and EventBridge.
    
    This stack creates:
    - IAM roles for FIS experiments, EventBridge, and Scheduler
    - CloudWatch alarms for experiment stop conditions
    - SNS topic for notifications
    - FIS experiment template for chaos testing
    - EventBridge rules for experiment state changes
    - EventBridge scheduler for automated experiments
    - CloudWatch dashboard for monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        notification_email: Optional[str] = None,
        target_resource_tags: Optional[Dict[str, str]] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Chaos Engineering Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            notification_email: Email address for SNS notifications
            target_resource_tags: Tags to identify target resources for experiments
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Set default values
        self.notification_email = notification_email or "admin@example.com"
        self.target_tags = target_resource_tags or {"ChaosReady": "true"}
        
        # Generate unique suffix for resource names
        self.unique_suffix = self.node.addr[:8].lower()

        # Create SNS topic for notifications
        self.sns_topic = self._create_sns_topic()
        
        # Create IAM roles
        self.fis_role = self._create_fis_role()
        self.eventbridge_role = self._create_eventbridge_role()
        self.scheduler_role = self._create_scheduler_role()
        
        # Create CloudWatch alarms for stop conditions
        self.alarms = self._create_cloudwatch_alarms()
        
        # Create FIS experiment template
        self.experiment_template = self._create_fis_experiment_template()
        
        # Create EventBridge rules for notifications
        self.eventbridge_rule = self._create_eventbridge_rule()
        
        # Create scheduled experiments
        self.scheduler_schedule = self._create_scheduler()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for chaos engineering notifications.
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "FISAlertsTopic",
            topic_name=f"fis-alerts-{self.unique_suffix}",
            display_name="AWS FIS Chaos Engineering Alerts",
            description="Notifications for chaos engineering experiments and alerts"
        )
        
        # Add email subscription if provided
        if self.notification_email != "admin@example.com":
            topic.add_subscription(
                sns_subscriptions.EmailSubscription(self.notification_email)
            )
        
        return topic

    def _create_fis_role(self) -> iam.Role:
        """
        Create IAM role for AWS Fault Injection Service experiments.
        
        Returns:
            iam.Role: The IAM role for FIS experiments
        """
        role = iam.Role(
            self,
            "FISExperimentRole",
            role_name=f"FISExperimentRole-{self.unique_suffix}",
            description="IAM role for AWS FIS chaos engineering experiments",
            assumed_by=iam.ServicePrincipal("fis.amazonaws.com"),
            managed_policies=[
                # Use PowerUserAccess for testing - restrict in production
                iam.ManagedPolicy.from_aws_managed_policy_name("PowerUserAccess")
            ]
        )
        
        # Add custom inline policy for FIS-specific permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ec2:DescribeInstances",
                    "ec2:TerminateInstances",
                    "ssm:SendCommand",
                    "ssm:DescribeInstanceInformation",
                    "ssm:DescribeCommandInvocations",
                    "logs:CreateLogDelivery",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams"
                ],
                resources=["*"]
            )
        )
        
        return role

    def _create_eventbridge_role(self) -> iam.Role:
        """
        Create IAM role for EventBridge to publish to SNS.
        
        Returns:
            iam.Role: The IAM role for EventBridge
        """
        role = iam.Role(
            self,
            "EventBridgeFISRole",
            role_name=f"EventBridgeFISRole-{self.unique_suffix}",
            description="IAM role for EventBridge to publish FIS events to SNS",
            assumed_by=iam.ServicePrincipal("events.amazonaws.com")
        )
        
        # Grant permission to publish to SNS topic
        self.sns_topic.grant_publish(role)
        
        return role

    def _create_scheduler_role(self) -> iam.Role:
        """
        Create IAM role for EventBridge Scheduler to start FIS experiments.
        
        Returns:
            iam.Role: The IAM role for EventBridge Scheduler
        """
        role = iam.Role(
            self,
            "SchedulerFISRole",
            role_name=f"SchedulerFISRole-{self.unique_suffix}",
            description="IAM role for EventBridge Scheduler to start FIS experiments",
            assumed_by=iam.ServicePrincipal("scheduler.amazonaws.com")
        )
        
        # Add policy to start FIS experiments
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["fis:StartExperiment"],
                resources=[
                    f"arn:aws:fis:{self.region}:{self.account}:experiment-template/*",
                    f"arn:aws:fis:{self.region}:{self.account}:experiment/*"
                ]
            )
        )
        
        return role

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """
        Create CloudWatch alarms that serve as stop conditions for FIS experiments.
        
        Returns:
            Dict[str, cloudwatch.Alarm]: Dictionary of created alarms
        """
        alarms = {}
        
        # High error rate alarm for Application Load Balancer
        alarms["error_rate"] = cloudwatch.Alarm(
            self,
            "FISHighErrorRateAlarm",
            alarm_name=f"FIS-HighErrorRate-{self.unique_suffix}",
            alarm_description="Stop FIS experiment on high error rate",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="HTTPCode_Target_4XX_Count",
                statistic="Sum",
                period=Duration.minutes(1)
            ),
            threshold=50,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # High CPU utilization alarm for EC2
        alarms["cpu_utilization"] = cloudwatch.Alarm(
            self,
            "FISHighCPUAlarm",
            alarm_name=f"FIS-HighCPU-{self.unique_suffix}",
            alarm_description="Monitor CPU utilization during chaos experiments",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=90,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Configure alarms to send notifications
        for alarm in alarms.values():
            alarm.add_alarm_action(
                cloudwatch_actions.SnsAction(self.sns_topic)
            )
        
        return alarms

    def _create_fis_experiment_template(self) -> fis.CfnExperimentTemplate:
        """
        Create FIS experiment template for chaos engineering tests.
        
        Returns:
            fis.CfnExperimentTemplate: The FIS experiment template
        """
        # Define experiment actions
        actions = {
            "cpu-stress": {
                "actionId": "aws:ssm:send-command",
                "description": "Inject CPU stress on EC2 instances",
                "parameters": {
                    "documentArn": f"arn:aws:ssm:{self.region}::document/AWSFIS-Run-CPU-Stress",
                    "documentParameters": json.dumps({
                        "DurationSeconds": "120",
                        "CPU": "0",
                        "LoadPercent": "80"
                    }),
                    "duration": "PT3M"
                },
                "targets": {
                    "Instances": "ec2-instances"
                }
            },
            "terminate-instance": {
                "actionId": "aws:ec2:terminate-instances",
                "description": "Terminate EC2 instance to test recovery",
                "targets": {
                    "Instances": "ec2-instances"
                },
                "startAfter": ["cpu-stress"]
            }
        }
        
        # Define experiment targets
        targets = {
            "ec2-instances": {
                "resourceType": "aws:ec2:instance",
                "selectionMode": "COUNT(1)",
                "resourceTags": self.target_tags
            }
        }
        
        # Define stop conditions
        stop_conditions = [
            {
                "source": "aws:cloudwatch:alarm",
                "value": self.alarms["error_rate"].alarm_arn
            }
        ]
        
        template = fis.CfnExperimentTemplate(
            self,
            "ChaosExperimentTemplate",
            description="Multi-action chaos experiment for resilience testing",
            role_arn=self.fis_role.role_arn,
            actions=actions,
            targets=targets,
            stop_conditions=stop_conditions,
            tags={
                "Environment": "Testing",
                "Purpose": "ChaosEngineering",
                "CreatedBy": "AWS-CDK"
            }
        )
        
        return template

    def _create_eventbridge_rule(self) -> events.Rule:
        """
        Create EventBridge rule to capture FIS experiment state changes.
        
        Returns:
            events.Rule: The EventBridge rule
        """
        rule = events.Rule(
            self,
            "FISExperimentStateChanges",
            rule_name=f"FIS-ExperimentStateChanges-{self.unique_suffix}",
            description="Capture all FIS experiment state changes",
            event_pattern=events.EventPattern(
                source=["aws.fis"],
                detail_type=["FIS Experiment State Change"]
            )
        )
        
        # Add SNS target
        rule.add_target(
            targets.SnsTopic(
                topic=self.sns_topic,
                message=events.RuleTargetInput.from_text(
                    "FIS Experiment State Change: Experiment {$.detail.experiment-id} "
                    "changed to state {$.detail.state.status}"
                )
            )
        )
        
        return rule

    def _create_scheduler(self) -> scheduler.CfnSchedule:
        """
        Create EventBridge Scheduler for automated chaos experiments.
        
        Returns:
            scheduler.CfnSchedule: The EventBridge schedule
        """
        # Create schedule that runs daily at 2 AM UTC
        schedule = scheduler.CfnSchedule(
            self,
            "FISDailyChaosTest",
            name=f"FIS-DailyChaosTest-{self.unique_suffix}",
            description="Automated daily chaos engineering experiments",
            schedule_expression="cron(0 2 * * ? *)",  # Daily at 2 AM UTC
            target=scheduler.CfnSchedule.TargetProperty(
                arn="arn:aws:scheduler:::aws-sdk:fis:startExperiment",
                role_arn=self.scheduler_role.role_arn,
                input=json.dumps({
                    "experimentTemplateId": self.experiment_template.ref
                })
            ),
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="OFF"
            ),
            state="ENABLED"
        )
        
        return schedule

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for chaos engineering monitoring.
        
        Returns:
            cloudwatch.Dashboard: The CloudWatch dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "ChaosMonitoringDashboard",
            dashboard_name=f"chaos-monitoring-{self.unique_suffix}",
            default_interval=Duration.minutes(5)
        )
        
        # Add FIS experiment metrics widget
        fis_metrics_widget = cloudwatch.GraphWidget(
            title="FIS Experiment Status",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/FIS",
                    metric_name="ExperimentsStarted",
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/FIS",
                    metric_name="ExperimentsStopped",
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/FIS",
                    metric_name="ExperimentsFailed",
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # Add application health metrics widget
        app_health_widget = cloudwatch.GraphWidget(
            title="Application Health During Experiments",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="CPUUtilization",
                    statistic="Average",
                    period=Duration.minutes(1)
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/ApplicationELB",
                    metric_name="TargetResponseTime",
                    statistic="Average",
                    period=Duration.minutes(1)
                ),
                cloudwatch.Metric(
                    namespace="AWS/ApplicationELB",
                    metric_name="HTTPCode_Target_4XX_Count",
                    statistic="Sum",
                    period=Duration.minutes(1)
                )
            ],
            width=12,
            height=6
        )
        
        # Add alarm status widget
        alarm_widget = cloudwatch.AlarmStatusWidget(
            title="Chaos Engineering Alarms",
            alarms=[
                self.alarms["error_rate"],
                self.alarms["cpu_utilization"]
            ],
            width=12,
            height=4
        )
        
        dashboard.add_widgets(
            fis_metrics_widget,
            app_health_widget,
            alarm_widget
        )
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self,
            "SNSTopicArn",
            description="ARN of the SNS topic for chaos engineering notifications",
            value=self.sns_topic.topic_arn
        )
        
        CfnOutput(
            self,
            "FISExperimentTemplateId",
            description="ID of the FIS experiment template",
            value=self.experiment_template.ref
        )
        
        CfnOutput(
            self,
            "FISRoleArn",
            description="ARN of the IAM role for FIS experiments",
            value=self.fis_role.role_arn
        )
        
        CfnOutput(
            self,
            "CloudWatchDashboardURL",
            description="URL to the CloudWatch dashboard",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}"
        )
        
        CfnOutput(
            self,
            "ErrorRateAlarmArn",
            description="ARN of the error rate CloudWatch alarm",
            value=self.alarms["error_rate"].alarm_arn
        )
        
        CfnOutput(
            self,
            "SchedulerName",
            description="Name of the EventBridge scheduler for automated experiments",
            value=self.scheduler_schedule.name
        )


class ChaosEngineeringApp(cdk.App):
    """
    CDK Application for Chaos Engineering with FIS and EventBridge.
    """
    
    def __init__(self):
        super().__init__()
        
        # Get context values for configuration
        notification_email = self.node.try_get_context("notification_email")
        target_tags = self.node.try_get_context("target_tags")
        
        # Create the main stack
        ChaosEngineeringStack(
            self,
            "ChaosEngineeringStack",
            notification_email=notification_email,
            target_resource_tags=target_tags,
            description="AWS Chaos Engineering infrastructure with FIS and EventBridge",
            env=cdk.Environment(
                account=self.account,
                region=self.region
            )
        )


# Entry point for the CDK application
if __name__ == "__main__":
    app = ChaosEngineeringApp()
    app.synth()