#!/usr/bin/env python3
"""
CDK Python Application for Database Security with Encryption and IAM Authentication

This application deploys a comprehensive database security solution using Amazon RDS 
with AWS KMS encryption, IAM database authentication, and CloudWatch monitoring.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_kms as kms,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_secretsmanager as secretsmanager,
    Tags,
)
from constructs import Construct


class DatabaseSecurityStack(Stack):
    """
    CDK Stack for implementing database security with encryption and IAM authentication.
    
    This stack creates:
    - Customer-managed KMS key for encryption
    - Secure VPC with private subnets
    - RDS PostgreSQL instance with encryption and IAM auth
    - RDS Proxy for connection pooling
    - CloudWatch monitoring and alarms
    - IAM roles and policies for database access
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment: str = "production",
        db_instance_class: str = "db.r5.large",
        enable_deletion_protection: bool = True,
        backup_retention_days: int = 7,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.environment = environment
        self.db_instance_class = db_instance_class
        self.enable_deletion_protection = enable_deletion_protection
        self.backup_retention_days = backup_retention_days

        # Generate unique suffix for resource names
        self.unique_suffix = self.node.addr[-6:].lower()
        
        # Create all infrastructure components
        self.kms_key = self._create_kms_key()
        self.vpc = self._create_vpc()
        self.security_group = self._create_security_group()
        self.db_subnet_group = self._create_db_subnet_group()
        self.parameter_group = self._create_parameter_group()
        self.monitoring_role = self._create_monitoring_role()
        self.database_access_role = self._create_database_access_role()
        self.rds_instance = self._create_rds_instance()
        self.rds_proxy = self._create_rds_proxy()
        self.cloudwatch_alarms = self._create_cloudwatch_alarms()
        
        # Add tags to all resources
        self._add_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_kms_key(self) -> kms.Key:
        """Create customer-managed KMS key for RDS encryption."""
        key_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="Enable IAM User Permissions",
                    effect=iam.Effect.ALLOW,
                    principals=[
                        iam.AccountRootPrincipal()
                    ],
                    actions=["kms:*"],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    sid="Allow RDS Service",
                    effect=iam.Effect.ALLOW,
                    principals=[
                        iam.ServicePrincipal("rds.amazonaws.com")
                    ],
                    actions=[
                        "kms:Decrypt",
                        "kms:GenerateDataKey",
                        "kms:DescribeKey"
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            f"kms:ViaService": f"rds.{self.region}.amazonaws.com"
                        }
                    }
                )
            ]
        )

        kms_key = kms.Key(
            self,
            "DatabaseEncryptionKey",
            description="Customer managed key for RDS encryption",
            policy=key_policy,
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY if not self.enable_deletion_protection else RemovalPolicy.RETAIN
        )

        # Create key alias
        kms.Alias(
            self,
            "DatabaseEncryptionKeyAlias",
            alias_name=f"alias/rds-security-key-{self.unique_suffix}",
            target_key=kms_key
        )

        return kms_key

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with private subnets for database deployment."""
        vpc = ec2.Vpc(
            self,
            "DatabaseVPC",
            max_azs=2,
            cidr="10.0.0.0/16",
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

        # Add VPC Flow Logs for security monitoring
        vpc_flow_log_role = iam.Role(
            self,
            "VPCFlowLogRole",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            inline_policies={
                "VPCFlowLogPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            actions=[
                                "logs:CreateLogGroup",
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

        vpc_flow_log_group = logs.LogGroup(
            self,
            "VPCFlowLogGroup",
            log_group_name=f"/aws/vpc/flowlogs/{self.unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        ec2.FlowLog(
            self,
            "VPCFlowLog",
            resource_type=ec2.FlowLogResourceType.from_vpc(vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                vpc_flow_log_group,
                vpc_flow_log_role
            )
        )

        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for database access."""
        security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for secure RDS instance",
            allow_all_outbound=False
        )

        # Allow PostgreSQL access from within the same security group
        security_group.add_ingress_rule(
            peer=security_group,
            connection=ec2.Port.tcp(5432),
            description="PostgreSQL access from within security group"
        )

        # Allow HTTPS outbound for AWS services
        security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for AWS services"
        )

        return security_group

    def _create_db_subnet_group(self) -> rds.SubnetGroup:
        """Create database subnet group for RDS deployment."""
        return rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for secure database",
            vpc=self.vpc,
            subnet_group_name=f"secure-db-subnet-group-{self.unique_suffix}",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            )
        )

    def _create_parameter_group(self) -> rds.ParameterGroup:
        """Create parameter group with security-enhanced settings."""
        parameter_group = rds.ParameterGroup(
            self,
            "DatabaseParameterGroup",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_7
            ),
            description="Security-enhanced PostgreSQL parameters",
            parameters={
                "rds.force_ssl": "1",  # Force SSL connections
                "log_statement": "all",  # Log all SQL statements
                "log_connections": "1",  # Log connections
                "log_disconnections": "1",  # Log disconnections
                "shared_preload_libraries": "pg_stat_statements",  # Enable query statistics
            }
        )

        return parameter_group

    def _create_monitoring_role(self) -> iam.Role:
        """Create IAM role for enhanced monitoring."""
        monitoring_role = iam.Role(
            self,
            "RDSMonitoringRole",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
            role_name=f"rds-monitoring-role-{self.unique_suffix}"
        )

        return monitoring_role

    def _create_database_access_role(self) -> iam.Role:
        """Create IAM role for database access with IAM authentication."""
        database_access_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["rds-db:connect"],
                    resources=[
                        f"arn:aws:rds-db:{self.region}:{self.account}:dbuser:*/app_user"
                    ]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "rds:DescribeDBInstances",
                        "rds:DescribeDBProxies"
                    ],
                    resources=["*"]
                )
            ]
        )

        database_access_role = iam.Role(
            self,
            "DatabaseAccessRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("lambda.amazonaws.com"),
                iam.ServicePrincipal("ec2.amazonaws.com")
            ),
            inline_policies={
                "DatabaseAccessPolicy": database_access_policy
            },
            role_name=f"database-access-role-{self.unique_suffix}"
        )

        return database_access_role

    def _create_rds_instance(self) -> rds.DatabaseInstance:
        """Create RDS instance with encryption and IAM authentication."""
        # Create master password in Secrets Manager
        master_password = secretsmanager.Secret(
            self,
            "DatabaseMasterPassword",
            description="Master password for RDS instance",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "dbadmin"}',
                generate_string_key="password",
                exclude_characters='"@/\\\'',
                password_length=32
            ),
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create RDS instance
        rds_instance = rds.DatabaseInstance(
            self,
            "SecureDatabase",
            instance_identifier=f"secure-db-{self.unique_suffix}",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_7
            ),
            instance_type=ec2.InstanceType(self.db_instance_class),
            allocated_storage=100,
            storage_type=rds.StorageType.GP3,
            storage_encrypted=True,
            storage_encryption_key=self.kms_key,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self.security_group],
            subnet_group=self.db_subnet_group,
            parameter_group=self.parameter_group,
            credentials=rds.Credentials.from_secret(master_password),
            backup_retention=Duration.days(self.backup_retention_days),
            preferred_backup_window="03:00-04:00",
            preferred_maintenance_window="sun:04:00-sun:05:00",
            iam_authentication=True,
            monitoring_interval=Duration.minutes(1),
            monitoring_role=self.monitoring_role,
            enable_performance_insights=True,
            performance_insight_encryption_key=self.kms_key,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            deletion_protection=self.enable_deletion_protection,
            database_name="secure_app_db",
            cloudwatch_logs_exports=[
                "postgresql"
            ],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_MONTH,
            remove_automated_backups=False,
            copy_tags_to_snapshot=True
        )

        return rds_instance

    def _create_rds_proxy(self) -> rds.DatabaseProxy:
        """Create RDS Proxy for enhanced security and connection pooling."""
        rds_proxy = rds.DatabaseProxy(
            self,
            "SecureDatabaseProxy",
            proxy_target=rds.ProxyTarget.from_instance(self.rds_instance),
            secrets=[self.rds_instance.secret],
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self.security_group],
            db_proxy_name=f"secure-proxy-{self.unique_suffix}",
            iam_auth=True,
            require_tls=True,
            idle_client_timeout=Duration.minutes(30),
            role=self.database_access_role,
            debug_logging=True
        )

        return rds_proxy

    def _create_cloudwatch_alarms(self) -> List[cloudwatch.Alarm]:
        """Create CloudWatch alarms for database monitoring."""
        alarms = []

        # High CPU usage alarm
        cpu_alarm = cloudwatch.Alarm(
            self,
            "DatabaseHighCPUAlarm",
            alarm_name=f"RDS-HighCPU-{self.rds_instance.instance_identifier}",
            alarm_description="High CPU usage on RDS instance",
            metric=self.rds_instance.metric_cpu_utilization(),
            threshold=80.0,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(cpu_alarm)

        # Database connection alarm
        connection_alarm = cloudwatch.Alarm(
            self,
            "DatabaseConnectionAlarm",
            alarm_name=f"RDS-HighConnections-{self.rds_instance.instance_identifier}",
            alarm_description="High number of database connections",
            metric=self.rds_instance.metric_database_connections(),
            threshold=50.0,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(connection_alarm)

        # Free storage space alarm
        storage_alarm = cloudwatch.Alarm(
            self,
            "DatabaseLowStorageAlarm",
            alarm_name=f"RDS-LowStorage-{self.rds_instance.instance_identifier}",
            alarm_description="Low free storage space on RDS instance",
            metric=self.rds_instance.metric_free_storage_space(),
            threshold=2000000000,  # 2GB in bytes
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(storage_alarm)

        return alarms

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Environment", self.environment)
        Tags.of(self).add("Application", "Database Security")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Security", "Encrypted")
        Tags.of(self).add("Compliance", "Enterprise")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        cdk.CfnOutput(
            self,
            "DatabaseEndpoint",
            value=self.rds_instance.instance_endpoint.hostname,
            description="RDS instance endpoint"
        )

        cdk.CfnOutput(
            self,
            "DatabasePort",
            value=str(self.rds_instance.instance_endpoint.port),
            description="RDS instance port"
        )

        cdk.CfnOutput(
            self,
            "ProxyEndpoint",
            value=self.rds_proxy.endpoint,
            description="RDS Proxy endpoint"
        )

        cdk.CfnOutput(
            self,
            "DatabaseAccessRoleArn",
            value=self.database_access_role.role_arn,
            description="IAM role ARN for database access"
        )

        cdk.CfnOutput(
            self,
            "KMSKeyId",
            value=self.kms_key.key_id,
            description="KMS key ID for database encryption"
        )

        cdk.CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="Security group ID for database access"
        )

        cdk.CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID where database is deployed"
        )

        cdk.CfnOutput(
            self,
            "DatabaseSecretArn",
            value=self.rds_instance.secret.secret_arn,
            description="Secrets Manager secret ARN for database credentials"
        )


class DatabaseSecurityApp(App):
    """CDK Application for Database Security with Encryption and IAM Authentication."""

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or use defaults
        environment = os.getenv("ENVIRONMENT", "production")
        db_instance_class = os.getenv("DB_INSTANCE_CLASS", "db.r5.large")
        enable_deletion_protection = os.getenv("ENABLE_DELETION_PROTECTION", "true").lower() == "true"
        backup_retention_days = int(os.getenv("BACKUP_RETENTION_DAYS", "7"))

        # Create the database security stack
        DatabaseSecurityStack(
            self,
            "DatabaseSecurityStack",
            environment=environment,
            db_instance_class=db_instance_class,
            enable_deletion_protection=enable_deletion_protection,
            backup_retention_days=backup_retention_days,
            env=cdk.Environment(
                account=os.getenv("CDK_DEFAULT_ACCOUNT"),
                region=os.getenv("CDK_DEFAULT_REGION")
            ),
            description="Database security implementation with encryption and IAM authentication"
        )


if __name__ == "__main__":
    app = DatabaseSecurityApp()
    app.synth()