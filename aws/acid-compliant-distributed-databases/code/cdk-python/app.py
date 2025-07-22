#!/usr/bin/env python3
"""
AWS CDK Application for Building ACID-Compliant Distributed Databases with Amazon QLDB

This CDK application deploys a complete QLDB ledger infrastructure with:
- Amazon QLDB ledger with deletion protection
- IAM roles for QLDB streaming operations
- S3 bucket for journal exports
- Kinesis Data Stream for real-time journal streaming
- CloudWatch monitoring and alarms

Author: AWS CDK Generator
Version: 2.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_qldb as qldb,
    aws_iam as iam,
    aws_s3 as s3,
    aws_kinesis as kinesis,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
    RemovalPolicy,
    Duration,
)
from constructs import Construct
from typing import Dict, Any
import json


class QLDBFinancialLedgerStack(Stack):
    """
    CDK Stack for deploying an ACID-compliant distributed database using Amazon QLDB.
    
    This stack creates a complete financial ledger infrastructure with cryptographic
    verification capabilities, real-time streaming, and S3 export functionality.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters with default values
        self.ledger_name = self.node.try_get_context("ledger_name") or "financial-ledger"
        self.enable_deletion_protection = (
            self.node.try_get_context("enable_deletion_protection") != "false"
        )
        self.kinesis_shard_count = int(
            self.node.try_get_context("kinesis_shard_count") or "1"
        )
        self.enable_kinesis_encryption = (
            self.node.try_get_context("enable_kinesis_encryption") != "false"
        )

        # Create S3 bucket for journal exports
        self.exports_bucket = self._create_s3_bucket()

        # Create Kinesis stream for real-time journal streaming
        self.kinesis_stream = self._create_kinesis_stream()

        # Create IAM role for QLDB operations
        self.qldb_service_role = self._create_qldb_service_role()

        # Create QLDB ledger
        self.ledger = self._create_qldb_ledger()

        # Create CloudWatch monitoring
        self._create_cloudwatch_monitoring()

        # Create outputs
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create an S3 bucket for storing QLDB journal exports.
        
        Returns:
            s3.Bucket: The created S3 bucket for journal exports
        """
        bucket = s3.Bucket(
            self,
            "QLDBExportsBucket",
            bucket_name=None,  # Let CDK generate unique name
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldExports",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INTELLIGENT_TIERING,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        ),
                    ],
                ),
            ],
        )

        # Add tags for compliance and cost management
        cdk.Tags.of(bucket).add("Purpose", "QLDB-Journal-Exports")
        cdk.Tags.of(bucket).add("Environment", "Production")
        cdk.Tags.of(bucket).add("Application", "Financial-Ledger")
        cdk.Tags.of(bucket).add("Compliance", "SOX-PCI-DSS")

        return bucket

    def _create_kinesis_stream(self) -> kinesis.Stream:
        """
        Create a Kinesis Data Stream for real-time QLDB journal streaming.
        
        Returns:
            kinesis.Stream: The created Kinesis stream
        """
        stream = kinesis.Stream(
            self,
            "QLDBJournalStream",
            stream_name=None,  # Let CDK generate unique name
            shard_count=self.kinesis_shard_count,
            retention_period=Duration.hours(168),  # 7 days
            encryption=kinesis.StreamEncryption.KMS if self.enable_kinesis_encryption else kinesis.StreamEncryption.UNENCRYPTED,
        )

        # Add tags for compliance and monitoring
        cdk.Tags.of(stream).add("Purpose", "QLDB-Journal-Streaming")
        cdk.Tags.of(stream).add("Environment", "Production")
        cdk.Tags.of(stream).add("Application", "Financial-Ledger")
        cdk.Tags.of(stream).add("DataType", "Financial-Transactions")

        return stream

    def _create_qldb_service_role(self) -> iam.Role:
        """
        Create an IAM role for QLDB to access S3 and Kinesis resources.
        
        Returns:
            iam.Role: The created IAM role for QLDB operations
        """
        # Create trust policy for QLDB service
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("qldb.amazonaws.com")],
                    actions=["sts:AssumeRole"],
                )
            ]
        )

        # Create the IAM role
        role = iam.Role(
            self,
            "QLDBServiceRole",
            assumed_by=iam.ServicePrincipal("qldb.amazonaws.com"),
            role_name=None,  # Let CDK generate unique name
            description="IAM role for QLDB to access S3 and Kinesis resources",
            inline_policies={
                "QLDBStreamPolicy": self._create_qldb_stream_policy(),
            },
        )

        # Add tags
        cdk.Tags.of(role).add("Purpose", "QLDB-Service-Role")
        cdk.Tags.of(role).add("Environment", "Production")
        cdk.Tags.of(role).add("Application", "Financial-Ledger")

        return role

    def _create_qldb_stream_policy(self) -> iam.PolicyDocument:
        """
        Create the IAM policy for QLDB streaming operations.
        
        Returns:
            iam.PolicyDocument: The policy document for QLDB operations
        """
        return iam.PolicyDocument(
            statements=[
                # S3 permissions for journal exports
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:PutObject",
                        "s3:GetObject",
                        "s3:ListBucket",
                        "s3:GetBucketVersioning",
                        "s3:PutObjectAcl",
                    ],
                    resources=[
                        self.exports_bucket.bucket_arn,
                        f"{self.exports_bucket.bucket_arn}/*",
                    ],
                ),
                # Kinesis permissions for journal streaming
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "kinesis:PutRecord",
                        "kinesis:PutRecords",
                        "kinesis:DescribeStream",
                        "kinesis:ListShards",
                    ],
                    resources=[self.kinesis_stream.stream_arn],
                ),
                # KMS permissions if encryption is enabled
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "kms:Encrypt",
                        "kms:Decrypt",
                        "kms:ReEncrypt*",
                        "kms:GenerateDataKey*",
                        "kms:DescribeKey",
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            "kms:ViaService": [
                                f"kinesis.{self.region}.amazonaws.com",
                                f"s3.{self.region}.amazonaws.com",
                            ]
                        }
                    },
                ) if self.enable_kinesis_encryption else None,
            ]
        )

    def _create_qldb_ledger(self) -> qldb.CfnLedger:
        """
        Create the Amazon QLDB ledger with security and compliance settings.
        
        Returns:
            qldb.CfnLedger: The created QLDB ledger
        """
        ledger = qldb.CfnLedger(
            self,
            "FinancialLedger",
            name=self.ledger_name,
            permissions_mode="STANDARD",
            deletion_protection=self.enable_deletion_protection,
            tags=[
                cdk.CfnTag(key="Environment", value="Production"),
                cdk.CfnTag(key="Application", value="Financial-Ledger"),
                cdk.CfnTag(key="Compliance", value="SOX-PCI-DSS"),
                cdk.CfnTag(key="DataClassification", value="Confidential"),
                cdk.CfnTag(key="BackupRequired", value="True"),
                cdk.CfnTag(key="MonitoringRequired", value="True"),
            ],
        )

        return ledger

    def _create_cloudwatch_monitoring(self) -> None:
        """
        Create CloudWatch alarms and dashboards for monitoring QLDB operations.
        """
        # Create CloudWatch alarm for QLDB read capacity
        read_capacity_alarm = cloudwatch.Alarm(
            self,
            "QLDBReadCapacityAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/QLDB",
                metric_name="ReadIOs",
                dimensions_map={
                    "LedgerName": self.ledger.name,
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1000,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="QLDB read capacity is approaching limits",
        )

        # Create CloudWatch alarm for QLDB write capacity
        write_capacity_alarm = cloudwatch.Alarm(
            self,
            "QLDBWriteCapacityAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/QLDB",
                metric_name="WriteIOs",
                dimensions_map={
                    "LedgerName": self.ledger.name,
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=500,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="QLDB write capacity is approaching limits",
        )

        # Create CloudWatch alarm for Kinesis stream errors
        kinesis_error_alarm = cloudwatch.Alarm(
            self,
            "KinesisStreamErrorAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/Kinesis",
                metric_name="WriteProvisionedThroughputExceeded",
                dimensions_map={
                    "StreamName": self.kinesis_stream.stream_name,
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            alarm_description="Kinesis stream is experiencing write throttling",
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for key resource identifiers.
        """
        CfnOutput(
            self,
            "LedgerName",
            value=self.ledger.name,
            description="Name of the QLDB ledger",
            export_name=f"{self.stack_name}-LedgerName",
        )

        CfnOutput(
            self,
            "LedgerArn",
            value=self.ledger.attr_arn,
            description="ARN of the QLDB ledger",
            export_name=f"{self.stack_name}-LedgerArn",
        )

        CfnOutput(
            self,
            "ExportsBucketName",
            value=self.exports_bucket.bucket_name,
            description="Name of the S3 bucket for journal exports",
            export_name=f"{self.stack_name}-ExportsBucketName",
        )

        CfnOutput(
            self,
            "ExportsBucketArn",
            value=self.exports_bucket.bucket_arn,
            description="ARN of the S3 bucket for journal exports",
            export_name=f"{self.stack_name}-ExportsBucketArn",
        )

        CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Name of the Kinesis stream for journal streaming",
            export_name=f"{self.stack_name}-KinesisStreamName",
        )

        CfnOutput(
            self,
            "KinesisStreamArn",
            value=self.kinesis_stream.stream_arn,
            description="ARN of the Kinesis stream for journal streaming",
            export_name=f"{self.stack_name}-KinesisStreamArn",
        )

        CfnOutput(
            self,
            "QLDBServiceRoleArn",
            value=self.qldb_service_role.role_arn,
            description="ARN of the IAM role for QLDB operations",
            export_name=f"{self.stack_name}-QLDBServiceRoleArn",
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = cdk.App()

    # Get environment configuration
    env = cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    )

    # Create the QLDB stack
    QLDBFinancialLedgerStack(
        app,
        "QLDBFinancialLedgerStack",
        env=env,
        description="ACID-compliant distributed database using Amazon QLDB for financial transactions",
        tags={
            "Project": "Financial-Ledger",
            "Environment": "Production",
            "Owner": "FinTech-Team",
            "CostCenter": "Engineering",
            "Compliance": "SOX-PCI-DSS",
        },
    )

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()