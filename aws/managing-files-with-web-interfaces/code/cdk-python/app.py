#!/usr/bin/env python3
"""
AWS CDK Python application for Self-Service File Management with Transfer Family Web Apps.

This application creates:
- S3 bucket with versioning and encryption
- IAM Identity Center integration
- S3 Access Grants instance and configuration
- Transfer Family Web App with custom branding
- Required IAM roles for secure access
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Tags,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from aws_cdk import aws_transfer as transfer
from aws_cdk import aws_s3control as s3control
from aws_cdk import aws_sso as sso
from aws_cdk import aws_ec2 as ec2
from constructs import Construct


class TransferFamilyFileManagementStack(Stack):
    """
    CDK Stack for Self-Service File Management with AWS Transfer Family Web Apps.
    
    This stack creates a complete file management solution with:
    - Secure S3 storage with encryption and versioning
    - IAM Identity Center integration for authentication
    - S3 Access Grants for fine-grained authorization
    - Transfer Family Web App for user-friendly file operations
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        identity_center_instance_arn: Optional[str] = None,
        identity_store_id: Optional[str] = None,
        enable_custom_branding: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the Transfer Family File Management Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            identity_center_instance_arn: ARN of existing IAM Identity Center instance
            identity_store_id: ID of the IAM Identity Center identity store
            enable_custom_branding: Whether to apply custom branding to the web app
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.identity_center_instance_arn = identity_center_instance_arn
        self.identity_store_id = identity_store_id
        self.enable_custom_branding = enable_custom_branding

        # Create core infrastructure
        self.s3_bucket = self._create_s3_bucket()
        self.access_grants_role = self._create_access_grants_role()
        self.identity_bearer_role = self._create_identity_bearer_role()
        
        # Create S3 Access Grants infrastructure
        self.access_grants_instance = self._create_access_grants_instance()
        self.access_grants_location = self._create_access_grants_location()
        
        # Get VPC information for web app
        self.vpc = self._get_default_vpc()
        
        # Create Transfer Family Web App
        self.web_app = self._create_transfer_web_app()
        
        # Add sample files to demonstrate folder structure
        self._create_sample_files()
        
        # Create stack outputs
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket with security best practices.
        
        Returns:
            S3 bucket configured with encryption, versioning, and public access blocking
        """
        bucket = s3.Bucket(
            self,
            "FileManagementBucket",
            bucket_name=f"file-management-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
        )

        # Add lifecycle configuration for cost optimization
        bucket.add_lifecycle_rule(
            id="TransitionToIA",
            enabled=True,
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(30)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(90)
                ),
            ],
        )

        # Add tags for resource management
        Tags.of(bucket).add("Component", "Storage")
        Tags.of(bucket).add("Purpose", "FileManagement")

        return bucket

    def _create_access_grants_role(self) -> iam.Role:
        """
        Create IAM role for S3 Access Grants service.
        
        Returns:
            IAM role that allows S3 Access Grants to access the bucket
        """
        role = iam.Role(
            self,
            "S3AccessGrantsRole",
            role_name=f"S3AccessGrantsRole-{cdk.Aws.REGION}-{cdk.Stack.of(self).stack_name}",
            assumed_by=iam.ServicePrincipal("s3.amazonaws.com"),
            description="Role for S3 Access Grants to manage bucket access",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3FullAccess")
            ],
        )

        # Add inline policy for additional permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetObjectVersion",
                    "s3:DeleteObjectVersion",
                ],
                resources=[
                    self.s3_bucket.bucket_arn,
                    f"{self.s3_bucket.bucket_arn}/*"
                ],
            )
        )

        Tags.of(role).add("Component", "AccessControl")
        Tags.of(role).add("Purpose", "AccessGrants")

        return role

    def _create_identity_bearer_role(self) -> iam.Role:
        """
        Create Identity Bearer role for Transfer Family to assume user identities.
        
        Returns:
            IAM role that enables Transfer Family to request credentials from S3 Access Grants
        """
        role = iam.Role(
            self,
            "TransferIdentityBearerRole",
            role_name=f"TransferIdentityBearerRole-{cdk.Aws.REGION}-{cdk.Stack.of(self).stack_name}",
            assumed_by=iam.ServicePrincipal("transfer.amazonaws.com"),
            description="Identity Bearer role for Transfer Family Web Apps to access S3 Access Grants",
        )

        # Add policy for S3 Access Grants integration
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetDataAccess"],
                resources=["*"],
                conditions={
                    "StringEquals": {
                        "s3:AccessGrantsInstanceId": cdk.Fn.ref("AccessGrantsInstance")
                    }
                }
            )
        )

        # Add policy for IAM Identity Center integration
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sso:DescribeInstance"],
                resources=["*"]
            )
        )

        Tags.of(role).add("Component", "Authentication")
        Tags.of(role).add("Purpose", "IdentityBearer")

        return role

    def _create_access_grants_instance(self) -> s3control.CfnAccessGrantsInstance:
        """
        Create S3 Access Grants instance with IAM Identity Center integration.
        
        Returns:
            S3 Access Grants instance configured for fine-grained access control
        """
        # Create the Access Grants instance
        instance = s3control.CfnAccessGrantsInstance(
            self,
            "AccessGrantsInstance",
            identity_center_arn=self.identity_center_instance_arn,
            tags=[
                cdk.CfnTag(key="Name", value=f"FileManagementGrants-{cdk.Stack.of(self).stack_name}"),
                cdk.CfnTag(key="Component", value="AccessControl"),
                cdk.CfnTag(key="Purpose", value="FileManagement"),
            ]
        )

        return instance

    def _create_access_grants_location(self) -> s3control.CfnAccessGrantsLocation:
        """
        Create S3 Access Grants location for the file management bucket.
        
        Returns:
            S3 Access Grants location that registers the bucket for fine-grained access
        """
        location = s3control.CfnAccessGrantsLocation(
            self,
            "AccessGrantsLocation",
            location_scope=f"{self.s3_bucket.bucket_arn}/user-files/*",
            iam_role_arn=self.access_grants_role.role_arn,
            tags=[
                cdk.CfnTag(key="Name", value="FileManagementLocation"),
                cdk.CfnTag(key="Component", value="AccessControl"),
                cdk.CfnTag(key="Purpose", value="FileManagement"),
            ]
        )

        # Ensure the location is created after the instance
        location.add_dependency(self.access_grants_instance)

        return location

    def _get_default_vpc(self) -> ec2.IVpc:
        """
        Get the default VPC for the web app endpoint.
        
        Returns:
            Default VPC in the current region
        """
        return ec2.Vpc.from_lookup(
            self,
            "DefaultVpc",
            is_default=True
        )

    def _create_transfer_web_app(self) -> transfer.CfnWebApp:
        """
        Create Transfer Family Web App with IAM Identity Center integration.
        
        Returns:
            Transfer Family Web App configured for secure file management
        """
        # Get first public subnet from default VPC
        public_subnets = self.vpc.public_subnets
        if not public_subnets:
            raise ValueError("No public subnets found in default VPC")

        # Prepare identity provider configuration
        identity_provider_details = {
            "identityCenterConfig": {
                "instanceArn": self.identity_center_instance_arn,
                "role": self.identity_bearer_role.role_arn
            }
        }

        # Create web app configuration
        web_app = transfer.CfnWebApp(
            self,
            "TransferWebApp",
            identity_provider_type="SERVICE_MANAGED",
            identity_provider_details=identity_provider_details,
            access_endpoint={
                "type": "VPC",
                "vpcId": self.vpc.vpc_id,
                "subnetIds": [public_subnets[0].subnet_id]
            },
            tags=[
                cdk.CfnTag(key="Name", value=f"FileManagementWebApp-{cdk.Stack.of(self).stack_name}"),
                cdk.CfnTag(key="Component", value="WebInterface"),
                cdk.CfnTag(key="Purpose", value="FileManagement"),
                cdk.CfnTag(key="Environment", value="Demo"),
            ]
        )

        # Add custom branding if enabled
        if self.enable_custom_branding:
            web_app.branding = {
                "title": "Secure File Management Portal",
                "description": "Upload, download, and manage your files securely through this enterprise portal",
                "logoUrl": "https://via.placeholder.com/200x60/0066CC/FFFFFF?text=Your+Organization",
                "faviconUrl": "https://via.placeholder.com/32x32/0066CC/FFFFFF?text=F"
            }

        # Ensure web app is created after required dependencies
        web_app.add_dependency(self.access_grants_instance)
        web_app.add_dependency(self.access_grants_location)

        return web_app

    def _create_sample_files(self) -> None:
        """
        Create sample files and folder structure in the S3 bucket.
        
        This demonstrates the file organization capabilities and provides
        a starting point for users to understand the system structure.
        """
        # Create sample README file
        s3.BucketDeployment(
            self,
            "SampleFiles",
            sources=[
                s3.Source.data(
                    "user-files/documents/README.txt",
                    """Welcome to the Secure File Management Portal!

