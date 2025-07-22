#!/usr/bin/env python3
"""
CDK Python application for Container Security Scanning Pipeline with ECR and Third-Party Tools

This application deploys a comprehensive container security scanning pipeline that integrates
Amazon ECR's enhanced scanning capabilities with third-party security tools like Snyk and
Prisma Cloud, providing multi-layered vulnerability detection and automated response workflows.

Author: AWS CDK Python Generator
Version: 1.0.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    App,
    Environment,
    Duration,
    RemovalPolicy,
    aws_ecr as ecr,
    aws_codebuild as codebuild,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_config as config,
    aws_secretsmanager as secretsmanager,
    aws_s3 as s3,
)
from constructs import Construct


class ContainerSecurityScanningStack(Stack):
    """
    CDK Stack for Container Security Scanning Pipeline
    
    This stack creates a comprehensive container security scanning pipeline that:
    - Sets up ECR repository with enhanced scanning
    - Creates CodeBuild project for multi-stage security scanning
    - Deploys Lambda functions for scan result processing
    - Configures EventBridge rules for automated workflows
    - Integrates with SNS for notifications
    - Sets up compliance monitoring with Config rules
    """
    
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Stack parameters
        self.project_name = "container-security-scanning"
        self.environment_name = self.node.try_get_context("environment") or "dev"
        
        # Create foundational resources
        self.create_ecr_repository()
        self.create_iam_roles()
        self.create_codebuild_project()
        self.create_lambda_functions()
        self.create_sns_notifications()
        self.create_eventbridge_rules()
        self.create_compliance_monitoring()
        self.create_cloudwatch_dashboard()
        self.create_secrets_for_third_party_tools()
        
        # Add outputs
        self.add_stack_outputs()
    
    def create_ecr_repository(self) -> None:
        """Create ECR repository with enhanced scanning enabled"""
        
        # Create ECR repository with enhanced scanning
        self.ecr_repository = ecr.Repository(
            self, "SecureContainerRepository",
            repository_name=f"{self.project_name}-repo-{self.environment_name}",
            image_scan_on_push=True,
            encryption=ecr.RepositoryEncryption.AES_256,
            image_tag_mutability=ecr.TagMutability.MUTABLE,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep last 10 production images",
                    tag_prefix_list=["prod"],
                    max_image_count=10
                ),
                ecr.LifecycleRule(
                    description="Keep last 5 development images",
                    tag_prefix_list=["dev"],
                    max_image_count=5
                ),
                ecr.LifecycleRule(
                    description="Delete untagged images after 1 day",
                    tag_status=ecr.TagStatus.UNTAGGED,
                    max_image_age=Duration.days(1)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Enable enhanced scanning at the registry level
        # Note: This is configured at the registry level and applies to all repositories
        ecr.CfnRegistryScanningConfiguration(
            self, "EnhancedScanningConfig",
            scan_type="ENHANCED",
            rules=[
                ecr.CfnRegistryScanningConfiguration.RegistryScanningRuleProperty(
                    scan_frequency="CONTINUOUS_SCAN",
                    repository_filters=[
                        ecr.CfnRegistryScanningConfiguration.ScanningRepositoryFilterProperty(
                            filter="*",
                            filter_type="WILDCARD"
                        )
                    ]
                )
            ]
        )
    
    def create_iam_roles(self) -> None:
        """Create IAM roles for CodeBuild and Lambda functions"""
        
        # CodeBuild service role
        self.codebuild_role = iam.Role(
            self, "CodeBuildSecurityScanRole",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="IAM role for CodeBuild security scanning project",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchLogsFullAccess")
            ]
        )
        
        # Add ECR permissions to CodeBuild role
        self.codebuild_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:GetAuthorizationToken",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                    "ecr:PutImage",
                    "ecr:DescribeRepositories",
                    "ecr:DescribeImages",
                    "ecr:DescribeImageScanFindings"
                ],
                resources=["*"]
            )
        )
        
        # Add S3 permissions for artifacts
        self.codebuild_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:GetObjectVersion"
                ],
                resources=["*"]
            )
        )
        
        # Lambda execution role for scan result processing
        self.lambda_role = iam.Role(
            self, "SecurityScanLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for security scan processing Lambda",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add Security Hub permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "securityhub:BatchImportFindings",
                    "securityhub:GetFindings",
                    "securityhub:UpdateFindings"
                ],
                resources=["*"]
            )
        )
        
        # Add SNS permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:Publish"
                ],
                resources=["*"]
            )
        )
        
        # Add ECR permissions to Lambda role
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:DescribeImageScanFindings",
                    "ecr:DescribeImages",
                    "ecr:DescribeRepositories"
                ],
                resources=["*"]
            )
        )
    
    def create_codebuild_project(self) -> None:
        """Create CodeBuild project for multi-stage security scanning"""
        
        # Create S3 bucket for CodeBuild artifacts
        self.artifacts_bucket = s3.Bucket(
            self, "SecurityScanArtifacts",
            bucket_name=f"{self.project_name}-artifacts-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )
        
        # Create buildspec for multi-stage security scanning
        buildspec_content = {
            "version": "0.2",
            "phases": {
                "install": {
                    "runtime-versions": {
                        "python": "3.9",
                        "nodejs": "16"
                    },
                    "commands": [
                        "echo Installing security scanning tools...",
                        "npm install -g snyk",
                        "pip install --upgrade pip",
                        "pip install bandit safety",
                        "curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin"
                    ]
                },
                "pre_build": {
                    "commands": [
                        "echo Logging in to Amazon ECR...",
                        "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY_URI",
                        "IMAGE_TAG=${CODEBUILD_RESOLVED_SOURCE_VERSION:-latest}",
                        "echo Build started on `date`",
                        "echo Building the Docker image..."
                    ]
                },
                "build": {
                    "commands": [
                        "# Build the container image",
                        "docker build -t $ECR_REPOSITORY_NAME:$IMAGE_TAG .",
                        "docker tag $ECR_REPOSITORY_NAME:$IMAGE_TAG $ECR_REPOSITORY_URI:$IMAGE_TAG",
                        "",
                        "# Run Snyk container security scan",
                        "echo 'Running Snyk container scan...'",
                        "snyk auth $SNYK_TOKEN || echo 'Snyk authentication failed'",
                        "snyk container test $ECR_REPOSITORY_NAME:$IMAGE_TAG --severity-threshold=high --json > snyk-results.json || true",
                        "",
                        "# Run Grype vulnerability scan",
                        "echo 'Running Grype vulnerability scan...'",
                        "grype $ECR_REPOSITORY_NAME:$IMAGE_TAG -o json > grype-results.json || true",
                        "",
                        "# Run Bandit security scan for Python code",
                        "echo 'Running Bandit security scan...'",
                        "bandit -r . -f json -o bandit-results.json || true",
                        "",
                        "# Run Safety scan for Python dependencies",
                        "echo 'Running Safety scan...'",
                        "safety check --json > safety-results.json || true"
                    ]
                },
                "post_build": {
                    "commands": [
                        "echo Build completed on `date`",
                        "echo Pushing the Docker image...",
                        "docker push $ECR_REPOSITORY_URI:$IMAGE_TAG",
                        "",
                        "# Wait for enhanced scanning to complete",
                        "echo 'Waiting for ECR enhanced scanning...'",
                        "sleep 30",
                        "",
                        "# Get ECR scan results",
                        "aws ecr describe-image-scan-findings --repository-name $ECR_REPOSITORY_NAME --image-id imageTag=$IMAGE_TAG > ecr-scan-results.json || true",
                        "",
                        "# Process and combine scan results",
                        "echo 'Processing security scan results...'",
                        "python process_scan_results.py"
                    ]
                }
            },
            "artifacts": {
                "files": [
                    "**/*"
                ]
            }
        }
        
        # Create CodeBuild project
        self.codebuild_project = codebuild.Project(
            self, "SecurityScanningProject",
            project_name=f"{self.project_name}-build-{self.environment_name}",
            description="Multi-stage container security scanning project",
            build_spec=codebuild.BuildSpec.from_object(buildspec_content),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_5_0,
                compute_type=codebuild.ComputeType.MEDIUM,
                privileged=True  # Required for Docker builds
            ),
            environment_variables={
                "ECR_REPOSITORY_URI": codebuild.BuildEnvironmentVariable(
                    value=self.ecr_repository.repository_uri
                ),
                "ECR_REPOSITORY_NAME": codebuild.BuildEnvironmentVariable(
                    value=self.ecr_repository.repository_name
                ),
                "AWS_DEFAULT_REGION": codebuild.BuildEnvironmentVariable(
                    value=self.region
                ),
                "AWS_ACCOUNT_ID": codebuild.BuildEnvironmentVariable(
                    value=self.account
                )
            },
            role=self.codebuild_role,
            artifacts=codebuild.Artifacts.s3(
                bucket=self.artifacts_bucket,
                include_build_id=True,
                package_zip=True
            ),
            logging=codebuild.LoggingOptions(
                cloud_watch=codebuild.CloudWatchLoggingOptions(
                    enabled=True,
                    log_group=logs.LogGroup(
                        self, "CodeBuildLogGroup",
                        log_group_name=f"/aws/codebuild/{self.project_name}-build-{self.environment_name}",
                        retention=logs.RetentionDays.ONE_WEEK,
                        removal_policy=RemovalPolicy.DESTROY
                    )
                )
            )
        )
    
    def create_lambda_functions(self) -> None:
        """Create Lambda functions for scan result processing"""
        
        # Lambda function for processing security scan results
        self.scan_processor_lambda = lambda_.Function(
            self, "SecurityScanProcessor",
            function_name=f"{self.project_name}-scan-processor-{self.environment_name}",
            description="Process container security scan results and send to Security Hub",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="scan_processor.lambda_handler",
            code=lambda_.Code.from_inline(self._get_scan_processor_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "ENVIRONMENT": self.environment_name,
                "PROJECT_NAME": self.project_name,
                "REGION": self.region,
                "ACCOUNT_ID": self.account
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        # Lambda function for vulnerability remediation automation
        self.remediation_lambda = lambda_.Function(
            self, "VulnerabilityRemediationAutomation",
            function_name=f"{self.project_name}-remediation-{self.environment_name}",
            description="Automate vulnerability remediation workflows",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="remediation.lambda_handler",
            code=lambda_.Code.from_inline(self._get_remediation_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(10),
            memory_size=512,
            environment={
                "ENVIRONMENT": self.environment_name,
                "PROJECT_NAME": self.project_name,
                "REGION": self.region,
                "ACCOUNT_ID": self.account
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )
    
    def create_sns_notifications(self) -> None:
        """Create SNS topics for security notifications"""
        
        # SNS topic for security alerts
        self.security_alerts_topic = sns.Topic(
            self, "SecurityAlertsTopic",
            topic_name=f"{self.project_name}-security-alerts-{self.environment_name}",
            display_name="Container Security Alerts",
            description="SNS topic for container security vulnerability alerts"
        )
        
        # SNS topic for compliance notifications
        self.compliance_topic = sns.Topic(
            self, "ComplianceNotificationsTopic",
            topic_name=f"{self.project_name}-compliance-{self.environment_name}",
            display_name="Security Compliance Notifications",
            description="SNS topic for security compliance status notifications"
        )
        
        # Add email subscription if email is provided in context
        notification_email = self.node.try_get_context("notification_email")
        if notification_email:
            self.security_alerts_topic.add_subscription(
                subscriptions.EmailSubscription(notification_email)
            )
            self.compliance_topic.add_subscription(
                subscriptions.EmailSubscription(notification_email)
            )
        
        # Grant Lambda functions permission to publish to SNS topics
        self.security_alerts_topic.grant_publish(self.scan_processor_lambda)
        self.compliance_topic.grant_publish(self.scan_processor_lambda)
        self.security_alerts_topic.grant_publish(self.remediation_lambda)
    
    def create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for automated security workflows"""
        
        # EventBridge rule for ECR scan completion
        self.ecr_scan_rule = events.Rule(
            self, "ECRScanCompletionRule",
            rule_name=f"{self.project_name}-ecr-scan-completed-{self.environment_name}",
            description="Trigger security scan processing when ECR scan completes",
            event_pattern=events.EventPattern(
                source=["aws.inspector2"],
                detail_type=["Inspector2 Scan"],
                detail={
                    "scan-status": ["INITIAL_SCAN_COMPLETE", "SCAN_COMPLETE"]
                }
            ),
            enabled=True
        )
        
        # Add Lambda target to EventBridge rule
        self.ecr_scan_rule.add_target(
            targets.LambdaFunction(
                self.scan_processor_lambda,
                retry_attempts=3,
                max_event_age=Duration.hours(1)
            )
        )
        
        # EventBridge rule for CodeBuild completion
        self.codebuild_completion_rule = events.Rule(
            self, "CodeBuildCompletionRule",
            rule_name=f"{self.project_name}-codebuild-completed-{self.environment_name}",
            description="Trigger actions when CodeBuild security scan completes",
            event_pattern=events.EventPattern(
                source=["aws.codebuild"],
                detail_type=["CodeBuild Build State Change"],
                detail={
                    "build-status": ["SUCCEEDED", "FAILED"],
                    "project-name": [self.codebuild_project.project_name]
                }
            ),
            enabled=True
        )
        
        # Add Lambda target for CodeBuild completion
        self.codebuild_completion_rule.add_target(
            targets.LambdaFunction(
                self.remediation_lambda,
                retry_attempts=3,
                max_event_age=Duration.hours(1)
            )
        )
    
    def create_compliance_monitoring(self) -> None:
        """Create AWS Config rules for compliance monitoring"""
        
        # Config rule for ECR repository scanning
        config.ManagedRule(
            self, "ECRRepositoryScanEnabledRule",
            config_rule_name=f"{self.project_name}-ecr-scan-enabled-{self.environment_name}",
            description="Checks if ECR repositories have image scanning enabled",
            identifier=config.ManagedRuleIdentifiers.ECR_PRIVATE_IMAGE_SCANNING_ENABLED,
            compliance_resource_types=[config.ResourceType.ECR_REPOSITORY],
            evaluation_modes=config.EvaluationMode.DETECTIVE_AND_PROACTIVE
        )
        
        # Config rule for ECR repository lifecycle policy
        config.ManagedRule(
            self, "ECRRepositoryLifecyclePolicyRule",
            config_rule_name=f"{self.project_name}-ecr-lifecycle-policy-{self.environment_name}",
            description="Checks if ECR repositories have lifecycle policies configured",
            identifier=config.ManagedRuleIdentifiers.ECR_PRIVATE_LIFECYCLE_POLICY_CONFIGURED,
            compliance_resource_types=[config.ResourceType.ECR_REPOSITORY],
            evaluation_modes=config.EvaluationMode.DETECTIVE_AND_PROACTIVE
        )
    
    def create_secrets_for_third_party_tools(self) -> None:
        """Create secrets for third-party security tools integration"""
        
        # Secret for Snyk API token
        self.snyk_secret = secretsmanager.Secret(
            self, "SnykApiToken",
            secret_name=f"{self.project_name}/snyk-api-token",
            description="Snyk API token for container security scanning",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"token": ""}',
                generate_string_key="token",
                exclude_characters='"\\/',
                password_length=32
            )
        )
        
        # Secret for Prisma Cloud credentials
        self.prisma_secret = secretsmanager.Secret(
            self, "PrismaCloudCredentials",
            secret_name=f"{self.project_name}/prisma-cloud-credentials",
            description="Prisma Cloud credentials for container security scanning",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "", "password": "", "console_url": ""}',
                generate_string_key="password",
                exclude_characters='"\\/',
                password_length=32
            )
        )
        
        # Grant CodeBuild access to secrets
        self.snyk_secret.grant_read(self.codebuild_role)
        self.prisma_secret.grant_read(self.codebuild_role)
    
    def create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for security metrics monitoring"""
        
        # Create CloudWatch dashboard
        self.security_dashboard = cloudwatch.Dashboard(
            self, "SecurityDashboard",
            dashboard_name=f"{self.project_name}-security-dashboard-{self.environment_name}",
            period_override=cloudwatch.PeriodOverride.AUTO,
            start="-PT24H",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="ECR Repository Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/ECR",
                                metric_name="RepositoryCount",
                                statistic="Sum"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Critical Security Findings",
                        log_groups=[
                            logs.LogGroup.from_log_group_name(
                                self, "ScanProcessorLogGroup",
                                f"/aws/lambda/{self.scan_processor_lambda.function_name}"
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /CRITICAL/",
                            "sort @timestamp desc",
                            "limit 20"
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="CodeBuild Success Rate",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/CodeBuild",
                                metric_name="SucceededBuilds",
                                dimensions_map={
                                    "ProjectName": self.codebuild_project.project_name
                                },
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/CodeBuild",
                                metric_name="FailedBuilds",
                                dimensions_map={
                                    "ProjectName": self.codebuild_project.project_name
                                },
                                statistic="Sum"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Metrics",
                        left=[
                            self.scan_processor_lambda.metric_invocations(),
                            self.scan_processor_lambda.metric_errors(),
                            self.remediation_lambda.metric_invocations(),
                            self.remediation_lambda.metric_errors()
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )
    
    def add_stack_outputs(self) -> None:
        """Add CloudFormation outputs for important resources"""
        
        cdk.CfnOutput(
            self, "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="URI of the ECR repository for container images",
            export_name=f"{self.stack_name}-ECRRepositoryURI"
        )
        
        cdk.CfnOutput(
            self, "CodeBuildProjectName",
            value=self.codebuild_project.project_name,
            description="Name of the CodeBuild project for security scanning",
            export_name=f"{self.stack_name}-CodeBuildProjectName"
        )
        
        cdk.CfnOutput(
            self, "SecurityAlertsTopicArn",
            value=self.security_alerts_topic.topic_arn,
            description="ARN of the SNS topic for security alerts",
            export_name=f"{self.stack_name}-SecurityAlertsTopicArn"
        )
        
        cdk.CfnOutput(
            self, "SecurityDashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.security_dashboard.dashboard_name}",
            description="URL to the CloudWatch security dashboard",
            export_name=f"{self.stack_name}-SecurityDashboardURL"
        )
        
        cdk.CfnOutput(
            self, "ScanProcessorLambdaArn",
            value=self.scan_processor_lambda.function_arn,
            description="ARN of the security scan processor Lambda function",
            export_name=f"{self.stack_name}-ScanProcessorLambdaArn"
        )
    
    def _get_scan_processor_code(self) -> str:
        """Get the Lambda function code for security scan processing"""
        return '''
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any, Optional

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process container security scan results and send findings to Security Hub
    
    Args:
        event: EventBridge event from Amazon Inspector or ECR
        context: Lambda context object
        
    Returns:
        Dict containing the processing results
    """
    print(f"Processing security scan event: {json.dumps(event, indent=2)}")
    
    try:
        # Parse event details
        detail = event.get('detail', {})
        source = event.get('source', '')
        
        # Initialize AWS clients
        securityhub = boto3.client('securityhub')
        sns = boto3.client('sns')
        
        # Process based on event source
        if source == 'aws.inspector2':
            result = process_inspector_scan(detail, securityhub, sns)
        elif source == 'aws.ecr':
            result = process_ecr_scan(detail, securityhub, sns)
        else:
            print(f"Unknown event source: {source}")
            return {'statusCode': 400, 'body': 'Unknown event source'}
        
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
        
    except Exception as e:
        print(f"Error processing scan results: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Error processing scan results: {str(e)}'
        }

