#!/usr/bin/env python3
"""
Infrastructure Monitoring Quick Setup with AWS CDK
==================================================

This CDK application deploys a comprehensive infrastructure monitoring solution
using AWS Systems Manager and CloudWatch. It automates the setup of monitoring,
compliance scanning, and alerting across EC2 instances.

Key Components:
- IAM roles and policies for Systems Manager operations
- CloudWatch Agent configuration stored in Parameter Store
- CloudWatch dashboards for infrastructure visualization
- CloudWatch alarms for proactive monitoring
- Systems Manager associations for compliance and patching
- CloudWatch log groups for centralized logging

Author: AWS CDK Team
Version: 1.0
Compatible with: CDK v2.x
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_ssm as ssm,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, List, Any
import json


class InfrastructureMonitoringStack(Stack):
    """
    CDK Stack for Infrastructure Monitoring Quick Setup
    
    This stack creates a comprehensive monitoring solution that includes:
    - IAM service roles for Systems Manager
    - CloudWatch Agent configuration
    - Monitoring dashboards and alarms
    - Compliance and patch management associations
    - Centralized logging configuration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate a unique suffix for resource naming
        self.unique_suffix = self.node.try_get_context("unique_suffix") or "infra-mon"
        
        # Create IAM service role for Systems Manager
        self.ssm_service_role = self._create_ssm_service_role()
        
        # Create CloudWatch Agent configuration
        self.agent_config = self._create_cloudwatch_agent_config()
        
        # Create monitoring dashboard
        self.dashboard = self._create_monitoring_dashboard()
        
        # Create CloudWatch alarms
        self.alarms = self._create_cloudwatch_alarms()
        
        # Create Systems Manager associations
        self.associations = self._create_ssm_associations()
        
        # Create log groups for centralized logging
        self.log_groups = self._create_log_groups()
        
        # Output important resource information
        self._create_outputs()

    def _create_ssm_service_role(self) -> iam.Role:
        """
        Create IAM service role for Systems Manager operations
        
        Returns:
            iam.Role: The created IAM role with necessary permissions
        """
        role = iam.Role(
            self, "SSMServiceRole",
            role_name=f"SSMServiceRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("ssm.amazonaws.com"),
            description="Service role for Systems Manager operations and monitoring",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
            ]
        )
        
        # Add custom policy for enhanced monitoring capabilities
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "cloudwatch:PutMetricData",
                "cloudwatch:GetMetricStatistics",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "ssm:UpdateInstanceInformation"
            ],
            resources=["*"]
        ))
        
        cdk.Tags.of(role).add("Purpose", "Infrastructure Monitoring")
        cdk.Tags.of(role).add("Component", "Systems Manager")
        
        return role

    def _create_cloudwatch_agent_config(self) -> ssm.StringParameter:
        """
        Create CloudWatch Agent configuration in Parameter Store
        
        Returns:
            ssm.StringParameter: The parameter containing agent configuration
        """
        # CloudWatch Agent configuration for comprehensive metrics collection
        agent_config = {
            "metrics": {
                "namespace": "CWAgent",
                "metrics_collected": {
                    "cpu": {
                        "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                        "metrics_collection_interval": 60,
                        "totalcpu": False
                    },
                    "disk": {
                        "measurement": ["used_percent", "inodes_free"],
                        "metrics_collection_interval": 60,
                        "resources": ["*"]
                    },
                    "diskio": {
                        "measurement": ["io_time", "read_bytes", "write_bytes", "reads", "writes"],
                        "metrics_collection_interval": 60,
                        "resources": ["*"]
                    },
                    "mem": {
                        "measurement": ["mem_used_percent", "mem_available_percent"],
                        "metrics_collection_interval": 60
                    },
                    "netstat": {
                        "measurement": ["tcp_established", "tcp_time_wait"],
                        "metrics_collection_interval": 60
                    },
                    "swap": {
                        "measurement": ["swap_used_percent"],
                        "metrics_collection_interval": 60
                    }
                }
            },
            "logs": {
                "logs_collected": {
                    "files": {
                        "collect_list": [
                            {
                                "file_path": "/var/log/messages",
                                "log_group_name": f"/aws/ec2/system-logs-{self.unique_suffix}",
                                "log_stream_name": "{instance_id}/messages"
                            }
                        ]
                    }
                }
            }
        }
        
        parameter = ssm.StringParameter(
            self, "CloudWatchAgentConfig",
            parameter_name=f"AmazonCloudWatch-Agent-Config-{self.unique_suffix}",
            description="CloudWatch Agent configuration for infrastructure monitoring",
            string_value=json.dumps(agent_config, indent=2),
            tier=ssm.ParameterTier.STANDARD
        )
        
        cdk.Tags.of(parameter).add("Purpose", "Infrastructure Monitoring")
        cdk.Tags.of(parameter).add("Component", "CloudWatch Agent")
        
        return parameter

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create comprehensive infrastructure monitoring dashboard
        
        Returns:
            cloudwatch.Dashboard: The created dashboard with monitoring widgets
        """
        dashboard = cloudwatch.Dashboard(
            self, "InfrastructureMonitoringDashboard",
            dashboard_name=f"Infrastructure-Monitoring-{self.unique_suffix}",
            period_override=cloudwatch.PeriodOverride.INHERIT
        )
        
        # EC2 Instance Performance Widget
        ec2_performance_widget = cloudwatch.GraphWidget(
            title="EC2 Instance Performance",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="CPUUtilization",
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkIn",
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkOut",
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ]
        )
        
        # Systems Manager Operations Widget
        ssm_operations_widget = cloudwatch.GraphWidget(
            title="Systems Manager Operations",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/SSM-RunCommand",
                    metric_name="CommandsSucceeded",
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/SSM-RunCommand",
                    metric_name="CommandsFailed",
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ]
        )
        
        # CloudWatch Agent Metrics Widget
        cw_agent_widget = cloudwatch.GraphWidget(
            title="Advanced System Metrics (CloudWatch Agent)",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="CWAgent",
                    metric_name="mem_used_percent",
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="CWAgent",
                    metric_name="used_percent",
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ]
        )
        
        # Compliance Status Widget
        compliance_widget = cloudwatch.SingleValueWidget(
            title="Compliance Status",
            width=12,
            height=6,
            metrics=[
                cloudwatch.Metric(
                    namespace="AWS/SSM",
                    metric_name="ComplianceByConfigRule",
                    statistic="Sum",
                    period=Duration.hours(1)
                )
            ]
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(
            ec2_performance_widget,
            ssm_operations_widget
        )
        dashboard.add_widgets(
            cw_agent_widget,
            compliance_widget
        )
        
        cdk.Tags.of(dashboard).add("Purpose", "Infrastructure Monitoring")
        cdk.Tags.of(dashboard).add("Component", "CloudWatch Dashboard")
        
        return dashboard

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for proactive monitoring
        
        Returns:
            Dict[str, cloudwatch.Alarm]: Dictionary of created alarms
        """
        alarms = {}
        
        # High CPU Utilization Alarm
        alarms["high_cpu"] = cloudwatch.Alarm(
            self, "HighCPUUtilizationAlarm",
            alarm_name=f"High-CPU-Utilization-{self.unique_suffix}",
            alarm_description="Alert when CPU exceeds 80% for 2 consecutive periods",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # High Disk Usage Alarm (requires CloudWatch Agent)
        alarms["high_disk"] = cloudwatch.Alarm(
            self, "HighDiskUsageAlarm",
            alarm_name=f"High-Disk-Usage-{self.unique_suffix}",
            alarm_description="Alert when disk usage exceeds 85%",
            metric=cloudwatch.Metric(
                namespace="CWAgent",
                metric_name="used_percent",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=85,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # High Memory Usage Alarm
        alarms["high_memory"] = cloudwatch.Alarm(
            self, "HighMemoryUsageAlarm",
            alarm_name=f"High-Memory-Usage-{self.unique_suffix}",
            alarm_description="Alert when memory usage exceeds 90%",
            metric=cloudwatch.Metric(
                namespace="CWAgent",
                metric_name="mem_used_percent",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=90,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Systems Manager Command Failure Alarm
        alarms["ssm_failures"] = cloudwatch.Alarm(
            self, "SSMCommandFailureAlarm",
            alarm_name=f"SSM-Command-Failures-{self.unique_suffix}",
            alarm_description="Alert when Systems Manager commands fail",
            metric=cloudwatch.Metric(
                namespace="AWS/SSM-RunCommand",
                metric_name="CommandsFailed",
                statistic="Sum",
                period=Duration.minutes(15)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add tags to all alarms
        for alarm_name, alarm in alarms.items():
            cdk.Tags.of(alarm).add("Purpose", "Infrastructure Monitoring")
            cdk.Tags.of(alarm).add("Component", "CloudWatch Alarm")
            cdk.Tags.of(alarm).add("AlarmType", alarm_name)
        
        return alarms

    def _create_ssm_associations(self) -> Dict[str, ssm.CfnAssociation]:
        """
        Create Systems Manager associations for compliance and patch management
        
        Returns:
            Dict[str, ssm.CfnAssociation]: Dictionary of created associations
        """
        associations = {}
        
        # Daily Inventory Collection Association
        associations["inventory"] = ssm.CfnAssociation(
            self, "DailyInventoryCollection",
            name="AWS-GatherSoftwareInventory",
            association_name=f"Daily-Inventory-Collection-{self.unique_suffix}",
            schedule_expression="rate(1 day)",
            targets=[{
                "key": "tag:Environment",
                "values": ["*"]
            }],
            parameters={
                "applications": ["Enabled"],
                "awsComponents": ["Enabled"],
                "customInventory": ["Enabled"],
                "instanceDetailedInformation": ["Enabled"],
                "networkConfig": ["Enabled"],
                "services": ["Enabled"],
                "windowsRegistry": ["Enabled"],
                "windowsRoles": ["Enabled"],
                "files": [""]
            }
        )
        
        # Weekly Patch Scanning Association
        associations["patch_scan"] = ssm.CfnAssociation(
            self, "WeeklyPatchScanning",
            name="AWS-RunPatchBaseline",
            association_name=f"Weekly-Patch-Scanning-{self.unique_suffix}",
            schedule_expression="rate(7 days)",
            targets=[{
                "key": "tag:Environment",
                "values": ["*"]
            }],
            parameters={
                "Operation": ["Scan"]
            }
        )
        
        # CloudWatch Agent Installation Association
        associations["cw_agent"] = ssm.CfnAssociation(
            self, "CloudWatchAgentInstallation",
            name="AmazonCloudWatch-ManageAgent",
            association_name=f"CloudWatch-Agent-Installation-{self.unique_suffix}",
            schedule_expression="rate(30 days)",
            targets=[{
                "key": "tag:Environment",
                "values": ["*"]
            }],
            parameters={
                "action": ["configure"],
                "mode": ["ec2"],
                "optionalConfigurationSource": ["ssm"],
                "optionalConfigurationLocation": [self.agent_config.parameter_name],
                "optionalRestart": ["yes"]
            }
        )
        
        # Add tags to all associations
        for assoc_name, association in associations.items():
            cdk.Tags.of(association).add("Purpose", "Infrastructure Monitoring")
            cdk.Tags.of(association).add("Component", "Systems Manager Association")
            cdk.Tags.of(association).add("AssociationType", assoc_name)
        
        return associations

    def _create_log_groups(self) -> Dict[str, logs.LogGroup]:
        """
        Create CloudWatch log groups for centralized logging
        
        Returns:
            Dict[str, logs.LogGroup]: Dictionary of created log groups
        """
        log_groups = {}
        
        # Systems Manager Infrastructure Logs
        log_groups["infrastructure"] = logs.LogGroup(
            self, "InfrastructureLogGroup",
            log_group_name=f"/aws/systems-manager/infrastructure-{self.unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Application Logs
        log_groups["application"] = logs.LogGroup(
            self, "ApplicationLogGroup",
            log_group_name=f"/aws/ec2/application-logs-{self.unique_suffix}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # System Logs (for CloudWatch Agent)
        log_groups["system"] = logs.LogGroup(
            self, "SystemLogGroup",
            log_group_name=f"/aws/ec2/system-logs-{self.unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Systems Manager Run Command Logs
        log_groups["run_command"] = logs.LogGroup(
            self, "RunCommandLogGroup",
            log_group_name=f"/aws/ssm/run-command-{self.unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Add tags to all log groups
        for lg_name, log_group in log_groups.items():
            cdk.Tags.of(log_group).add("Purpose", "Infrastructure Monitoring")
            cdk.Tags.of(log_group).add("Component", "CloudWatch Logs")
            cdk.Tags.of(log_group).add("LogType", lg_name)
        
        return log_groups

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        # IAM Role ARN
        cdk.CfnOutput(
            self, "SSMServiceRoleArn",
            value=self.ssm_service_role.role_arn,
            description="ARN of the Systems Manager service role",
            export_name=f"SSMServiceRole-{self.unique_suffix}"
        )
        
        # CloudWatch Agent Configuration Parameter
        cdk.CfnOutput(
            self, "CloudWatchAgentConfigParameter",
            value=self.agent_config.parameter_name,
            description="Parameter Store name for CloudWatch Agent configuration",
            export_name=f"CWAgentConfig-{self.unique_suffix}"
        )
        
        # Dashboard URL
        cdk.CfnOutput(
            self, "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to access the infrastructure monitoring dashboard"
        )
        
        # Log Groups
        for lg_name, log_group in self.log_groups.items():
            cdk.CfnOutput(
                self, f"LogGroup{lg_name.title()}",
                value=log_group.log_group_name,
                description=f"CloudWatch Log Group for {lg_name} logs"
            )
        
        # Alarm Names
        for alarm_name, alarm in self.alarms.items():
            cdk.CfnOutput(
                self, f"Alarm{alarm_name.title().replace('_', '')}",
                value=alarm.alarm_name,
                description=f"CloudWatch Alarm for {alarm_name.replace('_', ' ')} monitoring"
            )


# CDK App Configuration
app = cdk.App()

# Get configuration from context or use defaults
config = {
    "unique_suffix": app.node.try_get_context("unique_suffix") or "infra-mon",
    "environment": app.node.try_get_context("environment") or "development"
}

# Create the infrastructure monitoring stack
InfrastructureMonitoringStack(
    app, 
    "InfrastructureMonitoringStack",
    stack_name=f"infrastructure-monitoring-{config['unique_suffix']}",
    description="Infrastructure Monitoring Quick Setup with Systems Manager and CloudWatch",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    ),
    tags={
        "Purpose": "Infrastructure Monitoring",
        "Environment": config["environment"],
        "ManagedBy": "CDK",
        "Recipe": "infrastructure-monitoring-quick-setup"
    }
)

app.synth()