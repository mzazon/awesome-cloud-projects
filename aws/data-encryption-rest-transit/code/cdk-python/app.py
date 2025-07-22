#!/usr/bin/env python3
"""
AWS CDK Python Application for Data Encryption at Rest and in Transit

This CDK application implements comprehensive data encryption strategies using:
- AWS KMS for centralized key management
- S3 with server-side encryption (SSE-KMS)
- RDS with encryption at rest
- EC2 with encrypted EBS volumes
- AWS Secrets Manager for credential management
- CloudTrail for audit logging
- AWS Certificate Manager for TLS/SSL certificates

The solution demonstrates industry-standard encryption practices while maintaining
operational efficiency and regulatory compliance.
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    aws_kms as kms,
    aws_s3 as s3,
    aws_rds as rds,
    aws_ec2 as ec2,
    aws_secretsmanager as secretsmanager,
    aws_cloudtrail as cloudtrail,
    aws_certificatemanager as acm,
    aws_logs as logs,
    aws_iam as iam,
    Duration,
    Tags,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct
from typing import Dict, Any
import json


class DataEncryptionStack(Stack):
    """
    CDK Stack implementing comprehensive data encryption at rest and in transit.
    
    This stack creates a complete encryption architecture including:
    - Customer-managed KMS key for encryption
    - Encrypted S3 bucket with public access blocking
    - Encrypted RDS MySQL database
    - EC2 instance with encrypted EBS volumes
    - VPC with proper security groups
    - Secrets Manager for database credentials
    - CloudTrail for audit logging
    - SSL/TLS certificate management (optional)
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        domain_name: str = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Add stack tags for resource management
        Tags.of(self).add("Project", "DataEncryptionDemo")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("Purpose", "EncryptionAtRestAndInTransit")

        # Create customer-managed KMS key for encryption
        self.kms_key = self._create_kms_key()
        
        # Create VPC for networking
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create encrypted S3 bucket
        self.s3_bucket = self._create_encrypted_s3_bucket()
        
        # Create database credentials in Secrets Manager
        self.db_secret = self._create_database_secret()
        
        # Create encrypted RDS database
        self.rds_instance = self._create_encrypted_rds_database()
        
        # Create EC2 instance with encrypted EBS volumes
        self.ec2_instance = self._create_encrypted_ec2_instance()
        
        # Create CloudTrail for audit logging
        self.cloudtrail = self._create_cloudtrail()
        
        # Create SSL/TLS certificate if domain provided
        if domain_name:
            self.certificate = self._create_ssl_certificate(domain_name)
        
        # Create CloudFormation outputs
        self._create_outputs()

    def _create_kms_key(self) -> kms.Key:
        """
        Create a customer-managed KMS key for encryption operations.
        
        Returns:
            kms.Key: Customer-managed KMS key with proper permissions
        """
        # Create KMS key policy
        key_policy = iam.PolicyDocument(
            statements=[
                # Enable root permissions
                iam.PolicyStatement(
                    sid="EnableRootPermissions",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AccountRootPrincipal()],
                    actions=["kms:*"],
                    resources=["*"]
                ),
                # Allow services to use the key
                iam.PolicyStatement(
                    sid="AllowServiceUsage",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("s3.amazonaws.com")],
                    actions=[
                        "kms:Decrypt",
                        "kms:GenerateDataKey",
                        "kms:CreateGrant"
                    ],
                    resources=["*"]
                ),
                # Allow CloudTrail to use the key
                iam.PolicyStatement(
                    sid="AllowCloudTrailEncryption",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                    actions=[
                        "kms:GenerateDataKey",
                        "kms:CreateGrant",
                        "kms:Decrypt"
                    ],
                    resources=["*"]
                )
            ]
        )

        # Create KMS key
        kms_key = kms.Key(
            self,
            "EncryptionKey",
            description="Customer managed key for data encryption demo",
            policy=key_policy,
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY  # For demo purposes
        )

        # Create alias for the key
        kms.Alias(
            self,
            "EncryptionKeyAlias",
            alias_name="alias/encryption-demo-key",
            target_key=kms_key
        )

        return kms_key

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create a VPC with public and private subnets for the infrastructure.
        
        Returns:
            ec2.Vpc: VPC with proper subnet configuration
        """
        vpc = ec2.Vpc(
            self,
            "EncryptionVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Add VPC Flow Logs for security monitoring
        vpc.add_flow_log(
            "FlowLogs",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                log_group=logs.LogGroup(
                    self,
                    "VPCFlowLogsGroup",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY
                )
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL
        )

        return vpc

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for database and EC2 instances.
        
        Returns:
            Dict[str, ec2.SecurityGroup]: Dictionary of security groups
        """
        # Security group for RDS database
        db_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for encrypted RDS database",
            allow_all_outbound=False
        )

        # Allow MySQL access from within VPC
        db_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL access from VPC"
        )

        # Security group for EC2 instance
        ec2_security_group = ec2.SecurityGroup(
            self,
            "EC2SecurityGroup",
            vpc=self.vpc,
            description="Security group for encrypted EC2 instance",
            allow_all_outbound=True
        )

        # Allow SSH access (restrict to specific IP in production)
        ec2_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access (restrict in production)"
        )

        # Allow HTTPS traffic
        ec2_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic"
        )

        # Allow HTTP traffic
        ec2_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic"
        )

        return {
            "database": db_security_group,
            "ec2": ec2_security_group
        }

    def _create_encrypted_s3_bucket(self) -> s3.Bucket:
        """
        Create an S3 bucket with server-side encryption using KMS.
        
        Returns:
            s3.Bucket: Encrypted S3 bucket with security configurations
        """
        s3_bucket = s3.Bucket(
            self,
            "EncryptedDataBucket",
            bucket_name=None,  # Let CDK generate unique name
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            bucket_key_enabled=True,  # Reduce KMS API calls
            versioning=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            enforce_ssl=True,
            public_read_access=False,
            public_write_access=False,
            object_ownership=s3.ObjectOwnership.BUCKET_OWNER_ENFORCED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    status=s3.LifecycleRuleStatus.ENABLED,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )

        # Note: S3 event notifications can be added later for security monitoring
        # Example: s3_bucket.add_event_notification(s3.EventType.OBJECT_CREATED, destination)

        return s3_bucket

    def _create_database_secret(self) -> secretsmanager.Secret:
        """
        Create a secret in AWS Secrets Manager for database credentials.
        
        Returns:
            secretsmanager.Secret: Secret containing database credentials
        """
        # Generate database credentials
        secret = secretsmanager.Secret(
            self,
            "DatabaseCredentials",
            description="Database credentials for encryption demo",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template=json.dumps({
                    "username": "admin",
                    "engine": "mysql",
                    "host": "placeholder",
                    "port": 3306,
                    "dbname": "encrypteddemo"
                }),
                generate_string_key="password",
                exclude_characters='"@/\\',
                password_length=16,
                require_each_included_type=True
            ),
            encryption_key=self.kms_key,
            removal_policy=RemovalPolicy.DESTROY  # For demo purposes
        )

        return secret

    def _create_encrypted_rds_database(self) -> rds.DatabaseInstance:
        """
        Create an encrypted RDS MySQL database instance.
        
        Returns:
            rds.DatabaseInstance: Encrypted RDS database instance
        """
        # Create subnet group for RDS
        subnet_group = rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for encrypted RDS demo",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            )
        )

        # Create parameter group for enhanced security
        parameter_group = rds.ParameterGroup(
            self,
            "DatabaseParameterGroup",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            description="Parameter group for encrypted MySQL database",
            parameters={
                "slow_query_log": "1",
                "log_queries_not_using_indexes": "1",
                "innodb_encrypt_tables": "ON"
            }
        )

        # Create RDS instance with encryption
        rds_instance = rds.DatabaseInstance(
            self,
            "EncryptedDatabase",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO
            ),
            allocated_storage=20,
            storage_type=rds.StorageType.GP2,
            storage_encrypted=True,
            storage_encryption_key=self.kms_key,
            credentials=rds.Credentials.from_secret(self.db_secret),
            vpc=self.vpc,
            subnet_group=subnet_group,
            security_groups=[self.security_groups["database"]],
            parameter_group=parameter_group,
            backup_retention=Duration.days(7),
            copy_tags_to_snapshot=True,
            deletion_protection=False,  # For demo purposes
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            delete_automated_backups=True,  # For demo purposes
            monitoring_interval=Duration.seconds(60),
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            cloudwatch_logs_exports=["error", "general", "slow-query"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_WEEK
        )

        # Update secret with RDS endpoint
        secretsmanager.SecretTargetAttachment(
            self,
            "DatabaseSecretAttachment",
            secret=self.db_secret,
            target=rds_instance,
            target_type=secretsmanager.AttachmentTargetType.RDS_DB_INSTANCE
        )

        return rds_instance

    def _create_encrypted_ec2_instance(self) -> ec2.Instance:
        """
        Create an EC2 instance with encrypted EBS volumes.
        
        Returns:
            ec2.Instance: EC2 instance with encrypted storage
        """
        # Create key pair for EC2 access
        key_pair = ec2.KeyPair(
            self,
            "EncryptionDemoKeyPair",
            key_pair_name="encryption-demo-keypair",
            public_key_material=None,  # Let CDK generate
            format=ec2.KeyPairFormat.PEM,
            type=ec2.KeyPairType.RSA
        )

        # Get latest Amazon Linux 2 AMI
        ami = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE
        )

        # Create IAM role for EC2 instance
        ec2_role = iam.Role(
            self,
            "EC2InstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                )
            ]
        )

        # Grant permissions to access secrets
        self.db_secret.grant_read(ec2_role)
        self.s3_bucket.grant_read_write(ec2_role)

        # Create EC2 instance with encrypted EBS volume
        ec2_instance = ec2.Instance(
            self,
            "EncryptedEC2Instance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO
            ),
            machine_image=ami,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_group=self.security_groups["ec2"],
            key_name=key_pair.key_pair_name,
            role=ec2_role,
            user_data=ec2.UserData.for_linux(),
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=8,
                        volume_type=ec2.EbsDeviceVolumeType.GP2,
                        encrypted=True,
                        kms_key=self.kms_key,
                        delete_on_termination=True
                    )
                )
            ]
        )

        # Add user data script for initial setup
        ec2_instance.user_data.add_commands(
            "yum update -y",
            "yum install -y amazon-cloudwatch-agent",
            "yum install -y mysql",
            "yum install -y aws-cli",
            "# Install CloudWatch agent configuration",
            "amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c default"
        )

        return ec2_instance

    def _create_cloudtrail(self) -> cloudtrail.Trail:
        """
        Create CloudTrail for audit logging of encryption events.
        
        Returns:
            cloudtrail.Trail: CloudTrail with encryption event logging
        """
        # Create S3 bucket for CloudTrail logs
        cloudtrail_bucket = s3.Bucket(
            self,
            "CloudTrailBucket",
            bucket_name=None,  # Let CDK generate unique name
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            bucket_key_enabled=True,
            versioning=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            enforce_ssl=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="CloudTrailLogRetention",
                    status=s3.LifecycleRuleStatus.ENABLED,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    expiration=Duration.days(365)
                )
            ]
        )

        # Create CloudTrail
        trail = cloudtrail.Trail(
            self,
            "EncryptionAuditTrail",
            bucket=cloudtrail_bucket,
            is_multi_region_trail=True,
            include_global_service_events=True,
            enable_file_validation=True,
            kms_key=self.kms_key,
            send_to_cloud_watch_logs=True,
            cloud_watch_logs_retention=logs.RetentionDays.ONE_WEEK
        )

        # Add data events for S3 bucket
        trail.add_s3_event_selector(
            [cloudtrail.S3EventSelector(
                bucket=self.s3_bucket,
                object_prefix="",
                read_write_type=cloudtrail.ReadWriteType.ALL
            )]
        )

        return trail

    def _create_ssl_certificate(self, domain_name: str) -> acm.Certificate:
        """
        Create an SSL/TLS certificate using AWS Certificate Manager.
        
        Args:
            domain_name: Domain name for the certificate
            
        Returns:
            acm.Certificate: SSL/TLS certificate
        """
        certificate = acm.Certificate(
            self,
            "SSLCertificate",
            domain_name=domain_name,
            subject_alternative_names=[f"*.{domain_name}"],
            validation=acm.CertificateValidation.from_dns(),
            key_algorithm=acm.KeyAlgorithm.RSA_2048,
            transparency_logging_enabled=True
        )

        return certificate

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        # KMS Key outputs
        CfnOutput(
            self,
            "KMSKeyId",
            value=self.kms_key.key_id,
            description="KMS Key ID for encryption"
        )

        CfnOutput(
            self,
            "KMSKeyArn",
            value=self.kms_key.key_arn,
            description="KMS Key ARN for encryption"
        )

        # S3 Bucket outputs
        CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="Name of the encrypted S3 bucket"
        )

        CfnOutput(
            self,
            "S3BucketArn",
            value=self.s3_bucket.bucket_arn,
            description="ARN of the encrypted S3 bucket"
        )

        # RDS outputs
        CfnOutput(
            self,
            "RDSEndpoint",
            value=self.rds_instance.instance_endpoint.hostname,
            description="RDS instance endpoint"
        )

        CfnOutput(
            self,
            "RDSPort",
            value=str(self.rds_instance.instance_endpoint.port),
            description="RDS instance port"
        )

        # EC2 outputs
        CfnOutput(
            self,
            "EC2InstanceId",
            value=self.ec2_instance.instance_id,
            description="EC2 instance ID"
        )

        CfnOutput(
            self,
            "EC2PublicIP",
            value=self.ec2_instance.instance_public_ip,
            description="EC2 instance public IP"
        )

        # Secret outputs
        CfnOutput(
            self,
            "DatabaseSecretArn",
            value=self.db_secret.secret_arn,
            description="ARN of the database secret"
        )

        # VPC outputs
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID"
        )


def main():
    """Main function to create and deploy the CDK app."""
    app = App()
    
    # Get domain name from CDK context (optional)
    domain_name = app.node.try_get_context("domain_name")
    
    # Create the stack
    DataEncryptionStack(
        app,
        "DataEncryptionStack",
        domain_name=domain_name,
        description="Comprehensive data encryption at rest and in transit implementation",
        env=cdk.Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region")
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()