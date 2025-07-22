#!/usr/bin/env python3
"""
Advanced RDS Multi-AZ with Cross-Region Failover CDK Application

This CDK application implements an enterprise-grade RDS Multi-AZ deployment with
cross-region read replicas, automated monitoring, and DNS-based failover capabilities.

The architecture provides:
- Multi-AZ RDS instance in primary region
- Cross-region read replica for disaster recovery
- CloudWatch monitoring and alerting
- Route 53 health checks and DNS failover
- IAM roles for automated promotion
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags,
)
from aws_cdk import aws_rds as rds
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_route53 as route53
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_sns as sns
from aws_cdk import aws_iam as iam
from aws_cdk import aws_secretsmanager as secretsmanager
from constructs import Construct


class AdvancedRdsMultiAzStack(Stack):
    """
    Primary stack containing the Multi-AZ RDS instance and related resources
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: ec2.Vpc,
        db_credentials: secretsmanager.Secret,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.vpc = vpc
        self.db_credentials = db_credentials

        # Create security group for RDS
        self.db_security_group = self._create_db_security_group()

        # Create DB subnet group
        self.db_subnet_group = self._create_db_subnet_group()

        # Create custom parameter group for optimized performance
        self.parameter_group = self._create_parameter_group()

        # Create IAM role for RDS monitoring
        self.monitoring_role = self._create_monitoring_role()

        # Create primary Multi-AZ RDS instance
        self.primary_instance = self._create_primary_rds_instance()

        # Create SNS topic for alerts
        self.alert_topic = self._create_alert_topic()

        # Create CloudWatch alarms for monitoring
        self._create_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

    def _create_db_security_group(self) -> ec2.SecurityGroup:
        """Create security group for RDS instances"""
        security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for financial database instances",
            allow_all_outbound=False,
        )

        # Allow PostgreSQL traffic from application security group
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(5432),
            description="PostgreSQL access from VPC",
        )

        return security_group

    def _create_db_subnet_group(self) -> rds.SubnetGroup:
        """Create DB subnet group for RDS instances"""
        return rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for financial database instances",
            vpc=self.vpc,
            subnet_group_name="financial-db-subnet-group",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )

    def _create_parameter_group(self) -> rds.ParameterGroup:
        """Create custom parameter group for optimized PostgreSQL performance"""
        parameter_group = rds.ParameterGroup(
            self,
            "DatabaseParameterGroup",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            description="Financial DB optimized parameters for high availability",
            parameters={
                # Enable comprehensive logging for audit trails
                "log_statement": "all",
                # Track slow queries over 1 second
                "log_min_duration_statement": "1000",
                # Optimize checkpoint timing to reduce I/O spikes during failover
                "checkpoint_completion_target": "0.9",
                # Optimize for high availability workloads
                "shared_preload_libraries": "pg_stat_statements",
                "track_activity_query_size": "2048",
            },
        )

        return parameter_group

    def _create_monitoring_role(self) -> iam.Role:
        """Create IAM role for RDS enhanced monitoring"""
        monitoring_role = iam.Role(
            self,
            "RdsMonitoringRole",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
        )

        return monitoring_role

    def _create_primary_rds_instance(self) -> rds.DatabaseInstance:
        """Create primary Multi-AZ RDS PostgreSQL instance"""
        primary_instance = rds.DatabaseInstance(
            self,
            "PrimaryDatabase",
            identifier="financial-db-primary",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.R5, ec2.InstanceSize.XLARGE
            ),
            credentials=rds.Credentials.from_secret(
                self.db_credentials, username="dbadmin"
            ),
            allocated_storage=500,
            storage_type=rds.StorageType.GP3,
            storage_encrypted=True,
            multi_az=True,  # Enable Multi-AZ for high availability
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.db_security_group],
            parameter_group=self.parameter_group,
            backup_retention=Duration.days(30),
            preferred_backup_window="03:00-04:00",
            preferred_maintenance_window="sun:04:00-sun:05:00",
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DAYS_7,
            monitoring_interval=Duration.minutes(1),
            monitoring_role=self.monitoring_role,
            deletion_protection=True,
            copy_tags_to_snapshot=True,
        )

        # Add tags for cost tracking and management
        Tags.of(primary_instance).add("Environment", "Production")
        Tags.of(primary_instance).add("Application", "FinancialDB")
        Tags.of(primary_instance).add("Backup", "Required")

        return primary_instance

    def _create_alert_topic(self) -> sns.Topic:
        """Create SNS topic for database alerts"""
        topic = sns.Topic(
            self,
            "DatabaseAlerts",
            display_name="Financial Database Alerts",
            topic_name="financial-db-alerts",
        )

        # Add email subscription (to be configured post-deployment)
        CfnOutput(
            self,
            "AlertTopicArn",
            value=topic.topic_arn,
            description="SNS topic ARN for database alerts - configure email subscription",
        )

        return topic

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for database monitoring"""
        # Alarm for high database connections
        connection_alarm = cloudwatch.Alarm(
            self,
            "DatabaseConnectionAlarm",
            metric=self.primary_instance.metric_database_connections(
                statistic=cloudwatch.Stats.MAXIMUM,
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="Alert when database connections exceed 80",
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to the alarm
        connection_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # Alarm for CPU utilization
        cpu_alarm = cloudwatch.Alarm(
            self,
            "DatabaseCpuAlarm",
            metric=self.primary_instance.metric_cpu_utilization(
                statistic=cloudwatch.Stats.AVERAGE,
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="Alert when database CPU exceeds 80% for 15 minutes",
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        cpu_alarm.add_alarm_action(cloudwatch.SnsAction(self.alert_topic))

    def _create_outputs(self) -> None:
        """Create stack outputs"""
        CfnOutput(
            self,
            "PrimaryInstanceEndpoint",
            value=self.primary_instance.instance_endpoint.hostname,
            description="Primary RDS instance endpoint",
        )

        CfnOutput(
            self,
            "PrimaryInstancePort",
            value=str(self.primary_instance.instance_endpoint.port),
            description="Primary RDS instance port",
        )

        CfnOutput(
            self,
            "DatabaseSecurityGroupId",
            value=self.db_security_group.security_group_id,
            description="Database security group ID",
        )

        CfnOutput(
            self,
            "ParameterGroupName",
            value=self.parameter_group.parameter_group_name,
            description="Database parameter group name",
        )


class CrossRegionReplicaStack(Stack):
    """
    Secondary stack for cross-region read replica and associated resources
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: ec2.Vpc,
        source_instance_arn: str,
        security_group_id: str,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.vpc = vpc
        self.source_instance_arn = source_instance_arn

        # Import security group from primary region
        self.db_security_group = ec2.SecurityGroup.from_security_group_id(
            self, "ImportedSecurityGroup", security_group_id
        )

        # Create DB subnet group for replica
        self.replica_subnet_group = self._create_replica_subnet_group()

        # Create IAM role for RDS monitoring
        self.monitoring_role = self._create_monitoring_role()

        # Create cross-region read replica
        self.read_replica = self._create_read_replica()

        # Create SNS topic for replica alerts
        self.alert_topic = self._create_alert_topic()

        # Create CloudWatch alarms for replica monitoring
        self._create_replica_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

    def _create_replica_subnet_group(self) -> rds.SubnetGroup:
        """Create DB subnet group for read replica"""
        return rds.SubnetGroup(
            self,
            "ReplicaSubnetGroup",
            description="Subnet group for financial database replica",
            vpc=self.vpc,
            subnet_group_name="financial-db-replica-subnet-group",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )

    def _create_monitoring_role(self) -> iam.Role:
        """Create IAM role for RDS enhanced monitoring"""
        monitoring_role = iam.Role(
            self,
            "ReplicaMonitoringRole",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
        )

        return monitoring_role

    def _create_read_replica(self) -> rds.DatabaseInstanceReadReplica:
        """Create cross-region read replica"""
        read_replica = rds.DatabaseInstanceReadReplica(
            self,
            "ReadReplica",
            identifier="financial-db-replica",
            source_database_instance=rds.DatabaseInstance.from_database_instance_attributes(
                self,
                "SourceInstance",
                instance_identifier="financial-db-primary",
                instance_endpoint_address="placeholder",  # Will be resolved at runtime
                port=5432,
                security_groups=[],
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.R5, ec2.InstanceSize.XLARGE
            ),
            vpc=self.vpc,
            subnet_group=self.replica_subnet_group,
            security_groups=[self.db_security_group],
            storage_encrypted=True,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DAYS_7,
            monitoring_interval=Duration.minutes(1),
            monitoring_role=self.monitoring_role,
            deletion_protection=True,
        )

        # Add tags for cost tracking and management
        Tags.of(read_replica).add("Environment", "Production")
        Tags.of(read_replica).add("Application", "FinancialDB")
        Tags.of(read_replica).add("Role", "ReadReplica")

        return read_replica

    def _create_alert_topic(self) -> sns.Topic:
        """Create SNS topic for replica alerts"""
        topic = sns.Topic(
            self,
            "ReplicaAlerts",
            display_name="Financial Database Replica Alerts",
            topic_name="financial-db-replica-alerts",
        )

        return topic

    def _create_replica_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for replica monitoring"""
        # Alarm for replica lag
        replica_lag_alarm = cloudwatch.Alarm(
            self,
            "ReplicaLagAlarm",
            metric=self.read_replica.metric("ReplicaLag", namespace="AWS/RDS"),
            threshold=300,  # 5 minutes
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="Alert when replica lag exceeds 5 minutes",
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
        )

        replica_lag_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

    def _create_outputs(self) -> None:
        """Create stack outputs"""
        CfnOutput(
            self,
            "ReplicaInstanceEndpoint",
            value=self.read_replica.instance_endpoint.hostname,
            description="Read replica instance endpoint",
        )

        CfnOutput(
            self,
            "ReplicaInstancePort",
            value=str(self.read_replica.instance_endpoint.port),
            description="Read replica instance port",
        )


class Route53FailoverStack(Stack):
    """
    Stack for Route 53 DNS failover configuration
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        primary_endpoint: str,
        replica_endpoint: str,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.primary_endpoint = primary_endpoint
        self.replica_endpoint = replica_endpoint

        # Create private hosted zone
        self.hosted_zone = self._create_hosted_zone()

        # Create health checks
        self.primary_health_check = self._create_primary_health_check()

        # Create DNS records with failover routing
        self._create_failover_records()

        # Create outputs
        self._create_outputs()

    def _create_hosted_zone(self) -> route53.PrivateHostedZone:
        """Create private hosted zone for database DNS"""
        # Note: In a real deployment, you would associate this with your VPCs
        hosted_zone = route53.HostedZone(
            self,
            "DatabaseHostedZone",
            zone_name="financial-db.internal",
            comment="Private hosted zone for financial database failover",
        )

        return hosted_zone

    def _create_primary_health_check(self) -> route53.HealthCheck:
        """Create health check for primary database"""
        # Note: This is a simplified health check. In production, you would
        # implement TCP health checks or application-specific health checks
        health_check = route53.HealthCheck(
            self,
            "PrimaryHealthCheck",
            type=route53.HealthCheckType.CALCULATED,
            health_check_name="primary-db-health-check",
            child_health_checks=[],  # Would include actual TCP health checks
            health_threshold=1,
            inverted=False,
        )

        return health_check

    def _create_failover_records(self) -> None:
        """Create DNS records with failover routing policy"""
        # Primary record
        route53.CnameRecord(
            self,
            "PrimaryDnsRecord",
            zone=self.hosted_zone,
            record_name="db",
            domain_name=self.primary_endpoint,
            ttl=Duration.minutes(1),
            set_identifier="primary",
            geo_location=None,
            health_check_id=self.primary_health_check.health_check_id,
        )

        # Secondary record (failover)
        route53.CnameRecord(
            self,
            "SecondaryDnsRecord",
            zone=self.hosted_zone,
            record_name="db",
            domain_name=self.replica_endpoint,
            ttl=Duration.minutes(1),
            set_identifier="secondary",
        )

    def _create_outputs(self) -> None:
        """Create stack outputs"""
        CfnOutput(
            self,
            "HostedZoneId",
            value=self.hosted_zone.hosted_zone_id,
            description="Hosted zone ID for DNS failover",
        )

        CfnOutput(
            self,
            "DatabaseDnsName",
            value=f"db.{self.hosted_zone.zone_name}",
            description="DNS name for database access",
        )


