#!/usr/bin/env python3
"""
AWS CDK Python Application for Database Connection Pooling with RDS Proxy

This CDK application creates:
- VPC with private subnets across multiple AZs
- RDS MySQL instance with encryption
- RDS Proxy for connection pooling
- Secrets Manager for database credentials
- Lambda function for testing connectivity
- All necessary IAM roles and security groups

Author: AWS CDK Generator
Version: 1.0
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
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_secretsmanager as secretsmanager,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
)
from constructs import Construct


class DatabaseConnectionPoolingStack(Stack):
    """
    CDK Stack for Database Connection Pooling with RDS Proxy.
    
    This stack demonstrates best practices for serverless database connectivity
    by implementing connection pooling through Amazon RDS Proxy.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.db_name = "testdb"
        self.db_user = "admin"
        
        # Create VPC with public and private subnets
        self.vpc = self._create_vpc()
        
        # Create database credentials in Secrets Manager
        self.db_secret = self._create_database_secret()
        
        # Create security groups
        self.db_security_group, self.proxy_security_group = self._create_security_groups()
        
        # Create RDS instance
        self.rds_instance = self._create_rds_instance()
        
        # Create IAM role for RDS Proxy
        self.proxy_role = self._create_proxy_iam_role()
        
        # Create RDS Proxy
        self.rds_proxy = self._create_rds_proxy()
        
        # Create Lambda function for testing
        self.test_lambda = self._create_test_lambda()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets across multiple AZs."""
        return ec2.Vpc(
            self,
            "RdsProxyVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
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

    def _create_database_secret(self) -> secretsmanager.Secret:
        """Create Secrets Manager secret for database credentials."""
        return secretsmanager.Secret(
            self,
            "DatabaseSecret",
            description="Database credentials for RDS Proxy demo",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "' + self.db_user + '"}',
                generate_string_key="password",
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\",
                include_space=False,
                password_length=32,
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_security_groups(self) -> tuple[ec2.SecurityGroup, ec2.SecurityGroup]:
        """Create security groups for RDS instance and RDS Proxy."""
        # Security group for RDS instance
        db_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for RDS MySQL instance",
            allow_all_outbound=False,
        )

        # Security group for RDS Proxy
        proxy_security_group = ec2.SecurityGroup(
            self,
            "ProxySecurityGroup",
            vpc=self.vpc,
            description="Security group for RDS Proxy",
            allow_all_outbound=False,
        )

        # Allow RDS Proxy to connect to RDS instance
        db_security_group.add_ingress_rule(
            peer=proxy_security_group,
            connection=ec2.Port.tcp(3306),
            description="Allow RDS Proxy to connect to MySQL",
        )

        # Allow Lambda functions in VPC to connect to RDS Proxy
        proxy_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="Allow VPC resources to connect to RDS Proxy",
        )

        # Allow proxy to make HTTPS calls for Secrets Manager
        proxy_security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic for Secrets Manager",
        )

        return db_security_group, proxy_security_group

    def _create_rds_instance(self) -> rds.DatabaseInstance:
        """Create RDS MySQL instance with encryption and backup enabled."""
        # Create DB subnet group
        subnet_group = rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for RDS Proxy demo",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
        )

        return rds.DatabaseInstance(
            self,
            "DatabaseInstance",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO
            ),
            credentials=rds.Credentials.from_secret(
                secret=self.db_secret,
                username=self.db_user,
            ),
            database_name=self.db_name,
            allocated_storage=20,
            storage_type=rds.StorageType.GP2,
            storage_encrypted=True,
            vpc=self.vpc,
            subnet_group=subnet_group,
            security_groups=[self.db_security_group],
            backup_retention=Duration.days(7),
            deletion_protection=False,  # Set to True for production
            delete_automated_backups=True,
            removal_policy=RemovalPolicy.DESTROY,  # Set to RETAIN for production
            parameter_group=rds.ParameterGroup.from_parameter_group_name(
                self, "DefaultParameterGroup", "default.mysql8.0"
            ),
        )

    def _create_proxy_iam_role(self) -> iam.Role:
        """Create IAM role for RDS Proxy to access Secrets Manager."""
        role = iam.Role(
            self,
            "RdsProxyRole",
            assumed_by=iam.ServicePrincipal("rds.amazonaws.com"),
            description="IAM role for RDS Proxy to access Secrets Manager",
        )

        # Add policy to access the specific secret
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret",
                ],
                resources=[self.db_secret.secret_arn],
            )
        )

        return role

    def _create_rds_proxy(self) -> rds.DatabaseProxy:
        """Create RDS Proxy with connection pooling configuration."""
        return rds.DatabaseProxy(
            self,
            "DatabaseProxy",
            proxy_target=rds.ProxyTarget.from_instance(self.rds_instance),
            secrets=[self.db_secret],
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            security_groups=[self.proxy_security_group],
            role=self.proxy_role,
            idle_client_timeout=Duration.minutes(30),
            max_connections_percent=75,
            max_idle_connections_percent=25,
            require_tls=False,  # Set to True for production
            debug_logging=True,
        )

    def _create_test_lambda(self) -> lambda_.Function:
        """Create Lambda function for testing RDS Proxy connectivity."""
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaVPCAccessExecutionRole"
                )
            ],
        )

        # Grant Lambda permission to read the database secret
        self.db_secret.grant_read(lambda_role)

        # Create Lambda function
        function = lambda_.Function(
            self,
            "TestConnectivityFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            security_groups=[self.proxy_security_group],
            environment={
                "PROXY_ENDPOINT": self.rds_proxy.endpoint,
                "SECRET_ARN": self.db_secret.secret_arn,
                "DB_NAME": self.db_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        return function

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for testing connectivity."""
        return '''
import json
import boto3
import pymysql
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Test function to verify RDS Proxy connectivity and connection pooling.
    
    This function demonstrates how to connect to an RDS instance through
    RDS Proxy using credentials stored in AWS Secrets Manager.
    """
    try:
        # Get database credentials from Secrets Manager
        secrets_client = boto3.client('secretsmanager')
        secret_response = secrets_client.get_secret_value(
            SecretId=os.environ['SECRET_ARN']
        )
        
        secret = json.loads(secret_response['SecretString'])
        
        # Connect to database through RDS Proxy
        connection = pymysql.connect(
            host=os.environ['PROXY_ENDPOINT'],
            user=secret['username'],
            password=secret['password'],
            database=os.environ['DB_NAME'],
            port=3306,
            cursorclass=pymysql.cursors.DictCursor
        )
        
        with connection.cursor() as cursor:
            # Execute test queries
            cursor.execute("SELECT 1 as connection_test, CONNECTION_ID() as connection_id, NOW() as timestamp")
            result = cursor.fetchone()
            
            # Get connection information
            cursor.execute("SELECT USER() as user_info, DATABASE() as database_info")
            connection_info = cursor.fetchone()
            
        connection.close()
        
        logger.info(f"Successfully connected through RDS Proxy: {result}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully connected through RDS Proxy',
                'connection_test': result,
                'connection_info': connection_info,
                'proxy_endpoint': os.environ['PROXY_ENDPOINT']
            }, default=str)
        }
        
    except Exception as e:
        logger.error(f"Database connection failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to connect to database through RDS Proxy'
            })
        }
'''

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for the RDS Proxy demo",
        )

        CfnOutput(
            self,
            "DatabaseEndpoint",
            value=self.rds_instance.instance_endpoint.hostname,
            description="RDS instance endpoint (direct connection)",
        )

        CfnOutput(
            self,
            "ProxyEndpoint",
            value=self.rds_proxy.endpoint,
            description="RDS Proxy endpoint (recommended for applications)",
        )

        CfnOutput(
            self,
            "DatabaseSecretArn",
            value=self.db_secret.secret_arn,
            description="ARN of the database credentials secret",
        )

        CfnOutput(
            self,
            "TestLambdaFunction",
            value=self.test_lambda.function_name,
            description="Lambda function name for testing connectivity",
        )

        CfnOutput(
            self,
            "TestCommand",
            value=f"aws lambda invoke --function-name {self.test_lambda.function_name} --payload '{{}}' /tmp/response.json && cat /tmp/response.json",
            description="Command to test the RDS Proxy connection",
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get deployment environment from context or use defaults
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    env = Environment(account=account, region=region) if account and region else None
    
    # Create the stack
    DatabaseConnectionPoolingStack(
        app,
        "DatabaseConnectionPoolingStack",
        env=env,
        description="Database Connection Pooling with RDS Proxy - CDK Python Implementation",
        tags={
            "Project": "RDS-Proxy-Demo",
            "Environment": "Development",
            "CreatedBy": "AWS-CDK",
        },
    )
    
    app.synth()


if __name__ == "__main__":
    main()