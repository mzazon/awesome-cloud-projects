#!/usr/bin/env python3
"""
CDK Python Application for ECR Container Registry Replication Strategies

This application creates a comprehensive ECR replication solution with:
- Source repositories with scanning enabled
- Cross-region replication configuration
- Lifecycle policies for cost optimization
- Repository policies for access control
- CloudWatch monitoring and alerting
- Lambda automation for cleanup
"""

import aws_cdk as cdk
from aws_cdk import (
    aws_ecr as ecr,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_events as events,
    aws_events_targets as targets,
    Duration,
    Stack,
    CfnOutput,
    RemovalPolicy,
    Environment
)
from constructs import Construct
from typing import Dict, List, Optional
import json


class ECRReplicationStack(Stack):
    """
    CDK Stack for ECR Container Registry Replication Strategies
    
    This stack implements a comprehensive ECR replication solution with:
    - Multi-region replication
    - Lifecycle policies
    - Security controls
    - Monitoring and alerting
    - Automated cleanup
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        source_region: str = "us-east-1",
        destination_regions: List[str] = None,
        repository_prefix: str = "enterprise-apps",
        enable_monitoring: bool = True,
        enable_automation: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the ECR Replication Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            source_region: Primary region for ECR repositories
            destination_regions: List of regions for replication
            repository_prefix: Prefix for repository names
            enable_monitoring: Whether to enable CloudWatch monitoring
            enable_automation: Whether to enable Lambda automation
        """
        super().__init__(scope, construct_id, **kwargs)

        # Set default destination regions if not provided
        if destination_regions is None:
            destination_regions = ["us-west-2", "eu-west-1"]

        self.source_region = source_region
        self.destination_regions = destination_regions
        self.repository_prefix = repository_prefix
        self.enable_monitoring = enable_monitoring
        self.enable_automation = enable_automation

        # Create ECR repositories
        self.production_repository = self._create_production_repository()
        self.testing_repository = self._create_testing_repository()

        # Configure cross-region replication
        self._configure_replication()

        # Create IAM roles for repository access
        self.production_role = self._create_production_role()
        self.pipeline_role = self._create_pipeline_role()

        # Apply repository policies
        self._apply_repository_policies()

        # Create monitoring resources if enabled
        if self.enable_monitoring:
            self.sns_topic = self._create_sns_topic()
            self.cloudwatch_dashboard = self._create_cloudwatch_dashboard()
            self.replication_alarm = self._create_replication_alarm()

        # Create automation resources if enabled
        if self.enable_automation:
            self.cleanup_lambda = self._create_cleanup_lambda()
            self.cleanup_schedule = self._create_cleanup_schedule()

        # Create outputs
        self._create_outputs()

    def _create_production_repository(self) -> ecr.Repository:
        """
        Create the production ECR repository with security features
        
        Returns:
            Production ECR repository with scanning and immutable tags
        """
        return ecr.Repository(
            self,
            "ProductionRepository",
            repository_name=f"{self.repository_prefix}/production",
            image_scan_on_push=True,
            image_tag_mutability=ecr.TagMutability.IMMUTABLE,
            lifecycle_rules=[
                # Keep last 10 production images
                ecr.LifecycleRule(
                    rule_priority=1,
                    description="Keep last 10 production images",
                    selection=ecr.LifecycleSelection.tag_prefix_list(
                        tag_prefixes=["prod", "release"]
                    ),
                    max_image_count=10
                ),
                # Delete untagged images after 1 day
                ecr.LifecycleRule(
                    rule_priority=2,
                    description="Delete untagged images older than 1 day",
                    selection=ecr.LifecycleSelection.untagged_since_days(1),
                    max_image_age=Duration.days(1)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            empty_on_delete=True
        )

    def _create_testing_repository(self) -> ecr.Repository:
        """
        Create the testing ECR repository with development-friendly policies
        
        Returns:
            Testing ECR repository with mutable tags and aggressive cleanup
        """
        return ecr.Repository(
            self,
            "TestingRepository",
            repository_name=f"{self.repository_prefix}/testing",
            image_scan_on_push=True,
            image_tag_mutability=ecr.TagMutability.MUTABLE,
            lifecycle_rules=[
                # Keep last 5 testing images
                ecr.LifecycleRule(
                    rule_priority=1,
                    description="Keep last 5 testing images",
                    selection=ecr.LifecycleSelection.tag_prefix_list(
                        tag_prefixes=["test", "dev", "staging"]
                    ),
                    max_image_count=5
                ),
                # Delete all images older than 7 days
                ecr.LifecycleRule(
                    rule_priority=2,
                    description="Delete images older than 7 days",
                    selection=ecr.LifecycleSelection.any(),
                    max_image_age=Duration.days(7)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            empty_on_delete=True
        )

    def _configure_replication(self) -> None:
        """
        Configure cross-region replication for ECR repositories
        
        This creates a replication configuration that automatically
        replicates repositories matching the specified prefix to
        destination regions.
        """
        # Create replication destinations
        destinations = []
        for region in self.destination_regions:
            destinations.append(
                ecr.CfnReplicationConfiguration.ReplicationDestinationProperty(
                    region=region,
                    registry_id=self.account
                )
            )

        # Create replication configuration
        ecr.CfnReplicationConfiguration(
            self,
            "ReplicationConfiguration",
            replication_configuration=ecr.CfnReplicationConfiguration.ReplicationConfigurationProperty(
                rules=[
                    ecr.CfnReplicationConfiguration.ReplicationRuleProperty(
                        destinations=destinations,
                        repository_filters=[
                            ecr.CfnReplicationConfiguration.RepositoryFilterProperty(
                                filter=self.repository_prefix,
                                filter_type="PREFIX_MATCH"
                            )
                        ]
                    )
                ]
            )
        )

    def _create_production_role(self) -> iam.Role:
        """
        Create IAM role for production repository read access
        
        Returns:
            IAM role with read-only permissions for production repository
        """
        role = iam.Role(
            self,
            "ProductionRole",
            role_name="ECRProductionRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="Role for production ECR repository read access"
        )

        # Grant read permissions to production repository
        self.production_repository.grant_pull(role)

        return role

    def _create_pipeline_role(self) -> iam.Role:
        """
        Create IAM role for CI/CD pipeline push access
        
        Returns:
            IAM role with push permissions for repositories
        """
        role = iam.Role(
            self,
            "PipelineRole",
            role_name="ECRCIPipelineRole",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="Role for CI/CD pipeline ECR repository push access"
        )

        # Grant push permissions to both repositories
        self.production_repository.grant_push(role)
        self.testing_repository.grant_push(role)

        return role

    def _apply_repository_policies(self) -> None:
        """
        Apply repository policies for fine-grained access control
        
        This creates repository policies that complement IAM roles
        to provide defense-in-depth security.
        """
        # Production repository policy
        production_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="ProdReadOnlyAccess",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ArnPrincipal(self.production_role.role_arn)],
                    actions=[
                        "ecr:GetDownloadUrlForLayer",
                        "ecr:BatchGetImage",
                        "ecr:BatchCheckLayerAvailability"
                    ]
                ),
                iam.PolicyStatement(
                    sid="ProdPushAccess",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ArnPrincipal(self.pipeline_role.role_arn)],
                    actions=[
                        "ecr:PutImage",
                        "ecr:InitiateLayerUpload",
                        "ecr:UploadLayerPart",
                        "ecr:CompleteLayerUpload"
                    ]
                )
            ]
        )

        # Apply policy to production repository
        ecr.CfnRepositoryPolicy(
            self,
            "ProductionRepositoryPolicy",
            repository_name=self.production_repository.repository_name,
            policy_text=production_policy.to_json()
        )

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for ECR replication alerts
        
        Returns:
            SNS topic for replication monitoring notifications
        """
        return sns.Topic(
            self,
            "ECRReplicationAlerts",
            topic_name="ECR-Replication-Alerts",
            display_name="ECR Replication Alerts",
            description="SNS topic for ECR replication monitoring alerts"
        )

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for ECR monitoring
        
        Returns:
            CloudWatch dashboard with ECR metrics and widgets
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "ECRMonitoringDashboard",
            dashboard_name="ECR-Replication-Monitoring",
            default_interval=Duration.minutes(5)
        )

        # Add repository activity widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="ECR Repository Activity",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/ECR",
                        metric_name="RepositoryPullCount",
                        dimensions_map={
                            "RepositoryName": self.production_repository.repository_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5)
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/ECR",
                        metric_name="RepositoryPushCount",
                        dimensions_map={
                            "RepositoryName": self.production_repository.repository_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5)
                    )
                ]
            )
        )

        return dashboard

    def _create_replication_alarm(self) -> cloudwatch.Alarm:
        """
        Create CloudWatch alarm for replication monitoring
        
        Returns:
            CloudWatch alarm for replication failure detection
        """
        # Create custom metric for replication failures
        replication_metric = cloudwatch.Metric(
            namespace="AWS/ECR",
            metric_name="ReplicationFailureRate",
            statistic="Average",
            period=Duration.minutes(5)
        )

        return cloudwatch.Alarm(
            self,
            "ReplicationFailureAlarm",
            alarm_name="ECR-Replication-Failure-Rate",
            alarm_description="Monitor ECR replication failure rate",
            metric=replication_metric,
            threshold=0.1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            actions_enabled=True
        )

    def _create_cleanup_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for automated repository cleanup
        
        Returns:
            Lambda function for ECR repository cleanup automation
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "CleanupLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Grant ECR permissions to Lambda
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:DescribeRepositories",
                    "ecr:DescribeImages",
                    "ecr:BatchDeleteImage",
                    "ecr:ListImages"
                ],
                resources=["*"]
            )
        )

        # Create Lambda function
        cleanup_function = lambda_.Function(
            self,
            "CleanupLambda",
            function_name="ECR-Repository-Cleanup",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Automated cleanup for ECR repositories",
            environment={
                "REPOSITORY_PREFIX": self.repository_prefix,
                "CLEANUP_DAYS": "30"
            },
            code=lambda_.Code.from_inline("""
