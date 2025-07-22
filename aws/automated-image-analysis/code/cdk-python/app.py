#!/usr/bin/env python3
"""
AWS CDK Application for Image Analysis with Amazon Rekognition

This CDK application deploys the infrastructure needed to build an image analysis 
solution using Amazon Rekognition. It creates an S3 bucket for storing images and
configures the necessary IAM permissions for Rekognition to access the bucket.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_iam as iam,
    aws_s3_notifications as s3n,
)
from constructs import Construct


class ImageAnalysisStack(Stack):
    """
    CDK Stack for Image Analysis Application with Amazon Rekognition.
    
    This stack creates the infrastructure needed for image analysis including:
    - S3 bucket for storing images with versioning and lifecycle policies
    - IAM role with permissions for Rekognition to access S3
    - Bucket policies for secure access
    - CloudFormation outputs for easy integration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        """
        Initialize the Image Analysis Stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this construct
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Get stack name for resource naming
        stack_name = self.stack_name.lower()
        
        # Create S3 bucket for storing images
        self.images_bucket = self._create_images_bucket(stack_name)
        
        # Create IAM role for Rekognition service
        self.rekognition_role = self._create_rekognition_role()
        
        # Create bucket policy for Rekognition access
        self._create_bucket_policy()
        
        # Create CloudFormation outputs
        self._create_outputs()

    def _create_images_bucket(self, stack_name: str) -> s3.Bucket:
        """
        Create S3 bucket for storing images with appropriate configuration.
        
        Args:
            stack_name: Name of the stack for bucket naming
            
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "ImagesBucket",
            bucket_name=f"rekognition-images-{stack_name}-{self.account}",
            versioning=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(7)
                ),
                s3.LifecycleRule(
                    id="ArchiveOldObjects",
                    enabled=True,
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

        # Add tags for cost tracking and management
        cdk.Tags.of(bucket).add("Application", "ImageAnalysis")
        cdk.Tags.of(bucket).add("Purpose", "RekognitionImageStorage")
        cdk.Tags.of(bucket).add("Environment", "Demo")

        return bucket

    def _create_rekognition_role(self) -> iam.Role:
        """
        Create IAM role for Amazon Rekognition service.
        
        Returns:
            iam.Role: IAM role for Rekognition service
        """
        role = iam.Role(
            self,
            "RekognitionServiceRole",
            role_name=f"RekognitionRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("rekognition.amazonaws.com"),
            description="IAM role for Amazon Rekognition to access S3 bucket",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonRekognitionReadOnlyAccess"
                )
            ]
        )

        # Add custom policy for S3 access
        s3_policy = iam.PolicyStatement(
            sid="S3BucketAccess",
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:ListBucket"
            ],
            resources=[
                self.images_bucket.bucket_arn,
                f"{self.images_bucket.bucket_arn}/*"
            ]
        )

        role.add_to_policy(s3_policy)

        # Add tags
        cdk.Tags.of(role).add("Application", "ImageAnalysis")
        cdk.Tags.of(role).add("Purpose", "RekognitionServiceAccess")

        return role

    def _create_bucket_policy(self) -> None:
        """Create bucket policy for secure access."""
        # Allow Rekognition service to access the bucket
        rekognition_policy = iam.PolicyStatement(
            sid="AllowRekognitionAccess",
            effect=iam.Effect.ALLOW,
            principals=[iam.ServicePrincipal("rekognition.amazonaws.com")],
            actions=[
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            resources=[f"{self.images_bucket.bucket_arn}/*"],
            conditions={
                "StringEquals": {
                    "aws:SourceAccount": self.account
                }
            }
        )

        # Allow current AWS account root to manage the bucket
        account_access_policy = iam.PolicyStatement(
            sid="AllowAccountAccess", 
            effect=iam.Effect.ALLOW,
            principals=[iam.AccountRootPrincipal()],
            actions=["s3:*"],
            resources=[
                self.images_bucket.bucket_arn,
                f"{self.images_bucket.bucket_arn}/*"
            ]
        )

        # Apply bucket policy
        bucket_policy = iam.PolicyDocument(
            statements=[rekognition_policy, account_access_policy]
        )
        
        self.images_bucket.add_to_resource_policy(rekognition_policy)
        self.images_bucket.add_to_resource_policy(account_access_policy)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for easy reference."""
        CfnOutput(
            self,
            "ImagesBucketName",
            value=self.images_bucket.bucket_name,
            description="Name of the S3 bucket for storing images",
            export_name=f"{self.stack_name}-ImagesBucketName"
        )

        CfnOutput(
            self,
            "ImagesBucketArn", 
            value=self.images_bucket.bucket_arn,
            description="ARN of the S3 bucket for storing images",
            export_name=f"{self.stack_name}-ImagesBucketArn"
        )

        CfnOutput(
            self,
            "RekognitionRoleArn",
            value=self.rekognition_role.role_arn,
            description="ARN of the IAM role for Rekognition service",
            export_name=f"{self.stack_name}-RekognitionRoleArn"
        )

        CfnOutput(
            self,
            "SampleUploadCommand",
            value=f"aws s3 cp your-image.jpg s3://{self.images_bucket.bucket_name}/images/",
            description="Sample command to upload images to the bucket"
        )

        CfnOutput(
            self,
            "SampleAnalysisCommand",
            value=f"aws rekognition detect-labels --image \"{{S3Object:{{Bucket:'{self.images_bucket.bucket_name}',Name:'images/your-image.jpg'}}}}\" --region {self.region}",
            description="Sample command to analyze images with Rekognition"
        )


class ImageAnalysisApp(cdk.App):
    """
    CDK Application for Image Analysis with Amazon Rekognition.
    
    This application creates all the necessary infrastructure for building
    an image analysis solution using Amazon Rekognition and S3.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
        )

        # Create the main stack
        ImageAnalysisStack(
            self,
            "ImageAnalysisStack",
            env=env,
            description="Infrastructure for Image Analysis with Amazon Rekognition",
            tags={
                "Application": "ImageAnalysis",
                "CreatedBy": "AWS-CDK",
                "Purpose": "Demo"
            }
        )


# Create and run the application
if __name__ == "__main__":
    app = ImageAnalysisApp()
    app.synth()