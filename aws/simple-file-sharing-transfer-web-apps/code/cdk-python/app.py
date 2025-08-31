#!/usr/bin/env python3
"""
Simple File Sharing with Transfer Family Web Apps - CDK Python Application

This CDK application creates a secure file sharing solution using AWS Transfer Family Web Apps
integrated with S3 storage, IAM Identity Center authentication, and S3 Access Grants for
fine-grained permissions.

The solution provides a fully managed, browser-based file sharing platform that requires
no infrastructure management while maintaining enterprise-grade security.
"""

import os
from typing import Optional

import aws_cdk as cdk
from cdk_nag import AwsSolutionsChecks, HipaaSecurityChecks, NIST80053R5Checks
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Tags,
    CustomResource,
    custom_resources as cr,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from aws_cdk import aws_sso as sso
from aws_cdk import aws_transfer as transfer
from aws_cdk import aws_s3control as s3control
from constructs import Construct


class FileSharingTransferWebAppStack(Stack):
    """
    CDK Stack for Simple File Sharing with Transfer Family Web Apps.
    
    This stack creates:
    - S3 bucket with versioning and encryption for secure file storage
    - IAM roles for Transfer Family and S3 Access Grants integration
    - Transfer Family Web App with IAM Identity Center authentication
    - S3 Access Grants configuration for fine-grained permissions
    - Demo user setup for testing purposes
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        identity_center_instance_arn: Optional[str] = None,
        identity_store_id: Optional[str] = None,
        create_demo_user: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the File Sharing Transfer Web App Stack.
        
        Args:
            scope: Parent construct
            construct_id: Unique identifier for this stack
            identity_center_instance_arn: ARN of existing IAM Identity Center instance
            identity_store_id: ID of the identity store (required if creating demo user)
            create_demo_user: Whether to create a demo user for testing
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Create S3 bucket for file storage
        self.bucket = self._create_s3_bucket(unique_suffix)
        
        # Create IAM roles required for Transfer Family and S3 Access Grants
        self.webapp_role = self._create_webapp_role()
        self.access_grants_location_role = self._create_access_grants_location_role()
        
        # Create S3 Access Grants configuration
        self.access_grants_instance = self._create_access_grants_instance(identity_center_instance_arn)
        self.access_grants_location = self._create_access_grants_location()
        
        # Create demo user if requested
        self.demo_user_id = None
        if create_demo_user and identity_store_id:
            self.demo_user_id = self._create_demo_user(identity_store_id, unique_suffix)
            
            # Create access grant for demo user
            self.access_grant = self._create_access_grant(identity_store_id)
        
        # Create Transfer Family Web App
        self.web_app = self._create_transfer_web_app(identity_center_instance_arn, unique_suffix)
        
        # Configure S3 CORS for Web App access
        self._configure_s3_cors()
        
        # Assign demo user to web app if created
        if self.demo_user_id:
            self.web_app_assignment = self._create_web_app_assignment()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_s3_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket with versioning, encryption, and secure configuration.
        
        Args:
            unique_suffix: Unique suffix for bucket name
            
        Returns:
            The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "FileStorageBucket",
            bucket_name=f"file-sharing-demo-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            enforce_ssl=True,
        )
        
        # Add bucket policy to enforce SSL
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, bucket.arn_for_objects("*")],
                conditions={
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            )
        )
        
        return bucket

    def _create_webapp_role(self) -> iam.Role:
        """
        Create IAM role for Transfer Family Web App with S3 Access Grants integration.
        
        Returns:
            The created IAM role
        """
        role = iam.Role(
            self,
            "TransferFamilyWebAppRole",
            role_name="TransferFamily-S3AccessGrants-WebAppRole",
            assumed_by=iam.ServicePrincipal("transfer.amazonaws.com"),
            description="Role for Transfer Family Web App to integrate with S3 Access Grants",
        )
        
        # Add policy for S3 Access Grants integration
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetAccessGrant",
                    "s3:GetDataAccess",
                ],
                resources=["*"],
            )
        )
        
        # Add policy for web app operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sso:DescribeInstance",
                    "sso:GetPermissionSet",
                    "identitystore:DescribeUser",
                    "identitystore:DescribeGroup",
                    "identitystore:ListGroupMemberships",
                    "identitystore:IsMemberInGroups",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_access_grants_location_role(self) -> iam.Role:
        """
        Create IAM role for S3 Access Grants location.
        
        Returns:
            The created IAM role
        """
        role = iam.Role(
            self,
            "S3AccessGrantsLocationRole",
            role_name="S3AccessGrantsLocationRole",
            assumed_by=iam.ServicePrincipal("s3.amazonaws.com"),
            description="Role for S3 Access Grants to access bucket locations",
        )
        
        # Add policy for S3 bucket access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetObjectVersion",
                    "s3:PutObjectAcl",
                    "s3:GetObjectAcl",
                ],
                resources=[
                    self.bucket.bucket_arn,
                    self.bucket.arn_for_objects("*"),
                ],
            )
        )
        
        return role

    def _create_access_grants_instance(self, identity_center_instance_arn: Optional[str]) -> CustomResource:
        """
        Create S3 Access Grants instance using custom resource.
        
        Args:
            identity_center_instance_arn: ARN of IAM Identity Center instance
            
        Returns:
            The custom resource for Access Grants instance
        """
        # Custom resource to create S3 Access Grants instance
        access_grants_provider = cr.Provider(
            self,
            "AccessGrantsProvider",
            on_event_handler=self._create_access_grants_lambda(),
        )
        
        access_grants_instance = CustomResource(
            self,
            "AccessGrantsInstance",
            service_token=access_grants_provider.service_token,
            properties={
                "Action": "CreateAccessGrantsInstance",
                "IdentityCenterArn": identity_center_instance_arn,
                "AccountId": self.account,
            },
        )
        
        return access_grants_instance

    def _create_access_grants_lambda(self):
        """Create Lambda function for S3 Access Grants operations."""
        from aws_cdk import aws_lambda as lambda_
        
        # Lambda function code for S3 Access Grants operations
        lambda_code = '''
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """Handler for S3 Access Grants operations."""
    try:
        request_type = event['RequestType']
        properties = event['ResourceProperties']
        action = properties.get('Action')
        
        s3control = boto3.client('s3control')
        
        if request_type == 'Create':
            if action == 'CreateAccessGrantsInstance':
                account_id = properties['AccountId']
                identity_center_arn = properties.get('IdentityCenterArn')
                
                # Create access grants instance
                try:
                    response = s3control.create_access_grants_instance(
                        AccountId=account_id,
                        IdentityCenterArn=identity_center_arn
                    )
                    logger.info(f"Created Access Grants instance: {response}")
                    return {
                        'PhysicalResourceId': f"AccessGrantsInstance-{account_id}",
                        'Data': response
                    }
                except s3control.exceptions.ConflictException:
                    logger.info("Access Grants instance already exists")
                    return {
                        'PhysicalResourceId': f"AccessGrantsInstance-{account_id}",
                        'Data': {'AccessGrantsInstanceArn': f"arn:aws:s3::{account_id}:access-grants/default"}
                    }
                    
        elif request_type == 'Delete':
            # Access Grants instances can only be deleted when empty
            logger.info("Access Grants instance deletion handled by AWS")
            
        return {'PhysicalResourceId': event.get('PhysicalResourceId', 'DefaultPhysicalId')}
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise e
'''
        
        lambda_function = lambda_.Function(
            self,
            "AccessGrantsLambda",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=cdk.Duration.minutes(5),
        )
        
        # Grant permissions to manage S3 Access Grants
        lambda_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:CreateAccessGrantsInstance",
                    "s3:DeleteAccessGrantsInstance",
                    "s3:GetAccessGrantsInstance",
                    "s3:ListAccessGrantsInstances",
                ],
                resources=["*"],
            )
        )
        
        return lambda_function

    def _create_access_grants_location(self) -> s3control.CfnAccessGrantsLocation:
        """
        Create S3 Access Grants location for the bucket.
        
        Returns:
            The created Access Grants location
        """
        location = s3control.CfnAccessGrantsLocation(
            self,
            "AccessGrantsLocation",
            location_scope=f"{self.bucket.bucket_arn}/*",
            iam_role_arn=self.access_grants_location_role.role_arn,
        )
        
        # Add dependency on the access grants instance
        location.add_dependency(self.access_grants_instance.node.default_child)
        
        return location

    def _create_demo_user(self, identity_store_id: str, unique_suffix: str) -> str:
        """
        Create demo user in IAM Identity Center using custom resource.
        
        Args:
            identity_store_id: ID of the identity store
            unique_suffix: Unique suffix for user name
            
        Returns:
            The demo user ID
        """
        from aws_cdk import aws_lambda as lambda_
        
        # Lambda function code for identity store operations
        lambda_code = '''
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """Handler for Identity Store operations."""
    try:
        request_type = event['RequestType']
        properties = event['ResourceProperties']
        
        identitystore = boto3.client('identitystore')
        
        if request_type == 'Create':
            identity_store_id = properties['IdentityStoreId']
            user_name = properties['UserName']
            
            # Create user
            response = identitystore.create_user(
                IdentityStoreId=identity_store_id,
                UserName=user_name,
                DisplayName="Demo File Sharing User",
                Name={
                    'FamilyName': 'User',
                    'GivenName': 'Demo'
                },
                Emails=[
                    {
                        'Value': 'demo@example.com',
                        'Type': 'work',
                        'Primary': True
                    }
                ]
            )
            
            user_id = response['UserId']
            logger.info(f"Created user: {user_id}")
            
            return {
                'PhysicalResourceId': user_id,
                'Data': {'UserId': user_id}
            }
            
        elif request_type == 'Delete':
            user_id = event['PhysicalResourceId']
            identity_store_id = properties['IdentityStoreId']
            
            try:
                identitystore.delete_user(
                    IdentityStoreId=identity_store_id,
                    UserId=user_id
                )
                logger.info(f"Deleted user: {user_id}")
            except identitystore.exceptions.ResourceNotFoundException:
                logger.info(f"User {user_id} not found, already deleted")
                
        return {'PhysicalResourceId': event.get('PhysicalResourceId', 'DefaultPhysicalId')}
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise e
'''
        
        lambda_function = lambda_.Function(
            self,
            "IdentityStoreLambda",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=cdk.Duration.minutes(5),
        )
        
        # Grant permissions to manage identity store users
        lambda_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "identitystore:CreateUser",
                    "identitystore:DeleteUser",
                    "identitystore:DescribeUser",
                ],
                resources=["*"],
            )
        )
        
        demo_user_provider = cr.Provider(
            self,
            "DemoUserProvider",
            on_event_handler=lambda_function,
        )
        
        demo_user = CustomResource(
            self,
            "DemoUser",
            service_token=demo_user_provider.service_token,
            properties={
                "IdentityStoreId": identity_store_id,
                "UserName": f"demo-user-{unique_suffix}",
            },
        )
        
        return demo_user.get_att("UserId").to_string()

    def _create_access_grant(self, identity_store_id: str) -> s3control.CfnAccessGrant:
        """
        Create S3 Access Grant for the demo user.
        
        Args:
            identity_store_id: ID of the identity store
            
        Returns:
            The created Access Grant
        """
        access_grant = s3control.CfnAccessGrant(
            self,
            "DemoUserAccessGrant",
            access_grants_location_id=self.access_grants_location.attr_access_grants_location_id,
            grantee={
                "granteeType": "DIRECTORY_USER",
                "granteeIdentifier": f"{identity_store_id}:user/{self.demo_user_id}",
            },
            permission="READWRITE",
        )
        
        # Add dependency on the access grants location
        access_grant.add_dependency(self.access_grants_location)
        
        return access_grant

    def _create_transfer_web_app(
        self, 
        identity_center_instance_arn: Optional[str],
        unique_suffix: str
    ) -> transfer.CfnWebApp:
        """
        Create Transfer Family Web App.
        
        Args:
            identity_center_instance_arn: ARN of IAM Identity Center instance
            unique_suffix: Unique suffix for app name
            
        Returns:
            The created Transfer Family Web App
        """
        web_app = transfer.CfnWebApp(
            self,
            "TransferFamilyWebApp",
            identity_provider_details={
                "identityCenterConfig": {
                    "instanceArn": identity_center_instance_arn,
                    "role": self.webapp_role.role_arn,
                }
            },
            tags=[
                cdk.CfnTag(key="Name", value=f"file-sharing-app-{unique_suffix}"),
                cdk.CfnTag(key="Purpose", value="FileSharing"),
            ],
        )
        
        return web_app

    def _configure_s3_cors(self) -> None:
        """Configure S3 CORS for Web App access."""
        # Note: CORS configuration will be set up via custom resource after web app creation
        # since we need the web app access endpoint
        from aws_cdk import aws_lambda as lambda_
        
        # Lambda function code for S3 CORS configuration
        lambda_code = '''
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """Handler for S3 CORS configuration."""
    try:
        request_type = event['RequestType']
        properties = event['ResourceProperties']
        
        s3 = boto3.client('s3')
        
        if request_type in ['Create', 'Update']:
            bucket_name = properties['BucketName']
            web_app_id = properties['WebAppId']
            
            # Get web app access endpoint
            transfer = boto3.client('transfer')
            web_app_response = transfer.describe_web_app(WebAppId=web_app_id)
            access_endpoint = web_app_response['WebApp']['AccessEndpoint']
            
            # Configure CORS
            cors_configuration = {
                'CORSRules': [
                    {
                        'AllowedHeaders': ['*'],
                        'AllowedMethods': ['GET', 'PUT', 'POST', 'DELETE', 'HEAD'],
                        'AllowedOrigins': [access_endpoint],
                        'ExposeHeaders': [
                            'last-modified', 'content-length', 'etag',
                            'x-amz-version-id', 'content-type', 'x-amz-request-id',
                            'x-amz-id-2', 'date', 'x-amz-cf-id', 'x-amz-storage-class'
                        ],
                        'MaxAgeSeconds': 3000
                    }
                ]
            }
            
            s3.put_bucket_cors(
                Bucket=bucket_name,
                CORSConfiguration=cors_configuration
            )
            
            logger.info(f"Configured CORS for bucket {bucket_name} with endpoint {access_endpoint}")
            
        elif request_type == 'Delete':
            bucket_name = properties['BucketName']
            try:
                s3.delete_bucket_cors(Bucket=bucket_name)
                logger.info(f"Deleted CORS configuration for bucket {bucket_name}")
            except s3.exceptions.NoSuchCORSConfiguration:
                logger.info(f"No CORS configuration found for bucket {bucket_name}")
                
        return {'PhysicalResourceId': f"cors-{properties['BucketName']}"}
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise e
'''
        
        lambda_function = lambda_.Function(
            self,
            "CorsConfigLambda",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=cdk.Duration.minutes(5),
        )
        
        # Grant permissions to manage S3 CORS
        lambda_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutBucketCORS",
                    "s3:DeleteBucketCORS",
                    "s3:GetBucketCORS",
                ],
                resources=[self.bucket.bucket_arn],
            )
        )
        
        # Grant permissions to describe Transfer web app
        lambda_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["transfer:DescribeWebApp"],
                resources=["*"],
            )
        )
        
        cors_provider = cr.Provider(
            self,
            "CorsProvider",
            on_event_handler=lambda_function,
        )
        
        cors_config = CustomResource(
            self,
            "CorsConfiguration",
            service_token=cors_provider.service_token,
            properties={
                "BucketName": self.bucket.bucket_name,
                "WebAppId": self.web_app.ref,
            },
        )
        
        # Add dependency on web app
        cors_config.node.add_dependency(self.web_app)

    def _create_web_app_assignment(self) -> transfer.CfnWebAppAssignment:
        """
        Create web app assignment for demo user.
        
        Returns:
            The created web app assignment
        """
        assignment = transfer.CfnWebAppAssignment(
            self,
            "DemoUserWebAppAssignment",
            web_app_id=self.web_app.ref,
            grantee={
                "type": "USER",
                "identifier": self.demo_user_id,
            },
        )
        
        # Add dependency on web app
        assignment.add_dependency(self.web_app)
        
        return assignment

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "S3BucketName",
            value=self.bucket.bucket_name,
            description="Name of the S3 bucket for file storage",
        )
        
        CfnOutput(
            self,
            "TransferWebAppId",
            value=self.web_app.ref,
            description="Transfer Family Web App ID",
        )
        
        CfnOutput(
            self,
            "TransferWebAppAccessEndpoint",
            value=self.web_app.attr_access_endpoint,
            description="Transfer Family Web App access endpoint URL",
        )
        
        if self.demo_user_id:
            CfnOutput(
                self,
                "DemoUserId",
                value=self.demo_user_id,
                description="Demo user ID in IAM Identity Center",
            )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", "SimpleFileSharing")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("Service", "TransferFamilyWebApps")


class FileSharingApp(cdk.App):
    """CDK Application for Simple File Sharing with Transfer Family Web Apps."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get configuration from environment variables or context
        identity_center_instance_arn = self.node.try_get_context("identity_center_instance_arn")
        identity_store_id = self.node.try_get_context("identity_store_id")
        create_demo_user = self.node.try_get_context("create_demo_user")
        enable_cdk_nag = self.node.try_get_context("enable_cdk_nag")
        
        # Create the main stack
        stack = FileSharingTransferWebAppStack(
            self,
            "SimpleFileSharingTransferWebAppStack",
            identity_center_instance_arn=identity_center_instance_arn,
            identity_store_id=identity_store_id,
            create_demo_user=create_demo_user if create_demo_user is not None else True,
            description="Simple File Sharing with Transfer Family Web Apps - "
                       "Secure, browser-based file sharing solution",
        )
        
        # Apply CDK Nag checks if enabled (default: true)
        if enable_cdk_nag is not False:
            # Apply AWS Solutions Checks (recommended for all stacks)
            AwsSolutionsChecks(verbose=True).visit(stack)
            
            # Optionally apply additional compliance checks
            if self.node.try_get_context("enable_hipaa_checks"):
                HipaaSecurityChecks(verbose=True).visit(stack)
                
            if self.node.try_get_context("enable_nist_checks"):
                NIST80053R5Checks(verbose=True).visit(stack)


def main() -> None:
    """Main application entry point."""
    app = FileSharingApp()
    app.synth()


if __name__ == "__main__":
    main()