import boto3
import json
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ecr_client = boto3.client('ecr')
    repository_prefix = os.environ['REPOSITORY_PREFIX']
    cleanup_days = int(os.environ['CLEANUP_DAYS'])
    
    try:
        # Get all repositories with matching prefix
        repositories = ecr_client.describe_repositories()['repositories']
        filtered_repos = [
            repo for repo in repositories
            if repo['repositoryName'].startswith(repository_prefix)
        ]
        
        cleanup_results = []
        
        for repo in filtered_repos:
            repo_name = repo['repositoryName']
            
            # Get untagged images
            images = ecr_client.describe_images(
                repositoryName=repo_name,
                filter={'tagStatus': 'UNTAGGED'}
            )
            
            # Find old images
            old_images = []
            cutoff_date = datetime.now() - timedelta(days=cleanup_days)
            
            for image in images['imageDetails']:
                if image['imagePushedAt'].replace(tzinfo=None) < cutoff_date:
                    old_images.append({'imageDigest': image['imageDigest']})
            
            # Delete old images
            if old_images:
                response = ecr_client.batch_delete_image(
                    repositoryName=repo_name,
                    imageIds=old_images
                )
                
                cleanup_results.append({
                    'repository': repo_name,
                    'deleted_images': len(old_images),
                    'failures': len(response.get('failures', []))
                })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cleanup completed successfully',
                'results': cleanup_results
            })
        }
        
    except Exception as e:
        print(f"Error during cleanup: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
""")
        )

        return cleanup_function

    def _create_cleanup_schedule(self) -> events.Rule:
        """
        Create EventBridge rule for scheduled cleanup
        
        Returns:
            EventBridge rule that triggers cleanup Lambda weekly
        """
        return events.Rule(
            self,
            "CleanupSchedule",
            rule_name="ECR-Cleanup-Schedule",
            description="Schedule for automated ECR repository cleanup",
            schedule=events.Schedule.cron(
                minute="0",
                hour="2",
                day="*",
                month="*",
                week_day="SUN"
            ),
            targets=[
                targets.LambdaFunction(self.cleanup_lambda)
            ]
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for the stack
        
        This provides important information about created resources
        for integration with other systems and manual verification.
        """
        CfnOutput(
            self,
            "ProductionRepositoryUri",
            value=self.production_repository.repository_uri,
            description="URI of the production ECR repository",
            export_name=f"{self.stack_name}-ProductionRepositoryUri"
        )

        CfnOutput(
            self,
            "TestingRepositoryUri",
            value=self.testing_repository.repository_uri,
            description="URI of the testing ECR repository",
            export_name=f"{self.stack_name}-TestingRepositoryUri"
        )

        CfnOutput(
            self,
            "ProductionRoleArn",
            value=self.production_role.role_arn,
            description="ARN of the production access role",
            export_name=f"{self.stack_name}-ProductionRoleArn"
        )

        CfnOutput(
            self,
            "PipelineRoleArn",
            value=self.pipeline_role.role_arn,
            description="ARN of the CI/CD pipeline role",
            export_name=f"{self.stack_name}-PipelineRoleArn"
        )

        if self.enable_monitoring:
            CfnOutput(
                self,
                "SNSTopicArn",
                value=self.sns_topic.topic_arn,
                description="ARN of the SNS topic for alerts",
                export_name=f"{self.stack_name}-SNSTopicArn"
            )

        if self.enable_automation:
            CfnOutput(
                self,
                "CleanupLambdaArn",
                value=self.cleanup_lambda.function_arn,
                description="ARN of the cleanup Lambda function",
                export_name=f"{self.stack_name}-CleanupLambdaArn"
            )

        CfnOutput(
            self,
            "ReplicationRegions",
            value=", ".join(self.destination_regions),
            description="Regions configured for ECR replication",
            export_name=f"{self.stack_name}-ReplicationRegions"
        )


class ECRReplicationApp(cdk.App):
    """
    CDK Application for ECR Container Registry Replication
    
    This application creates a comprehensive ECR replication solution
    with monitoring, automation, and security controls.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from context or use defaults
        source_region = self.node.try_get_context("source_region") or "us-east-1"
        destination_regions = self.node.try_get_context("destination_regions") or ["us-west-2", "eu-west-1"]
        repository_prefix = self.node.try_get_context("repository_prefix") or "enterprise-apps"
        enable_monitoring = self.node.try_get_context("enable_monitoring") != "false"
        enable_automation = self.node.try_get_context("enable_automation") != "false"
        
        # Create the main stack
        ECRReplicationStack(
            self,
            "ECRReplicationStack",
            source_region=source_region,
            destination_regions=destination_regions,
            repository_prefix=repository_prefix,
            enable_monitoring=enable_monitoring,
            enable_automation=enable_automation,
            description="ECR Container Registry Replication Strategies Stack",
            env=Environment(
                account=self.account,
                region=self.region
            )
        )


# Create and synthesize the application
if __name__ == "__main__":
    app = ECRReplicationApp()
    app.synth()