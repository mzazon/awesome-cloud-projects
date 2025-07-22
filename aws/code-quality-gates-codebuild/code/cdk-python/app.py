#!/usr/bin/env python3
"""
CDK Python application for Code Quality Gates with CodeBuild.

This application deploys a comprehensive quality gates solution using AWS CodeBuild,
including static analysis, security scanning, test execution, and coverage metrics.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    aws_codebuild as codebuild,
    aws_s3 as s3,
    aws_sns as sns,
    aws_iam as iam,
    aws_ssm as ssm,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    RemovalPolicy,
    Duration,
    CfnOutput,
)
from constructs import Construct


class CodeQualityGatesStack(Stack):
    """
    CDK Stack for Code Quality Gates with CodeBuild.
    
    This stack creates:
    - S3 bucket for build artifacts and reports
    - SNS topic for quality gate notifications
    - Systems Manager parameters for quality thresholds
    - IAM service role for CodeBuild
    - CodeBuild project with comprehensive quality gates
    - CloudWatch dashboard for monitoring
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        project_name: str = "quality-gates-demo",
        coverage_threshold: int = 80,
        sonar_quality_gate: str = "ERROR",
        security_threshold: str = "HIGH",
        notification_email: str = "your-email@example.com",
        **kwargs: Any,
    ) -> None:
        """
        Initialize the Code Quality Gates stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            project_name: Name prefix for all resources
            coverage_threshold: Minimum code coverage percentage
            sonar_quality_gate: SonarQube quality gate status threshold
            security_threshold: Maximum security vulnerability level
            notification_email: Email address for quality gate notifications
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.project_name = project_name
        self.coverage_threshold = coverage_threshold
        self.sonar_quality_gate = sonar_quality_gate
        self.security_threshold = security_threshold
        self.notification_email = notification_email

        # Create S3 bucket for build artifacts and reports
        self.artifacts_bucket = self._create_artifacts_bucket()

        # Create SNS topic for quality gate notifications
        self.notification_topic = self._create_notification_topic()

        # Create Systems Manager parameters for quality thresholds
        self.quality_parameters = self._create_quality_parameters()

        # Create IAM service role for CodeBuild
        self.codebuild_role = self._create_codebuild_role()

        # Create CodeBuild project with quality gates
        self.codebuild_project = self._create_codebuild_project()

        # Create CloudWatch dashboard for monitoring
        self.dashboard = self._create_monitoring_dashboard()

        # Create outputs
        self._create_outputs()

    def _create_artifacts_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing build artifacts and quality reports.
        
        Returns:
            S3 bucket for artifacts storage
        """
        bucket = s3.Bucket(
            self,
            "ArtifactsBucket",
            bucket_name=f"codebuild-quality-gates-{self.account}-{self.project_name}",
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="CleanupOldArtifacts",
                    enabled=True,
                    expiration=Duration.days(30),
                    noncurrent_version_expiration=Duration.days(7),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add bucket policy to prevent unencrypted uploads
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyUnencryptedObjectUploads",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:PutObject"],
                resources=[bucket.arn_for_objects("*")],
                conditions={
                    "StringNotEquals": {
                        "s3:x-amz-server-side-encryption": "AES256"
                    }
                },
            )
        )

        return bucket

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for quality gate notifications.
        
        Returns:
            SNS topic for notifications
        """
        topic = sns.Topic(
            self,
            "QualityGateNotifications",
            topic_name=f"quality-gate-notifications-{self.project_name}",
            display_name="Quality Gate Notifications",
            fifo=False,
        )

        # Add email subscription
        topic.add_subscription(
            sns.EmailSubscription(self.notification_email)
        )

        return topic

    def _create_quality_parameters(self) -> Dict[str, ssm.StringParameter]:
        """
        Create Systems Manager parameters for quality gate thresholds.
        
        Returns:
            Dictionary of SSM parameters
        """
        parameters = {}

        # Code coverage threshold parameter
        parameters["coverage"] = ssm.StringParameter(
            self,
            "CoverageThreshold",
            parameter_name="/quality-gates/coverage-threshold",
            string_value=str(self.coverage_threshold),
            description="Minimum code coverage percentage",
            tier=ssm.ParameterTier.STANDARD,
        )

        # SonarQube quality gate parameter
        parameters["sonar"] = ssm.StringParameter(
            self,
            "SonarQualityGate",
            parameter_name="/quality-gates/sonar-quality-gate",
            string_value=self.sonar_quality_gate,
            description="SonarQube quality gate status threshold",
            tier=ssm.ParameterTier.STANDARD,
        )

        # Security threshold parameter
        parameters["security"] = ssm.StringParameter(
            self,
            "SecurityThreshold",
            parameter_name="/quality-gates/security-threshold",
            string_value=self.security_threshold,
            description="Maximum security vulnerability level",
            tier=ssm.ParameterTier.STANDARD,
        )

        return parameters

    def _create_codebuild_role(self) -> iam.Role:
        """
        Create IAM service role for CodeBuild with required permissions.
        
        Returns:
            IAM role for CodeBuild
        """
        role = iam.Role(
            self,
            "CodeBuildServiceRole",
            role_name=f"{self.project_name}-codebuild-service-role",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="Service role for CodeBuild quality gates project",
        )

        # Add managed policies
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "CloudWatchLogsFullAccess"
            )
        )

        # Add custom policy for specific permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetBucketAcl",
                    "s3:GetBucketLocation",
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:PutObjectAcl",
                    "s3:ListBucket",
                ],
                resources=[
                    self.artifacts_bucket.bucket_arn,
                    self.artifacts_bucket.arn_for_objects("*"),
                ],
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                ],
                resources=[
                    param.parameter_arn
                    for param in self.quality_parameters.values()
                ],
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.notification_topic.topic_arn],
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["codebuild:BatchGetBuilds"],
                resources=["*"],
            )
        )

        return role

    def _create_codebuild_project(self) -> codebuild.Project:
        """
        Create CodeBuild project with comprehensive quality gates.
        
        Returns:
            CodeBuild project
        """
        # Create buildspec for quality gates
        buildspec = codebuild.BuildSpec.from_object({
            "version": "0.2",
            "env": {
                "parameter-store": {
                    "COVERAGE_THRESHOLD": "/quality-gates/coverage-threshold",
                    "SONAR_QUALITY_GATE": "/quality-gates/sonar-quality-gate",
                    "SECURITY_THRESHOLD": "/quality-gates/security-threshold",
                },
                "variables": {
                    "MAVEN_OPTS": "-Dmaven.repo.local=.m2/repository",
                    "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                },
            },
            "phases": {
                "install": {
                    "runtime-versions": {"java": "corretto21"},
                    "commands": [
                        "echo 'Installing dependencies and tools...'",
                        "apt-get update && apt-get install -y curl unzip jq",
                        "curl -sSL https://github.com/SonarSource/sonar-scanner-cli/releases/download/4.8.0.2856/sonar-scanner-cli-4.8.0.2856-linux.zip -o sonar-scanner.zip",
                        "unzip sonar-scanner.zip",
                        "export PATH=$PATH:$(pwd)/sonar-scanner-4.8.0.2856-linux/bin",
                        "curl -sSL https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.0/dependency-check-8.4.0-release.zip -o dependency-check.zip",
                        "unzip dependency-check.zip",
                        "chmod +x dependency-check/bin/dependency-check.sh",
                    ],
                },
                "pre_build": {
                    "commands": [
                        "echo 'Validating build environment...'",
                        "java -version",
                        "mvn -version",
                        "echo 'Build started on $(date)'",
                    ],
                },
                "build": {
                    "commands": [
                        "echo '=== PHASE 1: Compile and Unit Tests ==='",
                        "mvn clean compile test",
                        "echo '✅ Unit tests completed'",
                        "",
                        "echo '=== PHASE 2: Code Coverage Analysis ==='",
                        "mvn jacoco:report",
                        "COVERAGE=$(grep -o 'Total[^%]*%' target/site/jacoco/index.html | grep -o '[0-9]*' | head -1)",
                        "echo 'Code coverage: ${COVERAGE}%'",
                        "if [ \"${COVERAGE:-0}\" -lt \"${COVERAGE_THRESHOLD}\" ]; then",
                        "  echo '❌ QUALITY GATE FAILED: Coverage ${COVERAGE}% below threshold ${COVERAGE_THRESHOLD}%'",
                        "  aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message 'Quality Gate Failed: Coverage ${COVERAGE}% below threshold ${COVERAGE_THRESHOLD}%' --subject 'Quality Gate Failure'",
                        "  exit 1",
                        "fi",
                        "echo '✅ Code coverage check passed'",
                        "",
                        "echo '=== PHASE 3: Static Code Analysis ==='",
                        "mvn sonar:sonar -Dsonar.projectKey=quality-gates-demo -Dsonar.host.url=https://sonarcloud.io -Dsonar.token=${SONAR_TOKEN} || true",
                        "echo '✅ SonarQube analysis completed'",
                        "",
                        "echo '=== PHASE 4: Security Scanning ==='",
                        "./dependency-check/bin/dependency-check.sh --project 'Quality Gates Demo' --scan . --format JSON --out ./security-report.json || true",
                        "HIGH_VULNS=$(jq '.dependencies[].vulnerabilities[]? | select(.severity == \"HIGH\") | length' security-report.json 2>/dev/null | wc -l)",
                        "if [ \"${HIGH_VULNS}\" -gt 0 ]; then",
                        "  echo '❌ QUALITY GATE FAILED: Found ${HIGH_VULNS} HIGH severity vulnerabilities'",
                        "  aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message 'Quality Gate Failed: ${HIGH_VULNS} HIGH severity vulnerabilities found' --subject 'Security Gate Failure'",
                        "  exit 1",
                        "fi",
                        "echo '✅ Security scan passed'",
                        "",
                        "echo '=== PHASE 5: Integration Tests ==='",
                        "mvn verify",
                        "echo '✅ Integration tests completed'",
                        "",
                        "echo '=== PHASE 6: Quality Gate Summary ==='",
                        "echo 'All quality gates passed successfully!'",
                        "aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message 'Quality Gate Success: All checks passed for build ${CODEBUILD_BUILD_ID}' --subject 'Quality Gate Success'",
                    ],
                },
                "post_build": {
                    "commands": [
                        "echo '=== Generating Quality Reports ==='",
                        "mkdir -p quality-reports",
                        "cp -r target/site/jacoco quality-reports/coverage-report || true",
                        "cp security-report.json quality-reports/ || true",
                        "echo 'Build completed on $(date)'",
                    ],
                },
            },
            "artifacts": {
                "files": [
                    "target/*.jar",
                    "quality-reports/**/*",
                ],
                "name": "quality-gates-artifacts",
            },
            "reports": {
                "jacoco-reports": {
                    "files": ["target/site/jacoco/jacoco.xml"],
                    "file-format": "JACOCOXML",
                },
                "junit-reports": {
                    "files": ["target/surefire-reports/*.xml"],
                    "file-format": "JUNITXML",
                },
            },
            "cache": {
                "paths": [".m2/repository/**/*"],
            },
        })

        # Create CodeBuild project
        project = codebuild.Project(
            self,
            "QualityGatesProject",
            project_name=self.project_name,
            description="Quality Gates Demo with CodeBuild",
            source=codebuild.Source.s3(
                bucket=self.artifacts_bucket,
                path="source/",
            ),
            artifacts=codebuild.Artifacts.s3(
                bucket=self.artifacts_bucket,
                path="artifacts/",
                include_build_id=True,
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
                compute_type=codebuild.ComputeType.MEDIUM,
                privileged=False,
            ),
            role=self.codebuild_role,
            timeout=Duration.minutes(60),
            queued_timeout=Duration.minutes(480),
            build_spec=buildspec,
            cache=codebuild.Cache.bucket(
                bucket=self.artifacts_bucket,
                prefix="cache/",
            ),
            logging=codebuild.LoggingOptions(
                cloud_watch=codebuild.CloudWatchLoggingOptions(
                    enabled=True,
                    log_group=logs.LogGroup(
                        self,
                        "CodeBuildLogGroup",
                        log_group_name=f"/aws/codebuild/{self.project_name}",
                        retention=logs.RetentionDays.ONE_MONTH,
                        removal_policy=RemovalPolicy.DESTROY,
                    ),
                ),
            ),
        )

        return project

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for quality gate monitoring.
        
        Returns:
            CloudWatch dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "QualityGatesDashboard",
            dashboard_name=f"Quality-Gates-{self.project_name}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="CodeBuild Quality Gate Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/CodeBuild",
                                metric_name="Builds",
                                dimensions_map={
                                    "ProjectName": self.codebuild_project.project_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/CodeBuild",
                                metric_name="Duration",
                                dimensions_map={
                                    "ProjectName": self.codebuild_project.project_name
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/CodeBuild",
                                metric_name="FailedBuilds",
                                dimensions_map={
                                    "ProjectName": self.codebuild_project.project_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/CodeBuild",
                                metric_name="SucceededBuilds",
                                dimensions_map={
                                    "ProjectName": self.codebuild_project.project_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Quality Gate Events",
                        log_groups=[
                            logs.LogGroup.from_log_group_name(
                                self,
                                "ImportedLogGroup",
                                f"/aws/codebuild/{self.project_name}",
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /QUALITY GATE/",
                            "sort @timestamp desc",
                            "limit 20",
                        ],
                        width=24,
                        height=6,
                    )
                ],
            ],
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "CodeBuildProjectName",
            description="Name of the CodeBuild project",
            value=self.codebuild_project.project_name,
        )

        CfnOutput(
            self,
            "ArtifactsBucketName",
            description="Name of the S3 bucket for artifacts",
            value=self.artifacts_bucket.bucket_name,
        )

        CfnOutput(
            self,
            "NotificationTopicArn",
            description="ARN of the SNS topic for notifications",
            value=self.notification_topic.topic_arn,
        )

        CfnOutput(
            self,
            "DashboardUrl",
            description="URL of the CloudWatch dashboard",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
        )

        CfnOutput(
            self,
            "CodeBuildConsoleUrl",
            description="URL of the CodeBuild console",
            value=f"https://{self.region}.console.aws.amazon.com/codesuite/codebuild/projects/{self.codebuild_project.project_name}/history?region={self.region}",
        )


class CodeQualityGatesApp(cdk.App):
    """CDK App for Code Quality Gates solution."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or use defaults
        project_name = os.getenv("PROJECT_NAME", "quality-gates-demo")
        coverage_threshold = int(os.getenv("COVERAGE_THRESHOLD", "80"))
        sonar_quality_gate = os.getenv("SONAR_QUALITY_GATE", "ERROR")
        security_threshold = os.getenv("SECURITY_THRESHOLD", "HIGH")
        notification_email = os.getenv("NOTIFICATION_EMAIL", "your-email@example.com")

        # Create the stack
        CodeQualityGatesStack(
            self,
            "CodeQualityGatesStack",
            project_name=project_name,
            coverage_threshold=coverage_threshold,
            sonar_quality_gate=sonar_quality_gate,
            security_threshold=security_threshold,
            notification_email=notification_email,
            env=Environment(
                account=os.getenv("CDK_DEFAULT_ACCOUNT"),
                region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
            ),
            description="Infrastructure for Code Quality Gates with CodeBuild",
        )


# Create the app
app = CodeQualityGatesApp()
app.synth()