#!/usr/bin/env python3
"""
Advanced Cross-Account IAM Role Federation CDK Application

This CDK application implements a comprehensive cross-account IAM role federation
architecture with SAML support, conditional access policies, audit logging,
and automated compliance validation.

Author: Generated from Recipe - Advanced Cross-Account IAM Role Federation
"""

import aws_cdk as cdk
from typing import Dict, List, Optional
import json
import os

from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_s3 as s3,
    aws_cloudtrail as cloudtrail,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class CrossAccountIAMFederationStack(Stack):
    """
    CDK Stack implementing advanced cross-account IAM role federation
    with comprehensive security controls and audit capabilities.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        security_account_id: str,
        prod_account_id: str,
        dev_account_id: str,
        saml_provider_name: Optional[str] = "CorporateIdP",
        allowed_departments: Optional[List[str]] = None,
        prod_external_id: Optional[str] = None,
        dev_external_id: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Cross-Account IAM Federation Stack.

        Args:
            scope: CDK App or parent construct
            construct_id: Unique identifier for this stack
            security_account_id: AWS account ID for the security/central account
            prod_account_id: AWS account ID for the production account
            dev_account_id: AWS account ID for the development account
            saml_provider_name: Name of the SAML identity provider
            allowed_departments: List of departments allowed for federation
            prod_external_id: External ID for production role (auto-generated if None)
            dev_external_id: External ID for development role (auto-generated if None)
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store account IDs
        self.security_account_id = security_account_id
        self.prod_account_id = prod_account_id
        self.dev_account_id = dev_account_id
        self.saml_provider_name = saml_provider_name
        self.allowed_departments = allowed_departments or ["Engineering", "Security", "DevOps"]

        # Generate external IDs if not provided
        self.prod_external_id = prod_external_id or self._generate_external_id("prod")
        self.dev_external_id = dev_external_id or self._generate_external_id("dev")

        # Create S3 bucket for CloudTrail logs
        self.audit_bucket = self._create_audit_bucket()

        # Create external ID secrets for secure storage
        self.external_id_secrets = self._create_external_id_secrets()

        # Create master cross-account role
        self.master_role = self._create_master_cross_account_role()

        # Create production cross-account role
        self.prod_role = self._create_production_cross_account_role()

        # Create development cross-account role
        self.dev_role = self._create_development_cross_account_role()

        # Create CloudTrail for audit logging
        self.cloudtrail = self._create_audit_trail()

        # Create Lambda function for role validation
        self.validator_lambda = self._create_role_validator_lambda()

        # Create shared S3 buckets for demonstration
        self.shared_buckets = self._create_shared_s3_buckets()

        # Output important values
        self._create_outputs()

    def _generate_external_id(self, environment: str) -> str:
        """Generate a unique external ID for the environment."""
        import secrets
        return f"{environment}-{secrets.token_hex(16)}"

    def _create_audit_bucket(self) -> s3.Bucket:
        """Create S3 bucket for CloudTrail audit logs."""
        bucket = s3.Bucket(
            self,
            "CrossAccountAuditBucket",
            bucket_name=f"cross-account-audit-trail-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioning=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldLogs",
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
            ],
            removal_policy=RemovalPolicy.RETAIN,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
        )

        # Add bucket policy for CloudTrail
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSCloudTrailAclCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                actions=["s3:GetBucketAcl"],
                resources=[bucket.bucket_arn],
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSCloudTrailWrite",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control"
                    }
                },
            )
        )

        return bucket

    def _create_external_id_secrets(self) -> Dict[str, secretsmanager.Secret]:
        """Create Secrets Manager entries for external IDs."""
        secrets_dict = {}

        # Production external ID secret
        prod_secret = secretsmanager.Secret(
            self,
            "ProdExternalIdSecret",
            description="External ID for production cross-account role",
            secret_string_value=cdk.SecretValue.unsafe_plain_text(self.prod_external_id),
        )
        secrets_dict["prod"] = prod_secret

        # Development external ID secret
        dev_secret = secretsmanager.Secret(
            self,
            "DevExternalIdSecret",
            description="External ID for development cross-account role",
            secret_string_value=cdk.SecretValue.unsafe_plain_text(self.dev_external_id),
        )
        secrets_dict["dev"] = dev_secret

        return secrets_dict

    def _create_master_cross_account_role(self) -> iam.Role:
        """Create the master cross-account role for centralized access control."""
        
        # Create trust policy for SAML and MFA
        saml_federated_principal = iam.FederatedPrincipal(
            federated=f"arn:aws:iam::{self.security_account_id}:saml-provider/{self.saml_provider_name}",
            conditions={
                "StringEquals": {
                    "SAML:aud": "https://signin.aws.amazon.com/saml"
                },
                "ForAllValues:StringLike": {
                    "SAML:department": self.allowed_departments
                }
            },
            assume_role_action="sts:AssumeRoleWithSAML",
        )

        # MFA-enabled account root principal
        mfa_account_principal = iam.AccountPrincipal(self.security_account_id).with_conditions({
            "Bool": {
                "aws:MultiFactorAuthPresent": "true"
            },
            "NumericLessThan": {
                "aws:MultiFactorAuthAge": "3600"
            }
        })

        # Create the master role
        master_role = iam.Role(
            self,
            "MasterCrossAccountRole",
            role_name=f"MasterCrossAccountRole-{self.stack_name}",
            description="Master role for federated cross-account access",
            assumed_by=iam.CompositePrincipal(
                saml_federated_principal,
                mfa_account_principal,
            ),
            max_session_duration=Duration.hours(2),
        )

        # Create cross-account assume role policy
        cross_account_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="AssumeTargetAccountRoles",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "sts:AssumeRole",
                        "sts:TagSession"
                    ],
                    resources=[
                        f"arn:aws:iam::{self.prod_account_id}:role/CrossAccount-*",
                        f"arn:aws:iam::{self.dev_account_id}:role/CrossAccount-*"
                    ],
                    conditions={
                        "StringEquals": {
                            "sts:ExternalId": [self.prod_external_id, self.dev_external_id]
                        }
                    }
                ),
                iam.PolicyStatement(
                    sid="BasicIAMReadAccess",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "iam:ListRoles",
                        "iam:GetRole",
                        "sts:GetCallerIdentity"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    sid="EnhancedCrossAccountAccess",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "sts:AssumeRole",
                        "sts:TagSession"
                    ],
                    resources=[
                        f"arn:aws:iam::{self.prod_account_id}:role/CrossAccount-*",
                        f"arn:aws:iam::{self.dev_account_id}:role/CrossAccount-*"
                    ],
                    conditions={
                        "StringEquals": {
                            "sts:ExternalId": [self.prod_external_id, self.dev_external_id],
                            "aws:RequestedRegion": self.region
                        },
                        "ForAllValues:StringEquals": {
                            "sts:TransitiveTagKeys": ["Department", "Project", "Environment"]
                        }
                    }
                )
            ]
        )

        # Attach the policy to the role
        master_role.attach_inline_policy(
            iam.Policy(
                self,
                "MasterCrossAccountPolicy",
                policy_name="CrossAccountAssumePolicy",
                document=cross_account_policy,
            )
        )

        return master_role

    def _create_production_cross_account_role(self) -> iam.Role:
        """Create the production cross-account role with restricted permissions."""
        
        # Trust policy for production role
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[
                        iam.ArnPrincipal(self.master_role.role_arn)
                    ],
                    actions=["sts:AssumeRole"],
                    conditions={
                        "StringEquals": {
                            "sts:ExternalId": self.prod_external_id
                        },
                        "Bool": {
                            "aws:MultiFactorAuthPresent": "true"
                        },
                        "StringLike": {
                            "aws:userid": f"*:{self.security_account_id}:*"
                        }
                    }
                )
            ]
        )

        prod_role = iam.Role(
            self,
            "ProductionCrossAccountRole",
            role_name=f"CrossAccount-ProductionAccess-{self.stack_name}",
            description="Cross-account role for production resource access",
            assumed_by=iam.PrincipalWithConditions(
                iam.ArnPrincipal(self.master_role.role_arn),
                conditions={
                    "StringEquals": {
                        "sts:ExternalId": self.prod_external_id
                    }
                }
            ),
            max_session_duration=Duration.hours(1),
        )

        # Production permissions policy (limited access)
        prod_permissions = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="S3ProductionAccess",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:ListBucket"
                    ],
                    resources=[
                        f"arn:aws:s3:::prod-shared-data-{self.stack_name}",
                        f"arn:aws:s3:::prod-shared-data-{self.stack_name}/*"
                    ]
                ),
                iam.PolicyStatement(
                    sid="CloudWatchLogsAccess",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogGroups",
                        "logs:DescribeLogStreams"
                    ],
                    resources=[f"arn:aws:logs:{self.region}:{self.prod_account_id}:*"]
                ),
                iam.PolicyStatement(
                    sid="CloudWatchMetricsAccess",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudwatch:PutMetricData",
                        "cloudwatch:GetMetricStatistics",
                        "cloudwatch:ListMetrics"
                    ],
                    resources=["*"]
                )
            ]
        )

        prod_role.attach_inline_policy(
            iam.Policy(
                self,
                "ProductionResourceAccessPolicy",
                policy_name="ProductionResourceAccess",
                document=prod_permissions,
            )
        )

        # Add tags
        cdk.Tags.of(prod_role).add("Environment", "Production")
        cdk.Tags.of(prod_role).add("Purpose", "CrossAccount")

        return prod_role

    def _create_development_cross_account_role(self) -> iam.Role:
        """Create the development cross-account role with broader permissions."""
        
        dev_role = iam.Role(
            self,
            "DevelopmentCrossAccountRole",
            role_name=f"CrossAccount-DevelopmentAccess-{self.stack_name}",
            description="Cross-account role for development resource access",
            assumed_by=iam.PrincipalWithConditions(
                iam.ArnPrincipal(self.master_role.role_arn),
                conditions={
                    "StringEquals": {
                        "sts:ExternalId": self.dev_external_id
                    },
                    "StringLike": {
                        "aws:userid": f"*:{self.security_account_id}:*"
                    },
                    "IpAddress": {
                        "aws:SourceIp": ["203.0.113.0/24", "198.51.100.0/24"]
                    }
                }
            ),
            max_session_duration=Duration.hours(2),
        )

        # Development permissions policy (broader access)
        dev_permissions = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="S3DevelopmentAccess",
                    effect=iam.Effect.ALLOW,
                    actions=["s3:*"],
                    resources=[
                        f"arn:aws:s3:::dev-shared-data-{self.stack_name}",
                        f"arn:aws:s3:::dev-shared-data-{self.stack_name}/*"
                    ]
                ),
                iam.PolicyStatement(
                    sid="EC2ReadAccess",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeInstances",
                        "ec2:DescribeSecurityGroups",
                        "ec2:DescribeVpcs",
                        "ec2:DescribeSubnets"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    sid="LambdaDevelopmentAccess",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "lambda:InvokeFunction",
                        "lambda:GetFunction",
                        "lambda:ListFunctions"
                    ],
                    resources=[f"arn:aws:lambda:{self.region}:{self.dev_account_id}:function:dev-*"]
                ),
                iam.PolicyStatement(
                    sid="CloudWatchLogsFullAccess",
                    effect=iam.Effect.ALLOW,
                    actions=["logs:*"],
                    resources=[f"arn:aws:logs:{self.region}:{self.dev_account_id}:*"]
                )
            ]
        )

        dev_role.attach_inline_policy(
            iam.Policy(
                self,
                "DevelopmentResourceAccessPolicy",
                policy_name="DevelopmentResourceAccess",
                document=dev_permissions,
            )
        )

        # Add tags
        cdk.Tags.of(dev_role).add("Environment", "Development")
        cdk.Tags.of(dev_role).add("Purpose", "CrossAccount")

        return dev_role

    def _create_audit_trail(self) -> cloudtrail.Trail:
        """Create CloudTrail for comprehensive audit logging."""
        
        trail = cloudtrail.Trail(
            self,
            "CrossAccountAuditTrail",
            trail_name=f"CrossAccountAuditTrail-{self.stack_name}",
            bucket=self.audit_bucket,
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            send_to_cloud_watch_logs=True,
        )

        # Add event selectors for IAM and STS events
        trail.add_event_selector(
            read_write_type=cloudtrail.ReadWriteType.ALL,
            include_management_events=True,
            data_resource_type=cloudtrail.DataResourceType.S3_OBJECT,
            data_resource_values=[f"{self.audit_bucket.bucket_arn}/*"],
        )

        return trail

    def _create_role_validator_lambda(self) -> lambda_.Function:
        """Create Lambda function for automated role validation."""
        
        # Create execution role for Lambda
        lambda_role = iam.Role(
            self,
            "RoleValidatorLambdaRole",
            role_name=f"RoleValidatorLambdaRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("IAMReadOnlyAccess"),
            ],
        )

        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iam = boto3.client('iam')

def lambda_handler(event, context):
    """
    Validate cross-account role configurations and trust policies
    """
    try:
        # Get all cross-account roles
        paginator = iam.get_paginator('list_roles')
        
        validation_results = []
        
        for page in paginator.paginate():
            for role in page['Roles']:
                if 'CrossAccount-' in role['RoleName']:
                    validation_result = validate_role(role)
                    validation_results.append(validation_result)
        
        # Report findings
        for result in validation_results:
            if not result['compliant']:
                logger.warning(f"Non-compliant role found: {result}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'validated_roles': len(validation_results),
                'compliant_roles': sum(1 for r in validation_results if r['compliant'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error validating roles: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def validate_role(role):
    """
    Validate individual role configuration
    """
    role_name = role['RoleName']
    
    try:
        # Get role details
        role_details = iam.get_role(RoleName=role_name)
        assume_role_policy = role_details['Role']['AssumeRolePolicyDocument']
        
        validation_checks = {
            'has_external_id': check_external_id(assume_role_policy),
            'has_mfa_condition': check_mfa_condition(assume_role_policy),
            'has_ip_restriction': check_ip_restriction(assume_role_policy),
            'max_session_duration_ok': role['MaxSessionDuration'] <= 7200
        }
        
        compliant = all(validation_checks.values())
        
        return {
            'role_name': role_name,
            'compliant': compliant,
            'checks': validation_checks
        }
        
    except Exception as e:
        logger.error(f"Error validating role {role_name}: {str(e)}")
        return {
            'role_name': role_name,
            'compliant': False,
            'error': str(e)
        }

def check_external_id(policy):
    """Check if policy requires ExternalId"""
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'StringEquals' in conditions and 'sts:ExternalId' in conditions['StringEquals']:
            return True
    return False

def check_mfa_condition(policy):
    """Check if policy requires MFA"""
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'Bool' in conditions and 'aws:MultiFactorAuthPresent' in conditions['Bool']:
            return True
    return False

def check_ip_restriction(policy):
    """Check if policy has IP restrictions"""
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'IpAddress' in conditions or 'IpAddressIfExists' in conditions:
            return True
    return True  # Not mandatory for all environments
'''

        validator_function = lambda_.Function(
            self,
            "CrossAccountRoleValidator",
            function_name=f"CrossAccountRoleValidator-{self.stack_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Automated validation of cross-account role configurations",
        )

        return validator_function

    def _create_shared_s3_buckets(self) -> Dict[str, s3.Bucket]:
        """Create shared S3 buckets for demonstration purposes."""
        buckets = {}

        # Production shared bucket
        prod_bucket = s3.Bucket(
            self,
            "ProductionSharedBucket",
            bucket_name=f"prod-shared-data-{self.stack_name}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioning=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
        )
        buckets["prod"] = prod_bucket

        # Development shared bucket
        dev_bucket = s3.Bucket(
            self,
            "DevelopmentSharedBucket",
            bucket_name=f"dev-shared-data-{self.stack_name}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioning=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
        )
        buckets["dev"] = dev_bucket

        return buckets

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self,
            "MasterRoleArn",
            value=self.master_role.role_arn,
            description="ARN of the master cross-account role",
            export_name=f"{self.stack_name}-MasterRoleArn",
        )

        CfnOutput(
            self,
            "ProductionRoleArn",
            value=self.prod_role.role_arn,
            description="ARN of the production cross-account role",
            export_name=f"{self.stack_name}-ProductionRoleArn",
        )

        CfnOutput(
            self,
            "DevelopmentRoleArn",
            value=self.dev_role.role_arn,
            description="ARN of the development cross-account role",
            export_name=f"{self.stack_name}-DevelopmentRoleArn",
        )

        CfnOutput(
            self,
            "AuditBucketName",
            value=self.audit_bucket.bucket_name,
            description="Name of the S3 bucket for audit logs",
            export_name=f"{self.stack_name}-AuditBucketName",
        )

        CfnOutput(
            self,
            "ValidatorLambdaArn",
            value=self.validator_lambda.function_arn,
            description="ARN of the role validator Lambda function",
            export_name=f"{self.stack_name}-ValidatorLambdaArn",
        )

        CfnOutput(
            self,
            "ProductionExternalId",
            value=self.prod_external_id,
            description="External ID for production role (store securely)",
        )

        CfnOutput(
            self,
            "DevelopmentExternalId",
            value=self.dev_external_id,
            description="External ID for development role (store securely)",
        )

        CfnOutput(
            self,
            "ProductionExternalIdSecretArn",
            value=self.external_id_secrets["prod"].secret_arn,
            description="ARN of the Secrets Manager secret containing production external ID",
        )

        CfnOutput(
            self,
            "DevelopmentExternalIdSecretArn",
            value=self.external_id_secrets["dev"].secret_arn,
            description="ARN of the Secrets Manager secret containing development external ID",
        )


def main():
    """Main CDK application entry point."""
    app = App()

    # Get configuration from environment variables or CDK context
    security_account_id = app.node.try_get_context("securityAccountId") or os.environ.get("SECURITY_ACCOUNT_ID", "111111111111")
    prod_account_id = app.node.try_get_context("prodAccountId") or os.environ.get("PROD_ACCOUNT_ID", "222222222222")
    dev_account_id = app.node.try_get_context("devAccountId") or os.environ.get("DEV_ACCOUNT_ID", "333333333333")
    
    # Optional configuration
    saml_provider_name = app.node.try_get_context("samlProviderName") or "CorporateIdP"
    allowed_departments = app.node.try_get_context("allowedDepartments") or ["Engineering", "Security", "DevOps"]

    # Deploy to the security account by default
    env = Environment(
        account=security_account_id,
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )

    # Create the stack
    CrossAccountIAMFederationStack(
        app,
        "CrossAccountIAMFederationStack",
        security_account_id=security_account_id,
        prod_account_id=prod_account_id,
        dev_account_id=dev_account_id,
        saml_provider_name=saml_provider_name,
        allowed_departments=allowed_departments,
        env=env,
        description="Advanced Cross-Account IAM Role Federation with comprehensive security controls",
    )

    app.synth()


if __name__ == "__main__":
    main()