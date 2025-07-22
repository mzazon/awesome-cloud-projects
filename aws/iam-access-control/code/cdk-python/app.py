#!/usr/bin/env python3
"""
CDK Python Application for Fine-Grained Access Control with IAM Policies and Conditions

This application demonstrates advanced IAM policy patterns using conditions,
resource-based policies, and context-aware access controls.
"""

import os
from typing import Any, Dict, List

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_iam as iam,
    aws_s3 as s3,
    aws_logs as logs,
)
from constructs import Construct


class FineGrainedAccessControlStack(Stack):
    """
    Stack implementing fine-grained access control patterns using IAM policies
    with advanced conditions, resource-based policies, and context-aware permissions.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.project_name = "finegrained-access"
        self.department = "Engineering"
        
        # Create S3 bucket for testing access controls
        self.test_bucket = self._create_test_bucket()
        
        # Create CloudWatch log group for testing
        self.log_group = self._create_log_group()
        
        # Create IAM policies with advanced conditions
        self.business_hours_policy = self._create_business_hours_policy()
        self.ip_restriction_policy = self._create_ip_restriction_policy()
        self.tag_based_policy = self._create_tag_based_policy()
        self.mfa_required_policy = self._create_mfa_required_policy()
        self.session_policy = self._create_session_policy()
        
        # Create test IAM user and role
        self.test_user = self._create_test_user()
        self.test_role = self._create_test_role()
        
        # Apply resource-based policies
        self._apply_bucket_policy()
        
        # Attach policies to principals
        self._attach_policies()
        
        # Create test objects with tags
        self._create_test_objects()
        
        # Create stack outputs
        self._create_outputs()

    def _create_test_bucket(self) -> s3.Bucket:
        """Create S3 bucket for testing access control policies."""
        bucket = s3.Bucket(
            self, "TestBucket",
            bucket_name=f"{self.project_name}-test-bucket-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add tags for testing tag-based access control
        cdk.Tags.of(bucket).add("Department", self.department)
        cdk.Tags.of(bucket).add("Project", self.project_name)
        cdk.Tags.of(bucket).add("Environment", "Test")
        
        return bucket

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for testing access control policies."""
        log_group = logs.LogGroup(
            self, "TestLogGroup",
            log_group_name=f"/aws/lambda/{self.project_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_group

    def _create_business_hours_policy(self) -> iam.ManagedPolicy:
        """
        Create policy allowing access only during business hours (9 AM - 5 PM UTC).
        
        This demonstrates temporal access controls using DateGreaterThan and
        DateLessThan condition operators.
        """
        policy_document = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:ListBucket"
                    ],
                    resources=[
                        self.test_bucket.bucket_arn,
                        f"{self.test_bucket.bucket_arn}/*"
                    ],
                    conditions={
                        "DateGreaterThan": {
                            "aws:CurrentTime": "09:00Z"
                        },
                        "DateLessThan": {
                            "aws:CurrentTime": "17:00Z"
                        }
                    }
                )
            ]
        )
        
        return iam.ManagedPolicy(
            self, "BusinessHoursPolicy",
            managed_policy_name=f"{self.project_name}-business-hours-policy",
            description="S3 access restricted to business hours (9 AM - 5 PM UTC)",
            document=policy_document,
        )

    def _create_ip_restriction_policy(self) -> iam.ManagedPolicy:
        """
        Create policy allowing access only from specific IP ranges.
        
        This demonstrates network-based access controls using IpAddress
        and NotIpAddress condition operators.
        """
        allowed_ip_ranges = [
            "203.0.113.0/24",  # Example IP range 1
            "198.51.100.0/24"  # Example IP range 2
        ]
        
        policy_document = iam.PolicyDocument(
            statements=[
                # Allow CloudWatch Logs access from specific IP ranges
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogGroups",
                        "logs:DescribeLogStreams"
                    ],
                    resources=[f"{self.log_group.log_group_arn}*"],
                    conditions={
                        "IpAddress": {
                            "aws:SourceIp": allowed_ip_ranges
                        }
                    }
                ),
                # Deny all actions from non-approved IP ranges
                # (except when called via AWS services)
                iam.PolicyStatement(
                    effect=iam.Effect.DENY,
                    actions=["*"],
                    resources=["*"],
                    conditions={
                        "Bool": {
                            "aws:ViaAWSService": "false"
                        },
                        "NotIpAddress": {
                            "aws:SourceIp": allowed_ip_ranges
                        }
                    }
                )
            ]
        )
        
        return iam.ManagedPolicy(
            self, "IpRestrictionPolicy",
            managed_policy_name=f"{self.project_name}-ip-restriction-policy",
            description="CloudWatch Logs access from specific IP ranges only",
            document=policy_document,
        )

    def _create_tag_based_policy(self) -> iam.ManagedPolicy:
        """
        Create policy using resource tags and principal tags for access control.
        
        This demonstrates attribute-based access control (ABAC) using
        StringEquals conditions with tag variables.
        """
        policy_document = iam.PolicyDocument(
            statements=[
                # Allow access to objects where principal's Department tag
                # matches the object's Department tag
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject"
                    ],
                    resources=[f"{self.test_bucket.bucket_arn}/*"],
                    conditions={
                        "StringEquals": {
                            "aws:PrincipalTag/Department": "${s3:ExistingObjectTag/Department}"
                        }
                    }
                ),
                # Allow access to shared folder for all users
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject"
                    ],
                    resources=[f"{self.test_bucket.bucket_arn}/shared/*"]
                ),
                # Allow listing bucket with prefix restrictions based on department
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["s3:ListBucket"],
                    resources=[self.test_bucket.bucket_arn],
                    conditions={
                        "StringLike": {
                            "s3:prefix": [
                                "shared/*",
                                "${aws:PrincipalTag/Department}/*"
                            ]
                        }
                    }
                )
            ]
        )
        
        return iam.ManagedPolicy(
            self, "TagBasedPolicy",
            managed_policy_name=f"{self.project_name}-tag-based-policy",
            description="S3 access based on user and resource tags",
            document=policy_document,
        )

    def _create_mfa_required_policy(self) -> iam.ManagedPolicy:
        """
        Create policy requiring MFA for sensitive operations.
        
        This demonstrates strong authentication requirements using
        MultiFactorAuthPresent and MultiFactorAuthAge conditions.
        """
        policy_document = iam.PolicyDocument(
            statements=[
                # Allow read operations without MFA
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:ListBucket"
                    ],
                    resources=[
                        self.test_bucket.bucket_arn,
                        f"{self.test_bucket.bucket_arn}/*"
                    ]
                ),
                # Require MFA for write operations (within 1 hour)
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:PutObjectAcl"
                    ],
                    resources=[f"{self.test_bucket.bucket_arn}/*"],
                    conditions={
                        "Bool": {
                            "aws:MultiFactorAuthPresent": "true"
                        },
                        "NumericLessThan": {
                            "aws:MultiFactorAuthAge": "3600"  # 1 hour in seconds
                        }
                    }
                )
            ]
        )
        
        return iam.ManagedPolicy(
            self, "MfaRequiredPolicy",
            managed_policy_name=f"{self.project_name}-mfa-required-policy",
            description="S3 write operations require MFA authentication",
            document=policy_document,
        )

    def _create_session_policy(self) -> iam.ManagedPolicy:
        """
        Create policy with session duration and identity constraints.
        
        This demonstrates session-based access controls using session
        duration limits and identity validation.
        """
        policy_document = iam.PolicyDocument(
            statements=[
                # Allow CloudWatch Logs operations with session constraints
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                    ],
                    resources=[f"{self.log_group.log_group_arn}*"],
                    conditions={
                        "StringEquals": {
                            "aws:userid": "${aws:userid}"  # Validate session identity
                        },
                        "StringLike": {
                            "aws:rolename": f"{self.project_name}*"  # Restrict to project roles
                        },
                        "NumericLessThan": {
                            "aws:TokenIssueTime": "${aws:CurrentTime}"  # Validate token freshness
                        }
                    }
                ),
                # Allow session token generation with duration limits
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sts:GetSessionToken"],
                    resources=["*"],
                    conditions={
                        "NumericLessThan": {
                            "aws:RequestedDuration": "3600"  # Max 1 hour sessions
                        }
                    }
                )
            ]
        )
        
        return iam.ManagedPolicy(
            self, "SessionPolicy",
            managed_policy_name=f"{self.project_name}-session-policy",
            description="Session-based access control with duration limits",
            document=policy_document,
        )

    def _create_test_user(self) -> iam.User:
        """Create test IAM user with appropriate tags for testing."""
        user = iam.User(
            self, "TestUser",
            user_name=f"{self.project_name}-test-user",
        )
        
        # Add tags for testing tag-based access control
        cdk.Tags.of(user).add("Department", self.department)
        cdk.Tags.of(user).add("Project", self.project_name)
        
        return user

    def _create_test_role(self) -> iam.Role:
        """
        Create test IAM role with conditional assume role policy.
        
        This demonstrates trust policy conditions for cross-account
        and regional access controls.
        """
        # Define assume role policy with conditions
        assume_role_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.UserPrincipal(self.test_user.user_arn)],
                    actions=["sts:AssumeRole"],
                    conditions={
                        "StringEquals": {
                            "aws:RequestedRegion": self.region
                        },
                        "IpAddress": {
                            "aws:SourceIp": [
                                "203.0.113.0/24",
                                "198.51.100.0/24"
                            ]
                        }
                    }
                )
            ]
        )
        
        role = iam.Role(
            self, "TestRole",
            role_name=f"{self.project_name}-test-role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),  # Placeholder principal
            assume_role_policy_document=assume_role_policy,
            description="Test role with conditional access",
        )
        
        # Add tags for testing
        cdk.Tags.of(role).add("Department", self.department)
        cdk.Tags.of(role).add("Environment", "Test")
        
        return role

    def _apply_bucket_policy(self) -> None:
        """
        Apply resource-based policy to S3 bucket with encryption and metadata requirements.
        
        This demonstrates resource-level access controls that work in conjunction
        with identity-based policies for defense-in-depth security.
        """
        bucket_policy = iam.PolicyDocument(
            statements=[
                # Allow access from test role with encryption and metadata requirements
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.RolePrincipal(self.test_role.role_arn)],
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject"
                    ],
                    resources=[f"{self.test_bucket.bucket_arn}/*"],
                    conditions={
                        "StringEquals": {
                            "s3:x-amz-server-side-encryption": "AES256"
                        },
                        "StringLike": {
                            "s3:x-amz-meta-project": f"{self.project_name}*"
                        }
                    }
                ),
                # Deny all insecure transport
                iam.PolicyStatement(
                    effect=iam.Effect.DENY,
                    principals=[iam.AnyPrincipal()],
                    actions=["s3:*"],
                    resources=[
                        self.test_bucket.bucket_arn,
                        f"{self.test_bucket.bucket_arn}/*"
                    ],
                    conditions={
                        "Bool": {
                            "aws:SecureTransport": "false"
                        }
                    }
                )
            ]
        )
        
        # Apply the policy to the bucket
        self.test_bucket.add_to_resource_policy(bucket_policy.statements[0])
        self.test_bucket.add_to_resource_policy(bucket_policy.statements[1])

    def _attach_policies(self) -> None:
        """Attach policies to test principals for validation."""
        # Attach tag-based policy to test user
        self.test_user.add_managed_policy(self.tag_based_policy)
        
        # Attach business hours policy to test role
        self.test_role.add_managed_policy(self.business_hours_policy)

    def _create_test_objects(self) -> None:
        """Create test S3 objects with appropriate tags and metadata."""
        # Create test objects using custom resource (Lambda-backed)
        # This would typically be done through a separate process or custom resource
        # For demonstration purposes, we're documenting the expected structure
        pass

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for testing and validation."""
        CfnOutput(
            self, "TestBucketName",
            value=self.test_bucket.bucket_name,
            description="Name of the S3 bucket for testing access controls"
        )
        
        CfnOutput(
            self, "TestBucketArn",
            value=self.test_bucket.bucket_arn,
            description="ARN of the S3 bucket for testing access controls"
        )
        
        CfnOutput(
            self, "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group for testing"
        )
        
        CfnOutput(
            self, "TestUserArn",
            value=self.test_user.user_arn,
            description="ARN of the test user for policy validation"
        )
        
        CfnOutput(
            self, "TestRoleArn",
            value=self.test_role.role_arn,
            description="ARN of the test role for policy validation"
        )
        
        CfnOutput(
            self, "BusinessHoursPolicyArn",
            value=self.business_hours_policy.managed_policy_arn,
            description="ARN of the business hours access policy"
        )
        
        CfnOutput(
            self, "TagBasedPolicyArn",
            value=self.tag_based_policy.managed_policy_arn,
            description="ARN of the tag-based access control policy"
        )
        
        CfnOutput(
            self, "MfaRequiredPolicyArn",
            value=self.mfa_required_policy.managed_policy_arn,
            description="ARN of the MFA-required policy"
        )


# CDK Application
app = cdk.App()

# Get context values or use defaults
project_name = app.node.try_get_context("project_name") or "finegrained-access"
environment = app.node.try_get_context("environment") or "test"

# Create the stack
FineGrainedAccessControlStack(
    app, "FineGrainedAccessControlStack",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    ),
    description="Fine-grained access control with IAM policies and conditions",
    tags={
        "Project": project_name,
        "Environment": environment,
        "Recipe": "fine-grained-access-control-iam-policies-conditions"
    }
)

app.synth()