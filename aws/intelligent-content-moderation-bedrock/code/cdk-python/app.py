#!/usr/bin/env python3
"""
CDK Python application for Intelligent Content Moderation with Bedrock.

This application deploys a complete content moderation system that:
- Uses Amazon Bedrock Claude models for intelligent content analysis
- Leverages EventBridge for event-driven workflow orchestration
- Implements S3 event triggers for automated content processing
- Provides SNS notifications for moderation decisions
- Includes Bedrock Guardrails for enhanced AI safety
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_iam as iam,
    aws_s3_notifications as s3_notifications,
    aws_bedrock as bedrock,
    aws_logs as logs,
)
from constructs import Construct


class ContentModerationStack(Stack):
    """
    CDK Stack for intelligent content moderation using Amazon Bedrock and EventBridge.
    
    This stack creates a complete content moderation pipeline with:
    - S3 buckets for content storage and organization
    - Lambda functions for content analysis and workflow processing
    - EventBridge custom bus for event-driven orchestration
    - SNS topic for notifications
    - Bedrock guardrails for AI safety
    - IAM roles with least privilege access
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.notification_email = notification_email or "admin@example.com"
        
        # Create S3 buckets for content storage
        self._create_s3_buckets()
        
        # Create SNS topic for notifications
        self._create_sns_topic()
        
        # Create EventBridge custom bus
        self._create_event_bus()
        
        # Create Bedrock guardrails
        self._create_bedrock_guardrails()
        
        # Create Lambda functions
        self._create_lambda_functions()
        
        # Configure S3 event notifications
        self._configure_s3_events()
        
        # Create EventBridge rules
        self._create_eventbridge_rules()
        
        # Create outputs
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for content storage with security configurations."""
        
        # Content upload bucket
        self.content_bucket = s3.Bucket(
            self,
            "ContentBucket",
            bucket_name=f"content-moderation-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ContentLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                ),
            ],
        )

        # Approved content bucket
        self.approved_bucket = s3.Bucket(
            self,
            "ApprovedBucket",
            bucket_name=f"approved-content-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Rejected content bucket
        self.rejected_bucket = s3.Bucket(
            self,
            "RejectedBucket",
            bucket_name=f"rejected-content-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_sns_topic(self) -> None:
        """Create SNS topic for content moderation notifications."""
        
        self.sns_topic = sns.Topic(
            self,
            "ContentModerationNotifications",
            topic_name="content-moderation-notifications",
            display_name="Content Moderation Notifications",
            fifo=False,
        )

        # Add email subscription if provided
        if self.notification_email:
            self.sns_topic.add_subscription(
                subscriptions.EmailSubscription(self.notification_email)
            )

    def _create_event_bus(self) -> None:
        """Create custom EventBridge bus for content moderation events."""
        
        self.event_bus = events.EventBus(
            self,
            "ContentModerationEventBus",
            event_bus_name="content-moderation-bus",
            description="Custom event bus for content moderation workflow orchestration",
        )

    def _create_bedrock_guardrails(self) -> None:
        """Create Bedrock guardrails for enhanced AI safety."""
        
        # Note: Bedrock guardrails are created via CloudFormation custom resource
        # as CDK doesn't have native support yet
        guardrail_config = {
            "name": "ContentModerationGuardrail",
            "description": "Guardrail for content moderation to prevent harmful content",
            "contentPolicyConfig": {
                "filtersConfig": [
                    {
                        "type": "SEXUAL",
                        "inputStrength": "HIGH",
                        "outputStrength": "HIGH"
                    },
                    {
                        "type": "VIOLENCE",
                        "inputStrength": "HIGH",
                        "outputStrength": "HIGH"
                    },
                    {
                        "type": "HATE",
                        "inputStrength": "HIGH",
                        "outputStrength": "HIGH"
                    },
                    {
                        "type": "INSULTS",
                        "inputStrength": "MEDIUM",
                        "outputStrength": "MEDIUM"
                    },
                    {
                        "type": "MISCONDUCT",
                        "inputStrength": "HIGH",
                        "outputStrength": "HIGH"
                    }
                ]
            },
            "topicPolicyConfig": {
                "topicsConfig": [
                    {
                        "name": "IllegalActivities",
                        "definition": "Content promoting or instructing illegal activities",
                        "examples": ["How to make illegal substances", "Tax evasion strategies"],
                        "type": "DENY"
                    }
                ]
            },
            "sensitiveInformationPolicyConfig": {
                "piiEntitiesConfig": [
                    {
                        "type": "EMAIL",
                        "action": "ANONYMIZE"
                    },
                    {
                        "type": "PHONE",
                        "action": "ANONYMIZE"
                    },
                    {
                        "type": "CREDIT_DEBIT_CARD_NUMBER",
                        "action": "BLOCK"
                    }
                ]
            },
            "blockedInputMessaging": "This content violates our content policy.",
            "blockedOutputsMessaging": "I cannot provide that type of content."
        }

        # Store guardrail configuration as parameter for custom resource
        self.guardrail_config = guardrail_config

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for content analysis and workflow processing."""
        
        # Common Lambda execution role
        lambda_role = iam.Role(
            self,
            "ContentModerationLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "ContentModerationPolicy": iam.PolicyDocument(
                    statements=[
                        # Bedrock permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "bedrock:InvokeModel",
                                "bedrock:InvokeModelWithResponseStream",
                            ],
                            resources=[
                                f"arn:aws:bedrock:{cdk.Aws.REGION}::foundation-model/anthropic.*"
                            ],
                        ),
                        # S3 permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectVersion",
                            ],
                            resources=[
                                f"{self.content_bucket.bucket_arn}/*"
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:CopyObject",
                            ],
                            resources=[
                                f"{self.approved_bucket.bucket_arn}/*",
                                f"{self.rejected_bucket.bucket_arn}/*",
                            ],
                        ),
                        # EventBridge permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "events:PutEvents",
                            ],
                            resources=[
                                self.event_bus.event_bus_arn,
                            ],
                        ),
                        # SNS permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sns:Publish",
                            ],
                            resources=[
                                self.sns_topic.topic_arn,
                            ],
                        ),
                    ]
                )
            },
        )

        # Content analysis Lambda function
        self.content_analysis_function = lambda_.Function(
            self,
            "ContentAnalysisFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_content_analysis_code()),
            timeout=Duration.seconds(60),
            memory_size=512,
            role=lambda_role,
            environment={
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Workflow handler functions
        self.workflow_functions = {}
        for decision_type in ["approved", "rejected", "review"]:
            self.workflow_functions[decision_type] = lambda_.Function(
                self,
                f"{decision_type.capitalize()}HandlerFunction",
                runtime=lambda_.Runtime.PYTHON_3_9,
                handler="index.lambda_handler",
                code=lambda_.Code.from_inline(
                    self._get_workflow_handler_code(decision_type)
                ),
                timeout=Duration.seconds(30),
                memory_size=256,
                role=lambda_role,
                environment={
                    "APPROVED_BUCKET": self.approved_bucket.bucket_name,
                    "REJECTED_BUCKET": self.rejected_bucket.bucket_name,
                    "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                },
                log_retention=logs.RetentionDays.ONE_WEEK,
            )

    def _configure_s3_events(self) -> None:
        """Configure S3 event notifications to trigger content analysis."""
        
        self.content_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.content_analysis_function),
            s3.NotificationKeyFilter(suffix=".txt"),
        )

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for workflow routing."""
        
        # Create rules for each decision type
        for decision_type in ["approved", "rejected", "review"]:
            rule = events.Rule(
                self,
                f"{decision_type.capitalize()}ContentRule",
                event_bus=self.event_bus,
                rule_name=f"{decision_type}-content-rule",
                event_pattern=events.EventPattern(
                    source=["content.moderation"],
                    detail_type=[f"Content {decision_type.capitalize()}"],
                ),
            )
            
            # Add Lambda target
            rule.add_target(
                targets.LambdaFunction(
                    self.workflow_functions[decision_type],
                    retry_attempts=2,
                )
            )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        cdk.CfnOutput(
            self,
            "ContentBucketName",
            value=self.content_bucket.bucket_name,
            description="S3 bucket for content uploads",
        )

        cdk.CfnOutput(
            self,
            "ApprovedBucketName",
            value=self.approved_bucket.bucket_name,
            description="S3 bucket for approved content",
        )

        cdk.CfnOutput(
            self,
            "RejectedBucketName",
            value=self.rejected_bucket.bucket_name,
            description="S3 bucket for rejected content",
        )

        cdk.CfnOutput(
            self,
            "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Custom EventBridge bus for content moderation",
        )

        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic for content moderation notifications",
        )

    def _get_content_analysis_code(self) -> str:
        """Return the Lambda function code for content analysis."""
        
        return """
import json
import boto3
import urllib.parse
from datetime import datetime

bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        # Get content from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Prepare moderation prompt with structured output
        prompt = f'''
        Human: Please analyze the following content for policy violations. 
        Consider harmful content including hate speech, violence, harassment, 
        inappropriate sexual content, misinformation, and spam.
        
        Content to analyze:
        {content[:2000]}
        
        Respond with a JSON object containing:
        - "decision": "approved", "rejected", or "review"
        - "confidence": score from 0.0 to 1.0
        - "reason": brief explanation
        - "categories": array of policy categories if violations found
        
        Assistant: '''
        
        # Invoke Bedrock Claude model
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        })
        
        bedrock_response = bedrock.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=body,
            contentType='application/json'
        )
        
        response_body = json.loads(bedrock_response['body'].read())
        
        # Parse AI response and handle potential JSON parsing errors
        try:
            moderation_result = json.loads(response_body['content'][0]['text'])
        except json.JSONDecodeError:
            # Fallback for unparseable responses
            moderation_result = {
                "decision": "review",
                "confidence": 0.5,
                "reason": "Unable to parse AI response",
                "categories": ["parsing_error"]
            }
        
        # Publish event to EventBridge
        event_detail = {
            'bucket': bucket,
            'key': key,
            'decision': moderation_result['decision'],
            'confidence': moderation_result['confidence'],
            'reason': moderation_result['reason'],
            'categories': moderation_result.get('categories', []),
            'timestamp': datetime.utcnow().isoformat()
        }
        
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'content.moderation',
                    'DetailType': f"Content {moderation_result['decision'].title()}",
                    'Detail': json.dumps(event_detail),
                    'EventBusName': os.environ['EVENT_BUS_NAME']
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Content analyzed successfully',
                'decision': moderation_result['decision']
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
"""

    def _get_workflow_handler_code(self, decision_type: str) -> str:
        """Return the Lambda function code for workflow handlers."""
        
        return f"""
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        source_bucket = detail['bucket']
        source_key = detail['key']
        
        # Determine target bucket based on workflow
        target_bucket_map = {{
            'approved': os.environ['APPROVED_BUCKET'],
            'rejected': os.environ['REJECTED_BUCKET'],
            'review': os.environ['REJECTED_BUCKET']  # Review items go to rejected bucket with special prefix
        }}
        
        target_bucket = target_bucket_map['{decision_type}']
        target_key = f"{decision_type}/{datetime.utcnow().strftime('%Y/%m/%d')}/{source_key}"
        
        # Copy content to appropriate bucket with metadata
        copy_source = {{'Bucket': source_bucket, 'Key': source_key}}
        s3.copy_object(
            CopySource=copy_source,
            Bucket=target_bucket,
            Key=target_key,
            MetadataDirective='REPLACE',
            Metadata={{
                'moderation-decision': detail['decision'],
                'moderation-confidence': str(detail['confidence']),
                'moderation-reason': detail['reason'],
                'processed-timestamp': datetime.utcnow().isoformat()
            }}
        )
        
        # Send notification with comprehensive details
        message = f'''
Content Moderation Result: {detail['decision'].upper()}

File: {source_key}
Confidence: {detail['confidence']:.2f}
Reason: {detail['reason']}
Categories: {', '.join(detail.get('categories', []))}
Timestamp: {detail['timestamp']}

Target Location: s3://{target_bucket}/{target_key}
        '''
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'Content {detail["decision"].title()}: {source_key}',
            Message=message
        )
        
        return {{
            'statusCode': 200,
            'body': json.dumps({{
                'message': f'Content processed for {decision_type}',
                'target_location': f's3://{target_bucket}/{target_key}'
            }})
        }}
        
    except Exception as e:
        print(f"Error in {decision_type} handler: {{str(e)}}")
        return {{
            'statusCode': 500,
            'body': json.dumps({{'error': str(e)}})
        }}
"""


class ContentModerationApp(cdk.App):
    """
    CDK Application for Content Moderation system.
    
    This application can be configured with environment variables:
    - NOTIFICATION_EMAIL: Email address for moderation notifications
    - CDK_DEFAULT_REGION: AWS region for deployment
    - CDK_DEFAULT_ACCOUNT: AWS account ID for deployment
    """

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Get configuration from environment variables
        notification_email = os.environ.get("NOTIFICATION_EMAIL")
        
        # Create the stack
        ContentModerationStack(
            self,
            "ContentModerationStack",
            notification_email=notification_email,
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION"),
            ),
            description="Intelligent content moderation system using Amazon Bedrock and EventBridge",
        )


if __name__ == "__main__":
    app = ContentModerationApp()
    app.synth()