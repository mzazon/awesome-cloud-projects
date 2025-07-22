#!/usr/bin/env python3
"""
Multi-Account Governance with AWS Organizations and Service Control Policies
CDK Python Application

This CDK application implements a comprehensive multi-account governance framework
using AWS Organizations with Service Control Policies (SCPs) to establish
enterprise-wide guardrails and governance controls.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_organizations as organizations,
    aws_s3 as s3,
    aws_cloudtrail as cloudtrail,
    aws_iam as iam,
    aws_budgets as budgets,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    CfnOutput,
    RemovalPolicy,
    Duration,
)
from constructs import Construct
import json
from typing import Dict, List, Any


class MultiAccountGovernanceStack(Stack):
    """
    CDK Stack for implementing multi-account governance with AWS Organizations
    and Service Control Policies.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 buckets for organization-wide logging
        self.cloudtrail_bucket = self._create_cloudtrail_bucket()
        self.config_bucket = self._create_config_bucket()

        # Create AWS Organization with all features enabled
        self.organization = self._create_organization()

        # Create Organizational Units
        self.organizational_units = self._create_organizational_units()

        # Create Service Control Policies
        self.service_control_policies = self._create_service_control_policies()

        # Attach SCPs to Organizational Units
        self._attach_policies_to_ous()

        # Set up organization-wide CloudTrail
        self.cloudtrail = self._create_organization_cloudtrail()

        # Create governance monitoring dashboard
        self._create_governance_dashboard()

        # Create organization-wide budget
        self._create_organization_budget()

        # Output important resource information
        self._create_outputs()

    def _create_cloudtrail_bucket(self) -> s3.Bucket:
        """Create S3 bucket for CloudTrail logging with proper permissions."""
        bucket = s3.Bucket(
            self,
            "CloudTrailBucket",
            bucket_name=f"org-cloudtrail-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add bucket policy for CloudTrail service
        bucket_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="AWSCloudTrailAclCheck",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                    actions=["s3:GetBucketAcl"],
                    resources=[bucket.bucket_arn],
                ),
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
                ),
            ]
        )

        bucket.add_to_resource_policy(bucket_policy.statements[0])
        bucket.add_to_resource_policy(bucket_policy.statements[1])

        return bucket

    def _create_config_bucket(self) -> s3.Bucket:
        """Create S3 bucket for AWS Config logging."""
        bucket = s3.Bucket(
            self,
            "ConfigBucket",
            bucket_name=f"org-config-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        return bucket

    def _create_organization(self) -> organizations.CfnOrganization:
        """Create AWS Organization with all features enabled."""
        organization = organizations.CfnOrganization(
            self,
            "Organization",
            feature_set="ALL",
        )

        return organization

    def _create_organizational_units(self) -> Dict[str, organizations.CfnOrganizationalUnit]:
        """Create Organizational Units for different environments."""
        ou_configs = [
            {"name": "Production", "id": "ProductionOU"},
            {"name": "Development", "id": "DevelopmentOU"},
            {"name": "Sandbox", "id": "SandboxOU"},
            {"name": "Security", "id": "SecurityOU"},
        ]

        organizational_units = {}

        for config in ou_configs:
            ou = organizations.CfnOrganizationalUnit(
                self,
                config["id"],
                name=config["name"],
                parent_id=self.organization.attr_root_id,
            )
            organizational_units[config["name"]] = ou

        return organizational_units

    def _create_service_control_policies(self) -> Dict[str, organizations.CfnPolicy]:
        """Create Service Control Policies for governance."""
        policies = {}

        # Cost Control SCP
        cost_control_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "DenyExpensiveInstances",
                    "Effect": "Deny",
                    "Action": ["ec2:RunInstances"],
                    "Resource": "arn:aws:ec2:*:*:instance/*",
                    "Condition": {
                        "ForAnyValue:StringLike": {
                            "ec2:InstanceType": [
                                "*.8xlarge",
                                "*.12xlarge",
                                "*.16xlarge",
                                "*.24xlarge",
                                "p3.*",
                                "p4.*",
                                "x1e.*",
                                "r5.*large",
                                "r6i.*large",
                            ]
                        }
                    },
                },
                {
                    "Sid": "DenyExpensiveRDSInstances",
                    "Effect": "Deny",
                    "Action": ["rds:CreateDBInstance", "rds:CreateDBCluster"],
                    "Resource": "*",
                    "Condition": {
                        "ForAnyValue:StringLike": {
                            "rds:db-instance-class": [
                                "*.8xlarge",
                                "*.12xlarge",
                                "*.16xlarge",
                                "*.24xlarge",
                            ]
                        }
                    },
                },
                {
                    "Sid": "RequireCostAllocationTags",
                    "Effect": "Deny",
                    "Action": [
                        "ec2:RunInstances",
                        "rds:CreateDBInstance",
                        "s3:CreateBucket",
                    ],
                    "Resource": "*",
                    "Condition": {
                        "Null": {"aws:RequestedRegion": "false"},
                        "ForAllValues:StringNotEquals": {
                            "aws:TagKeys": ["Department", "Project", "Environment", "Owner"]
                        },
                    },
                },
            ],
        }

        policies["CostControl"] = organizations.CfnPolicy(
            self,
            "CostControlPolicy",
            name="CostControlPolicy",
            description="Policy to control costs and enforce tagging",
            type="SERVICE_CONTROL_POLICY",
            content=json.dumps(cost_control_policy),
        )

        # Security Baseline SCP
        security_baseline_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "DenyRootUserActions",
                    "Effect": "Deny",
                    "Action": "*",
                    "Resource": "*",
                    "Condition": {"StringEquals": {"aws:PrincipalType": "Root"}},
                },
                {
                    "Sid": "DenyCloudTrailDisable",
                    "Effect": "Deny",
                    "Action": [
                        "cloudtrail:StopLogging",
                        "cloudtrail:DeleteTrail",
                        "cloudtrail:PutEventSelectors",
                        "cloudtrail:UpdateTrail",
                    ],
                    "Resource": "*",
                },
                {
                    "Sid": "DenyConfigDisable",
                    "Effect": "Deny",
                    "Action": [
                        "config:DeleteConfigRule",
                        "config:DeleteConfigurationRecorder",
                        "config:DeleteDeliveryChannel",
                        "config:StopConfigurationRecorder",
                    ],
                    "Resource": "*",
                },
                {
                    "Sid": "DenyUnencryptedS3Objects",
                    "Effect": "Deny",
                    "Action": "s3:PutObject",
                    "Resource": "*",
                    "Condition": {
                        "StringNotEquals": {"s3:x-amz-server-side-encryption": "AES256"},
                        "Null": {"s3:x-amz-server-side-encryption": "true"},
                    },
                },
            ],
        }

        policies["SecurityBaseline"] = organizations.CfnPolicy(
            self,
            "SecurityBaselinePolicy",
            name="SecurityBaselinePolicy",
            description="Baseline security controls for all accounts",
            type="SERVICE_CONTROL_POLICY",
            content=json.dumps(security_baseline_policy),
        )

        # Region Restriction SCP
        region_restriction_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "DenyNonApprovedRegions",
                    "Effect": "Deny",
                    "NotAction": [
                        "iam:*",
                        "organizations:*",
                        "route53:*",
                        "cloudfront:*",
                        "waf:*",
                        "wafv2:*",
                        "waf-regional:*",
                        "support:*",
                        "trustedadvisor:*",
                    ],
                    "Resource": "*",
                    "Condition": {
                        "StringNotEquals": {
                            "aws:RequestedRegion": [
                                "us-east-1",
                                "us-west-2",
                                "eu-west-1",
                            ]
                        }
                    },
                }
            ],
        }

        policies["RegionRestriction"] = organizations.CfnPolicy(
            self,
            "RegionRestrictionPolicy",
            name="RegionRestrictionPolicy",
            description="Restrict sandbox accounts to approved regions",
            type="SERVICE_CONTROL_POLICY",
            content=json.dumps(region_restriction_policy),
        )

        return policies

    def _attach_policies_to_ous(self) -> None:
        """Attach Service Control Policies to appropriate Organizational Units."""
        # Attach cost control SCP to Production and Development OUs
        for ou_name in ["Production", "Development"]:
            organizations.CfnPolicyAttachment(
                self,
                f"CostControlAttachment{ou_name}",
                policy_id=self.service_control_policies["CostControl"].ref,
                target_id=self.organizational_units[ou_name].ref,
            )

        # Attach security baseline SCP to Production OU
        organizations.CfnPolicyAttachment(
            self,
            "SecurityBaselineAttachmentProduction",
            policy_id=self.service_control_policies["SecurityBaseline"].ref,
            target_id=self.organizational_units["Production"].ref,
        )

        # Attach region restriction SCP to Sandbox OU
        organizations.CfnPolicyAttachment(
            self,
            "RegionRestrictionAttachmentSandbox",
            policy_id=self.service_control_policies["RegionRestriction"].ref,
            target_id=self.organizational_units["Sandbox"].ref,
        )

    def _create_organization_cloudtrail(self) -> cloudtrail.Trail:
        """Create organization-wide CloudTrail for audit logging."""
        trail = cloudtrail.Trail(
            self,
            "OrganizationTrail",
            trail_name="OrganizationTrail",
            bucket=self.cloudtrail_bucket,
            include_global_service_events=True,
            is_multi_region_trail=True,
            is_organization_trail=True,
            enable_file_validation=True,
            send_to_cloud_watch_logs=True,
        )

        return trail

    def _create_governance_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for governance monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "GovernanceDashboard",
            dashboard_name="OrganizationGovernance",
        )

        # Add widgets for organization metrics
        organization_widget = cloudwatch.GraphWidget(
            title="Organization Account Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Organizations",
                    metric_name="TotalAccounts",
                    statistic="Sum",
                ),
                cloudwatch.Metric(
                    namespace="AWS/Organizations",
                    metric_name="ActiveAccounts",
                    statistic="Sum",
                ),
            ],
            width=12,
            height=6,
        )

        dashboard.add_widgets(organization_widget)

        return dashboard

    def _create_organization_budget(self) -> budgets.CfnBudget:
        """Create organization-wide budget for cost monitoring."""
        budget = budgets.CfnBudget(
            self,
            "OrganizationBudget",
            budget={
                "budgetName": "OrganizationMasterBudget",
                "budgetLimit": {"amount": "5000", "unit": "USD"},
                "timeUnit": "MONTHLY",
                "budgetType": "COST",
                "costFilters": {"LinkedAccount": [self.account]},
            },
        )

        return budget

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "OrganizationId",
            value=self.organization.ref,
            description="AWS Organization ID",
        )

        CfnOutput(
            self,
            "CloudTrailBucket",
            value=self.cloudtrail_bucket.bucket_name,
            description="S3 bucket for CloudTrail logs",
        )

        CfnOutput(
            self,
            "ConfigBucket",
            value=self.config_bucket.bucket_name,
            description="S3 bucket for AWS Config",
        )

        # Output Organizational Unit IDs
        for name, ou in self.organizational_units.items():
            CfnOutput(
                self,
                f"{name}OuId",
                value=ou.ref,
                description=f"{name} Organizational Unit ID",
            )

        # Output Service Control Policy IDs
        for name, policy in self.service_control_policies.items():
            CfnOutput(
                self,
                f"{name}PolicyId",
                value=policy.ref,
                description=f"{name} Service Control Policy ID",
            )


class MultiAccountGovernanceApp(cdk.App):
    """
    CDK Application for Multi-Account Governance with Organizations and SCPs.
    """

    def __init__(self) -> None:
        super().__init__()

        # Create the main stack
        MultiAccountGovernanceStack(
            self,
            "MultiAccountGovernanceStack",
            description="Multi-Account Governance with AWS Organizations and Service Control Policies",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region"),
            ),
        )


# Create and run the CDK application
app = MultiAccountGovernanceApp()
app.synth()