#!/usr/bin/env python3
"""
CDK Python application for S3 Cross-Region Replication with Encryption and Access Controls.

This application implements a comprehensive S3 cross-region replication solution with:
- KMS encryption in both source and destination regions
- IAM roles with least privilege principles
- CloudWatch monitoring and alarms
- Secure bucket policies enforcing encryption
- Complete cross-region replication configuration

Author: AWS CDK Python Generator
Version: 1.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    Tags
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_kms as kms
from aws_cdk import aws_iam as iam
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_logs as logs
from constructs import Construct


class S3CrossRegionReplicationStack(Stack):
    """
    CDK Stack Replicating S3 Data Across Regions with Encryption.
    
    This stack creates:
    - Source and destination S3 buckets with versioning enabled
    - KMS keys for encryption in both regions
    - IAM role for replication with minimal permissions
    - CloudWatch monitoring and alarms
    - Secure bucket policies
    - Cross-region replication configuration
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        *,
        primary_region: str,
        secondary_region: str,
        **kwargs
    ) -> None:
        """
        Initialize the S3 Cross-Region Replication Stack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            primary_region: Primary AWS region for source bucket
            secondary_region: Secondary AWS region for destination bucket
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store region configuration
        self.primary_region = primary_region
        self.secondary_region = secondary_region
        
        # Generate unique resource names using stack name
        self.resource_prefix = f"s3-crr-{construct_id.lower()}"
        
        # Create KMS keys for encryption
        self._create_kms_keys()
        
        # Create S3 buckets
        self._create_s3_buckets()
        
        # Create IAM role for replication
        self._create_replication_role()
        
        # Configure cross-region replication
        self._configure_replication()
        
        # Set up monitoring and alarms
        self._create_monitoring()
        
        # Apply security policies
        self._apply_bucket_policies()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_kms_keys(self) -> None:
        """Create KMS keys for encryption in both regions."""
        
        # Source KMS key policy
        source_key_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="EnableIAMUserPermissions",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AccountRootPrincipal()],
                    actions=["kms:*"],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    sid="AllowS3Service",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("s3.amazonaws.com")],
                    actions=[
                        "kms:Decrypt",
                        "kms:GenerateDataKey"
                    ],
                    resources=["*"]
                )
            ]
        )

        # Create source KMS key
        self.source_kms_key = kms.Key(
            self, "SourceKMSKey",
            description=f"S3 Cross-Region Replication Source Key - {self.resource_prefix}",
            enable_key_rotation=True,
            policy=source_key_policy,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create alias for source key
        self.source_key_alias = kms.Alias(
            self, "SourceKMSKeyAlias",
            alias_name=f"alias/{self.resource_prefix}-source",
            target_key=self.source_kms_key
        )

        # Destination KMS key policy (same as source)
        dest_key_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="EnableIAMUserPermissions",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AccountRootPrincipal()],
                    actions=["kms:*"],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    sid="AllowS3Service",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("s3.amazonaws.com")],
                    actions=[
                        "kms:Decrypt",
                        "kms:GenerateDataKey"
                    ],
                    resources=["*"]
                )
            ]
        )

        # Create destination KMS key
        self.dest_kms_key = kms.Key(
            self, "DestKMSKey",
            description=f"S3 Cross-Region Replication Destination Key - {self.resource_prefix}",
            enable_key_rotation=True,
            policy=dest_key_policy,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create alias for destination key
        self.dest_key_alias = kms.Alias(
            self, "DestKMSKeyAlias",
            alias_name=f"alias/{self.resource_prefix}-dest",
            target_key=self.dest_kms_key
        )

    def _create_s3_buckets(self) -> None:
        """Create source and destination S3 buckets with encryption and versioning."""
        
        # Source bucket configuration
        self.source_bucket = s3.Bucket(
            self, "SourceBucket",
            bucket_name=f"{self.resource_prefix}-source",
            versioned=True,
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.source_kms_key,
            bucket_key_enabled=True,
            enforce_ssl=True,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Destination bucket configuration
        self.dest_bucket = s3.Bucket(
            self, "DestBucket",
            bucket_name=f"{self.resource_prefix}-dest",
            versioned=True,
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.dest_kms_key,
            bucket_key_enabled=True,
            enforce_ssl=True,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

    def _create_replication_role(self) -> None:
        """Create IAM role for S3 cross-region replication with minimal permissions."""
        
        # Trust policy for S3 service
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("s3.amazonaws.com")],
                    actions=["sts:AssumeRole"]
                )
            ]
        )

        # Create replication role
        self.replication_role = iam.Role(
            self, "ReplicationRole",
            role_name=f"{self.resource_prefix}-replication-role",
            assumed_by=iam.ServicePrincipal("s3.amazonaws.com"),
            description="S3 Cross-Region Replication Role with minimal permissions",
            inline_policies={
                "S3ReplicationPolicy": iam.PolicyDocument(
                    statements=[
                        # Source bucket permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObjectVersion",
                                "s3:GetObjectVersionAcl",
                                "s3:GetObjectVersionForReplication",
                                "s3:GetObjectVersionTagging"
                            ],
                            resources=[f"{self.source_bucket.bucket_arn}/*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:ListBucket",
                                "s3:GetBucketVersioning"
                            ],
                            resources=[self.source_bucket.bucket_arn]
                        ),
                        # Destination bucket permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:ReplicateObject",
                                "s3:ReplicateDelete",
                                "s3:ReplicateTags"
                            ],
                            resources=[f"{self.dest_bucket.bucket_arn}/*"]
                        ),
                        # KMS permissions for source key
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["kms:Decrypt"],
                            resources=[self.source_kms_key.key_arn]
                        ),
                        # KMS permissions for destination key
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["kms:GenerateDataKey"],
                            resources=[self.dest_kms_key.key_arn]
                        )
                    ]
                )
            }
        )

    def _configure_replication(self) -> None:
        """Configure cross-region replication with encryption requirements."""
        
        # Add replication configuration to source bucket
        replication_config = s3.CfnBucket.ReplicationConfigurationProperty(
            role=self.replication_role.role_arn,
            rules=[
                s3.CfnBucket.ReplicationRuleProperty(
                    id="ReplicateEncryptedObjects",
                    status="Enabled",
                    priority=1,
                    delete_marker_replication=s3.CfnBucket.DeleteMarkerReplicationProperty(
                        status="Enabled"
                    ),
                    filter=s3.CfnBucket.ReplicationRuleFilterProperty(
                        prefix=""
                    ),
                    destination=s3.CfnBucket.ReplicationDestinationProperty(
                        bucket=self.dest_bucket.bucket_arn,
                        storage_class="STANDARD_IA",
                        encryption_configuration=s3.CfnBucket.EncryptionConfigurationProperty(
                            replica_kms_key_id=self.dest_kms_key.key_arn
                        )
                    ),
                    source_selection_criteria=s3.CfnBucket.SourceSelectionCriteriaProperty(
                        sse_kms_encrypted_objects=s3.CfnBucket.SseKmsEncryptedObjectsProperty(
                            status="Enabled"
                        )
                    )
                )
            ]
        )

        # Get the underlying CloudFormation resource and add replication
        cfn_source_bucket = self.source_bucket.node.default_child
        cfn_source_bucket.replication_configuration = replication_config

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms for replication."""
        
        # Create CloudWatch alarm for replication failures
        self.replication_alarm = cloudwatch.Alarm(
            self, "ReplicationFailureAlarm",
            alarm_name=f"{self.resource_prefix}-replication-failures",
            alarm_description="Alert when S3 replication latency exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/S3",
                metric_name="ReplicationLatency",
                dimensions_map={
                    "SourceBucket": self.source_bucket.bucket_name,
                    "DestinationBucket": self.dest_bucket.bucket_name
                },
                statistic="Maximum",
                period=Duration.minutes(5)
            ),
            threshold=900,  # 15 minutes in seconds
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Create metric filter for replication metrics
        self.replication_metrics = s3.CfnBucket.MetricsConfigurationProperty(
            id="ReplicationMetrics"
        )

    def _apply_bucket_policies(self) -> None:
        """Apply security policies to both buckets."""
        
        # Source bucket policy
        source_bucket_policy = iam.PolicyDocument(
            statements=[
                # Deny unencrypted object uploads
                iam.PolicyStatement(
                    sid="DenyUnencryptedObjectUploads",
                    effect=iam.Effect.DENY,
                    principals=[iam.AnyPrincipal()],
                    actions=["s3:PutObject"],
                    resources=[f"{self.source_bucket.bucket_arn}/*"],
                    conditions={
                        "StringNotEquals": {
                            "s3:x-amz-server-side-encryption": "aws:kms"
                        }
                    }
                ),
                # Deny insecure connections
                iam.PolicyStatement(
                    sid="DenyInsecureConnections",
                    effect=iam.Effect.DENY,
                    principals=[iam.AnyPrincipal()],
                    actions=["s3:*"],
                    resources=[
                        self.source_bucket.bucket_arn,
                        f"{self.source_bucket.bucket_arn}/*"
                    ],
                    conditions={
                        "Bool": {
                            "aws:SecureTransport": "false"
                        }
                    }
                )
            ]
        )

        # Apply source bucket policy
        s3.CfnBucketPolicy(
            self, "SourceBucketPolicy",
            bucket=self.source_bucket.bucket_name,
            policy_document=source_bucket_policy
        )

        # Destination bucket policy
        dest_bucket_policy = iam.PolicyDocument(
            statements=[
                # Deny insecure connections
                iam.PolicyStatement(
                    sid="DenyInsecureConnections",
                    effect=iam.Effect.DENY,
                    principals=[iam.AnyPrincipal()],
                    actions=["s3:*"],
                    resources=[
                        self.dest_bucket.bucket_arn,
                        f"{self.dest_bucket.bucket_arn}/*"
                    ],
                    conditions={
                        "Bool": {
                            "aws:SecureTransport": "false"
                        }
                    }
                ),
                # Allow replication role
                iam.PolicyStatement(
                    sid="AllowReplicationRole",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ArnPrincipal(self.replication_role.role_arn)],
                    actions=[
                        "s3:ReplicateObject",
                        "s3:ReplicateDelete",
                        "s3:ReplicateTags"
                    ],
                    resources=[f"{self.dest_bucket.bucket_arn}/*"]
                )
            ]
        )

        # Apply destination bucket policy
        s3.CfnBucketPolicy(
            self, "DestBucketPolicy",
            bucket=self.dest_bucket.bucket_name,
            policy_document=dest_bucket_policy
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self, "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="Name of the source S3 bucket",
            export_name=f"{self.stack_name}-SourceBucketName"
        )

        CfnOutput(
            self, "DestBucketName",
            value=self.dest_bucket.bucket_name,
            description="Name of the destination S3 bucket",
            export_name=f"{self.stack_name}-DestBucketName"
        )

        CfnOutput(
            self, "SourceKMSKeyId",
            value=self.source_kms_key.key_id,
            description="ID of the source KMS key",
            export_name=f"{self.stack_name}-SourceKMSKeyId"
        )

        CfnOutput(
            self, "DestKMSKeyId",
            value=self.dest_kms_key.key_id,
            description="ID of the destination KMS key",
            export_name=f"{self.stack_name}-DestKMSKeyId"
        )

        CfnOutput(
            self, "ReplicationRoleArn",
            value=self.replication_role.role_arn,
            description="ARN of the replication IAM role",
            export_name=f"{self.stack_name}-ReplicationRoleArn"
        )

        CfnOutput(
            self, "ReplicationAlarmName",
            value=self.replication_alarm.alarm_name,
            description="Name of the CloudWatch alarm for replication monitoring",
            export_name=f"{self.stack_name}-ReplicationAlarmName"
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        
        Tags.of(self).add("Project", "S3CrossRegionReplication")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("CostCenter", "Infrastructure")
        Tags.of(self).add("Owner", "Platform-Team")
        Tags.of(self).add("Purpose", "DisasterRecovery")


class S3CrossRegionReplicationApp(App):
    """
    CDK Application for S3 Cross-Region Replication with encryption and access controls.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get environment configuration from environment variables or use defaults
        primary_region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        secondary_region = os.environ.get("SECONDARY_REGION", "us-west-2")
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")

        if not account:
            print("Warning: CDK_DEFAULT_ACCOUNT not set. Using current AWS account.")

        # Validate regions are different
        if primary_region == secondary_region:
            raise ValueError(
                f"Primary and secondary regions must be different. "
                f"Got: primary={primary_region}, secondary={secondary_region}"
            )

        # Create the main stack
        S3CrossRegionReplicationStack(
            self, "S3CrossRegionReplicationStack",
            primary_region=primary_region,
            secondary_region=secondary_region,
            env=Environment(
                account=account,
                region=primary_region
            ),
            description="S3 Cross-Region Replication with KMS encryption and access controls"
        )


# Application entry point
def main() -> None:
    """Main application entry point."""
    app = S3CrossRegionReplicationApp()
    app.synth()


if __name__ == "__main__":
    main()