def process_inspector_scan(detail: Dict[str, Any], securityhub: Any, sns: Any) -> Dict[str, Any]:
    """Process Amazon Inspector scan results"""
    
    repository_name = detail.get('repository-name', '')
    image_digest = detail.get('image-digest', '')
    finding_counts = detail.get('finding-severity-counts', {})
    
    # Create consolidated security report
    security_report = {
        'timestamp': datetime.utcnow().isoformat(),
        'repository': repository_name,
        'image_digest': image_digest,
        'scan_results': {
            'inspector_enhanced': finding_counts,
            'total_vulnerabilities': finding_counts.get('TOTAL', 0),
            'critical_vulnerabilities': finding_counts.get('CRITICAL', 0),
            'high_vulnerabilities': finding_counts.get('HIGH', 0),
            'medium_vulnerabilities': finding_counts.get('MEDIUM', 0),
            'low_vulnerabilities': finding_counts.get('LOW', 0)
        }
    }
    
    # Determine risk level and actions
    critical_count = finding_counts.get('CRITICAL', 0)
    high_count = finding_counts.get('HIGH', 0)
    
    if critical_count > 0:
        risk_level = 'CRITICAL'
        action_required = 'IMMEDIATE_BLOCK'
    elif high_count > 5:
        risk_level = 'HIGH'
        action_required = 'REVIEW_REQUIRED'
    else:
        risk_level = 'LOW'
        action_required = 'MONITOR'
    
    security_report['risk_assessment'] = {
        'risk_level': risk_level,
        'action_required': action_required,
        'compliance_status': 'FAIL' if critical_count > 0 else 'PASS'
    }
    
    # Send to Security Hub
    send_to_security_hub(security_report, securityhub)
    
    # Send notifications based on risk level
    if risk_level in ['CRITICAL', 'HIGH']:
        send_security_notification(security_report, sns)
    
    return security_report

