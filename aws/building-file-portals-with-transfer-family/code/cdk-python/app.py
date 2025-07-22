#!/usr/bin/env python3
"""
AWS CDK Python Application for Secure Self-Service File Portals
This application deploys a complete AWS Transfer Family Web App solution with
IAM Identity Center integration and S3 Access Grants for secure file sharing.
"""

import os
from typing import Any, Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_ssoadmin as sso_admin
from aws_cdk import aws_transfer as transfer
from constructs import Construct


class SecureFilePortalStack(Stack):
    """
    CDK Stack for deploying a secure self-service file portal using AWS Transfer Family Web Apps.
    
    This stack creates:
    - S3 bucket with encryption and versioning
    - IAM Identity Center configuration
    - S3 Access Grants setup
    - Transfer Family Web App
    - Required IAM roles and policies
    - CORS configuration for web access
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        identity_center_instance_arn: Optional[str] = None,
        identity_store_id: Optional[str] = None,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Secure File Portal Stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            identity_center_instance_arn: Existing IAM Identity Center instance ARN
            identity_store_id: Existing IAM Identity Store ID
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[:8].lower()
        
        # Store parameters for cross-stack references
        self.identity_center_instance_arn = identity_center_instance_arn
        self.identity_store_id = identity_store_id

        # Create S3 bucket for file storage
        self.file_storage_bucket = self._create_file_storage_bucket(unique_suffix)
        
        # Create IAM roles
        self.location_role = self._create_access_grants_location_role(unique_suffix)
        self.webapp_role = self._create_transfer_family_webapp_role()
        
        # Create Transfer Family Web App
        self.web_app = self._create_transfer_family_web_app(unique_suffix)
        
        # Configure CORS for the S3 bucket
        self._configure_bucket_cors()
        
        # Create outputs
        self._create_outputs()

    def _create_file_storage_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket with enterprise security features.
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            S3 bucket with security configurations
        """
        bucket = s3.Bucket(
            self,
            "FileStorageBucket",
            bucket_name=f"file-portal-bucket-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            server_access_logs_bucket=None,  # Will be configured separately if needed
            enforce_ssl=True,
        )
        
        # Add bucket policy to enforce SSL connections
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, bucket.arn_for_objects("*")],
                conditions={
                    "Bool": {"aws:SecureTransport": "false"}
                }
            )
        )
        
        # Tag the bucket
        Tags.of(bucket).add("Purpose", "TransferFamilyWebApp")
        Tags.of(bucket).add("Component", "FileStorage")
        
        return bucket

    def _create_access_grants_location_role(self, unique_suffix: str) -> iam.Role:
        """
        Create IAM role for S3 Access Grants location.
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            IAM role for Access Grants operations
        """
        role = iam.Role(
            self,
            "AccessGrantsLocationRole",
            role_name=f"S3AccessGrantsLocationRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("s3.amazonaws.com"),
            description="IAM role for S3 Access Grants location operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3FullAccess")
            ],
        )
        
        # Add additional permissions for Access Grants operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetAccessGrant",
                    "s3:ListAccessGrants",
                    "s3:CreateAccessGrant",
                    "s3:DeleteAccessGrant",
                    "s3:PutAccessGrantsLocation",
                    "s3:GetAccessGrantsLocation",
                    "s3:ListAccessGrantsLocations",
                    "s3:DeleteAccessGrantsLocation",
                ],
                resources=["*"],
            )
        )
        
        Tags.of(role).add("Purpose", "AccessGrantsLocation")
        
        return role

    def _create_transfer_family_webapp_role(self) -> iam.Role:
        """
        Create IAM role for Transfer Family Web App.
        
        Returns:
            IAM role for Transfer Family Web App operations
        """
        role = iam.Role(
            self,
            "TransferFamilyWebAppRole",
            role_name="AWSTransferFamilyWebAppIdentityBearerRole",
            assumed_by=iam.ServicePrincipal("transfer.amazonaws.com"),
            description="IAM role for AWS Transfer Family Web App identity operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSTransferFamilyWebAppIdentityBearerRole"
                )
            ],
        )
        
        # Add additional permissions for S3 Access Grants integration
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetDataAccess",
                    "s3:ListBucket",
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "sso:DescribeInstance",
                    "sso:ListInstances",
                    "identitystore:DescribeUser",
                    "identitystore:DescribeGroup",
                    "identitystore:ListUsers",
                    "identitystore:ListGroups",
                ],
                resources=["*"],
            )
        )
        
        Tags.of(role).add("Purpose", "TransferFamilyWebApp")
        
        return role

    def _create_transfer_family_web_app(self, unique_suffix: str) -> transfer.CfnWebApp:
        """
        Create Transfer Family Web App with IAM Identity Center integration.
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            Transfer Family Web App
        """
        # Create web app configuration
        web_app = transfer.CfnWebApp(
            self,
            "TransferFamilyWebApp",
            access_role=self.webapp_role.role_arn,
            identity_provider_type="IDENTITY_CENTER",
            web_app_units=1,
            tags=[
                cdk.CfnTag(key="Name", value=f"file-portal-webapp-{unique_suffix}"),
                cdk.CfnTag(key="Purpose", value="SecureFilePortal"),
                cdk.CfnTag(key="Component", value="WebApp"),
            ],
        )
        
        # Configure Identity Center integration if provided
        if self.identity_center_instance_arn:
            web_app.identity_provider_details = {
                "IdentityCenterConfig": {
                    "InstanceArn": self.identity_center_instance_arn
                }
            }
        
        return web_app

    def _configure_bucket_cors(self) -> None:
        """
        Configure CORS policy for the S3 bucket to allow web app access.
        """
        # Create CORS configuration
        cors_rule = s3.CorsRule(
            allowed_headers=["*"],
            allowed_methods=[
                s3.HttpMethods.GET,
                s3.HttpMethods.PUT,
                s3.HttpMethods.POST,
                s3.HttpMethods.DELETE,
                s3.HttpMethods.HEAD,
            ],
            allowed_origins=[f"https://{self.web_app.attr_access_endpoint}"],
            exposed_headers=[
                "last-modified",
                "content-length",
                "etag",
                "x-amz-version-id",
                "content-type",
                "x-amz-request-id",
                "x-amz-id-2",
                "date",
                "x-amz-cf-id",
                "x-amz-storage-class",
            ],
            max_age=3000,
        )
        
        # Apply CORS configuration to bucket
        self.file_storage_bucket.add_cors_rule(
            allowed_headers=cors_rule.allowed_headers,
            allowed_methods=cors_rule.allowed_methods,
            allowed_origins=cors_rule.allowed_origins,
            exposed_headers=cors_rule.exposed_headers,
            max_age=cors_rule.max_age,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        cdk.CfnOutput(
            self,
            "FileStorageBucketName",
            value=self.file_storage_bucket.bucket_name,
            description="Name of the S3 bucket for file storage",
            export_name=f"{self.stack_name}-FileStorageBucketName",
        )
        
        cdk.CfnOutput(
            self,
            "FileStorageBucketArn",
            value=self.file_storage_bucket.bucket_arn,
            description="ARN of the S3 bucket for file storage",
            export_name=f"{self.stack_name}-FileStorageBucketArn",
        )
        
        cdk.CfnOutput(
            self,
            "WebAppId",
            value=self.web_app.ref,
            description="Transfer Family Web App ID",
            export_name=f"{self.stack_name}-WebAppId",
        )
        
        cdk.CfnOutput(
            self,
            "WebAppAccessEndpoint",
            value=self.web_app.attr_access_endpoint,
            description="Transfer Family Web App access endpoint URL",
            export_name=f"{self.stack_name}-WebAppAccessEndpoint",
        )
        
        cdk.CfnOutput(
            self,
            "WebAppRoleArn",
            value=self.webapp_role.role_arn,
            description="ARN of the Transfer Family Web App IAM role",
            export_name=f"{self.stack_name}-WebAppRoleArn",
        )
        
        cdk.CfnOutput(
            self,
            "LocationRoleArn",
            value=self.location_role.role_arn,
            description="ARN of the S3 Access Grants location IAM role",
            export_name=f"{self.stack_name}-LocationRoleArn",
        )


class SecureFilePortalApp(App):
    """
    CDK Application for the Secure File Portal solution.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()
        
        # Get environment configuration
        env = Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )
        
        # Get Identity Center configuration from environment
        identity_center_instance_arn = os.environ.get("IDENTITY_CENTER_INSTANCE_ARN")
        identity_store_id = os.environ.get("IDENTITY_STORE_ID")
        
        # Create the main stack
        secure_file_portal_stack = SecureFilePortalStack(
            self,
            "SecureFilePortalStack",
            env=env,
            identity_center_instance_arn=identity_center_instance_arn,
            identity_store_id=identity_store_id,
            description="Secure self-service file portal using AWS Transfer Family Web Apps",
        )
        
        # Add stack-level tags
        Tags.of(secure_file_portal_stack).add("Project", "SecureFilePortal")
        Tags.of(secure_file_portal_stack).add("Environment", "Demo")
        Tags.of(secure_file_portal_stack).add("Owner", "CloudRecipe")
        Tags.of(secure_file_portal_stack).add("CostCenter", "IT")


def main() -> None:
    """Main entry point for the CDK application."""
    app = SecureFilePortalApp()
    app.synth()


if __name__ == "__main__":
    main()