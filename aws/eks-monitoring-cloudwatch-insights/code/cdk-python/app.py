#!/usr/bin/env python3
"""
CDK Python application for EKS CloudWatch Container Insights monitoring setup.

This application creates the necessary infrastructure for comprehensive monitoring
and alerting of Amazon EKS clusters using CloudWatch Container Insights with
enhanced observability and SNS notifications.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_eks as eks,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_logs as logs,
    CfnParameter,
    CfnOutput,
    Tags,
)
from constructs import Construct
from typing import Optional


class EksCloudWatchContainerInsightsStack(Stack):
    """
    CDK Stack for setting up EKS CloudWatch Container Insights monitoring.
    
    This stack creates:
    - SNS topic for alerts
    - IAM roles and service accounts for Container Insights
    - CloudWatch alarms for monitoring EKS cluster health
    - Log groups for container logs
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        cluster_name: str,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the EKS CloudWatch Container Insights stack.

        Args:
            scope: CDK scope
            construct_id: Stack identifier
            cluster_name: Name of the existing EKS cluster
            notification_email: Email address for alert notifications
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Parameters
        self.cluster_name = cluster_name
        
        # Create parameter for notification email if not provided
        if notification_email:
            self.notification_email = notification_email
        else:
            email_parameter = CfnParameter(
                self,
                "NotificationEmail",
                type="String",
                description="Email address to receive CloudWatch alarms",
                constraint_description="Must be a valid email address",
            )
            self.notification_email = email_parameter.value_as_string

        # Create SNS topic for alerts
        self.alerts_topic = self._create_sns_topic()
        
        # Create IAM role for CloudWatch agent
        self.cloudwatch_agent_role = self._create_cloudwatch_agent_role()
        
        # Create CloudWatch log groups
        self.log_groups = self._create_log_groups()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Add outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for monitoring alerts.
        
        Returns:
            SNS topic for alert notifications
        """
        topic = sns.Topic(
            self,
            "EksMonitoringAlerts",
            topic_name=f"eks-{self.cluster_name}-monitoring-alerts",
            display_name=f"EKS {self.cluster_name} Monitoring Alerts",
            description=f"SNS topic for EKS cluster {self.cluster_name} monitoring alerts",
        )
        
        # Subscribe email to the topic
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.notification_email)
        )
        
        return topic

    def _create_cloudwatch_agent_role(self) -> iam.Role:
        """
        Create IAM role for CloudWatch agent with IRSA support.
        
        Returns:
            IAM role for CloudWatch agent
        """
        # Create OIDC provider condition for the specific cluster
        # Note: In a real deployment, you would get the OIDC issuer URL from the existing cluster
        oidc_condition = {
            f"oidc.eks.{self.region}.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub": 
                "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent",
            f"oidc.eks.{self.region}.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:aud": 
                "sts.amazonaws.com"
        }
        
        # Create trust policy for IRSA
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.FederatedPrincipal(
                        f"arn:aws:iam::{self.account}:oidc-provider/oidc.eks.{self.region}.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE",
                        {
                            "StringEquals": oidc_condition
                        }
                    )],
                    actions=["sts:AssumeRoleWithWebIdentity"]
                )
            ]
        )
        
        role = iam.Role(
            self,
            "CloudWatchAgentRole",
            role_name=f"EKS-{self.cluster_name}-CloudWatchAgentRole",
            description=f"IAM role for CloudWatch agent on EKS cluster {self.cluster_name}",
            assumed_by=iam.WebIdentityPrincipal(
                f"arn:aws:iam::{self.account}:oidc-provider/oidc.eks.{self.region}.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE",
                {
                    "StringEquals": oidc_condition
                }
            ),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
            ]
        )
        
        return role

    def _create_log_groups(self) -> dict:
        """
        Create CloudWatch log groups for EKS container logs.
        
        Returns:
            Dictionary of created log groups
        """
        log_groups = {}
        
        # Application logs
        log_groups["application"] = logs.LogGroup(
            self,
            "ApplicationLogs",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/application",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        # Dataplane logs
        log_groups["dataplane"] = logs.LogGroup(
            self,
            "DataplaneLogs",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/dataplane",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        # Host logs
        log_groups["host"] = logs.LogGroup(
            self,
            "HostLogs",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/host",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        # Performance logs
        log_groups["performance"] = logs.LogGroup(
            self,
            "PerformanceLogs",
            log_group_name=f"/aws/containerinsights/{self.cluster_name}/performance",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        return log_groups

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for EKS cluster monitoring."""
        
        # High CPU utilization alarm
        cpu_alarm = cloudwatch.Alarm(
            self,
            "HighCpuAlarm",
            alarm_name=f"EKS-{self.cluster_name}-HighCPU",
            alarm_description=f"EKS cluster {self.cluster_name} high CPU utilization",
            metric=cloudwatch.Metric(
                namespace="ContainerInsights",
                metric_name="node_cpu_utilization",
                dimensions_map={
                    "ClusterName": self.cluster_name
                },
                statistic="Average",
                period=cdk.Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        cpu_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.alerts_topic)
        )
        
        # High memory utilization alarm
        memory_alarm = cloudwatch.Alarm(
            self,
            "HighMemoryAlarm",
            alarm_name=f"EKS-{self.cluster_name}-HighMemory",
            alarm_description=f"EKS cluster {self.cluster_name} high memory utilization",
            metric=cloudwatch.Metric(
                namespace="ContainerInsights",
                metric_name="node_memory_utilization",
                dimensions_map={
                    "ClusterName": self.cluster_name
                },
                statistic="Average",
                period=cdk.Duration.minutes(5)
            ),
            threshold=85,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        memory_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.alerts_topic)
        )
        
        # Failed pods alarm
        failed_pods_alarm = cloudwatch.Alarm(
            self,
            "FailedPodsAlarm",
            alarm_name=f"EKS-{self.cluster_name}-FailedPods",
            alarm_description=f"EKS cluster {self.cluster_name} has failed pods",
            metric=cloudwatch.Metric(
                namespace="ContainerInsights",
                metric_name="cluster_failed_node_count",
                dimensions_map={
                    "ClusterName": self.cluster_name
                },
                statistic="Maximum",
                period=cdk.Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        failed_pods_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.alerts_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self,
            "SnsTopicArn",
            value=self.alerts_topic.topic_arn,
            description="ARN of the SNS topic for monitoring alerts",
            export_name=f"EKS-{self.cluster_name}-AlertsTopic"
        )
        
        CfnOutput(
            self,
            "CloudWatchAgentRoleArn",
            value=self.cloudwatch_agent_role.role_arn,
            description="ARN of the IAM role for CloudWatch agent",
            export_name=f"EKS-{self.cluster_name}-CloudWatchAgentRole"
        )
        
        CfnOutput(
            self,
            "ApplicationLogGroup",
            value=self.log_groups["application"].log_group_name,
            description="Name of the application log group",
            export_name=f"EKS-{self.cluster_name}-ApplicationLogGroup"
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        
        Tags.of(self).add("Project", "EKS-Monitoring")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ClusterName", self.cluster_name)
        Tags.of(self).add("ManagedBy", "CDK")


# CDK App
app = cdk.App()

# Get cluster name from context or use default
cluster_name = app.node.try_get_context("cluster_name") or "my-eks-cluster"
notification_email = app.node.try_get_context("notification_email")

# Create the stack
EksCloudWatchContainerInsightsStack(
    app,
    "EksCloudWatchContainerInsightsStack",
    cluster_name=cluster_name,
    notification_email=notification_email,
    description="EKS CloudWatch Container Insights monitoring infrastructure",
    env=cdk.Environment(
        account=app.node.try_get_context("account") or None,
        region=app.node.try_get_context("region") or "us-west-2"
    )
)

app.synth()