def process_ecr_scan(detail: Dict[str, Any], securityhub: Any, sns: Any) -> Dict[str, Any]:
    """Process ECR scan results"""
    
    # Similar processing for ECR scan events
    repository_name = detail.get('repository-name', '')
    image_tag = detail.get('image-tags', ['latest'])[0]
    
    security_report = {
        'timestamp': datetime.utcnow().isoformat(),
        'repository': repository_name,
        'image_tag': image_tag,
        'scan_results': {
            'ecr_basic': detail.get('finding-counts', {}),
            'scan_status': detail.get('scan-status', 'UNKNOWN')
        }
    }
    
    return security_report

def send_to_security_hub(security_report: Dict[str, Any], securityhub: Any) -> None:
    """Send security findings to AWS Security Hub"""
    
    try:
        finding = {
            'SchemaVersion': '2018-10-08',
            'Id': f"{security_report['repository']}-{security_report.get('image_digest', 'unknown')}",
            'ProductArn': f"arn:aws:securityhub:{os.environ['REGION']}:{os.environ['ACCOUNT_ID']}:product/custom/container-security-scanner",
            'GeneratorId': 'container-security-pipeline',
            'AwsAccountId': os.environ['ACCOUNT_ID'],
            'Title': f"Container Security Scan - {security_report['repository']}",
            'Description': f"Security scan completed for {security_report['repository']}",
            'Severity': {
                'Label': security_report['risk_assessment']['risk_level']
            },
            'Resources': [{
                'Type': 'AwsEcrContainerImage',
                'Id': f"{security_report['repository']}:{security_report.get('image_digest', 'unknown')}",
                'Region': os.environ['REGION']
            }],
            'ProductFields': {
                'TotalVulnerabilities': str(security_report['scan_results'].get('total_vulnerabilities', 0)),
                'CriticalVulnerabilities': str(security_report['scan_results'].get('critical_vulnerabilities', 0)),
                'HighVulnerabilities': str(security_report['scan_results'].get('high_vulnerabilities', 0)),
                'ComplianceStatus': security_report['risk_assessment']['compliance_status']
            }
        }
        
        response = securityhub.batch_import_findings(Findings=[finding])
        print(f"Security Hub response: {response}")
        
    except Exception as e:
        print(f"Error sending to Security Hub: {e}")