This system provides a secure, easy-to-use interface for managing your files.

Getting Started:
1. Navigate through folders using the web interface
2. Upload files by dragging and dropping or using the upload button
3. Download files by clicking on them
4. Create new folders using the "New Folder" button

Folder Structure:
- /documents/ - Store your personal documents here
- /shared/ - Shared resources accessible to your team
- /archive/ - Long-term storage for older files

Security Features:
- All files are encrypted at rest and in transit
- Access is controlled through IAM Identity Center
- Fine-grained permissions ensure you only see authorized content
- All file operations are logged for audit purposes

For support, contact your IT administrator.
"""
                ),
                s3.Source.data(
                    "user-files/documents/sample-document.txt",
                    """Sample Document for File Management Demo

This is a sample document to demonstrate the file management capabilities
of the AWS Transfer Family Web Apps solution.

Features demonstrated:
- Secure file upload and download
- Browser-based file management
- Integration with corporate identity systems
- Fine-grained access controls
- Automated file organization

You can upload, download, and manage files like this one through the
user-friendly web interface without requiring any special software
or technical knowledge.
"""
                ),
                s3.Source.data(
                    "user-files/shared/team-resources.txt",
                    """Shared Team Resources

This folder contains shared resources for the team.
All authorized team members have access to files in this location.

