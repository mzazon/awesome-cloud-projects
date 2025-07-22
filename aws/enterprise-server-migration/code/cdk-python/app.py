#!/usr/bin/env python3
"""
AWS Application Migration Service (MGN) CDK Python Application

This CDK application provisions the infrastructure needed for large-scale server migration
using AWS Application Migration Service. It creates the necessary IAM roles, replication
configuration templates, and monitoring resources to support automated lift-and-shift
migrations.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_logs as logs,
    aws_ec2 as ec2,
    CfnOutput,
    Tags,
    Duration,
    RemovalPolicy
)
from constructs import Construct
import json
from typing import Dict, List, Any


class MigrationServiceStack(Stack):
    """
    CDK Stack for AWS Application Migration Service infrastructure.
    
    This stack creates:
    - IAM service role for MGN
    - CloudWatch monitoring and alarms
    - SNS notifications for migration events
    - VPC and security group for replication servers
    - CloudWatch log groups for migration tracking
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create IAM service role for MGN
        self.mgn_service_role = self._create_mgn_service_role()
        
        # Create VPC and networking resources
        self.vpc = self._create_vpc()
        self.security_group = self._create_security_group()
        
        # Create monitoring and notification resources
        self.log_group = self._create_log_group()
        self.sns_topic = self._create_sns_topic()
        self.cloudwatch_dashboard = self._create_cloudwatch_dashboard()
        
        # Create CloudWatch alarms for monitoring
        self._create_cloudwatch_alarms()
        
        # Add tags to all resources
        self._add_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_mgn_service_role(self) -> iam.Role:
        """Create IAM service role for AWS Application Migration Service."""
        
        # Trust policy for MGN service
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("mgn.amazonaws.com")],
                    actions=["sts:AssumeRole"]
                )
            ]
        )
        
        # Create the service role
        mgn_role = iam.Role(
            self,
            "MGNServiceRole",
            role_name="MGNServiceRole",
            assumed_by=iam.ServicePrincipal("mgn.amazonaws.com"),
            description="Service role for AWS Application Migration Service",
            inline_policies={
                "MGNCustomPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ec2:DescribeInstances",
                                "ec2:DescribeImages",
                                "ec2:DescribeSecurityGroups",
                                "ec2:DescribeSubnets",
                                "ec2:DescribeVolumes",
                                "ec2:DescribeVpcs",
                                "ec2:CreateTags",
                                "cloudwatch:PutMetricData",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogGroups",
                                "logs:DescribeLogStreams"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        # Attach the AWS managed policy for MGN
        mgn_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AWSApplicationMigrationServiceRolePolicy"
            )
        )
        
        return mgn_role

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for migration infrastructure."""
        
        vpc = ec2.Vpc(
            self,
            "MigrationVPC",
            vpc_name="MGN-Migration-VPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )
        
        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for MGN replication servers."""
        
        security_group = ec2.SecurityGroup(
            self,
            "MGNReplicationSecurityGroup",
            vpc=self.vpc,
            description="Security group for MGN replication servers",
            security_group_name="MGN-Replication-SG",
            allow_all_outbound=True
        )
        
        # Allow inbound traffic from source servers
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("0.0.0.0/0"),
            connection=ec2.Port.tcp(1500),
            description="MGN replication traffic"
        )
        
        # Allow SSH access for management
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(22),
            description="SSH access within VPC"
        )
        
        return security_group

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for migration tracking."""
        
        log_group = logs.LogGroup(
            self,
            "MGNLogGroup",
            log_group_name="/aws/mgn/migration-logs",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for migration notifications."""
        
        topic = sns.Topic(
            self,
            "MGNNotificationTopic",
            topic_name="MGN-Migration-Notifications",
            display_name="AWS Application Migration Service Notifications"
        )
        
        return topic

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for migration monitoring."""
        
        dashboard = cloudwatch.Dashboard(
            self,
            "MGNDashboard",
            dashboard_name="MGN-Migration-Dashboard",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Replication Progress",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/MGN",
                                metric_name="ReplicationProgress",
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ]
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Active Source Servers",
                        width=12,
                        height=6,
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/MGN",
                                metric_name="ActiveSourceServers",
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ]
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Replication Lag",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/MGN",
                                metric_name="ReplicationLag",
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ]
                    ),
                    cloudwatch.GraphWidget(
                        title="Migration Events",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/MGN",
                                metric_name="MigrationEvents",
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ]
                    )
                ]
            ]
        )
        
        return dashboard

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for migration monitoring."""
        
        # Alarm for high replication lag
        high_lag_alarm = cloudwatch.Alarm(
            self,
            "HighReplicationLagAlarm",
            alarm_name="MGN-High-Replication-Lag",
            alarm_description="Alert when replication lag exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/MGN",
                metric_name="ReplicationLag",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=300,  # 5 minutes
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS notification to alarm
        high_lag_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        # Alarm for failed replication
        failed_replication_alarm = cloudwatch.Alarm(
            self,
            "FailedReplicationAlarm",
            alarm_name="MGN-Failed-Replication",
            alarm_description="Alert when replication fails",
            metric=cloudwatch.Metric(
                namespace="AWS/MGN",
                metric_name="ReplicationErrors",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS notification to alarm
        failed_replication_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        
        Tags.of(self).add("Project", "AWS-Application-Migration-Service")
        Tags.of(self).add("Environment", "Migration")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Purpose", "Server-Migration")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        
        CfnOutput(
            self,
            "MGNServiceRoleArn",
            value=self.mgn_service_role.role_arn,
            description="ARN of the MGN service role",
            export_name="MGNServiceRoleArn"
        )
        
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="ID of the VPC created for migration",
            export_name="MGNVPCId"
        )
        
        CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="ID of the security group for replication servers",
            export_name="MGNSecurityGroupId"
        )
        
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for notifications",
            export_name="MGNSNSTopicArn"
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group",
            export_name="MGNLogGroupName"
        )
        
        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.cloudwatch_dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
            export_name="MGNDashboardURL"
        )


