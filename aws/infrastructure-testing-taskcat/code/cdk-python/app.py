#!/usr/bin/env python3
"""
TaskCat Infrastructure Testing CDK Application

This CDK application creates infrastructure for testing CloudFormation templates
using TaskCat across multiple AWS regions. It includes a sample VPC architecture
and supporting resources for comprehensive infrastructure testing.
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Environment,
    aws_ec2 as ec2,
    aws_s3 as s3,
    aws_iam as iam,
    aws_secretsmanager as secretsmanager,
    RemovalPolicy,
    CfnOutput,
    Duration,
)


class TaskCatTestingStack(Stack):
    """
    CDK Stack for TaskCat Infrastructure Testing
    
    This stack creates:
    - VPC with public and private subnets
    - S3 bucket for TaskCat artifacts
    - IAM roles for testing
    - Security groups for test resources
    - Secrets for testing dynamic parameters
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Environment name parameter for resource tagging
        environment_name = cdk.CfnParameter(
            self,
            "EnvironmentName",
            type="String",
            default="TaskCatDemo",
            description="Environment name for resource tagging",
        )

        # VPC CIDR parameter
        vpc_cidr = cdk.CfnParameter(
            self,
            "VpcCidr",
            type="String",
            default="10.0.0.0/16",
            description="CIDR block for the VPC",
        )

        # Create NAT Gateway parameter
        create_nat_gateway = cdk.CfnParameter(
            self,
            "CreateNatGateway",
            type="String",
            default="true",
            allowed_values=["true", "false"],
            description="Create NAT Gateway for private subnets",
        )

        # Create condition for NAT Gateway
        create_nat_condition = cdk.CfnCondition(
            self,
            "CreateNatGatewayCondition",
            expression=cdk.Fn.condition_equals(create_nat_gateway, "true"),
        )

        # Create VPC with custom CIDR
        vpc = ec2.Vpc(
            self,
            "TaskCatVPC",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr.value_as_string),
            max_azs=2,
            nat_gateways=1,  # Will be conditionally created
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="PublicSubnet",
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="PrivateSubnet",
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add tags to VPC
        cdk.Tags.of(vpc).add("Name", f"{environment_name.value_as_string}-VPC")
        cdk.Tags.of(vpc).add("Environment", environment_name.value_as_string)

        # Create S3 bucket for TaskCat artifacts
        taskcat_bucket = s3.Bucket(
            self,
            "TaskCatArtifactsBucket",
            bucket_name=f"taskcat-artifacts-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
        )

        # Add tags to S3 bucket
        cdk.Tags.of(taskcat_bucket).add("Name", f"{environment_name.value_as_string}-TaskCat-Bucket")
        cdk.Tags.of(taskcat_bucket).add("Environment", environment_name.value_as_string)

        # Create security group for testing
        test_security_group = ec2.SecurityGroup(
            self,
            "TaskCatTestSecurityGroup",
            vpc=vpc,
            description="Security group for TaskCat testing resources",
            allow_all_outbound=True,
        )

        # Add ingress rules for common protocols
        test_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(80),
            "Allow HTTP traffic",
        )

        test_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(443),
            "Allow HTTPS traffic",
        )

        test_security_group.add_ingress_rule(
            ec2.Peer.ipv4(vpc_cidr.value_as_string),
            ec2.Port.tcp(22),
            "Allow SSH from VPC",
        )

        # Add tags to security group
        cdk.Tags.of(test_security_group).add("Name", f"{environment_name.value_as_string}-Test-SG")
        cdk.Tags.of(test_security_group).add("Environment", environment_name.value_as_string)

        # Create IAM role for TaskCat testing
        taskcat_role = iam.Role(
            self,
            "TaskCatTestingRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for TaskCat testing resources",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("ReadOnlyAccess"),
            ],
        )

        # Add custom policy for TaskCat operations
        taskcat_policy = iam.Policy(
            self,
            "TaskCatTestingPolicy",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudformation:*",
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket",
                        "ec2:CreateKeyPair",
                        "ec2:DeleteKeyPair",
                        "ec2:DescribeKeyPairs",
                        "secretsmanager:GetSecretValue",
                        "secretsmanager:CreateSecret",
                        "secretsmanager:DeleteSecret",
                    ],
                    resources=["*"],
                ),
            ],
        )

        taskcat_role.attach_inline_policy(taskcat_policy)

        # Create secret for database password testing
        database_secret = secretsmanager.Secret(
            self,
            "TaskCatDatabaseSecret",
            description="Database password for TaskCat testing",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                length=16,
                exclude_characters=" \"'\\@/",
                include_space=False,
                require_each_included_type=True,
            ),
        )

        # Add tags to secret
        cdk.Tags.of(database_secret).add("Name", f"{environment_name.value_as_string}-DB-Secret")
        cdk.Tags.of(database_secret).add("Environment", environment_name.value_as_string)

        # Create EC2 key pair for testing (optional)
        key_pair = ec2.CfnKeyPair(
            self,
            "TaskCatTestKeyPair",
            key_name=f"taskcat-test-{cdk.Aws.REGION}",
            key_type="rsa",
            key_format="pem",
        )

        # Create additional S3 bucket for application testing
        app_bucket = s3.Bucket(
            self,
            "TaskCatApplicationBucket",
            bucket_name=f"taskcat-app-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add lifecycle configuration to application bucket
        app_bucket.add_lifecycle_rule(
            id="DeleteOldObjects",
            expiration=Duration.days(30),
            enabled=True,
        )

        # Create VPC Endpoints for S3 and EC2
        vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
        )

        vpc.add_interface_endpoint(
            "EC2Endpoint",
            service=ec2.InterfaceVpcEndpointAwsService.EC2,
        )

        # Outputs for TaskCat testing and validation
        CfnOutput(
            self,
            "VPCId",
            value=vpc.vpc_id,
            description="VPC ID for TaskCat testing",
            export_name=f"{environment_name.value_as_string}-VPC-ID",
        )

        CfnOutput(
            self,
            "PublicSubnets",
            value=",".join([subnet.subnet_id for subnet in vpc.public_subnets]),
            description="Public subnet IDs",
            export_name=f"{environment_name.value_as_string}-Public-Subnets",
        )

        CfnOutput(
            self,
            "PrivateSubnets",
            value=",".join([subnet.subnet_id for subnet in vpc.private_subnets]),
            description="Private subnet IDs",
            export_name=f"{environment_name.value_as_string}-Private-Subnets",
        )

        CfnOutput(
            self,
            "TaskCatBucketName",
            value=taskcat_bucket.bucket_name,
            description="S3 bucket for TaskCat artifacts",
            export_name=f"{environment_name.value_as_string}-TaskCat-Bucket",
        )

        CfnOutput(
            self,
            "ApplicationBucketName",
            value=app_bucket.bucket_name,
            description="S3 bucket for application testing",
            export_name=f"{environment_name.value_as_string}-App-Bucket",
        )

        CfnOutput(
            self,
            "SecurityGroupId",
            value=test_security_group.security_group_id,
            description="Security group for testing resources",
            export_name=f"{environment_name.value_as_string}-Security-Group",
        )

        CfnOutput(
            self,
            "TaskCatRoleArn",
            value=taskcat_role.role_arn,
            description="IAM role ARN for TaskCat testing",
            export_name=f"{environment_name.value_as_string}-TaskCat-Role",
        )

        CfnOutput(
            self,
            "KeyPairName",
            value=key_pair.key_name,
            description="EC2 Key Pair name for testing",
            export_name=f"{environment_name.value_as_string}-KeyPair",
        )

        CfnOutput(
            self,
            "DatabaseSecretArn",
            value=database_secret.secret_arn,
            description="Database secret ARN for testing",
            export_name=f"{environment_name.value_as_string}-DB-Secret",
        )


class TaskCatDemoApp(cdk.App):
    """
    CDK Application for TaskCat Infrastructure Testing
    """

    def __init__(self):
        super().__init__()

        # Get account and region from environment or defaults
        account = self.node.try_get_context("account") or cdk.Aws.ACCOUNT_ID
        region = self.node.try_get_context("region") or cdk.Aws.REGION

        # Create the main testing stack
        TaskCatTestingStack(
            self,
            "TaskCatTestingStack",
            env=Environment(account=account, region=region),
            description="Infrastructure for TaskCat CloudFormation testing",
        )


# Create and synthesize the CDK app
app = TaskCatDemoApp()
app.synth()