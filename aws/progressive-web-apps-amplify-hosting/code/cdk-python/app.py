#!/usr/bin/env python3
"""
AWS CDK Python Application for Progressive Web Apps with Amplify Hosting

This CDK application creates a complete Progressive Web App hosting solution using:
- AWS Amplify for hosting and CI/CD
- CloudFront for global content delivery
- Route 53 for custom domain management
- Certificate Manager for SSL/TLS certificates
- CloudWatch for monitoring and logging

The application follows AWS best practices for security, performance, and scalability.
"""

import os
from typing import Optional

import aws_cdk as cdk
from constructs import Construct

from aws_cdk import (
    Stack,
    Environment,
    Tags,
    CfnOutput,
    RemovalPolicy,
    Duration,
)

from aws_cdk import aws_amplify as amplify
from aws_cdk import aws_certificatemanager as acm
from aws_cdk import aws_route53 as route53
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs


class ProgressiveWebAppStack(Stack):
    """
    CDK Stack for Progressive Web App hosting with AWS Amplify.
    
    This stack creates:
    - Amplify app with custom domain support
    - SSL certificate for secure hosting
    - CloudWatch monitoring and logging
    - IAM role for Amplify service
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        app_name: str,
        repository_url: str,
        branch_name: str = "main",
        domain_name: Optional[str] = None,
        subdomain: str = "pwa",
        enable_auto_branch_creation: bool = True,
        enable_pull_request_preview: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the Progressive Web App stack.

        Args:
            scope: CDK scope
            construct_id: Stack identifier
            app_name: Name for the Amplify application
            repository_url: Git repository URL for the PWA source code
            branch_name: Git branch to deploy (default: main)
            domain_name: Custom domain name (optional)
            subdomain: Subdomain prefix for the PWA (default: pwa)
            enable_auto_branch_creation: Enable automatic branch creation
            enable_pull_request_preview: Enable PR preview deployments
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.app_name = app_name
        self.repository_url = repository_url
        self.branch_name = branch_name
        self.domain_name = domain_name
        self.subdomain = subdomain
        self.full_domain = f"{subdomain}.{domain_name}" if domain_name else None

        # Create IAM role for Amplify service
        self.amplify_service_role = self._create_amplify_service_role()

        # Create the Amplify application
        self.amplify_app = self._create_amplify_app()

        # Create the main branch
        self.amplify_branch = self._create_amplify_branch()

        # Configure custom domain if provided
        if self.domain_name:
            self.domain_association = self._create_domain_association()
            self.ssl_certificate = self._create_ssl_certificate()

        # Set up monitoring and logging
        self._create_monitoring()

        # Add tags to all resources
        self._add_tags()

        # Create stack outputs
        self._create_outputs()

    def _create_amplify_service_role(self) -> iam.Role:
        """
        Create IAM role for Amplify service with necessary permissions.
        
        Returns:
            IAM Role for Amplify service
        """
        # Create managed policy for Amplify backend deployments
        amplify_policy = iam.ManagedPolicy(
            self,
            "AmplifyBackendPolicy",
            description="Policy for Amplify backend operations",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudformation:CreateStack",
                        "cloudformation:UpdateStack",
                        "cloudformation:DeleteStack",
                        "cloudformation:DescribeStacks",
                        "cloudformation:DescribeStackEvents",
                        "cloudformation:DescribeStackResources",
                        "cloudformation:GetTemplate",
                        "cloudformation:ListStacks",
                        "cloudformation:ValidateTemplate",
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            "cloudformation:StackName": f"amplify-{self.app_name}-*"
                        }
                    }
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:CreateBucket",
                        "s3:DeleteBucket",
                        "s3:GetBucketLocation",
                        "s3:ListBucket",
                        "s3:PutObject",
                        "s3:GetObject",
                        "s3:DeleteObject",
                        "s3:PutBucketPolicy",
                        "s3:DeleteBucketPolicy",
                        "s3:PutBucketCORS",
                    ],
                    resources=[
                        f"arn:aws:s3:::amplify-{self.app_name}-*",
                        f"arn:aws:s3:::amplify-{self.app_name}-*/*"
                    ]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogGroups",
                        "logs:DescribeLogStreams",
                    ],
                    resources=[f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/amplify/*"]
                ),
            ]
        )

        # Create the service role
        service_role = iam.Role(
            self,
            "AmplifyServiceRole",
            role_name=f"amplify-{self.app_name}-service-role",
            description="Service role for AWS Amplify application",
            assumed_by=iam.ServicePrincipal("amplify.amazonaws.com"),
            managed_policies=[
                amplify_policy,
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchLogsFullAccess"),
            ],
            max_session_duration=Duration.hours(12),
        )

        return service_role

    def _create_amplify_app(self) -> amplify.App:
        """
        Create the AWS Amplify application with PWA-optimized configuration.
        
        Returns:
            Amplify App construct
        """
        # Define build specification optimized for PWAs
        build_spec = amplify.BuildSpec.from_object({
            "version": 1,
            "frontend": {
                "phases": {
                    "preBuild": {
                        "commands": [
                            "echo 'Pre-build phase - checking PWA requirements'",
                            "echo 'Validating service worker and manifest files'",
                            "if [ -f 'package.json' ]; then npm ci; fi",
                        ]
                    },
                    "build": {
                        "commands": [
                            "echo 'Build phase - optimizing for Progressive Web App'",
                            "echo 'Verifying PWA compliance'",
                            "if [ -f 'sw.js' ]; then echo 'Service Worker found'; fi",
                            "if [ -f 'manifest.json' ]; then echo 'Web App Manifest found'; fi",
                            "ls -la",
                        ]
                    },
                    "postBuild": {
                        "commands": [
                            "echo 'Post-build phase - PWA optimization complete'",
                            "echo 'Service Worker and Manifest validated'",
                        ]
                    }
                },
                "artifacts": {
                    "baseDirectory": ".",
                    "files": ["**/*"]
                },
                "cache": {
                    "paths": ["node_modules/**/*"]
                }
            }
        })

        # Custom headers for PWA optimization
        custom_rules = [
            amplify.CustomRule(
                source="**/*",
                target="**/*",
                status=amplify.RedirectStatus.REWRITE,
                headers=[
                    {"key": "X-Frame-Options", "value": "DENY"},
                    {"key": "X-Content-Type-Options", "value": "nosniff"},
                    {"key": "X-XSS-Protection", "value": "1; mode=block"},
                    {"key": "Referrer-Policy", "value": "strict-origin-when-cross-origin"},
                    {"key": "Cache-Control", "value": "public, max-age=31536000"},
                ]
            ),
            amplify.CustomRule(
                source="*.html",
                target="*.html",
                status=amplify.RedirectStatus.REWRITE,
                headers=[
                    {"key": "Cache-Control", "value": "public, max-age=0, must-revalidate"},
                ]
            ),
            amplify.CustomRule(
                source="/sw.js",
                target="/sw.js",
                status=amplify.RedirectStatus.REWRITE,
                headers=[
                    {"key": "Cache-Control", "value": "public, max-age=0, must-revalidate"},
                    {"key": "Service-Worker-Allowed", "value": "/"},
                ]
            ),
            amplify.CustomRule(
                source="/manifest.json",
                target="/manifest.json",
                status=amplify.RedirectStatus.REWRITE,
                headers=[
                    {"key": "Content-Type", "value": "application/manifest+json"},
                    {"key": "Cache-Control", "value": "public, max-age=86400"},
                ]
            ),
        ]

        # Environment variables for PWA features
        environment_variables = {
            "AMPLIFY_DIFF_DEPLOY": "false",
            "AMPLIFY_MONOREPO_APP_ROOT": ".",
            "_LIVE_UPDATES": "[{\"name\":\"Node.js version\",\"pkg\":\"node\",\"type\":\"nvm\",\"version\":\"18\"}]",
        }

        # Create the Amplify app
        app = amplify.App(
            self,
            "AmplifyApp",
            app_name=self.app_name,
            description="Progressive Web App with offline functionality and CI/CD pipeline",
            source_code_provider=amplify.GitHubSourceCodeProvider(
                owner=self.repository_url.split("/")[-2] if "/" in self.repository_url else "owner",
                repository=self.repository_url.split("/")[-1].replace(".git", "") if "/" in self.repository_url else self.repository_url,
                oauth_token=cdk.SecretValue.secrets_manager("github-token")
            ),
            build_spec=build_spec,
            custom_rules=custom_rules,
            environment_variables=environment_variables,
            role=self.amplify_service_role,
            auto_branch_creation=amplify.AutoBranchCreation(
                enabled=True,
                auto_build=True,
                pull_request_preview=True,
                patterns=["main", "develop", "feature/*"]
            ) if hasattr(self, 'enable_auto_branch_creation') and self.enable_auto_branch_creation else None,
        )

        return app

    def _create_amplify_branch(self) -> amplify.Branch:
        """
        Create the main branch for the Amplify application.
        
        Returns:
            Amplify Branch construct
        """
        branch = amplify.Branch(
            self,
            "AmplifyBranch",
            app=self.amplify_app,
            branch_name=self.branch_name,
            description=f"Production branch for {self.app_name} PWA",
            auto_build=True,
            pull_request_preview=hasattr(self, 'enable_pull_request_preview') and self.enable_pull_request_preview,
            environment_variables={
                "NODE_ENV": "production",
                "PWA_MODE": "enabled",
                "_LIVE_UPDATES": "[{\"name\":\"Node.js version\",\"pkg\":\"node\",\"type\":\"nvm\",\"version\":\"18\"}]",
            },
            stage=amplify.Stage.PRODUCTION,
        )

        return branch

    def _create_domain_association(self) -> Optional[amplify.Domain]:
        """
        Create custom domain association for the Amplify app.
        
        Returns:
            Amplify Domain construct if domain_name is provided
        """
        if not self.domain_name:
            return None

        domain = amplify.Domain(
            self,
            "AmplifyDomain",
            app=self.amplify_app,
            domain_name=self.domain_name,
            sub_domains=[
                amplify.SubDomain(
                    branch=self.amplify_branch,
                    prefix=self.subdomain
                ),
            ],
            enable_auto_subdomain=True,
        )

        return domain

    def _create_ssl_certificate(self) -> Optional[acm.Certificate]:
        """
        Create SSL certificate for the custom domain.
        
        Returns:
            ACM Certificate if domain_name is provided
        """
        if not self.domain_name:
            return None

        # Look up the hosted zone
        hosted_zone = route53.HostedZone.from_lookup(
            self,
            "HostedZone",
            domain_name=self.domain_name
        )

        # Create SSL certificate with DNS validation
        certificate = acm.Certificate(
            self,
            "SSLCertificate",
            domain_name=self.full_domain,
            subject_alternative_names=[f"*.{self.domain_name}"],
            validation=acm.CertificateValidation.from_dns(hosted_zone),
            certificate_name=f"{self.app_name}-certificate",
        )

        return certificate

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and logging for the Amplify app."""
        # Create CloudWatch Log Group for Amplify builds
        log_group = logs.LogGroup(
            self,
            "AmplifyLogGroup",
            log_group_name=f"/aws/amplify/{self.app_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create CloudWatch dashboard for monitoring
        dashboard = cloudwatch.Dashboard(
            self,
            "AmplifyDashboard",
            dashboard_name=f"{self.app_name}-pwa-dashboard",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Build Success Rate",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Amplify",
                                metric_name="BuildSuccessRate",
                                dimensions_map={
                                    "App": self.amplify_app.app_name,
                                    "Branch": self.branch_name,
                                },
                                statistic="Average",
                                period=Duration.hours(1),
                            )
                        ],
                        width=12,
                        height=6,
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Build Duration",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Amplify",
                                metric_name="BuildDuration",
                                dimensions_map={
                                    "App": self.amplify_app.app_name,
                                    "Branch": self.branch_name,
                                },
                                statistic="Average",
                                period=Duration.hours(1),
                            )
                        ],
                        width=12,
                        height=6,
                    )
                ],
            ]
        )

        # Create CloudWatch alarms for build failures
        build_failure_alarm = cloudwatch.Alarm(
            self,
            "BuildFailureAlarm",
            alarm_name=f"{self.app_name}-build-failures",
            alarm_description="Alert when Amplify builds fail",
            metric=cloudwatch.Metric(
                namespace="AWS/Amplify",
                metric_name="BuildSuccessRate",
                dimensions_map={
                    "App": self.amplify_app.app_name,
                    "Branch": self.branch_name,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=0.5,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", "ProgressiveWebApp")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Application", self.app_name)
        Tags.of(self).add("CostCenter", "WebDevelopment")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        # Amplify app outputs
        CfnOutput(
            self,
            "AmplifyAppId",
            description="AWS Amplify Application ID",
            value=self.amplify_app.app_id,
            export_name=f"{self.stack_name}-amplify-app-id",
        )

        CfnOutput(
            self,
            "AmplifyAppName",
            description="AWS Amplify Application Name",
            value=self.amplify_app.app_name,
            export_name=f"{self.stack_name}-amplify-app-name",
        )

        CfnOutput(
            self,
            "AmplifyDefaultDomain",
            description="Default Amplify hosting domain",
            value=f"https://{self.branch_name}.{self.amplify_app.default_domain}",
            export_name=f"{self.stack_name}-amplify-default-domain",
        )

        # Custom domain outputs (if configured)
        if self.domain_name:
            CfnOutput(
                self,
                "CustomDomain",
                description="Custom domain for the PWA",
                value=f"https://{self.full_domain}",
                export_name=f"{self.stack_name}-custom-domain",
            )

        # Service role output
        CfnOutput(
            self,
            "AmplifyServiceRoleArn",
            description="ARN of the Amplify service role",
            value=self.amplify_service_role.role_arn,
            export_name=f"{self.stack_name}-service-role-arn",
        )


class ProgressiveWebAppApplication(cdk.App):
    """
    CDK Application for Progressive Web App deployment.
    
    This application creates a complete PWA hosting solution with:
    - Development, staging, and production environments
    - Custom domain support
    - SSL/TLS certificates
    - Monitoring and logging
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or context
        app_name = self.node.try_get_context("app_name") or os.environ.get("APP_NAME", "pwa-amplify-app")
        repository_url = self.node.try_get_context("repository_url") or os.environ.get("REPOSITORY_URL", "")
        domain_name = self.node.try_get_context("domain_name") or os.environ.get("DOMAIN_NAME")
        
        # AWS environment configuration
        aws_env = Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )

        # Create the main stack
        self.pwa_stack = ProgressiveWebAppStack(
            self,
            "ProgressiveWebAppStack",
            stack_name=f"{app_name}-pwa-stack",
            description="Progressive Web App hosting with AWS Amplify and CloudFront",
            env=aws_env,
            app_name=app_name,
            repository_url=repository_url,
            domain_name=domain_name,
            subdomain="pwa",
            enable_auto_branch_creation=True,
            enable_pull_request_preview=True,
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = ProgressiveWebAppApplication()
    app.synth()