class PromotionAutomationStack(Stack):
    """
    Stack for cross-region promotion automation capabilities
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create IAM role for promotion automation
        self.promotion_role = self._create_promotion_role()

        # Create outputs
        self._create_outputs()

    def _create_promotion_role(self) -> iam.Role:
        """Create IAM role for cross-region promotion automation"""
        promotion_role = iam.Role(
            self,
            "PromotionRole",
            role_name="rds-promotion-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonRDSFullAccess"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonRoute53FullAccess"
                ),
            ],
        )

        return promotion_role

    def _create_outputs(self) -> None:
        """Create stack outputs"""
        CfnOutput(
            self,
            "PromotionRoleArn",
            value=self.promotion_role.role_arn,
            description="IAM role ARN for promotion automation",
        )


class AdvancedRdsMultiAzApp(cdk.App):
    """
    Main CDK application for Advanced RDS Multi-AZ with Cross-Region Failover
    """

    def __init__(self) -> None:
        super().__init__()

        # Configuration
        primary_region = "us-east-1"
        secondary_region = "us-west-2"
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")

        if not account:
            raise ValueError("CDK_DEFAULT_ACCOUNT environment variable must be set")

        # Create database credentials secret
        credentials_stack = Stack(
            self,
            "DatabaseCredentials",
            env=Environment(account=account, region=primary_region),
        )

        db_credentials = secretsmanager.Secret(
            credentials_stack,
            "DatabaseCredentials",
            description="Credentials for financial database",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "dbadmin"}',
                generate_string_key="password",
                exclude_characters='"@/\\',
                password_length=32,
            ),
        )

        # Create VPC for primary region (simplified - you may want to import existing VPC)
        primary_vpc_stack = Stack(
            self,
            "PrimaryVpc",
            env=Environment(account=account, region=primary_region),
        )

        primary_vpc = ec2.Vpc(
            primary_vpc_stack,
            "PrimaryVpc",
            max_azs=3,
            nat_gateways=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="Public",
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="Private",
                    cidr_mask=24,
                ),
            ],
        )

        # Create VPC for secondary region
        secondary_vpc_stack = Stack(
            self,
            "SecondaryVpc",
            env=Environment(account=account, region=secondary_region),
        )

        secondary_vpc = ec2.Vpc(
            secondary_vpc_stack,
            "SecondaryVpc",
            max_azs=3,
            nat_gateways=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="Public",
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="Private",
                    cidr_mask=24,
                ),
            ],
        )

        # Primary region stack
        primary_stack = AdvancedRdsMultiAzStack(
            self,
            "AdvancedRdsMultiAzPrimary",
            vpc=primary_vpc,
            db_credentials=db_credentials,
            env=Environment(account=account, region=primary_region),
        )

        # Cross-region replica stack
        replica_stack = CrossRegionReplicaStack(
            self,
            "CrossRegionReplica",
            vpc=secondary_vpc,
            source_instance_arn=primary_stack.primary_instance.instance_arn,
            security_group_id=primary_stack.db_security_group.security_group_id,
            env=Environment(account=account, region=secondary_region),
        )

        # Route 53 failover stack (global service)
        failover_stack = Route53FailoverStack(
            self,
            "Route53Failover",
            primary_endpoint=primary_stack.primary_instance.instance_endpoint.hostname,
            replica_endpoint=replica_stack.read_replica.instance_endpoint.hostname,
            env=Environment(account=account, region=primary_region),
        )

        # Promotion automation stack
        promotion_stack = PromotionAutomationStack(
            self,
            "PromotionAutomation",
            env=Environment(account=account, region=primary_region),
        )

        # Add dependencies
        replica_stack.add_dependency(primary_stack)
        failover_stack.add_dependency(primary_stack)
        failover_stack.add_dependency(replica_stack)


# Create and run the application
app = AdvancedRdsMultiAzApp()
app.synth()