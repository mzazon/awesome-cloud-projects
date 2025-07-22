#!/usr/bin/env python3
"""
AWS CDK Python application for Hybrid Cloud Storage with AWS Storage Gateway.

This CDK application deploys a complete hybrid cloud storage solution using:
- AWS Storage Gateway (File Gateway) running on EC2
- S3 bucket for cloud storage backend
- IAM roles for secure access
- CloudWatch monitoring and logging
- KMS encryption for data security
- Security groups for network access control

The solution enables on-premises applications to seamlessly access cloud storage
through standard file protocols (NFS/SMB) while maintaining local cache performance.
"""

import os
from aws_cdk import (
    App,
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3 as s3,
    aws_kms as kms,
    aws_logs as logs,
    aws_storagegateway as storagegateway,
)
from constructs import Construct
import json


class HybridCloudStorageStack(Stack):
    """
    CDK Stack for deploying AWS Storage Gateway hybrid cloud storage solution.
    
    This stack creates:
    - EC2 instance running Storage Gateway appliance
    - S3 bucket with versioning and encryption
    - IAM roles and policies for Storage Gateway
    - KMS key for encryption
    - CloudWatch log group for monitoring
    - Security groups for network access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters - can be customized via CDK context
        self.gateway_name = self.node.try_get_context("gateway_name") or "hybrid-storage-gateway"
        self.instance_type = self.node.try_get_context("instance_type") or "m5.large"
        self.cache_disk_size = int(self.node.try_get_context("cache_disk_size") or 100)
        self.allowed_cidr = self.node.try_get_context("allowed_cidr") or "10.0.0.0/8"

        # Get default VPC or create one if specified
        self.vpc = self._get_or_create_vpc()

        # Create KMS key for encryption
        self.kms_key = self._create_kms_key()

        # Create S3 bucket for Storage Gateway backend
        self.s3_bucket = self._create_s3_bucket()

        # Create IAM role for Storage Gateway
        self.gateway_role = self._create_storage_gateway_role()

        # Create CloudWatch log group
        self.log_group = self._create_cloudwatch_log_group()

        # Create security group for Storage Gateway
        self.security_group = self._create_security_group()

        # Create EC2 instance for Storage Gateway
        self.gateway_instance = self._create_storage_gateway_instance()

        # Create cache disk for the gateway
        self.cache_volume = self._create_cache_volume()

        # Outputs
        self._create_outputs()

    def _get_or_create_vpc(self) -> ec2.IVpc:
        """Get the default VPC or create a new one if specified."""
        create_vpc = self.node.try_get_context("create_vpc")
        
        if create_vpc:
            return ec2.Vpc(
                self, "StorageGatewayVpc",
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
        else:
            # Use default VPC
            return ec2.Vpc.from_lookup(self, "DefaultVpc", is_default=True)

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for encrypting Storage Gateway data."""
        key = kms.Key(
            self, "StorageGatewayKmsKey",
            description="KMS key for Storage Gateway encryption",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
        )

        # Create alias for the key
        kms.Alias(
            self, "StorageGatewayKmsKeyAlias",
            alias_name=f"alias/storage-gateway-{self.gateway_name}",
            target_key=key,
        )

        return key

    def _create_s3_bucket(self) -> s3.Bucket:
        """Create S3 bucket for Storage Gateway backend storage."""
        bucket = s3.Bucket(
            self, "StorageGatewayBucket",
            bucket_name=f"storage-gateway-{self.account}-{self.region}-{self.gateway_name}",
            versioning=True,
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
        )

        # Add lifecycle rule for cost optimization
        bucket.add_lifecycle_rule(
            id="TransitionToIA",
            enabled=True,
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(30),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(90),
                ),
            ],
        )

        return bucket

    def _create_storage_gateway_role(self) -> iam.Role:
        """Create IAM role for Storage Gateway with required permissions."""
        # Trust policy for Storage Gateway service
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("storagegateway.amazonaws.com")],
                    actions=["sts:AssumeRole"],
                )
            ]
        )

        # Create the role
        role = iam.Role(
            self, "StorageGatewayRole",
            role_name=f"StorageGatewayRole-{self.gateway_name}",
            assumed_by=iam.ServicePrincipal("storagegateway.amazonaws.com"),
            inline_policies={
                "StorageGatewayS3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetAccelerateConfiguration",
                                "s3:GetBucketLocation",
                                "s3:GetBucketVersioning",
                                "s3:ListBucket",
                                "s3:ListBucketVersions",
                                "s3:ListBucketMultipartUploads",
                            ],
                            resources=[self.s3_bucket.bucket_arn],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:AbortMultipartUpload",
                                "s3:DeleteObject",
                                "s3:DeleteObjectVersion",
                                "s3:GetObject",
                                "s3:GetObjectAcl",
                                "s3:GetObjectVersion",
                                "s3:ListMultipartUploadParts",
                                "s3:PutObject",
                                "s3:PutObjectAcl",
                            ],
                            resources=[f"{self.s3_bucket.bucket_arn}/*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kms:Decrypt",
                                "kms:DescribeKey",
                                "kms:Encrypt",
                                "kms:GenerateDataKey*",
                                "kms:ReEncrypt*",
                            ],
                            resources=[self.kms_key.key_arn],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogStreams",
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/storagegateway/*"
                            ],
                        ),
                    ]
                )
            },
        )

        # Attach AWS managed policy for Storage Gateway
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/StorageGatewayServiceRole"
            )
        )

        return role

    def _create_cloudwatch_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for Storage Gateway monitoring."""
        return logs.LogGroup(
            self, "StorageGatewayLogGroup",
            log_group_name=f"/aws/storagegateway/{self.gateway_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for Storage Gateway EC2 instance."""
        sg = ec2.SecurityGroup(
            self, "StorageGatewaySecurityGroup",
            vpc=self.vpc,
            description="Security group for Storage Gateway",
            allow_all_outbound=True,
        )

        # HTTP access for activation
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP access for gateway activation",
        )

        # HTTPS access for management
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS access for gateway management",
        )

        # NFS access from specified CIDR
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.allowed_cidr),
            connection=ec2.Port.tcp(2049),
            description="NFS access for file shares",
        )

        # SMB access from specified CIDR
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.allowed_cidr),
            connection=ec2.Port.tcp(445),
            description="SMB access for file shares",
        )

        # SSH access (optional, for debugging)
        if self.node.try_get_context("enable_ssh"):
            sg.add_ingress_rule(
                peer=ec2.Peer.ipv4(self.allowed_cidr),
                connection=ec2.Port.tcp(22),
                description="SSH access for debugging",
            )

        return sg

    def _create_storage_gateway_instance(self) -> ec2.Instance:
        """Create EC2 instance running Storage Gateway appliance."""
        # Get the latest Storage Gateway AMI
        storage_gateway_ami = ec2.MachineImage.lookup(
            name="aws-storage-gateway-*",
            owners=["amazon"],
        )

        # Create instance
        instance = ec2.Instance(
            self, "StorageGatewayInstance",
            instance_type=ec2.InstanceType(self.instance_type),
            machine_image=storage_gateway_ami,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            security_group=self.security_group,
            role=iam.Role(
                self, "StorageGatewayInstanceRole",
                assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
                managed_policies=[
                    iam.ManagedPolicy.from_aws_managed_policy_name(
                        "AmazonSSMManagedInstanceCore"
                    )
                ],
            ),
            user_data=ec2.UserData.for_linux(),
        )

        # Tag the instance
        instance.node.default_child.add_property_override(
            "Tags",
            [
                {"Key": "Name", "Value": f"StorageGateway-{self.gateway_name}"},
                {"Key": "Purpose", "Value": "HybridCloudStorage"},
            ],
        )

        return instance

    def _create_cache_volume(self) -> ec2.Volume:
        """Create EBS volume for Storage Gateway cache."""
        volume = ec2.Volume(
            self, "StorageGatewayCacheVolume",
            availability_zone=self.gateway_instance.instance_availability_zone,
            size=ec2.Size.gibibytes(self.cache_disk_size),
            volume_type=ec2.EbsDeviceVolumeType.GP3,
            encrypted=True,
            encryption_key=self.kms_key,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Attach volume to instance
        volume.attach_to_instance(self.gateway_instance, device="/dev/sdf")

        return volume

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self, "StorageGatewayInstanceId",
            value=self.gateway_instance.instance_id,
            description="Storage Gateway EC2 instance ID",
        )

        CfnOutput(
            self, "StorageGatewayPublicIp",
            value=self.gateway_instance.instance_public_ip,
            description="Storage Gateway public IP address",
        )

        CfnOutput(
            self, "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="S3 bucket name for Storage Gateway backend",
        )

        CfnOutput(
            self, "GatewayRoleArn",
            value=self.gateway_role.role_arn,
            description="IAM role ARN for Storage Gateway",
        )

        CfnOutput(
            self, "KmsKeyId",
            value=self.kms_key.key_id,
            description="KMS key ID for encryption",
        )

        CfnOutput(
            self, "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group name",
        )

        CfnOutput(
            self, "ActivationUrl",
            value=f"http://{self.gateway_instance.instance_public_ip}/?activationRegion={self.region}",
            description="Storage Gateway activation URL",
        )

        CfnOutput(
            self, "NFSMountCommand",
            value=f"sudo mount -t nfs {self.gateway_instance.instance_public_ip}:/{self.s3_bucket.bucket_name} /mnt/nfs",
            description="Example NFS mount command",
        )


def main() -> None:
    """Main function to create and deploy the CDK app."""
    app = App()

    # Get environment configuration
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")

    if not account or not region:
        raise ValueError(
            "Account and region must be specified either via CDK context or environment variables"
        )

    env = Environment(account=account, region=region)

    # Create the stack
    HybridCloudStorageStack(
        app,
        "HybridCloudStorageStack",
        env=env,
        description="Hybrid Cloud Storage solution using AWS Storage Gateway",
    )

    # Synthesize the app
    app.synth()


if __name__ == "__main__":
    main()