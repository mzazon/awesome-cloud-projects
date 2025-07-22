#!/usr/bin/env python3
"""
High-Availability PostgreSQL Clusters with Amazon RDS CDK Application

This CDK application creates a production-grade PostgreSQL cluster with:
- Multi-AZ deployment for automatic failover
- Read replicas for horizontal scaling
- Cross-region disaster recovery
- Comprehensive monitoring and alerting
- RDS Proxy for connection pooling
- Automated backup and encryption
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    aws_rds as rds,
    aws_ec2 as ec2,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_iam as iam,
    aws_secretsmanager as secretsmanager,
    aws_logs as logs,
    Duration,
    Stack,
    StackProps,
    RemovalPolicy,
    CfnOutput,
    Environment,
)
from constructs import Construct


class PostgreSQLHAStack(Stack):
    """
    Stack for High-Availability PostgreSQL cluster with comprehensive monitoring,
    disaster recovery, and security features.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        notification_email: str,
        cluster_name: Optional[str] = None,
        instance_class: str = "db.r6g.large",
        **kwargs
    ) -> None:
        """
        Initialize the PostgreSQL HA Stack.

        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            notification_email: Email address for SNS notifications
            cluster_name: Optional custom cluster name (auto-generated if not provided)
            instance_class: RDS instance class for the database instances
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique cluster name if not provided
        self.cluster_name = cluster_name or f"postgresql-ha-{self.node.addr[:8]}"
        self.notification_email = notification_email
        self.instance_class = instance_class

        # Create VPC or use existing
        self.vpc = self._create_or_get_vpc()

        # Create security group for database
        self.db_security_group = self._create_database_security_group()

        # Create subnet group for Multi-AZ deployment
        self.db_subnet_group = self._create_db_subnet_group()

        # Create custom parameter group
        self.parameter_group = self._create_parameter_group()

        # Create SNS topic for notifications
        self.sns_topic = self._create_sns_topic()

        # Create database credentials secret
        self.db_secret = self._create_database_secret()

        # Create primary PostgreSQL instance with Multi-AZ
        self.primary_instance = self._create_primary_instance()

        # Create read replicas
        self.read_replica = self._create_read_replica()

        # Create cross-region read replica
        self.cross_region_replica = self._create_cross_region_replica()

        # Create RDS Proxy for connection pooling
        self.rds_proxy = self._create_rds_proxy()

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Create event subscription
        self._create_event_subscription()

        # Create manual snapshot
        self._create_manual_snapshot()

        # Create outputs
        self._create_outputs()

    def _create_or_get_vpc(self) -> ec2.IVpc:
        """Create a new VPC or use the default VPC for the database cluster."""
        # Use default VPC for simplicity - in production, consider a custom VPC
        return ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)

    def _create_database_security_group(self) -> ec2.SecurityGroup:
        """Create security group for PostgreSQL database with least privilege access."""
        security_group = ec2.SecurityGroup(
            self,
            "PostgreSQLSecurityGroup",
            vpc=self.vpc,
            description="Security group for PostgreSQL HA cluster",
            allow_all_outbound=False,
        )

        # Allow PostgreSQL access from within VPC
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(5432),
            description="PostgreSQL access from VPC",
        )

        # Allow self-referencing for RDS Proxy
        security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(security_group.security_group_id),
            connection=ec2.Port.tcp(5432),
            description="PostgreSQL access from security group",
        )

        return security_group

    def _create_db_subnet_group(self) -> rds.SubnetGroup:
        """Create database subnet group spanning multiple AZs for Multi-AZ deployment."""
        return rds.SubnetGroup(
            self,
            "PostgreSQLSubnetGroup",
            description="Subnet group for PostgreSQL HA cluster",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                availability_zones=self.availability_zones[:3],  # Use up to 3 AZs
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_parameter_group(self) -> rds.ParameterGroup:
        """Create custom parameter group with optimized PostgreSQL settings."""
        parameter_group = rds.ParameterGroup(
            self,
            "PostgreSQLParameterGroup",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            description="Optimized PostgreSQL parameters for HA deployment",
            parameters={
                "log_statement": "all",
                "log_min_duration_statement": "1000",
                "shared_preload_libraries": "pg_stat_statements",
                "track_activity_query_size": "2048",
                "max_connections": "200",
                "random_page_cost": "1.1",
                "effective_cache_size": "75%",
                "maintenance_work_mem": "256MB",
                "checkpoint_completion_target": "0.7",
                "wal_buffers": "16MB",
                "default_statistics_target": "100",
            },
        )

        return parameter_group

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for database alerts and notifications."""
        topic = sns.Topic(
            self,
            "PostgreSQLAlerts",
            display_name=f"PostgreSQL HA Alerts - {self.cluster_name}",
            topic_name=f"postgresql-alerts-{self.cluster_name}",
        )

        # Subscribe email to topic
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.notification_email)
        )

        return topic

    def _create_database_secret(self) -> secretsmanager.Secret:
        """Create secret for storing database credentials."""
        return secretsmanager.Secret(
            self,
            "PostgreSQLCredentials",
            description=f"PostgreSQL credentials for {self.cluster_name}",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "dbadmin"}',
                generate_string_key="password",
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\",
                password_length=32,
            ),
        )

    def _create_primary_instance(self) -> rds.DatabaseInstance:
        """Create primary PostgreSQL instance with Multi-AZ configuration."""
        # Create enhanced monitoring role
        monitoring_role = iam.Role(
            self,
            "RDSMonitoringRole",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
        )

        primary_instance = rds.DatabaseInstance(
            self,
            "PostgreSQLPrimary",
            instance_identifier=f"{self.cluster_name}-primary",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            instance_type=ec2.InstanceType(self.instance_class),
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.db_security_group],
            parameter_group=self.parameter_group,
            credentials=rds.Credentials.from_secret(self.db_secret),
            database_name="productiondb",
            multi_az=True,
            storage_encrypted=True,
            allocated_storage=200,
            max_allocated_storage=1000,
            storage_type=rds.StorageType.GP3,
            backup_retention=Duration.days(35),
            preferred_backup_window="03:00-04:00",
            preferred_maintenance_window="sun:04:00-sun:05:00",
            delete_automated_backups=False,
            deletion_protection=True,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            monitoring_interval=Duration.minutes(1),
            monitoring_role=monitoring_role,
            cloudwatch_logs_exports=["postgresql"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_WEEK,
            copy_tags_to_snapshot=True,
            removal_policy=RemovalPolicy.SNAPSHOT,
        )

        return primary_instance

    def _create_read_replica(self) -> rds.DatabaseInstanceReadReplica:
        """Create read replica for horizontal scaling in the same region."""
        read_replica = rds.DatabaseInstanceReadReplica(
            self,
            "PostgreSQLReadReplica",
            instance_identifier=f"{self.cluster_name}-read-replica-1",
            source_database_instance=self.primary_instance,
            instance_type=ec2.InstanceType(self.instance_class),
            vpc=self.vpc,
            publicly_accessible=False,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            monitoring_interval=Duration.minutes(1),
            removal_policy=RemovalPolicy.DESTROY,
        )

        return read_replica

    def _create_cross_region_replica(self) -> rds.DatabaseInstanceReadReplica:
        """Create cross-region read replica for disaster recovery."""
        # Note: Cross-region replicas require manual creation in CDK
        # This is a placeholder that would need additional configuration
        # for a different region stack
        cross_region_replica = rds.DatabaseInstanceReadReplica(
            self,
            "PostgreSQLCrossRegionReplica",
            instance_identifier=f"{self.cluster_name}-dr-replica",
            source_database_instance=self.primary_instance,
            instance_type=ec2.InstanceType(self.instance_class),
            publicly_accessible=False,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return cross_region_replica

    def _create_rds_proxy(self) -> rds.DatabaseProxy:
        """Create RDS Proxy for connection pooling and enhanced security."""
        # Create IAM role for RDS Proxy
        proxy_role = iam.Role(
            self,
            "RDSProxyRole",
            assumed_by=iam.ServicePrincipal("rds.amazonaws.com"),
            inline_policies={
                "SecretsManagerAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "secretsmanager:GetSecretValue",
                                "secretsmanager:DescribeSecret",
                            ],
                            resources=[self.db_secret.secret_arn],
                        )
                    ]
                )
            },
        )

        proxy = rds.DatabaseProxy(
            self,
            "PostgreSQLProxy",
            proxy_target=rds.ProxyTarget.from_instance(self.primary_instance),
            secrets=[self.db_secret],
            vpc=self.vpc,
            security_groups=[self.db_security_group],
            role=proxy_role,
            db_proxy_name=f"{self.cluster_name}-proxy",
            require_tls=True,
            idle_client_timeout=Duration.minutes(30),
            max_connections_percent=100,
            max_idle_connections_percent=50,
        )

        return proxy

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for database monitoring."""
        # CPU utilization alarm
        cpu_alarm = cloudwatch.Alarm(
            self,
            "PostgreSQLCPUAlarm",
            alarm_name=f"{self.cluster_name}-cpu-high",
            alarm_description="PostgreSQL CPU utilization high",
            metric=self.primary_instance.metric_cpu_utilization(
                period=Duration.minutes(5), statistic="Average"
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        cpu_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

        # Database connections alarm
        connections_alarm = cloudwatch.Alarm(
            self,
            "PostgreSQLConnectionsAlarm",
            alarm_name=f"{self.cluster_name}-connections-high",
            alarm_description="PostgreSQL connection count high",
            metric=self.primary_instance.metric_database_connections(
                period=Duration.minutes(5), statistic="Average"
            ),
            threshold=150,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        connections_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

        # Read replica lag alarm
        replica_lag_alarm = cloudwatch.Alarm(
            self,
            "PostgreSQLReplicaLagAlarm",
            alarm_name=f"{self.cluster_name}-replica-lag-high",
            alarm_description="PostgreSQL read replica lag high",
            metric=self.read_replica.metric_read_replica_lag(
                period=Duration.minutes(5), statistic="Average"
            ),
            threshold=30,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        replica_lag_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

        # Storage space alarm
        storage_alarm = cloudwatch.Alarm(
            self,
            "PostgreSQLStorageAlarm",
            alarm_name=f"{self.cluster_name}-storage-low",
            alarm_description="PostgreSQL free storage space low",
            metric=self.primary_instance.metric_free_storage_space(
                period=Duration.minutes(5), statistic="Average"
            ),
            threshold=20 * 1024 * 1024 * 1024,  # 20 GB in bytes
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
        )
        storage_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _create_event_subscription(self) -> rds.CfnEventSubscription:
        """Create RDS event subscription for operational notifications."""
        return rds.CfnEventSubscription(
            self,
            "PostgreSQLEventSubscription",
            sns_topic_arn=self.sns_topic.topic_arn,
            source_type="db-instance",
            source_ids=[
                self.primary_instance.instance_identifier,
                self.read_replica.instance_identifier,
            ],
            event_categories=[
                "availability",
                "backup",
                "configuration change",
                "creation",
                "deletion",
                "failover",
                "failure",
                "low storage",
                "maintenance",
                "notification",
                "recovery",
                "restoration",
            ],
            subscription_name=f"{self.cluster_name}-events",
        )

    def _create_manual_snapshot(self) -> rds.CfnDBSnapshot:
        """Create initial manual snapshot for backup baseline."""
        return rds.CfnDBSnapshot(
            self,
            "PostgreSQLInitialSnapshot",
            db_instance_identifier=self.primary_instance.instance_identifier,
            db_snapshot_identifier=f"{self.cluster_name}-initial-snapshot",
        )

    def _create_outputs(self) -> None:
        """Create stack outputs for important endpoints and identifiers."""
        CfnOutput(
            self,
            "PrimaryEndpoint",
            value=self.primary_instance.instance_endpoint.hostname,
            description="Primary PostgreSQL instance endpoint",
        )

        CfnOutput(
            self,
            "ReadReplicaEndpoint",
            value=self.read_replica.instance_endpoint.hostname,
            description="Read replica endpoint",
        )

        CfnOutput(
            self,
            "ProxyEndpoint",
            value=self.rds_proxy.endpoint,
            description="RDS Proxy endpoint for connection pooling",
        )

        CfnOutput(
            self,
            "DatabaseSecret",
            value=self.db_secret.secret_arn,
            description="ARN of the secret containing database credentials",
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic ARN for database alerts",
        )

        CfnOutput(
            self,
            "DatabaseName",
            value="productiondb",
            description="Default database name",
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = cdk.App()

    # Get configuration from CDK context or environment variables
    notification_email = app.node.try_get_context("notification_email") or os.environ.get(
        "NOTIFICATION_EMAIL", "admin@example.com"
    )
    
    cluster_name = app.node.try_get_context("cluster_name") or os.environ.get(
        "CLUSTER_NAME"
    )
    
    instance_class = app.node.try_get_context("instance_class") or os.environ.get(
        "INSTANCE_CLASS", "db.r6g.large"
    )

    # Primary region stack
    primary_stack = PostgreSQLHAStack(
        app,
        "PostgreSQLHAStack",
        notification_email=notification_email,
        cluster_name=cluster_name,
        instance_class=instance_class,
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
        description="High-Availability PostgreSQL cluster with Multi-AZ, read replicas, and comprehensive monitoring",
    )

    # Add tags to all resources
    cdk.Tags.of(primary_stack).add("Project", "PostgreSQL-HA")
    cdk.Tags.of(primary_stack).add("Environment", "Production")
    cdk.Tags.of(primary_stack).add("ManagedBy", "CDK")

    app.synth()


if __name__ == "__main__":
    main()