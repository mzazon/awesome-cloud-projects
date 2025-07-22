#!/usr/bin/env python3
"""
AWS CDK Python application for Multi-Part Upload Strategies with S3.

This CDK application creates the infrastructure needed to demonstrate
S3 multipart upload strategies for large files, including:
- S3 bucket with optimized configuration
- CloudWatch dashboard for monitoring
- Lifecycle policies for cleanup
- IAM roles and policies for secure access
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
)
from constructs import Construct


class MultiPartUploadStack(Stack):
    """
    CDK Stack for S3 Multi-Part Upload demonstration infrastructure.
    
    This stack creates:
    - S3 bucket optimized for large file uploads
    - Lifecycle policies for multipart upload cleanup
    - CloudWatch dashboard for monitoring
    - IAM role for secure access
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name suffix
        unique_suffix = self.node.addr[:8].lower()
        
        # Create S3 bucket for multipart uploads
        self.upload_bucket = self._create_upload_bucket(unique_suffix)
        
        # Create lifecycle policy for incomplete uploads cleanup
        self._configure_lifecycle_policy()
        
        # Create IAM role for upload operations
        self.upload_role = self._create_upload_role()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_monitoring_dashboard()
        
        # Output important values
        self._create_outputs()

    def _create_upload_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket optimized for large file multipart uploads.
        
        Args:
            suffix: Unique suffix for bucket name
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self,
            "MultiPartUploadBucket",
            bucket_name=f"multipart-upload-demo-{suffix}",
            # Enable versioning for data protection
            versioned=True,
            # Block all public access for security
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Enable server-side encryption
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Enable access logging for auditing
            server_access_logs_prefix="access-logs/",
            # Configure CORS for web applications
            cors=[
                s3.CorsRule(
                    allowed_methods=[
                        s3.HttpMethods.GET,
                        s3.HttpMethods.POST,
                        s3.HttpMethods.PUT,
                        s3.HttpMethods.DELETE,
                        s3.HttpMethods.HEAD,
                    ],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    exposed_headers=[
                        "ETag",
                        "x-amz-meta-custom-header",
                    ],
                    max_age=3000,
                )
            ],
            # Enable event notifications for monitoring
            event_bridge_enabled=True,
            # Configure intelligent tiering for cost optimization
            intelligent_tiering_configurations=[
                s3.IntelligentTieringConfiguration(
                    name="EntireBucket",
                    prefix="",
                    archive_access_tier_time=Duration.days(90),
                    deep_archive_access_tier_time=Duration.days(180),
                )
            ],
            # Remove bucket when stack is deleted (for demo purposes)
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add tags for cost allocation and management
        cdk.Tags.of(bucket).add("Purpose", "MultiPartUploadDemo")
        cdk.Tags.of(bucket).add("Environment", "Demo")
        cdk.Tags.of(bucket).add("CostCenter", "Engineering")

        return bucket

    def _configure_lifecycle_policy(self) -> None:
        """
        Configure lifecycle policies for automatic cleanup of incomplete uploads.
        """
        # Add lifecycle rule to abort incomplete multipart uploads after 7 days
        self.upload_bucket.add_lifecycle_rule(
            id="CleanupIncompleteMultipartUploads",
            enabled=True,
            abort_incomplete_multipart_upload_after=Duration.days(7),
            # Also transition objects to cheaper storage classes
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(30),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(90),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(365),
                ),
            ],
        )

        # Add lifecycle rule for old versions cleanup
        self.upload_bucket.add_lifecycle_rule(
            id="CleanupOldVersions",
            enabled=True,
            noncurrent_version_expiration=Duration.days(30),
            noncurrent_version_transitions=[
                s3.NoncurrentVersionTransition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(30),
                ),
            ],
        )

    def _create_upload_role(self) -> iam.Role:
        """
        Create IAM role with permissions for multipart upload operations.
        
        Returns:
            IAM Role construct
        """
        # Create role that can be assumed by EC2 instances or users
        upload_role = iam.Role(
            self,
            "MultiPartUploadRole",
            role_name=f"MultiPartUploadRole-{self.region}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("ec2.amazonaws.com"),
                iam.AccountRootPrincipal(),
            ),
            description="Role for performing S3 multipart upload operations",
        )

        # Create custom policy for multipart upload operations
        multipart_policy = iam.PolicyDocument(
            statements=[
                # Permissions for multipart upload operations
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:CreateMultipartUpload",
                        "s3:UploadPart",
                        "s3:CompleteMultipartUpload",
                        "s3:AbortMultipartUpload",
                        "s3:ListMultipartUploadParts",
                        "s3:ListBucketMultipartUploads",
                    ],
                    resources=[
                        self.upload_bucket.bucket_arn,
                        f"{self.upload_bucket.bucket_arn}/*",
                    ],
                ),
                # Permissions for object operations
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:GetObjectVersion",
                        "s3:GetObjectAttributes",
                    ],
                    resources=[f"{self.upload_bucket.bucket_arn}/*"],
                ),
                # Permissions for bucket operations
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:ListBucket",
                        "s3:GetBucketLocation",
                        "s3:GetBucketVersioning",
                    ],
                    resources=[self.upload_bucket.bucket_arn],
                ),
                # Permissions for CloudWatch metrics
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudwatch:PutMetricData",
                        "cloudwatch:GetMetricStatistics",
                        "cloudwatch:ListMetrics",
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            "cloudwatch:namespace": "AWS/S3"
                        }
                    },
                ),
            ]
        )

        # Attach the custom policy to the role
        upload_role.attach_inline_policy(
            iam.Policy(
                self,
                "MultiPartUploadPolicy",
                document=multipart_policy,
                policy_name="MultiPartUploadOperations",
            )
        )

        # Add tags for identification
        cdk.Tags.of(upload_role).add("Purpose", "MultiPartUploadDemo")

        return upload_role

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for monitoring S3 multipart uploads.
        
        Returns:
            CloudWatch Dashboard construct
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "MultiPartUploadDashboard",
            dashboard_name="S3-MultipartUpload-Monitoring",
            default_interval=Duration.hours(1),
        )

        # Create widgets for bucket metrics
        bucket_size_widget = cloudwatch.GraphWidget(
            title="S3 Bucket Size",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="BucketSizeBytes",
                    dimensions_map={
                        "BucketName": self.upload_bucket.bucket_name,
                        "StorageType": "StandardStorage",
                    },
                    statistic="Average",
                    period=Duration.hours(1),
                )
            ],
            width=12,
            height=6,
        )

        object_count_widget = cloudwatch.GraphWidget(
            title="S3 Object Count",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="NumberOfObjects",
                    dimensions_map={
                        "BucketName": self.upload_bucket.bucket_name,
                        "StorageType": "AllStorageTypes",
                    },
                    statistic="Average",
                    period=Duration.hours(1),
                )
            ],
            width=12,
            height=6,
        )

        # Create widget for request metrics
        request_metrics_widget = cloudwatch.GraphWidget(
            title="S3 Request Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="AllRequests",
                    dimensions_map={
                        "BucketName": self.upload_bucket.bucket_name,
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="4xxErrors",
                    dimensions_map={
                        "BucketName": self.upload_bucket.bucket_name,
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="5xxErrors",
                    dimensions_map={
                        "BucketName": self.upload_bucket.bucket_name,
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
            ],
            width=12,
            height=6,
        )

        # Add widgets to dashboard
        dashboard.add_widgets(
            bucket_size_widget,
            object_count_widget,
            request_metrics_widget,
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource values."""
        CfnOutput(
            self,
            "BucketName",
            value=self.upload_bucket.bucket_name,
            description="Name of the S3 bucket for multipart uploads",
            export_name=f"{self.stack_name}-BucketName",
        )

        CfnOutput(
            self,
            "BucketArn",
            value=self.upload_bucket.bucket_arn,
            description="ARN of the S3 bucket for multipart uploads",
            export_name=f"{self.stack_name}-BucketArn",
        )

        CfnOutput(
            self,
            "UploadRoleArn",
            value=self.upload_role.role_arn,
            description="ARN of the IAM role for multipart upload operations",
            export_name=f"{self.stack_name}-UploadRoleArn",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
        )

        CfnOutput(
            self,
            "BucketUrl",
            value=f"https://s3.console.aws.amazon.com/s3/buckets/{self.upload_bucket.bucket_name}",
            description="URL to the S3 bucket in AWS Console",
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()

    # Get environment configuration
    env = Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
    )

    # Create the stack
    MultiPartUploadStack(
        app,
        "MultiPartUploadStack",
        env=env,
        description="Infrastructure for S3 Multi-Part Upload Strategies demonstration",
        tags={
            "Project": "CloudRecipes",
            "Recipe": "multi-part-upload-strategies",
            "Environment": "Demo",
        },
    )

    app.synth()


if __name__ == "__main__":
    main()