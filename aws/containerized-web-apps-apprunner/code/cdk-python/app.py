#!/usr/bin/env python3
"""
CDK Python application for containerized web applications with App Runner and RDS.

This application creates:
- Amazon ECR repository for container images
- Amazon RDS PostgreSQL database with secure networking
- AWS Secrets Manager for database credentials
- AWS App Runner service with automatic scaling
- CloudWatch monitoring and alarms
- Required IAM roles and policies
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_ecr as ecr,
    aws_apprunner as apprunner,
    aws_secretsmanager as secretsmanager,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from typing import Dict, Any
from constructs import Construct


class ContainerizedWebAppStack(Stack):
    """
    CDK Stack for Containerized Web Applications with App Runner.
    
    This stack creates a complete infrastructure for hosting containerized web applications
    using AWS App Runner connected to an RDS PostgreSQL database with secure credential
    management and comprehensive monitoring.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create VPC for RDS database
        self._create_vpc()
        
        # Create ECR repository for container images
        self._create_ecr_repository()
        
        # Create RDS database with secure networking
        self._create_database()
        
        # Create database credentials in Secrets Manager
        self._create_database_secret()
        
        # Create IAM roles for App Runner
        self._create_iam_roles()
        
        # Create App Runner service
        self._create_app_runner_service()
        
        # Create CloudWatch monitoring
        self._create_monitoring()
        
        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> None:
        """Create VPC and subnets for RDS database with secure networking."""
        # Create VPC with public and private subnets
        self.vpc = ec2.Vpc(
            self, "WebAppVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            nat_gateways=0,  # No NAT gateway needed for this use case
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Create security group for RDS database
        self.db_security_group = ec2.SecurityGroup(
            self, "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for RDS PostgreSQL database",
            allow_all_outbound=False
        )

        # Allow inbound connections on PostgreSQL port from VPC CIDR
        self.db_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/16"),
            connection=ec2.Port.tcp(5432),
            description="Allow PostgreSQL connections from VPC"
        )

    def _create_ecr_repository(self) -> None:
        """Create Amazon ECR repository for container images with lifecycle policies."""
        self.ecr_repository = ecr.Repository(
            self, "WebAppRepository",
            repository_name="webapp-apprunner",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep only 10 most recent images",
                    max_image_count=10,
                    rule_priority=1
                )
            ],
            removal_policy=RemovalPolicy.DESTROY  # Allow cleanup for demo
        )

    def _create_database(self) -> None:
        """Create RDS PostgreSQL database with automated backups and encryption."""
        # Create DB subnet group
        self.db_subnet_group = rds.SubnetGroup(
            self, "DatabaseSubnetGroup",
            description="Subnet group for web app database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            )
        )

        # Generate random password for database
        self.db_password = secretsmanager.Secret(
            self, "DatabasePassword",
            description="Auto-generated password for RDS database",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "postgres"}',
                generate_string_key="password",
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\@",
                include_space=False,
                password_length=32
            )
        )

        # Create RDS PostgreSQL instance
        self.database = rds.DatabaseInstance(
            self, "WebAppDatabase",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_14_9
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3,
                ec2.InstanceSize.MICRO
            ),
            credentials=rds.Credentials.from_secret(
                self.db_password,
                username="postgres"
            ),
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.db_security_group],
            database_name="webapp",
            allocated_storage=20,
            storage_type=rds.StorageType.GP2,
            backup_retention=Duration.days(7),
            delete_automated_backups=True,
            deletion_protection=False,  # Allow deletion for demo
            multi_az=False,  # Single AZ for cost optimization
            publicly_accessible=False,
            storage_encrypted=True,
            monitoring_interval=Duration.seconds(60),
            removal_policy=RemovalPolicy.DESTROY  # Allow cleanup for demo
        )

    def _create_database_secret(self) -> None:
        """Create Secrets Manager secret with database connection details."""
        # Create secret with database connection information
        self.db_connection_secret = secretsmanager.Secret(
            self, "DatabaseConnectionSecret",
            description="Database connection details for web application",
            secret_object_value={
                "username": cdk.SecretValue.unsafe_plain_text("postgres"),
                "password": self.db_password.secret_value_from_json("password"),
                "host": cdk.SecretValue.unsafe_plain_text(
                    self.database.instance_endpoint.hostname
                ),
                "port": cdk.SecretValue.unsafe_plain_text("5432"),
                "dbname": cdk.SecretValue.unsafe_plain_text("webapp")
            }
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for App Runner service and instance."""
        # Create App Runner access role for ECR
        self.access_role = iam.Role(
            self, "AppRunnerAccessRole",
            assumed_by=iam.ServicePrincipal("build.apprunner.amazonaws.com"),
            description="IAM role for App Runner to access ECR",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSAppRunnerServicePolicyForECRAccess"
                )
            ]
        )

        # Create App Runner instance role for Secrets Manager access
        self.instance_role = iam.Role(
            self, "AppRunnerInstanceRole",
            assumed_by=iam.ServicePrincipal("tasks.apprunner.amazonaws.com"),
            description="IAM role for App Runner tasks"
        )

        # Grant access to database connection secret
        self.db_connection_secret.grant_read(self.instance_role)

        # Grant access to CloudWatch Logs
        self.instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams"
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/apprunner/*"
                ]
            )
        )

    def _create_app_runner_service(self) -> None:
        """Create App Runner service with automatic scaling and health checks."""
        # Create App Runner service
        self.app_runner_service = apprunner.CfnService(
            self, "WebAppService",
            service_name="webapp-apprunner",
            source_configuration=apprunner.CfnService.SourceConfigurationProperty(
                image_repository=apprunner.CfnService.ImageRepositoryProperty(
                    image_identifier=f"{self.ecr_repository.repository_uri}:latest",
                    image_configuration=apprunner.CfnService.ImageConfigurationProperty(
                        port="8080",
                        runtime_environment_variables={
                            "NODE_ENV": "production",
                            "AWS_REGION": self.region,
                            "DB_SECRET_NAME": self.db_connection_secret.secret_name
                        }
                    ),
                    image_repository_type="ECR"
                ),
                auto_deployments_enabled=True
            ),
            service_role_arn=self.access_role.role_arn,
            instance_configuration=apprunner.CfnService.InstanceConfigurationProperty(
                cpu="0.25 vCPU",
                memory="0.5 GB",
                instance_role_arn=self.instance_role.role_arn
            ),
            health_check_configuration=apprunner.CfnService.HealthCheckConfigurationProperty(
                protocol="HTTP",
                path="/health",
                interval=10,
                timeout=5,
                healthy_threshold=1,
                unhealthy_threshold=5
            ),
            network_configuration=apprunner.CfnService.NetworkConfigurationProperty(
                egress_configuration=apprunner.CfnService.EgressConfigurationProperty(
                    egress_type="DEFAULT"
                )
            ),
            observability_configuration=apprunner.CfnService.ObservabilityConfigurationProperty(
                observability_enabled=True
            )
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring, alarms, and log groups."""
        # Create log group for application logs
        self.app_log_group = logs.LogGroup(
            self, "ApplicationLogGroup",
            log_group_name=f"/aws/apprunner/webapp-apprunner/application",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create CloudWatch alarms for App Runner metrics
        # High CPU utilization alarm
        cloudwatch.Alarm(
            self, "HighCpuAlarm",
            alarm_name="webapp-apprunner-high-cpu",
            alarm_description="Alert when CPU exceeds 80%",
            metric=cloudwatch.Metric(
                namespace="AWS/AppRunner",
                metric_name="CPUUtilization",
                dimensions_map={
                    "ServiceName": "webapp-apprunner"
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # High memory utilization alarm
        cloudwatch.Alarm(
            self, "HighMemoryAlarm",
            alarm_name="webapp-apprunner-high-memory",
            alarm_description="Alert when memory exceeds 80%",
            metric=cloudwatch.Metric(
                namespace="AWS/AppRunner",
                metric_name="MemoryUtilization",
                dimensions_map={
                    "ServiceName": "webapp-apprunner"
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # High response latency alarm
        cloudwatch.Alarm(
            self, "HighLatencyAlarm",
            alarm_name="webapp-apprunner-high-latency",
            alarm_description="Alert when response time exceeds 2 seconds",
            metric=cloudwatch.Metric(
                namespace="AWS/AppRunner",
                metric_name="RequestLatency",
                dimensions_map={
                    "ServiceName": "webapp-apprunner"
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=2000,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self, "EcrRepositoryUri",
            value=self.ecr_repository.repository_uri,
            description="ECR repository URI for container images"
        )

        CfnOutput(
            self, "DatabaseEndpoint",
            value=self.database.instance_endpoint.hostname,
            description="RDS database endpoint"
        )

        CfnOutput(
            self, "DatabaseSecretArn",
            value=self.db_connection_secret.secret_arn,
            description="Secrets Manager ARN for database credentials"
        )

        CfnOutput(
            self, "AppRunnerServiceArn",
            value=self.app_runner_service.attr_service_arn,
            description="App Runner service ARN"
        )

        CfnOutput(
            self, "AppRunnerServiceUrl",
            value=self.app_runner_service.attr_service_url,
            description="App Runner service URL"
        )

        CfnOutput(
            self, "LogGroupName",
            value=self.app_log_group.log_group_name,
            description="CloudWatch log group for application logs"
        )


# CDK application entry point
app = cdk.App()

# Create the stack
ContainerizedWebAppStack(
    app, 
    "ContainerizedWebAppStack",
    description="Infrastructure for containerized web applications with App Runner and RDS",
    env=cdk.Environment(
        account=app.node.try_get_context("account") or None,
        region=app.node.try_get_context("region") or None
    )
)

# Add tags to all resources
cdk.Tags.of(app).add("Project", "ContainerizedWebApp")
cdk.Tags.of(app).add("Environment", "Development")
cdk.Tags.of(app).add("ManagedBy", "CDK")

app.synth()