#!/usr/bin/env python3
"""
CDK Python Application for Analytics Workload Isolation with Redshift Workload Management

This application creates a complete infrastructure stack for implementing workload isolation
in Amazon Redshift using Workload Management (WLM) configuration, monitoring, and alerting.

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    aws_redshift as redshift,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    aws_s3 as s3,
    RemovalPolicy,
    CfnOutput,
    Duration,
)
from constructs import Construct
import json
from typing import Dict, List, Any


class RedshiftWlmStack(Stack):
    """
    CDK Stack for Analytics Workload Isolation with Redshift WLM
    
    This stack creates:
    - Redshift cluster with custom parameter group
    - WLM configuration for workload isolation
    - CloudWatch monitoring and alarms
    - SNS topic for notifications
    - IAM roles and security groups
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create SNS topic for WLM alerts
        self.sns_topic = self._create_sns_topic()
        
        # Create IAM role for Redshift
        self.redshift_role = self._create_redshift_role()
        
        # Create S3 bucket for Redshift logs and data
        self.s3_bucket = self._create_s3_bucket()
        
        # Create VPC security group for Redshift
        self.security_group = self._create_security_group()
        
        # Create subnet group for Redshift
        self.subnet_group = self._create_subnet_group()
        
        # Create custom parameter group with WLM configuration
        self.parameter_group = self._create_parameter_group_with_wlm()
        
        # Create Redshift cluster
        self.redshift_cluster = self._create_redshift_cluster()
        
        # Create CloudWatch alarms for monitoring
        self._create_cloudwatch_alarms()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()
        
        # Output important values
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for WLM alerts and notifications."""
        topic = sns.Topic(
            self,
            "RedshiftWlmAlertsTopic",
            topic_name=f"redshift-wlm-alerts-{self.stack_name.lower()}",
            display_name="Redshift WLM Performance Alerts",
            description="SNS topic for Redshift Workload Management alerts and notifications"
        )
        
        return topic

    def _create_redshift_role(self) -> iam.Role:
        """Create IAM role for Redshift cluster with necessary permissions."""
        role = iam.Role(
            self,
            "RedshiftClusterRole",
            assumed_by=iam.ServicePrincipal("redshift.amazonaws.com"),
            description="IAM role for Redshift cluster with S3 and monitoring permissions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3ReadOnlyAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchLogsFullAccess")
            ]
        )
        
        # Add custom policy for enhanced monitoring
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "cloudwatch:GetMetricStatistics",
                    "cloudwatch:ListMetrics",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]
            )
        )
        
        return role

    def _create_s3_bucket(self) -> s3.Bucket:
        """Create S3 bucket for Redshift audit logs and data storage."""
        bucket = s3.Bucket(
            self,
            "RedshiftLogsBucket",
            bucket_name=f"redshift-wlm-logs-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(90)
                )
            ]
        )
        
        return bucket

    def _create_security_group(self) -> None:
        """Create security group for Redshift cluster (placeholder - requires VPC)."""
        # Note: In a real deployment, you would create a VPC and security group
        # For this example, we'll use the default VPC
        pass

    def _create_subnet_group(self) -> None:
        """Create subnet group for Redshift cluster (placeholder - requires VPC)."""
        # Note: In a real deployment, you would create subnets and subnet group
        # For this example, we'll use the default subnet group
        pass

    def _get_wlm_configuration(self) -> str:
        """
        Create WLM configuration JSON for workload isolation.
        
        Returns:
            str: JSON string containing WLM configuration with 4 queues
        """
        wlm_config = [
            {
                "user_group": "bi-dashboard-group",
                "query_group": "dashboard",
                "query_concurrency": 15,
                "memory_percent_to_use": 25,
                "max_execution_time": 120000,
                "query_group_wild_card": 0,
                "rules": [
                    {
                        "rule_name": "dashboard_timeout_rule",
                        "predicate": "query_execution_time > 120",
                        "action": "abort"
                    },
                    {
                        "rule_name": "dashboard_cpu_rule",
                        "predicate": "query_cpu_time > 30",
                        "action": "log"
                    }
                ]
            },
            {
                "user_group": "data-science-group",
                "query_group": "analytics",
                "query_concurrency": 3,
                "memory_percent_to_use": 40,
                "max_execution_time": 7200000,
                "query_group_wild_card": 0,
                "rules": [
                    {
                        "rule_name": "analytics_memory_rule",
                        "predicate": "query_temp_blocks_to_disk > 100000",
                        "action": "log"
                    },
                    {
                        "rule_name": "analytics_nested_loop_rule",
                        "predicate": "nested_loop_join_row_count > 1000000",
                        "action": "hop"
                    }
                ]
            },
            {
                "user_group": "etl-process-group",
                "query_group": "etl",
                "query_concurrency": 5,
                "memory_percent_to_use": 25,
                "max_execution_time": 3600000,
                "query_group_wild_card": 0,
                "rules": [
                    {
                        "rule_name": "etl_timeout_rule",
                        "predicate": "query_execution_time > 3600",
                        "action": "abort"
                    },
                    {
                        "rule_name": "etl_scan_rule",
                        "predicate": "scan_row_count > 1000000000",
                        "action": "log"
                    }
                ]
            },
            {
                "query_concurrency": 2,
                "memory_percent_to_use": 10,
                "max_execution_time": 1800000,
                "query_group_wild_card": 1,
                "rules": [
                    {
                        "rule_name": "default_timeout_rule",
                        "predicate": "query_execution_time > 1800",
                        "action": "abort"
                    }
                ]
            }
        ]
        
        return json.dumps(wlm_config, separators=(',', ':'))

    def _create_parameter_group_with_wlm(self) -> redshift.CfnClusterParameterGroup:
        """Create Redshift parameter group with WLM configuration."""
        parameter_group = redshift.CfnClusterParameterGroup(
            self,
            "RedshiftWlmParameterGroup",
            description="Analytics workload isolation parameter group with WLM configuration",
            parameter_group_family="redshift-1.0",
            parameter_group_name=f"analytics-wlm-pg-{self.stack_name.lower()}",
            parameters=[
                {
                    "parameterName": "wlm_json_configuration",
                    "parameterValue": self._get_wlm_configuration()
                },
                {
                    "parameterName": "enable_user_activity_logging",
                    "parameterValue": "true"
                },
                {
                    "parameterName": "log_statement",
                    "parameterValue": "all"
                },
                {
                    "parameterName": "log_min_duration_statement",
                    "parameterValue": "5000"
                }
            ]
        )
        
        return parameter_group

    def _create_redshift_cluster(self) -> redshift.CfnCluster:
        """Create Redshift cluster with custom parameter group and WLM configuration."""
        cluster = redshift.CfnCluster(
            self,
            "RedshiftAnalyticsCluster",
            cluster_type="multi-node",
            node_type="ra3.xlplus",
            number_of_nodes=2,
            cluster_identifier=f"analytics-wlm-cluster-{self.stack_name.lower()}",
            master_username="admin",
            master_user_password="TempPassword123!",  # Change this in production
            db_name="analytics",
            cluster_parameter_group_name=self.parameter_group.ref,
            iam_roles=[self.redshift_role.role_arn],
            logging_properties={
                "bucketName": self.s3_bucket.bucket_name,
                "s3KeyPrefix": "redshift-logs/"
            },
            enhanced_vpc_routing=True,
            encrypted=True,
            port=5439,
            preferred_maintenance_window="Sun:03:00-Sun:04:00",
            allow_version_upgrade=True,
            automated_snapshot_retention_period=7,
            publicly_accessible=False
        )
        
        # Add dependency on parameter group
        cluster.add_dependency(self.parameter_group)
        
        return cluster

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring WLM performance."""
        # High queue wait time alarm
        cloudwatch.Alarm(
            self,
            "HighQueueWaitTimeAlarm",
            alarm_name=f"RedshiftWLM-HighQueueWaitTime-{self.stack_name}",
            alarm_description="Alert when WLM queue wait time is high",
            metric=cloudwatch.Metric(
                namespace="AWS/Redshift",
                metric_name="QueueLength",
                dimensions_map={
                    "ClusterIdentifier": self.redshift_cluster.cluster_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        ).add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        # High CPU utilization alarm
        cloudwatch.Alarm(
            self,
            "HighCPUUtilizationAlarm",
            alarm_name=f"RedshiftWLM-HighCPUUtilization-{self.stack_name}",
            alarm_description="Alert when cluster CPU utilization is high",
            metric=cloudwatch.Metric(
                namespace="AWS/Redshift",
                metric_name="CPUUtilization",
                dimensions_map={
                    "ClusterIdentifier": self.redshift_cluster.cluster_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=85,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3
        ).add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        # Low query completion rate alarm
        cloudwatch.Alarm(
            self,
            "LowQueryCompletionRateAlarm",
            alarm_name=f"RedshiftWLM-LowQueryCompletionRate-{self.stack_name}",
            alarm_description="Alert when query completion rate is low",
            metric=cloudwatch.Metric(
                namespace="AWS/Redshift",
                metric_name="QueriesCompletedPerSecond",
                dimensions_map={
                    "ClusterIdentifier": self.redshift_cluster.cluster_identifier
                },
                statistic="Sum",
                period=Duration.minutes(15)
            ),
            threshold=10,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2
        ).add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for WLM monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "RedshiftWlmDashboard",
            dashboard_name=f"RedshiftWLM-{self.stack_name}",
            period_override=cloudwatch.PeriodOverride.AUTO
        )
        
        # Add widgets for key metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Redshift WLM Performance Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Redshift",
                        metric_name="QueueLength",
                        dimensions_map={
                            "ClusterIdentifier": self.redshift_cluster.cluster_identifier
                        },
                        statistic="Average"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Redshift",
                        metric_name="QueriesCompletedPerSecond",
                        dimensions_map={
                            "ClusterIdentifier": self.redshift_cluster.cluster_identifier
                        },
                        statistic="Average"
                    )
                ],
                right=[
                    cloudwatch.Metric(
                        namespace="AWS/Redshift",
                        metric_name="CPUUtilization",
                        dimensions_map={
                            "ClusterIdentifier": self.redshift_cluster.cluster_identifier
                        },
                        statistic="Average"
                    )
                ],
                width=12,
                height=6
            )
        )
        
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Cluster Health and Connections",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Redshift",
                        metric_name="DatabaseConnections",
                        dimensions_map={
                            "ClusterIdentifier": self.redshift_cluster.cluster_identifier
                        },
                        statistic="Average"
                    )
                ],
                right=[
                    cloudwatch.Metric(
                        namespace="AWS/Redshift",
                        metric_name="HealthStatus",
                        dimensions_map={
                            "ClusterIdentifier": self.redshift_cluster.cluster_identifier
                        },
                        statistic="Average"
                    )
                ],
                width=12,
                height=6
            )
        )
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important values."""
        CfnOutput(
            self,
            "RedshiftClusterIdentifier",
            value=self.redshift_cluster.cluster_identifier,
            description="Redshift cluster identifier",
            export_name=f"{self.stack_name}-cluster-identifier"
        )
        
        CfnOutput(
            self,
            "RedshiftClusterEndpoint",
            value=self.redshift_cluster.attr_endpoint_address,
            description="Redshift cluster endpoint address",
            export_name=f"{self.stack_name}-cluster-endpoint"
        )
        
        CfnOutput(
            self,
            "ParameterGroupName",
            value=self.parameter_group.parameter_group_name,
            description="Custom parameter group name with WLM configuration",
            export_name=f"{self.stack_name}-parameter-group"
        )
        
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic ARN for WLM alerts",
            export_name=f"{self.stack_name}-sns-topic-arn"
        )
        
        CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="S3 bucket for Redshift logs",
            export_name=f"{self.stack_name}-s3-bucket"
        )
        
        CfnOutput(
            self,
            "IAMRoleArn",
            value=self.redshift_role.role_arn,
            description="IAM role ARN for Redshift cluster",
            export_name=f"{self.stack_name}-iam-role-arn"
        )


def main():
    """Main application entry point."""
    app = cdk.App()
    
    # Get context values
    stack_name = app.node.try_get_context("stackName") or "RedshiftWlmStack"
    environment = app.node.try_get_context("environment") or "dev"
    
    # Create the stack
    RedshiftWlmStack(
        app,
        f"{stack_name}-{environment}",
        description="Analytics Workload Isolation with Redshift Workload Management",
        env=Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region") or "us-east-1"
        ),
        tags={
            "Project": "AnalyticsWorkloadIsolation",
            "Environment": environment,
            "Component": "RedshiftWLM",
            "CostCenter": "Analytics",
            "Owner": "DataEngineering"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()