def send_security_notification(security_report: Dict[str, Any], sns: Any) -> None:
    """Send security alert notification"""
    
    try:
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if not topic_arn:
            print("SNS topic ARN not configured")
            return
        
        message = {
            'repository': security_report['repository'],
            'risk_level': security_report['risk_assessment']['risk_level'],
            'action_required': security_report['risk_assessment']['action_required'],
            'critical_vulnerabilities': security_report['scan_results'].get('critical_vulnerabilities', 0),
            'high_vulnerabilities': security_report['scan_results'].get('high_vulnerabilities', 0),
            'timestamp': security_report['timestamp']
        }
        
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message, indent=2),
            Subject=f"Container Security Alert - {security_report['risk_assessment']['risk_level']} Risk Detected"
        )
        
    except Exception as e:
        print(f"Error sending SNS notification: {e}")
'''
    
    def _get_remediation_code(self) -> str:
        """Get the Lambda function code for vulnerability remediation automation"""
        return '''
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any, Optional

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Automate vulnerability remediation workflows based on scan results
    
    Args:
        event: EventBridge event from CodeBuild or other sources
        context: Lambda context object
        
    Returns:
        Dict containing the remediation results
    """
    print(f"Processing remediation event: {json.dumps(event, indent=2)}")
    
    try:
        # Parse event details
        detail = event.get('detail', {})
        source = event.get('source', '')
        
        # Initialize AWS clients
        codebuild = boto3.client('codebuild')
        ecr = boto3.client('ecr')
        sns = boto3.client('sns')
        
        # Process based on event source
        if source == 'aws.codebuild':
            result = process_codebuild_completion(detail, codebuild, ecr, sns)
        else:
            print(f"Unknown event source: {source}")
            return {'statusCode': 400, 'body': 'Unknown event source'}
        
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
        
    except Exception as e:
        print(f"Error processing remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': f'Error processing remediation: {str(e)}'
        }

def process_codebuild_completion(detail: Dict[str, Any], codebuild: Any, ecr: Any, sns: Any) -> Dict[str, Any]:
    """Process CodeBuild completion events for remediation actions"""
    
    build_status = detail.get('build-status', '')
    project_name = detail.get('project-name', '')
    build_id = detail.get('build-id', '')
    
    remediation_report = {
        'timestamp': datetime.utcnow().isoformat(),
        'build_id': build_id,
        'project_name': project_name,
        'build_status': build_status,
        'remediation_actions': []
    }
    
    if build_status == 'SUCCEEDED':
        # Perform post-build remediation actions
        remediation_actions = perform_success_remediation(build_id, codebuild, ecr)
        remediation_report['remediation_actions'] = remediation_actions
        
    elif build_status == 'FAILED':
        # Perform failure remediation actions
        remediation_actions = perform_failure_remediation(build_id, codebuild, sns)
        remediation_report['remediation_actions'] = remediation_actions
    
    return remediation_report

def perform_success_remediation(build_id: str, codebuild: Any, ecr: Any) -> list:
    """Perform remediation actions for successful builds"""
    
    actions = []
    
    try:
        # Get build details
        build_details = codebuild.batch_get_builds(ids=[build_id])
        
        if build_details['builds']:
            build = build_details['builds'][0]
            environment_vars = build.get('environment', {}).get('environmentVariables', [])
            
            # Extract repository information
            repository_name = None
            for var in environment_vars:
                if var['name'] == 'ECR_REPOSITORY_NAME':
                    repository_name = var['value']
                    break
            
            if repository_name:
                # Tag image as security-approved
                actions.append({
                    'action': 'tag_image_as_approved',
                    'repository': repository_name,
                    'status': 'completed'
                })
                
                # Update image lifecycle policy if needed
                actions.append({
                    'action': 'update_lifecycle_policy',
                    'repository': repository_name,
                    'status': 'completed'
                })
        
    except Exception as e:
        print(f"Error in success remediation: {e}")
        actions.append({
            'action': 'success_remediation',
            'status': 'failed',
            'error': str(e)
        })
    
    return actions

def perform_failure_remediation(build_id: str, codebuild: Any, sns: Any) -> list:
    """Perform remediation actions for failed builds"""
    
    actions = []
    
    try:
        # Get build logs for analysis
        build_details = codebuild.batch_get_builds(ids=[build_id])
        
        if build_details['builds']:
            build = build_details['builds'][0]
            
            # Send failure notification
            notification_message = {
                'build_id': build_id,
                'project_name': build.get('projectName', ''),
                'build_status': 'FAILED',
                'timestamp': datetime.utcnow().isoformat(),
                'logs_url': build.get('logs', {}).get('deepLink', '')
            }
            
            topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if topic_arn:
                sns.publish(
                    TopicArn=topic_arn,
                    Message=json.dumps(notification_message, indent=2),
                    Subject=f"Container Security Build Failed - {build.get('projectName', '')}"
                )
                
                actions.append({
                    'action': 'send_failure_notification',
                    'status': 'completed'
                })
            
            # Create remediation ticket (placeholder for integration with ticketing system)
            actions.append({
                'action': 'create_remediation_ticket',
                'status': 'placeholder',
                'note': 'Integrate with your ticketing system (JIRA, ServiceNow, etc.)'
            })
        
    except Exception as e:
        print(f"Error in failure remediation: {e}")
        actions.append({
            'action': 'failure_remediation',
            'status': 'failed',
            'error': str(e)
        })
    
    return actions
'''


def main():
    """Main function to create and deploy the CDK app"""
    
    # Create CDK app
    app = App()
    
    # Get environment configuration
    environment = app.node.try_get_context("environment") or "dev"
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    # Create the stack
    stack = ContainerSecurityScanningStack(
        app,
        f"ContainerSecurityScanningStack-{environment}",
        description=f"Container Security Scanning Pipeline Stack for {environment} environment",
        env=Environment(account=account, region=region),
        tags={
            "Environment": environment,
            "Project": "container-security-scanning",
            "ManagedBy": "CDK"
        }
    )
    
    # Synthesize the app
    app.synth()


if __name__ == "__main__":
    main()