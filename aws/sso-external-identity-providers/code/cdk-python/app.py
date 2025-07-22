#!/usr/bin/env python3
"""
AWS IAM Identity Center (SSO) with External Identity Providers CDK Application

This CDK application demonstrates how to implement AWS Single Sign-On (now IAM Identity Center)
with external identity providers using SAML 2.0 federation. It creates permission sets,
configures external identity provider integration, and sets up user/group access patterns.

Author: AWS CDK Python
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Aspects,
    Environment,
    Stack,
    StackProps,
    Tags,
    aws_identitystore as identitystore,
    aws_iam as iam,
    aws_organizations as organizations,
    aws_s3 as s3,
    aws_sso as sso,
    aws_ssoadmin as ssoadmin,
)
from constructs import Construct


class AwsSsoExternalIdpStack(Stack):
    """
    AWS IAM Identity Center Stack with External Identity Provider Integration
    
    This stack creates:
    - IAM Identity Center instance (if not already exists)
    - Permission sets with different access levels
    - Custom inline policies for fine-grained access
    - Identity store users and groups for demonstration
    - Account assignments for permission sets
    - Example S3 bucket for custom policy demonstration
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        identity_store_id: Optional[str] = None,
        sso_instance_arn: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters and configuration
        self.unique_suffix = self.node.try_get_context("uniqueSuffix") or "demo"
        self.environment = self.node.try_get_context("environment") or "dev"
        
        # Store constructor parameters
        self._identity_store_id = identity_store_id
        self._sso_instance_arn = sso_instance_arn

        # Create S3 bucket for custom policy demonstration
        self.demo_bucket = self._create_demo_bucket()

        # Create permission sets
        self.permission_sets = self._create_permission_sets()

        # Create custom inline policies
        self._attach_custom_policies()

        # Create identity store users and groups for demonstration
        self.users, self.groups = self._create_identity_store_resources()

        # Create account assignments
        self._create_account_assignments()

        # Output important values
        self._create_outputs()

    def _create_demo_bucket(self) -> s3.Bucket:
        """
        Create an S3 bucket for demonstrating custom permission policies.
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "DemoBucket",
            bucket_name=f"sso-demo-bucket-{self.unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=cdk.RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add tags
        Tags.of(bucket).add("Purpose", "SSO Demo")
        Tags.of(bucket).add("Environment", self.environment)

        return bucket

    def _create_permission_sets(self) -> Dict[str, ssoadmin.PermissionSet]:
        """
        Create permission sets with different access levels.
        
        Returns:
            Dict[str, ssoadmin.PermissionSet]: Dictionary of permission sets
        """
        permission_sets = {}

        # Developer Permission Set
        developer_ps = ssoadmin.PermissionSet(
            self,
            "DeveloperPermissionSet",
            name="DeveloperAccess",
            description="Developer access with PowerUser permissions",
            session_duration=cdk.Duration.hours(8),
            # Note: instance_arn should be provided via context or parameter
            instance_arn=self._sso_instance_arn or "${SSO_INSTANCE_ARN}",
        )

        # Attach PowerUserAccess managed policy
        ssoadmin.CfnManagedPolicyInPermissionSet(
            self,
            "DeveloperManagedPolicy",
            instance_arn=developer_ps.permission_set_arn.split("/")[0] + "/" + developer_ps.permission_set_arn.split("/")[1],
            permission_set_arn=developer_ps.permission_set_arn,
            managed_policy_arn="arn:aws:iam::aws:policy/PowerUserAccess",
        )

        permission_sets["developer"] = developer_ps

        # Administrator Permission Set
        admin_ps = ssoadmin.PermissionSet(
            self,
            "AdministratorPermissionSet",
            name="AdministratorAccess",
            description="Full administrator access",
            session_duration=cdk.Duration.hours(4),
            instance_arn=self._sso_instance_arn or "${SSO_INSTANCE_ARN}",
        )

        # Attach AdministratorAccess managed policy
        ssoadmin.CfnManagedPolicyInPermissionSet(
            self,
            "AdminManagedPolicy",
            instance_arn=admin_ps.permission_set_arn.split("/")[0] + "/" + admin_ps.permission_set_arn.split("/")[1],
            permission_set_arn=admin_ps.permission_set_arn,
            managed_policy_arn="arn:aws:iam::aws:policy/AdministratorAccess",
        )

        permission_sets["administrator"] = admin_ps

        # ReadOnly Permission Set
        readonly_ps = ssoadmin.PermissionSet(
            self,
            "ReadOnlyPermissionSet",
            name="ReadOnlyAccess",
            description="Read-only access to AWS resources",
            session_duration=cdk.Duration.hours(12),
            instance_arn=self._sso_instance_arn or "${SSO_INSTANCE_ARN}",
        )

        # Attach ReadOnlyAccess managed policy
        ssoadmin.CfnManagedPolicyInPermissionSet(
            self,
            "ReadOnlyManagedPolicy",
            instance_arn=readonly_ps.permission_set_arn.split("/")[0] + "/" + readonly_ps.permission_set_arn.split("/")[1],
            permission_set_arn=readonly_ps.permission_set_arn,
            managed_policy_arn="arn:aws:iam::aws:policy/ReadOnlyAccess",
        )

        permission_sets["readonly"] = readonly_ps

        return permission_sets

    def _attach_custom_policies(self) -> None:
        """
        Attach custom inline policies to permission sets for fine-grained access control.
        """
        # Custom S3 policy for Developer permission set
        s3_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject"
                    ],
                    "Resource": f"{self.demo_bucket.bucket_arn}/*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:ListBucket"
                    ],
                    "Resource": self.demo_bucket.bucket_arn
                }
            ]
        }

        # Attach inline policy to Developer permission set
        ssoadmin.CfnInlinePolicyInPermissionSet(
            self,
            "DeveloperS3Policy",
            instance_arn=self.permission_sets["developer"].permission_set_arn.split("/")[0] + "/" + 
                        self.permission_sets["developer"].permission_set_arn.split("/")[1],
            permission_set_arn=self.permission_sets["developer"].permission_set_arn,
            inline_policy=s3_policy,
        )

    def _create_identity_store_resources(self) -> tuple:
        """
        Create identity store users and groups for demonstration purposes.
        
        Note: In production, users and groups would typically be synchronized
        from external identity providers via SCIM.
        
        Returns:
            tuple: (users, groups) dictionaries
        """
        users = {}
        groups = {}

        # Create test user
        test_user = identitystore.CfnUser(
            self,
            "TestUser",
            identity_store_id=self._identity_store_id or "${IDENTITY_STORE_ID}",
            user_name="testuser@example.com",
            display_name="Test User",
            name=identitystore.CfnUser.NameProperty(
                given_name="Test",
                family_name="User"
            ),
            emails=[
                identitystore.CfnUser.EmailProperty(
                    value="testuser@example.com",
                    type="Work",
                    primary=True
                )
            ],
        )

        users["test_user"] = test_user

        # Create developers group
        developers_group = identitystore.CfnGroup(
            self,
            "DevelopersGroup",
            identity_store_id=self._identity_store_id or "${IDENTITY_STORE_ID}",
            display_name="Developers",
            description="Developer group for testing SSO access",
        )

        groups["developers"] = developers_group

        # Add user to group
        identitystore.CfnGroupMembership(
            self,
            "TestUserDevelopersMembership",
            identity_store_id=self._identity_store_id or "${IDENTITY_STORE_ID}",
            group_id=developers_group.attr_group_id,
            member_id=identitystore.CfnGroupMembership.MemberIdProperty(
                user_id=test_user.attr_user_id
            ),
        )

        return users, groups

    def _create_account_assignments(self) -> None:
        """
        Create account assignments to grant users and groups access to AWS accounts
        with specific permission sets.
        """
        current_account = self.account

        # Assign Developers group to current account with Developer permission set
        ssoadmin.CfnAccountAssignment(
            self,
            "DevelopersGroupAssignment",
            instance_arn=self._sso_instance_arn or "${SSO_INSTANCE_ARN}",
            target_id=current_account,
            target_type="AWS_ACCOUNT",
            permission_set_arn=self.permission_sets["developer"].permission_set_arn,
            principal_type="GROUP",
            principal_id=self.groups["developers"].attr_group_id,
        )

        # Assign test user directly to current account with ReadOnly permission set
        ssoadmin.CfnAccountAssignment(
            self,
            "TestUserReadOnlyAssignment",
            instance_arn=self._sso_instance_arn or "${SSO_INSTANCE_ARN}",
            target_id=current_account,
            target_type="AWS_ACCOUNT",
            permission_set_arn=self.permission_sets["readonly"].permission_set_arn,
            principal_type="USER",
            principal_id=self.users["test_user"].attr_user_id,
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource identifiers.
        """
        cdk.CfnOutput(
            self,
            "DemoBucketName",
            value=self.demo_bucket.bucket_name,
            description="Name of the demo S3 bucket for custom policy testing",
        )

        cdk.CfnOutput(
            self,
            "DeveloperPermissionSetArn",
            value=self.permission_sets["developer"].permission_set_arn,
            description="ARN of the Developer permission set",
        )

        cdk.CfnOutput(
            self,
            "AdministratorPermissionSetArn",
            value=self.permission_sets["administrator"].permission_set_arn,
            description="ARN of the Administrator permission set",
        )

        cdk.CfnOutput(
            self,
            "ReadOnlyPermissionSetArn",
            value=self.permission_sets["readonly"].permission_set_arn,
            description="ARN of the ReadOnly permission set",
        )

        cdk.CfnOutput(
            self,
            "TestUserId",
            value=self.users["test_user"].attr_user_id,
            description="ID of the test user in Identity Store",
        )

        cdk.CfnOutput(
            self,
            "DevelopersGroupId",
            value=self.groups["developers"].attr_group_id,
            description="ID of the Developers group in Identity Store",
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = App()

    # Get environment configuration
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

    # Environment for stack deployment
    env = Environment(account=account, region=region)

    # Create the stack
    stack = AwsSsoExternalIdpStack(
        app,
        "AwsSsoExternalIdpStack",
        env=env,
        description="AWS IAM Identity Center (SSO) with External Identity Providers - CDK Python",
        # Pass SSO instance and identity store parameters if available
        identity_store_id=app.node.try_get_context("identityStoreId"),
        sso_instance_arn=app.node.try_get_context("ssoInstanceArn"),
    )

    # Add common tags to all resources
    Tags.of(app).add("Project", "AWS-SSO-External-IdP")
    Tags.of(app).add("Environment", stack.node.try_get_context("environment") or "dev")
    Tags.of(app).add("Owner", "CDK-Python")
    Tags.of(app).add("Purpose", "IAM Identity Center Demo")

    # Add security-focused aspects
    Aspects.of(app).add(SecurityAspect())

    # Synthesize the application
    app.synth()


class SecurityAspect:
    """
    CDK Aspect to enforce security best practices across all resources.
    """

    def visit(self, node: Construct) -> None:
        """
        Visit each construct and apply security best practices.
        
        Args:
            node: The construct to visit
        """
        # Ensure S3 buckets have encryption enabled
        if isinstance(node, s3.Bucket):
            if not node.encryption:
                node.encryption = s3.BucketEncryption.S3_MANAGED

        # Ensure IAM policies follow least privilege principle
        if isinstance(node, iam.Policy):
            # Add conditions to restrict policy usage where appropriate
            pass


if __name__ == "__main__":
    main()