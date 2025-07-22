#!/usr/bin/env python3
"""
CDK Python application for CodeGuru code review automation.

This application deploys infrastructure for automated code quality gates
using Amazon CodeGuru Reviewer and CodeGuru Profiler with CodeCommit integration.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_codecommit as codecommit,
    aws_codeguru_reviewer as codeguru_reviewer,
    aws_codeguru_profiler as codeguru_profiler,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_ssm as ssm,
    CfnOutput,
    Tags
)
from constructs import Construct


class CodeGuruAutomationStack(Stack):
    """
    Stack for CodeGuru code review automation infrastructure.
    
    This stack creates:
    - CodeCommit repository for source code
    - CodeGuru Reviewer association for automated code reviews
    - CodeGuru Profiler group for runtime performance monitoring
    - Lambda functions for automation workflows
    - SNS topics for notifications
    - IAM roles and policies for service integration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters from CDK context or environment
        project_name = self.node.try_get_context("project_name") or "codeguru-automation"
        notification_email = self.node.try_get_context("notification_email")
        
        # Create CodeCommit repository
        self.repository = self._create_repository(project_name)
        
        # Create IAM roles for CodeGuru services
        self.codeguru_role = self._create_codeguru_service_role()
        
        # Create CodeGuru Reviewer association
        self.reviewer_association = self._create_reviewer_association()
        
        # Create CodeGuru Profiler group
        self.profiler_group = self._create_profiler_group(project_name)
        
        # Create Lambda functions for automation
        self.quality_gate_function = self._create_quality_gate_lambda()
        self.notification_function = self._create_notification_lambda()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic(notification_email)
        
        # Create EventBridge rules for automation
        self._create_automation_rules()
        
        # Create SSM parameters for configuration
        self._create_ssm_parameters(project_name)
        
        # Add tags to all resources
        self._add_tags(project_name)

    def _create_repository(self, project_name: str) -> codecommit.Repository:
        """Create CodeCommit repository for source code."""
        repository = codecommit.Repository(
            self, "CodeRepository",
            repository_name=f"{project_name}-repo",
            description="Repository for CodeGuru code review automation demo",
            code=codecommit.Code.from_directory(
                directory_path="sample-code",
                branch="main"
            ) if os.path.exists("sample-code") else None
        )
        
        CfnOutput(
            self, "RepositoryCloneUrl",
            value=repository.repository_clone_url_http,
            description="CodeCommit repository clone URL"
        )
        
        return repository

    def _create_codeguru_service_role(self) -> iam.Role:
        """Create IAM role for CodeGuru services."""
        role = iam.Role(
            self, "CodeGuruServiceRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("codeguru-reviewer.amazonaws.com"),
                iam.ServicePrincipal("codeguru-profiler.amazonaws.com")
            ),
            description="Service role for CodeGuru Reviewer and Profiler",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonCodeGuruReviewerServiceRolePolicy"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonCodeGuruProfilerAgentAccess"
                )
            ]
        )
        
        # Add additional permissions for CodeCommit integration
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codecommit:GetRepository",
                    "codecommit:GetBranch",
                    "codecommit:GetCommit",
                    "codecommit:ListBranches",
                    "codecommit:ListRepositories"
                ],
                resources=[self.repository.repository_arn]
            )
        )
        
        return role

    def _create_reviewer_association(self) -> codeguru_reviewer.CfnRepositoryAssociation:
        """Create CodeGuru Reviewer repository association."""
        association = codeguru_reviewer.CfnRepositoryAssociation(
            self, "ReviewerAssociation",
            repository={
                "codecommit": {
                    "name": self.repository.repository_name
                }
            },
            type="CodeCommit"
        )
        
        # Ensure repository is created before association
        association.add_dependency(self.repository.node.default_child)
        
        CfnOutput(
            self, "ReviewerAssociationArn",
            value=association.attr_association_arn,
            description="CodeGuru Reviewer association ARN"
        )
        
        return association

    def _create_profiler_group(self, project_name: str) -> codeguru_profiler.ProfilingGroup:
        """Create CodeGuru Profiler group."""
        profiler_group = codeguru_profiler.ProfilingGroup(
            self, "ProfilerGroup",
            profiling_group_name=f"{project_name}-profiler-group",
            compute_platform=codeguru_profiler.ComputePlatform.DEFAULT,
            agent_permissions=codeguru_profiler.AgentPermissions.builder()
                .principals([
                    iam.ArnPrincipal(f"arn:aws:iam::{self.account}:root")
                ])
                .build()
        )
        
        CfnOutput(
            self, "ProfilerGroupName",
            value=profiler_group.profiling_group_name,
            description="CodeGuru Profiler group name"
        )
        
        return profiler_group

    def _create_quality_gate_lambda(self) -> lambda_.Function:
        """Create Lambda function for automated quality gates."""
        # Create execution role for Lambda
        lambda_role = iam.Role(
            self, "QualityGateLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for quality gate Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add permissions for CodeGuru operations
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codeguru-reviewer:ListRecommendations",
                    "codeguru-reviewer:DescribeCodeReview",
                    "codeguru-reviewer:CreateCodeReview",
                    "codeguru-reviewer:PutRecommendationFeedback",
                    "sns:Publish",
                    "ssm:GetParameter"
                ],
                resources=["*"]
            )
        )
        
        # Create Lambda function
        function = lambda_.Function(
            self, "QualityGateFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="quality_gate.handler",
            code=lambda_.Code.from_inline(self._get_quality_gate_code()),
            role=lambda_role,
            description="Automated quality gate enforcement for CodeGuru recommendations",
            timeout=Duration.minutes(5),
            environment={
                "SNS_TOPIC_ARN": "",  # Will be set after SNS topic creation
                "REPOSITORY_ASSOCIATION_ARN": self.reviewer_association.attr_association_arn
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        return function

    def _create_notification_lambda(self) -> lambda_.Function:
        """Create Lambda function for sending notifications."""
        # Create execution role for Lambda
        lambda_role = iam.Role(
            self, "NotificationLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for notification Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add permissions for SNS publishing
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=["*"]
            )
        )
        
        # Create Lambda function
        function = lambda_.Function(
            self, "NotificationFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="notifications.handler",
            code=lambda_.Code.from_inline(self._get_notification_code()),
            role=lambda_role,
            description="Send notifications for CodeGuru events",
            timeout=Duration.minutes(2),
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        return function

    def _create_notification_topic(self, notification_email: str = None) -> sns.Topic:
        """Create SNS topic for notifications."""
        topic = sns.Topic(
            self, "NotificationTopic",
            display_name="CodeGuru Automation Notifications",
            description="Notifications for CodeGuru code review automation events"
        )
        
        # Add email subscription if provided
        if notification_email:
            topic.add_subscription(
                subscriptions.EmailSubscription(notification_email)
            )
        
        # Update Lambda environment variables
        self.quality_gate_function.add_environment(
            "SNS_TOPIC_ARN", 
            topic.topic_arn
        )
        self.notification_function.add_environment(
            "SNS_TOPIC_ARN", 
            topic.topic_arn
        )
        
        # Grant publish permissions to Lambda functions
        topic.grant_publish(self.quality_gate_function)
        topic.grant_publish(self.notification_function)
        
        CfnOutput(
            self, "NotificationTopicArn",
            value=topic.topic_arn,
            description="SNS topic ARN for notifications"
        )
        
        return topic

    def _create_automation_rules(self) -> None:
        """Create EventBridge rules for automation workflows."""
        # Rule for CodeCommit state changes (pull requests)
        codecommit_rule = events.Rule(
            self, "CodeCommitRule",
            description="Trigger quality gate on CodeCommit events",
            event_pattern=events.EventPattern(
                source=["aws.codecommit"],
                detail_type=["CodeCommit Repository State Change"],
                detail={
                    "event": ["pullRequestCreated", "pullRequestSourceBranchUpdated"],
                    "repositoryName": [self.repository.repository_name]
                }
            )
        )
        
        # Add Lambda target to the rule
        codecommit_rule.add_target(
            targets.LambdaFunction(
                self.quality_gate_function,
                retry_attempts=2
            )
        )
        
        # Grant EventBridge permission to invoke Lambda
        self.quality_gate_function.grant_invoke(
            iam.ServicePrincipal("events.amazonaws.com")
        )

    def _create_ssm_parameters(self, project_name: str) -> None:
        """Create SSM parameters for configuration."""
        # Quality gate thresholds
        ssm.StringParameter(
            self, "QualityGateThresholds",
            parameter_name=f"/{project_name}/quality-gate/thresholds",
            string_value='{"high_severity_max": 0, "medium_severity_max": 5, "low_severity_max": 20}',
            description="Quality gate thresholds for CodeGuru recommendations",
            tier=ssm.ParameterTier.STANDARD
        )
        
        # Profiler configuration
        ssm.StringParameter(
            self, "ProfilerConfig",
            parameter_name=f"/{project_name}/profiler/config",
            string_value=f'{{"profiling_group_name": "{self.profiler_group.profiling_group_name}", "sampling_interval_seconds": 1}}',
            description="CodeGuru Profiler configuration",
            tier=ssm.ParameterTier.STANDARD
        )

    def _add_tags(self, project_name: str) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", project_name)
        Tags.of(self).add("Environment", self.node.try_get_context("environment") or "dev")
        Tags.of(self).add("Owner", self.node.try_get_context("owner") or "DevOps")
        Tags.of(self).add("CostCenter", self.node.try_get_context("cost_center") or "Engineering")
        Tags.of(self).add("AutoDelete", "true")

    def _get_quality_gate_code(self) -> str:
        """Return inline code for quality gate Lambda function."""
        return '''
import json
import boto3
import os
from typing import Dict, Any, List

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to enforce quality gates based on CodeGuru recommendations.
    
    Args:
        event: EventBridge event data
        context: Lambda context
        
    Returns:
        Response dictionary with status and results
    """
    
    codeguru_client = boto3.client('codeguru-reviewer')
    sns_client = boto3.client('sns')
    ssm_client = boto3.client('ssm')
    
    try:
        # Extract repository information from event
        repository_name = event.get('detail', {}).get('repositoryName', '')
        
        if not repository_name:
            print("No repository name found in event")
            return {'statusCode': 400, 'body': 'Invalid event data'}
        
        # Get quality gate thresholds from SSM
        thresholds = get_quality_thresholds(ssm_client)
        
        # Create code review for the repository
        association_arn = os.environ['REPOSITORY_ASSOCIATION_ARN']
        code_review_arn = create_code_review(codeguru_client, association_arn)
        
        if code_review_arn:
            # Wait for review completion and check recommendations
            recommendations = wait_and_get_recommendations(codeguru_client, code_review_arn)
            
            # Evaluate quality gate
            gate_result = evaluate_quality_gate(recommendations, thresholds)
            
            # Send notification
            send_notification(sns_client, gate_result, repository_name)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'repository': repository_name,
                    'code_review_arn': code_review_arn,
                    'quality_gate_passed': gate_result['passed'],
                    'recommendations_count': gate_result['counts']
                })
            }
        else:
            return {'statusCode': 500, 'body': 'Failed to create code review'}
            
    except Exception as e:
        print(f"Error in quality gate function: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def get_quality_thresholds(ssm_client) -> Dict[str, int]:
    """Get quality gate thresholds from SSM Parameter Store."""
    try:
        parameter_name = "/codeguru-automation/quality-gate/thresholds"
        response = ssm_client.get_parameter(Name=parameter_name)
        return json.loads(response['Parameter']['Value'])
    except Exception:
        # Default thresholds if parameter not found
        return {"high_severity_max": 0, "medium_severity_max": 5, "low_severity_max": 20}

def create_code_review(codeguru_client, association_arn: str) -> str:
    """Create a new code review."""
    try:
        response = codeguru_client.create_code_review(
            Name=f"automated-review-{int(time.time())}",
            RepositoryAssociationArn=association_arn,
            Type={
                'RepositoryAnalysis': {
                    'RepositoryHead': {'BranchName': 'main'}
                }
            }
        )
        return response['CodeReview']['CodeReviewArn']
    except Exception as e:
        print(f"Error creating code review: {str(e)}")
        return None

def wait_and_get_recommendations(codeguru_client, code_review_arn: str) -> List[Dict]:
    """Wait for code review completion and get recommendations."""
    import time
    
    max_wait_time = 300  # 5 minutes
    wait_interval = 30   # 30 seconds
    elapsed_time = 0
    
    while elapsed_time < max_wait_time:
        try:
            response = codeguru_client.describe_code_review(CodeReviewArn=code_review_arn)
            state = response['CodeReview']['State']
            
            if state == 'Completed':
                # Get recommendations
                recommendations_response = codeguru_client.list_recommendations(
                    CodeReviewArn=code_review_arn
                )
                return recommendations_response.get('RecommendationSummaries', [])
            elif state == 'Failed':
                print("Code review failed")
                return []
            
            time.sleep(wait_interval)
            elapsed_time += wait_interval
            
        except Exception as e:
            print(f"Error checking code review status: {str(e)}")
            return []
    
    print("Code review did not complete within timeout")
    return []

def evaluate_quality_gate(recommendations: List[Dict], thresholds: Dict[str, int]) -> Dict[str, Any]:
    """Evaluate quality gate based on recommendations."""
    counts = {"HIGH": 0, "MEDIUM": 0, "LOW": 0, "INFO": 0}
    
    for rec in recommendations:
        severity = rec.get('Severity', 'INFO')
        counts[severity] = counts.get(severity, 0) + 1
    
    # Check if quality gate passes
    passed = (
        counts['HIGH'] <= thresholds.get('high_severity_max', 0) and
        counts['MEDIUM'] <= thresholds.get('medium_severity_max', 5) and
        counts['LOW'] <= thresholds.get('low_severity_max', 20)
    )
    
    return {
        'passed': passed,
        'counts': counts,
        'thresholds': thresholds,
        'recommendations': recommendations
    }

def send_notification(sns_client, gate_result: Dict[str, Any], repository_name: str) -> None:
    """Send SNS notification with quality gate results."""
    try:
        topic_arn = os.environ['SNS_TOPIC_ARN']
        
        status = "PASSED" if gate_result['passed'] else "FAILED"
        subject = f"Quality Gate {status} for {repository_name}"
        
        message = f"""
Quality Gate Results for Repository: {repository_name}

Status: {status}

Recommendation Counts:
- High Severity: {gate_result['counts']['HIGH']}
- Medium Severity: {gate_result['counts']['MEDIUM']}
- Low Severity: {gate_result['counts']['LOW']}
- Info: {gate_result['counts']['INFO']}

Thresholds:
- High Severity Max: {gate_result['thresholds']['high_severity_max']}
- Medium Severity Max: {gate_result['thresholds']['medium_severity_max']}
- Low Severity Max: {gate_result['thresholds']['low_severity_max']}

{len(gate_result['recommendations'])} total recommendations found.
        """
        
        sns_client.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message
        )
        
    except Exception as e:
        print(f"Error sending notification: {str(e)}")

import time
'''

    def _get_notification_code(self) -> str:
        """Return inline code for notification Lambda function."""
        return '''
import json
import boto3
import os
from typing import Dict, Any

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to send formatted notifications for CodeGuru events.
    
    Args:
        event: SNS or direct invocation event
        context: Lambda context
        
    Returns:
        Response dictionary with status
    """
    
    sns_client = boto3.client('sns')
    
    try:
        # Extract message information
        message_type = event.get('messageType', 'general')
        repository_name = event.get('repository', 'Unknown')
        
        if message_type == 'quality_gate_result':
            send_quality_gate_notification(sns_client, event)
        elif message_type == 'profiler_insight':
            send_profiler_notification(sns_client, event)
        else:
            send_general_notification(sns_client, event)
        
        return {'statusCode': 200, 'body': 'Notification sent successfully'}
        
    except Exception as e:
        print(f"Error in notification function: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def send_quality_gate_notification(sns_client, event: Dict[str, Any]) -> None:
    """Send quality gate specific notification."""
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    subject = f"CodeGuru Quality Gate - {event.get('status', 'UNKNOWN')} - {event.get('repository', 'Unknown')}"
    
    message = f"""
CodeGuru Quality Gate Report

Repository: {event.get('repository', 'Unknown')}
Status: {event.get('status', 'UNKNOWN')}
Code Review ARN: {event.get('code_review_arn', 'N/A')}

Recommendation Summary:
{json.dumps(event.get('recommendations_summary', {}), indent=2)}

Timestamp: {event.get('timestamp', 'N/A')}
    """
    
    sns_client.publish(
        TopicArn=topic_arn,
        Subject=subject,
        Message=message
    )

def send_profiler_notification(sns_client, event: Dict[str, Any]) -> None:
    """Send profiler insight notification."""
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    subject = f"CodeGuru Profiler Insight - {event.get('application', 'Unknown')}"
    
    message = f"""
CodeGuru Profiler Performance Insight

Application: {event.get('application', 'Unknown')}
Profiling Group: {event.get('profiling_group', 'Unknown')}
Insight Type: {event.get('insight_type', 'Unknown')}

Summary: {event.get('summary', 'N/A')}

Recommendations:
{json.dumps(event.get('recommendations', []), indent=2)}

Timestamp: {event.get('timestamp', 'N/A')}
    """
    
    sns_client.publish(
        TopicArn=topic_arn,
        Subject=subject,
        Message=message
    )

def send_general_notification(sns_client, event: Dict[str, Any]) -> None:
    """Send general notification."""
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    subject = f"CodeGuru Automation - {event.get('subject', 'General Notification')}"
    message = event.get('message', json.dumps(event, indent=2))
    
    sns_client.publish(
        TopicArn=topic_arn,
        Subject=subject,
        Message=message
    )
'''


class CodeGuruAutomationApp(cdk.App):
    """CDK Application for CodeGuru automation."""

    def __init__(self) -> None:
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )

        # Create the main stack
        CodeGuruAutomationStack(
            self, "CodeGuruAutomationStack",
            env=env,
            description="Infrastructure for CodeGuru code review automation with quality gates and notifications",
            tags={
                "Application": "CodeGuruAutomation",
                "ManagedBy": "CDK"
            }
        )


# Application entry point
app = CodeGuruAutomationApp()
app.synth()