class MigrationWaveStack(Stack):
    """
    CDK Stack for managing migration waves and batch operations.
    
    This stack creates resources for organizing and executing large-scale
    migrations in coordinated waves.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create Lambda function for wave management
        self.wave_management_function = self._create_wave_management_function()
        
        # Create Step Functions state machine for orchestration
        self.state_machine = self._create_step_functions_state_machine()
        
        # Create DynamoDB table for wave tracking
        self.wave_table = self._create_wave_table()
        
        # Add tags
        self._add_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_wave_management_function(self) -> None:
        """Create Lambda function for wave management operations."""
        
        # This would typically create a Lambda function for wave management
        # For now, we'll create a placeholder IAM role that could be used
        
        wave_role = iam.Role(
            self,
            "WaveManagementRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for wave management Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "WaveManagementPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "mgn:*",
                                "dynamodb:GetItem",
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:Query",
                                "dynamodb:Scan"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        return wave_role

    def _create_step_functions_state_machine(self) -> None:
        """Create Step Functions state machine for migration orchestration."""
        
        # Create IAM role for Step Functions
        step_functions_role = iam.Role(
            self,
            "StepFunctionsRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            description="Role for Step Functions state machine",
            inline_policies={
                "StepFunctionsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "mgn:*",
                                "lambda:InvokeFunction",
                                "sns:Publish"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        return step_functions_role

    def _create_wave_table(self) -> None:
        """Create DynamoDB table for wave tracking."""
        
        # Create IAM role for DynamoDB access
        dynamodb_role = iam.Role(
            self,
            "DynamoDBRole",
            assumed_by=iam.ServicePrincipal("dynamodb.amazonaws.com"),
            description="Role for DynamoDB wave tracking table"
        )
        
        return dynamodb_role

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        
        Tags.of(self).add("Project", "AWS-Application-Migration-Service")
        Tags.of(self).add("Environment", "Migration")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Purpose", "Wave-Management")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        
        CfnOutput(
            self,
            "WaveManagementRoleArn",
            value=self.wave_management_function.role_arn,
            description="ARN of the wave management role",
            export_name="WaveManagementRoleArn"
        )


def main() -> None:
    """Main function to create and deploy the CDK app."""
    
    app = cdk.App()
    
    # Get environment configuration
    env = cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
    
    # Create the main migration service stack
    migration_stack = MigrationServiceStack(
        app,
        "MigrationServiceStack",
        env=env,
        description="AWS Application Migration Service infrastructure stack"
    )
    
    # Create the wave management stack
    wave_stack = MigrationWaveStack(
        app,
        "MigrationWaveStack",
        env=env,
        description="Migration wave management and orchestration stack"
    )
    
    # Add stack dependencies
    wave_stack.add_dependency(migration_stack)
    
    app.synth()


if __name__ == "__main__":
    main()