Collaboration Guidelines:
- Use descriptive file names with dates
- Organize files into logical subfolders
- Remove outdated files to keep the space clean
- Follow your organization's data classification policies

The file management system automatically maintains version history
and provides audit trails for all file operations.
"""
                )
            ],
            destination_bucket=self.s3_bucket,
            retain_on_delete=False
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="Name of the S3 bucket for file storage",
            export_name=f"{self.stack_name}-S3BucketName"
        )

        CfnOutput(
            self,
            "S3BucketArn",
            value=self.s3_bucket.bucket_arn,
            description="ARN of the S3 bucket for file storage",
            export_name=f"{self.stack_name}-S3BucketArn"
        )

        CfnOutput(
            self,
            "AccessGrantsInstanceArn",
            value=self.access_grants_instance.attr_access_grants_instance_arn,
            description="ARN of the S3 Access Grants instance",
            export_name=f"{self.stack_name}-AccessGrantsInstanceArn"
        )

        CfnOutput(
            self,
            "IdentityBearerRoleArn",
            value=self.identity_bearer_role.role_arn,
            description="ARN of the Identity Bearer role for Transfer Family",
            export_name=f"{self.stack_name}-IdentityBearerRoleArn"
        )

        CfnOutput(
            self,
            "WebAppArn",
            value=self.web_app.attr_arn,
            description="ARN of the Transfer Family Web App",
            export_name=f"{self.stack_name}-WebAppArn"
        )

        CfnOutput(
            self,
            "WebAppEndpoint",
            value=self.web_app.attr_web_app_endpoint,
            description="URL endpoint for the Transfer Family Web App",
            export_name=f"{self.stack_name}-WebAppEndpoint"
        )


class TransferFamilyFileManagementApp(cdk.App):
    """
    CDK Application for Transfer Family File Management solution.
    
    This application can be configured through environment variables:
    - IDENTITY_CENTER_INSTANCE_ARN: ARN of existing IAM Identity Center instance
    - IDENTITY_STORE_ID: ID of the IAM Identity Center identity store
    - ENABLE_CUSTOM_BRANDING: Whether to apply custom branding (default: true)
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment or context
        identity_center_instance_arn = self.node.try_get_context("identity_center_instance_arn")
        identity_store_id = self.node.try_get_context("identity_store_id")
        enable_custom_branding = self.node.try_get_context("enable_custom_branding") != "false"

        # Create the main stack
        TransferFamilyFileManagementStack(
            self,
            "TransferFamilyFileManagementStack",
            identity_center_instance_arn=identity_center_instance_arn,
            identity_store_id=identity_store_id,
            enable_custom_branding=enable_custom_branding,
            description="Self-Service File Management with AWS Transfer Family Web Apps and S3 Access Grants",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION")
            ),
        )


# Create and run the application
app = TransferFamilyFileManagementApp()
app.synth()