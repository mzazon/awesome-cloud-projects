#!/usr/bin/env python3
"""
AWS CDK application for Database Monitoring Dashboards with CloudWatch.

This application creates comprehensive database monitoring infrastructure including:
- RDS MySQL instance with enhanced monitoring
- CloudWatch dashboard with database performance metrics
- CloudWatch alarms for critical thresholds
- SNS topic for alert notifications
- IAM role for enhanced monitoring

Author: AWS CDK Python Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Tags,
    Duration,
    RemovalPolicy,
)
from aws_cdk import aws_rds as rds
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_sns as sns
from aws_cdk import aws_sns_subscriptions as subscriptions
from aws_cdk import aws_iam as iam
from aws_cdk import aws_ec2 as ec2
from constructs import Construct
import random
import string


class DatabaseMonitoringDashboardStack(Stack):
    """
    CDK Stack for Database Monitoring Dashboards with CloudWatch.
    
    This stack creates a complete database monitoring solution including:
    - RDS MySQL instance with Performance Insights
    - Enhanced monitoring with detailed OS metrics
    - CloudWatch dashboard for visualization
    - CloudWatch alarms for proactive alerting
    - SNS notifications for critical events
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate random suffix for unique resource names
        random_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

        # Parameters for customization
        db_instance_class = self.node.try_get_context("db_instance_class") or "db.t3.micro"
        alert_email = self.node.try_get_context("alert_email") or "admin@example.com"
        monitoring_interval = int(self.node.try_get_context("monitoring_interval") or "60")
        
        # Get default VPC (or create one if needed)
        vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)
        
        # Create security group for RDS instance
        db_security_group = ec2.SecurityGroup(
            self, "DatabaseSecurityGroup",
            vpc=vpc,
            description="Security group for RDS database instance",
            allow_all_outbound=False
        )
        
        # Add inbound rule for MySQL (for demonstration - restrict in production)
        db_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="MySQL access from VPC"
        )

        # Create IAM role for enhanced monitoring
        monitoring_role = iam.Role(
            self, "RDSMonitoringRole",
            role_name=f"rds-monitoring-role-{random_suffix}",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
            description="IAM role for RDS enhanced monitoring"
        )

        # Create RDS subnet group
        db_subnet_group = rds.SubnetGroup(
            self, "DatabaseSubnetGroup",
            description="Subnet group for RDS database instance",
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create RDS MySQL instance with monitoring enabled
        database = rds.DatabaseInstance(
            self, "MonitoringDemoDatabase",
            instance_identifier=f"monitoring-demo-{random_suffix}",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            instance_type=ec2.InstanceType(db_instance_class),
            vpc=vpc,
            subnet_group=db_subnet_group,
            security_groups=[db_security_group],
            allocated_storage=20,
            storage_encrypted=True,
            multi_az=False,
            credentials=rds.Credentials.from_generated_secret(
                username="admin",
                secret_name=f"rds-credentials-{random_suffix}"
            ),
            backup_retention=Duration.days(7),
            deletion_protection=False,
            delete_automated_backups=True,
            monitoring_interval=Duration.seconds(monitoring_interval),
            monitoring_role=monitoring_role,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            removal_policy=RemovalPolicy.DESTROY,
            parameter_group=rds.ParameterGroup.from_parameter_group_name(
                self, "ParameterGroup", "default.mysql8.0"
            )
        )

        # Create SNS topic for database alerts
        alert_topic = sns.Topic(
            self, "DatabaseAlertTopic",
            topic_name=f"database-alerts-{random_suffix}",
            display_name="Database Monitoring Alerts",
            description="SNS topic for database monitoring alerts"
        )

        # Subscribe email to SNS topic
        alert_topic.add_subscription(
            subscriptions.EmailSubscription(alert_email)
        )

        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self, "DatabaseMonitoringDashboard",
            dashboard_name=f"DatabaseMonitoring-{random_suffix}",
            period_override=cloudwatch.PeriodOverride.INHERIT,
            start="-PT3H",  # Show last 3 hours by default
            widgets=[
                [
                    # Database Performance Overview
                    cloudwatch.GraphWidget(
                        title="Database Performance Overview",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="CPUUtilization",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="CPU Utilization (%)"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="DatabaseConnections",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Database Connections"
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="FreeableMemory",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Freeable Memory (Bytes)"
                            )
                        ],
                        width=12,
                        height=6,
                        legend_position=cloudwatch.LegendPosition.BOTTOM
                    ),
                    
                    # Storage and Latency Metrics
                    cloudwatch.GraphWidget(
                        title="Storage and Latency Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="FreeStorageSpace",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Free Storage Space (Bytes)"
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="ReadLatency",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Read Latency (ms)"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="WriteLatency",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Write Latency (ms)"
                            )
                        ],
                        width=12,
                        height=6,
                        legend_position=cloudwatch.LegendPosition.BOTTOM
                    )
                ],
                [
                    # I/O Performance Metrics
                    cloudwatch.GraphWidget(
                        title="I/O Performance Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="ReadIOPS",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Read IOPS"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="WriteIOPS",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Write IOPS"
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="ReadThroughput",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Read Throughput (Bytes/sec)"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/RDS",
                                metric_name="WriteThroughput",
                                dimensions_map={
                                    "DBInstanceIdentifier": database.instance_identifier
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Write Throughput (Bytes/sec)"
                            )
                        ],
                        width=24,
                        height=6,
                        legend_position=cloudwatch.LegendPosition.BOTTOM
                    )
                ]
            ]
        )

        # Create CloudWatch alarms for critical metrics
        
        # CPU Utilization Alarm
        cpu_alarm = cloudwatch.Alarm(
            self, "DatabaseHighCPUAlarm",
            alarm_name=f"{database.instance_identifier}-HighCPU",
            alarm_description=f"High CPU utilization on {database.instance_identifier}",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="CPUUtilization",
                dimensions_map={
                    "DBInstanceIdentifier": database.instance_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        cpu_alarm.add_alarm_action(cloudwatch.SnsAction(alert_topic))

        # Database Connections Alarm
        connections_alarm = cloudwatch.Alarm(
            self, "DatabaseHighConnectionsAlarm",
            alarm_name=f"{database.instance_identifier}-HighConnections",
            alarm_description=f"High database connections on {database.instance_identifier}",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="DatabaseConnections",
                dimensions_map={
                    "DBInstanceIdentifier": database.instance_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=50,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        connections_alarm.add_alarm_action(cloudwatch.SnsAction(alert_topic))

        # Free Storage Space Alarm (2GB threshold)
        storage_alarm = cloudwatch.Alarm(
            self, "DatabaseLowStorageAlarm",
            alarm_name=f"{database.instance_identifier}-LowStorage",
            alarm_description=f"Low free storage space on {database.instance_identifier}",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="FreeStorageSpace",
                dimensions_map={
                    "DBInstanceIdentifier": database.instance_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=2147483648,  # 2GB in bytes
            evaluation_periods=1,
            datapoints_to_alarm=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        storage_alarm.add_alarm_action(cloudwatch.SnsAction(alert_topic))

        # High Read Latency Alarm
        read_latency_alarm = cloudwatch.Alarm(
            self, "DatabaseHighReadLatencyAlarm",
            alarm_name=f"{database.instance_identifier}-HighReadLatency",
            alarm_description=f"High read latency on {database.instance_identifier}",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="ReadLatency",
                dimensions_map={
                    "DBInstanceIdentifier": database.instance_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=0.2,  # 200ms
            evaluation_periods=3,
            datapoints_to_alarm=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        read_latency_alarm.add_alarm_action(cloudwatch.SnsAction(alert_topic))

        # Apply tags to all resources
        Tags.of(self).add("Project", "DatabaseMonitoring")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("GeneratedBy", "CDK-Python")

        # CloudFormation outputs
        CfnOutput(
            self, "DatabaseInstanceIdentifier",
            value=database.instance_identifier,
            description="RDS Database Instance Identifier"
        )

        CfnOutput(
            self, "DatabaseEndpoint",
            value=database.instance_endpoint.hostname,
            description="RDS Database Instance Endpoint"
        )

        CfnOutput(
            self, "DatabasePort",
            value=str(database.instance_endpoint.port),
            description="RDS Database Instance Port"
        )

        CfnOutput(
            self, "DatabaseSecretArn",
            value=database.secret.secret_arn if database.secret else "N/A",
            description="ARN of the secret containing database credentials"
        )

        CfnOutput(
            self, "SNSTopicArn",
            value=alert_topic.topic_arn,
            description="SNS Topic ARN for database alerts"
        )

        CfnOutput(
            self, "CloudWatchDashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL"
        )

        CfnOutput(
            self, "MonitoringRoleArn",
            value=monitoring_role.role_arn,
            description="IAM Role ARN for enhanced monitoring"
        )


# CDK Application
app = cdk.App()

# Get environment configuration
env = Environment(
    account=app.node.try_get_context("account") or None,
    region=app.node.try_get_context("region") or None
)

# Create the stack
DatabaseMonitoringDashboardStack(
    app, 
    "DatabaseMonitoringDashboardStack",
    env=env,
    description="Database Monitoring Dashboards with CloudWatch - Complete monitoring solution for RDS instances"
)

app.synth()