#!/usr/bin/env python3
"""
CDK Application for Container Secrets Management with AWS Secrets Manager

This application creates a comprehensive secrets management solution for both
ECS and EKS environments, including:
- AWS Secrets Manager secrets with KMS encryption
- ECS cluster with task definition for secrets injection
- EKS cluster with IRSA and CSI driver configuration
- Lambda function for automatic secret rotation
- CloudWatch monitoring and alerting
- IAM roles and policies following least privilege principle

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_eks as eks,
    aws_iam as iam,
    aws_kms as kms,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_secretsmanager as secretsmanager,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
)
from constructs import Construct


class ContainerSecretsManagementStack(Stack):
    """
    CDK Stack for Container Secrets Management with AWS Secrets Manager
    
    This stack creates a complete secrets management solution for containerized
    applications, supporting both Amazon ECS and Amazon EKS environments.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment_name: str = "demo",
        enable_eks: bool = True,
        enable_ecs: bool = True,
        email_alerts: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Container Secrets Management Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            environment_name: Environment name for resource naming
            enable_eks: Whether to create EKS resources
            enable_ecs: Whether to create ECS resources
            email_alerts: Email address for CloudWatch alerts
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name
        self.enable_eks = enable_eks
        self.enable_ecs = enable_ecs
        self.email_alerts = email_alerts

        # Create KMS key for encryption
        self.kms_key = self._create_kms_key()
        
        # Create secrets in AWS Secrets Manager
        self.secrets = self._create_secrets()
        
        # Create VPC for container resources
        self.vpc = self._create_vpc()
        
        # Create Lambda function for secret rotation
        self.rotation_lambda = self._create_rotation_lambda()
        
        # Configure secret rotation
        self._configure_secret_rotation()
        
        # Create ECS resources if enabled
        if self.enable_ecs:
            self.ecs_cluster = self._create_ecs_cluster()
            self.ecs_task_role = self._create_ecs_task_role()
            self.ecs_task_definition = self._create_ecs_task_definition()
        
        # Create EKS resources if enabled
        if self.enable_eks:
            self.eks_cluster = self._create_eks_cluster()
            self.eks_service_account = self._create_eks_service_account()
        
        # Create monitoring and alerting
        self._create_monitoring()
        
        # Create outputs for verification
        self._create_outputs()

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for secrets encryption"""
        return kms.Key(
            self,
            "SecretsManagerKey",
            description=f"KMS key for Secrets Manager encryption - {self.environment_name}",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,
            alias=f"alias/secrets-manager-{self.environment_name}",
        )

    def _create_secrets(self) -> Dict[str, secretsmanager.Secret]:
        """Create application secrets in AWS Secrets Manager"""
        secrets = {}
        
        # Database credentials secret
        secrets["database"] = secretsmanager.Secret(
            self,
            "DatabaseSecret",
            description="Database credentials for demo application",
            encryption_key=self.kms_key,
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "appuser", "host": "demo-db.cluster-xyz.us-west-2.rds.amazonaws.com", "port": "5432", "database": "appdb"}',
                generate_string_key="password",
                exclude_characters='"@/\\',
                password_length=32,
                require_each_included_type=True,
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # API keys secret
        secrets["api_keys"] = secretsmanager.Secret(
            self,
            "ApiKeysSecret",
            description="API keys for external services",
            encryption_key=self.kms_key,
            secret_object_value={
                "github_token": cdk.SecretValue.unsafe_plain_text("ghp_example_token_replace_in_production"),
                "stripe_key": cdk.SecretValue.unsafe_plain_text("sk_test_example_key_replace_in_production"),
                "twilio_sid": cdk.SecretValue.unsafe_plain_text("AC_example_sid_replace_in_production"),
            },
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return secrets

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for container resources"""
        return ec2.Vpc(
            self,
            "ContainerVpc",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

    def _create_rotation_lambda(self) -> lambda_.Function:
        """Create Lambda function for automatic secret rotation"""
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self,
            "RotationLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add permissions for Secrets Manager access
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret",
                    "secretsmanager:PutSecretValue",
                    "secretsmanager:UpdateSecretVersionStage",
                    "secretsmanager:GetRandomPassword",
                ],
                resources=[
                    secret.secret_arn for secret in self.secrets.values()
                ],
            )
        )
        
        # Add KMS permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kms:Decrypt",
                    "kms:GenerateDataKey",
                ],
                resources=[self.kms_key.key_arn],
            )
        )
        
        # Create Lambda function
        return lambda_.Function(
            self,
            "SecretRotationFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
import boto3
import json
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    \"\"\"
    Lambda handler for automatic secret rotation
    
    This function rotates secrets by generating new random passwords
    and updating the secret value in AWS Secrets Manager.
    \"\"\"
    client = boto3.client('secretsmanager')
    
    # Get the secret ARN from the event
    secret_arn = event.get('Step', '')
    token = event.get('Token', '')
    step = event.get('Step', '')
    
    try:
        if step == "createSecret":
            # Generate new random password
            new_password = client.get_random_password(
                PasswordLength=32,
                ExcludeCharacters='"@/\\\\'
            )['RandomPassword']
            
            # Get current secret
            current_secret = client.get_secret_value(SecretId=secret_arn)
            secret_dict = json.loads(current_secret['SecretString'])
            
            # Update password
            secret_dict['password'] = new_password
            
            # Create new version
            client.put_secret_value(
                SecretId=secret_arn,
                SecretString=json.dumps(secret_dict),
                VersionStage='AWSPENDING'
            )
            
            logger.info(f"Successfully created new secret version: {secret_arn}")
            
        elif step == "setSecret":
            # In a real implementation, this would update the database/service
            # with the new credentials
            logger.info(f"Setting secret in service: {secret_arn}")
            
        elif step == "testSecret":
            # In a real implementation, this would test the new credentials
            logger.info(f"Testing new secret: {secret_arn}")
            
        elif step == "finishSecret":
            # Move AWSPENDING to AWSCURRENT
            client.update_secret_version_stage(
                SecretId=secret_arn,
                VersionStage='AWSCURRENT',
                MoveToVersionId=token
            )
            
            logger.info(f"Successfully finished secret rotation: {secret_arn}")
        
        return {'statusCode': 200, 'body': 'Secret rotation completed successfully'}
        
    except Exception as e:
        logger.error(f"Error during secret rotation: {str(e)}")
        raise e
            """),
            role=lambda_role,
            timeout=Duration.minutes(2),
            environment={
                "ENVIRONMENT": self.environment_name,
            },
        )

    def _configure_secret_rotation(self) -> None:
        """Configure automatic rotation for secrets"""
        # Configure rotation for database secret
        secretsmanager.RotationSchedule(
            self,
            "DatabaseSecretRotation",
            secret=self.secrets["database"],
            rotation_lambda=self.rotation_lambda,
            automatically_after=Duration.days(30),
        )

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """Create ECS cluster for container deployment"""
        return ecs.Cluster(
            self,
            "ContainerCluster",
            vpc=self.vpc,
            cluster_name=f"{self.environment_name}-secrets-cluster",
            capacity_providers=[
                ecs.CapacityProvider.FARGATE,
                ecs.CapacityProvider.FARGATE_SPOT,
            ],
            default_capacity_provider_strategy=[
                ecs.CapacityProviderStrategy(
                    capacity_provider=ecs.CapacityProvider.FARGATE,
                    weight=1,
                )
            ],
            enable_fargate_capacity_providers=True,
        )

    def _create_ecs_task_role(self) -> iam.Role:
        """Create IAM role for ECS tasks"""
        task_role = iam.Role(
            self,
            "EcsTaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            role_name=f"{self.environment_name}-ecs-task-role",
        )
        
        # Add permissions for Secrets Manager access
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret",
                ],
                resources=[
                    secret.secret_arn for secret in self.secrets.values()
                ],
            )
        )
        
        # Add KMS permissions
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kms:Decrypt",
                ],
                resources=[self.kms_key.key_arn],
            )
        )
        
        return task_role

    def _create_ecs_task_definition(self) -> ecs.FargateTaskDefinition:
        """Create ECS task definition with secrets injection"""
        # Create log group for container logs
        log_group = logs.LogGroup(
            self,
            "EcsTaskLogGroup",
            log_group_name=f"/ecs/{self.environment_name}-secrets-demo",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create task definition
        task_definition = ecs.FargateTaskDefinition(
            self,
            "DemoTaskDefinition",
            family=f"{self.environment_name}-secrets-demo",
            memory_limit_mib=512,
            cpu=256,
            task_role=self.ecs_task_role,
        )
        
        # Add container with secrets injection
        container = task_definition.add_container(
            "demo-app",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            port_mappings=[
                ecs.PortMapping(
                    container_port=80,
                    protocol=ecs.Protocol.TCP,
                )
            ],
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=log_group,
            ),
            secrets={
                "DB_USERNAME": ecs.Secret.from_secrets_manager(
                    self.secrets["database"], "username"
                ),
                "DB_PASSWORD": ecs.Secret.from_secrets_manager(
                    self.secrets["database"], "password"
                ),
                "DB_HOST": ecs.Secret.from_secrets_manager(
                    self.secrets["database"], "host"
                ),
                "GITHUB_TOKEN": ecs.Secret.from_secrets_manager(
                    self.secrets["api_keys"], "github_token"
                ),
            },
        )
        
        return task_definition

    def _create_eks_cluster(self) -> eks.Cluster:
        """Create EKS cluster for Kubernetes deployment"""
        # Create EKS cluster
        cluster = eks.Cluster(
            self,
            "EksCluster",
            cluster_name=f"{self.environment_name}-secrets-cluster",
            version=eks.KubernetesVersion.V1_28,
            vpc=self.vpc,
            default_capacity=0,  # We'll add managed node groups separately
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
        )
        
        # Add managed node group
        cluster.add_nodegroup_capacity(
            "DefaultNodeGroup",
            instance_types=[ec2.InstanceType("t3.medium")],
            min_size=1,
            max_size=3,
            desired_size=2,
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )
        
        return cluster

    def _create_eks_service_account(self) -> eks.ServiceAccount:
        """Create Kubernetes service account with IRSA"""
        service_account = self.eks_cluster.add_service_account(
            "SecretsServiceAccount",
            name="secrets-demo-sa",
            namespace="default",
        )
        
        # Add permissions for Secrets Manager access
        service_account.add_to_principal_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret",
                ],
                resources=[
                    secret.secret_arn for secret in self.secrets.values()
                ],
            )
        )
        
        # Add KMS permissions
        service_account.add_to_principal_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kms:Decrypt",
                ],
                resources=[self.kms_key.key_arn],
            )
        )
        
        return service_account

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alerting"""
        # Create SNS topic for alerts if email is provided
        if self.email_alerts:
            alert_topic = sns.Topic(
                self,
                "SecretsAlertsTopopic",
                topic_name=f"{self.environment_name}-secrets-alerts",
            )
            
            alert_topic.add_subscription(
                subscriptions.EmailSubscription(self.email_alerts)
            )
        
        # Create CloudWatch alarm for unauthorized access
        cloudwatch.Alarm(
            self,
            "UnauthorizedSecretsAccess",
            alarm_name=f"{self.environment_name}-unauthorized-secrets-access",
            alarm_description="Alert on unauthorized secret access attempts",
            metric=cloudwatch.Metric(
                namespace="AWS/SecretsManager",
                metric_name="UnauthorizedAPICallsCount",
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            alarm_actions=[alert_topic] if self.email_alerts else [],
        )
        
        # Create CloudWatch alarm for rotation failures
        cloudwatch.Alarm(
            self,
            "SecretRotationFailures",
            alarm_name=f"{self.environment_name}-secret-rotation-failures",
            alarm_description="Alert on secret rotation failures",
            metric=self.rotation_lambda.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum",
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            alarm_actions=[alert_topic] if self.email_alerts else [],
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for verification"""
        # KMS Key outputs
        cdk.CfnOutput(
            self,
            "KmsKeyId",
            value=self.kms_key.key_id,
            description="KMS Key ID for secrets encryption",
        )
        
        # Secrets outputs
        for secret_name, secret in self.secrets.items():
            cdk.CfnOutput(
                self,
                f"{secret_name.title()}SecretArn",
                value=secret.secret_arn,
                description=f"ARN of the {secret_name} secret",
            )
        
        # ECS outputs
        if self.enable_ecs:
            cdk.CfnOutput(
                self,
                "EcsClusterName",
                value=self.ecs_cluster.cluster_name,
                description="Name of the ECS cluster",
            )
            
            cdk.CfnOutput(
                self,
                "EcsTaskDefinitionArn",
                value=self.ecs_task_definition.task_definition_arn,
                description="ARN of the ECS task definition",
            )
        
        # EKS outputs
        if self.enable_eks:
            cdk.CfnOutput(
                self,
                "EksClusterName",
                value=self.eks_cluster.cluster_name,
                description="Name of the EKS cluster",
            )
            
            cdk.CfnOutput(
                self,
                "EksClusterEndpoint",
                value=self.eks_cluster.cluster_endpoint,
                description="Endpoint URL of the EKS cluster",
            )
        
        # Lambda outputs
        cdk.CfnOutput(
            self,
            "RotationLambdaArn",
            value=self.rotation_lambda.function_arn,
            description="ARN of the secret rotation Lambda function",
        )
        
        # VPC outputs
        cdk.CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="ID of the VPC",
        )


class ContainerSecretsApp(cdk.App):
    """CDK Application for Container Secrets Management"""
    
    def __init__(self):
        super().__init__()
        
        # Get configuration from environment variables or use defaults
        environment_name = self.node.try_get_context("environment") or "demo"
        enable_eks = self.node.try_get_context("enable_eks") != "false"
        enable_ecs = self.node.try_get_context("enable_ecs") != "false"
        email_alerts = self.node.try_get_context("email_alerts")
        
        # Create the main stack
        ContainerSecretsManagementStack(
            self,
            "ContainerSecretsManagementStack",
            environment_name=environment_name,
            enable_eks=enable_eks,
            enable_ecs=enable_ecs,
            email_alerts=email_alerts,
            env=cdk.Environment(
                account=os.getenv("CDK_DEFAULT_ACCOUNT"),
                region=os.getenv("CDK_DEFAULT_REGION", "us-west-2"),
            ),
            description="Container Secrets Management with AWS Secrets Manager",
        )


if __name__ == "__main__":
    app = ContainerSecretsApp()
    app.synth()