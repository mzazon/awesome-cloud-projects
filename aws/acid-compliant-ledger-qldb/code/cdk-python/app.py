#!/usr/bin/env python3
"""
CDK Python application for Amazon QLDB ACID-compliant distributed database recipe.

This application creates:
- Amazon QLDB Ledger with encryption and deletion protection
- IAM roles for QLDB operations
- Kinesis Data Stream for journal streaming
- S3 bucket for journal exports
- Necessary policies and permissions

Author: AWS Recipe Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_qldb as qldb,
    aws_iam as iam,
    aws_s3 as s3,
    aws_kinesis as kinesis,
    RemovalPolicy,
    CfnOutput,
    Duration,
    Tags
)
from constructs import Construct
from typing import Optional


class QLDBAcidDatabaseStack(Stack):
    """
    CDK Stack for Amazon QLDB ACID-compliant distributed database.
    
    This stack implements a complete QLDB solution with:
    - Immutable ledger with cryptographic verification
    - Real-time journal streaming to Kinesis
    - S3 exports for compliance and archival
    - Proper IAM roles and security controls
    """
    
    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        ledger_name: Optional[str] = None,
        enable_deletion_protection: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the QLDB ACID Database Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            ledger_name: Optional custom name for the QLDB ledger
            enable_deletion_protection: Whether to enable deletion protection
            **kwargs: Additional arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)
        
        # Generate unique suffix for resource names
        unique_suffix = construct_id.lower().replace('_', '-')
        
        # Define resource names
        self.ledger_name = ledger_name or f"financial-ledger-{unique_suffix}"
        self.bucket_name = f"qldb-exports-{unique_suffix}"
        self.stream_name = f"qldb-journal-stream-{unique_suffix}"
        
        # Create the infrastructure components
        self._create_s3_bucket()
        self._create_kinesis_stream()
        self._create_iam_roles()
        self._create_qldb_ledger(enable_deletion_protection)
        self._create_outputs()
        self._add_tags()
    
    def _create_s3_bucket(self) -> None:
        """Create S3 bucket for QLDB journal exports with encryption and security."""
        self.export_bucket = s3.Bucket(
            self,
            "QLDBExportBucket",
            bucket_name=self.bucket_name,
            # Enable encryption at rest
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Block all public access for security
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Enable versioning for data protection
            versioned=True,
            # Lifecycle rules for cost optimization
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldExports",
                    status=s3.LifecycleRuleStatus.ENABLED,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        )
                    ]
                )
            ],
            # Configure removal policy based on environment
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
        )
    
    def _create_kinesis_stream(self) -> None:
        """Create Kinesis Data Stream for real-time journal streaming."""
        self.journal_stream = kinesis.Stream(
            self,
            "QLDBJournalStream",
            stream_name=self.stream_name,
            # Single shard for demo - scale based on throughput needs
            shard_count=1,
            # Retain data for 24 hours (default)
            retention_period=Duration.hours(24),
            # Enable server-side encryption
            encryption=kinesis.StreamEncryption.KMS,
        )
    
    def _create_iam_roles(self) -> None:
        """Create IAM roles and policies for QLDB operations."""
        
        # Create IAM role for QLDB to access Kinesis and S3
        self.qldb_service_role = iam.Role(
            self,
            "QLDBServiceRole",
            role_name=f"qldb-service-role-{self.node.unique_id}",
            assumed_by=iam.ServicePrincipal("qldb.amazonaws.com"),
            description="IAM role for QLDB to stream journal data and export to S3"
        )
        
        # Policy for Kinesis access
        kinesis_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "kinesis:PutRecord",
                "kinesis:PutRecords", 
                "kinesis:DescribeStream"
            ],
            resources=[self.journal_stream.stream_arn]
        )
        
        # Policy for S3 access
        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            resources=[
                self.export_bucket.bucket_arn,
                f"{self.export_bucket.bucket_arn}/*"
            ]
        )
        
        # Attach policies to the role
        self.qldb_service_role.add_to_policy(kinesis_policy)
        self.qldb_service_role.add_to_policy(s3_policy)
        
        # Optional: Create application role for QLDB access
        self.application_role = iam.Role(
            self,
            "QLDBApplicationRole",
            role_name=f"qldb-app-role-{self.node.unique_id}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("lambda.amazonaws.com"),
                iam.ServicePrincipal("ec2.amazonaws.com")
            ),
            description="IAM role for applications to access QLDB ledger"
        )
        
        # Policy for QLDB access
        qldb_access_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "qldb:SendCommand",
                "qldb:PartiQLSelect",
                "qldb:PartiQLInsert",
                "qldb:PartiQLUpdate",
                "qldb:PartiQLDelete",
                "qldb:GetDigest",
                "qldb:GetRevision",
                "qldb:GetBlock"
            ],
            resources=[f"arn:aws:qldb:{self.region}:{self.account}:ledger/{self.ledger_name}"]
        )
        
        self.application_role.add_to_policy(qldb_access_policy)
    
    def _create_qldb_ledger(self, enable_deletion_protection: bool) -> None:
        """
        Create Amazon QLDB ledger with proper configuration.
        
        Args:
            enable_deletion_protection: Whether to enable deletion protection
        """
        self.ledger = qldb.CfnLedger(
            self,
            "FinancialLedger",
            name=self.ledger_name,
            # Use STANDARD permissions mode for IAM-based access control
            permissions_mode="STANDARD",
            # Enable deletion protection for production environments
            deletion_protection=enable_deletion_protection,
            # Add tags for resource management
            tags=[
                cdk.CfnTag(key="Environment", value="Production"),
                cdk.CfnTag(key="Application", value="Financial"),
                cdk.CfnTag(key="DataClassification", value="Sensitive"),
                cdk.CfnTag(key="Compliance", value="SOX,PCI-DSS")
            ]
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "LedgerName",
            value=self.ledger.name,
            description="Name of the QLDB ledger",
            export_name=f"{self.stack_name}-LedgerName"
        )
        
        CfnOutput(
            self,
            "LedgerArn",
            value=f"arn:aws:qldb:{self.region}:{self.account}:ledger/{self.ledger.name}",
            description="ARN of the QLDB ledger",
            export_name=f"{self.stack_name}-LedgerArn"
        )
        
        CfnOutput(
            self,
            "ExportBucketName",
            value=self.export_bucket.bucket_name,
            description="S3 bucket for QLDB journal exports",
            export_name=f"{self.stack_name}-ExportBucket"
        )
        
        CfnOutput(
            self,
            "JournalStreamName",
            value=self.journal_stream.stream_name,
            description="Kinesis stream for QLDB journal data",
            export_name=f"{self.stack_name}-JournalStream"
        )
        
        CfnOutput(
            self,
            "ServiceRoleArn",
            value=self.qldb_service_role.role_arn,
            description="IAM role ARN for QLDB service operations",
            export_name=f"{self.stack_name}-ServiceRoleArn"
        )
        
        CfnOutput(
            self,
            "ApplicationRoleArn",
            value=self.application_role.role_arn,
            description="IAM role ARN for application access to QLDB",
            export_name=f"{self.stack_name}-ApplicationRoleArn"
        )
        
        # Output verification commands for easy testing
        CfnOutput(
            self,
            "VerificationCommands",
            value=" | ".join([
                f"aws qldb describe-ledger --name {self.ledger.name}",
                f"aws qldb get-digest --name {self.ledger.name}",
                f"aws s3 ls s3://{self.export_bucket.bucket_name}/",
                f"aws kinesis describe-stream --stream-name {self.journal_stream.stream_name}"
            ]),
            description="Commands to verify the QLDB infrastructure deployment"
        )
    
    def _add_tags(self) -> None:
        """Add consistent tags to all resources in the stack."""
        Tags.of(self).add("Project", "QLDB-ACID-Database")
        Tags.of(self).add("Recipe", "acid-compliant-distributed-databases-amazon-qldb")
        Tags.of(self).add("IaC-Tool", "CDK-Python")
        Tags.of(self).add("CostCenter", "Infrastructure")


class QLDBAcidDatabaseApp(cdk.App):
    """CDK Application for Amazon QLDB ACID-compliant database solution."""
    
    def __init__(self):
        """Initialize the CDK application."""
        super().__init__()
        
        # Define environment - customize as needed
        env = cdk.Environment(
            account=self.node.try_get_context("account"),
            region=self.node.try_get_context("region") or "us-east-1"
        )
        
        # Create the main stack
        QLDBAcidDatabaseStack(
            self,
            "QLDBAcidDatabaseStack",
            env=env,
            description="Amazon QLDB ACID-compliant distributed database infrastructure",
            # Customize ledger configuration
            ledger_name=self.node.try_get_context("ledger_name"),
            enable_deletion_protection=self.node.try_get_context("deletion_protection") != "false"
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = QLDBAcidDatabaseApp()
    app.synth()


if __name__ == "__main__":
    main()