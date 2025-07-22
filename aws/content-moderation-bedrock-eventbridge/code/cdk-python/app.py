#!/usr/bin/env python3
"""
Content Moderation CDK Application

This CDK application implements an intelligent content moderation system using Amazon Bedrock
and EventBridge. It creates a complete infrastructure stack including:
- S3 buckets for content storage
- Lambda functions for content analysis and workflow processing
- EventBridge custom bus for event routing
- SNS topic for notifications
- IAM roles with least privilege permissions
- Bedrock Guardrails for enhanced AI safety

Author: AWS CDK Generator
Version: 1.0.0
"""

import os
from typing import List, Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_s3_notifications as s3n,
    aws_bedrock as bedrock,
    CfnOutput,
    RemovalPolicy,
)
from constructs import Construct


class ContentModerationStack(Stack):
    """
    CDK Stack for intelligent content moderation using Amazon Bedrock and EventBridge.
    
    This stack creates a complete event-driven content moderation system that automatically
    analyzes uploaded content using Amazon Bedrock's Claude models and routes the results
    through EventBridge to appropriate downstream workflows.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.stack_prefix = "content-moderation"
        self.notification_email = self.node.try_get_context("notification_email") or "admin@example.com"
        
        # Create S3 buckets for content storage
        self.content_bucket = self._create_content_bucket()
        self.approved_bucket = self._create_approved_bucket()
        self.rejected_bucket = self._create_rejected_bucket()
        
        # Create SNS topic for notifications
        self.sns_topic = self._create_sns_topic()
        
        # Create custom EventBridge bus
        self.event_bus = self._create_event_bus()
        
        # Create IAM roles
        self.content_analysis_role = self._create_content_analysis_role()
        self.workflow_handler_role = self._create_workflow_handler_role()
        
        # Create Lambda functions
        self.content_analysis_function = self._create_content_analysis_function()
        self.approved_handler_function = self._create_approved_handler_function()
        self.rejected_handler_function = self._create_rejected_handler_function()
        self.review_handler_function = self._create_review_handler_function()
        
        # Configure S3 event notifications
        self._configure_s3_notifications()
        
        # Create EventBridge rules
        self._create_eventbridge_rules()
        
        # Create Bedrock Guardrails
        self.guardrail = self._create_bedrock_guardrail()
        
        # Create outputs
        self._create_outputs()

    def _create_content_bucket(self) -> s3.Bucket:
        """Create the main content upload bucket with security features enabled."""
        bucket = s3.Bucket(
            self,
            "ContentBucket",
            bucket_name=f"{self.stack_prefix}-content-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    expiration=Duration.days(30),
                    noncurrent_version_expiration=Duration.days(7),
                )
            ],
        )
        
        # Add bucket policy to deny insecure transport
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, bucket.arn_for_objects("*")],
                conditions={
                    "Bool": {"aws:SecureTransport": "false"}
                },
            )
        )
        
        return bucket

    def _create_approved_bucket(self) -> s3.Bucket:
        """Create bucket for approved content storage."""
        return s3.Bucket(
            self,
            "ApprovedBucket",
            bucket_name=f"{self.stack_prefix}-approved-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_rejected_bucket(self) -> s3.Bucket:
        """Create bucket for rejected content storage."""
        return s3.Bucket(
            self,
            "RejectedBucket",
            bucket_name=f"{self.stack_prefix}-rejected-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for moderation notifications."""
        topic = sns.Topic(
            self,
            "NotificationTopic",
            topic_name=f"{self.stack_prefix}-notifications",
            display_name="Content Moderation Notifications",
        )
        
        # Add email subscription if provided
        if self.notification_email != "admin@example.com":
            topic.add_subscription(
                sns_subscriptions.EmailSubscription(self.notification_email)
            )
        
        return topic

    def _create_event_bus(self) -> events.EventBus:
        """Create custom EventBridge bus for content moderation events."""
        return events.EventBus(
            self,
            "ContentModerationBus",
            event_bus_name=f"{self.stack_prefix}-bus",
        )

    def _create_content_analysis_role(self) -> iam.Role:
        """Create IAM role for content analysis Lambda function."""
        role = iam.Role(
            self,
            "ContentAnalysisRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add Bedrock permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "bedrock:InvokeModel",
                    "bedrock:InvokeModelWithResponseStream",
                ],
                resources=[
                    f"arn:aws:bedrock:{cdk.Aws.REGION}::foundation-model/anthropic.*"
                ],
            )
        )
        
        # Add S3 read permissions for content bucket
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject", "s3:GetObjectVersion"],
                resources=[self.content_bucket.arn_for_objects("*")],
            )
        )
        
        # Add EventBridge permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["events:PutEvents"],
                resources=[self.event_bus.event_bus_arn],
            )
        )
        
        return role

    def _create_workflow_handler_role(self) -> iam.Role:
        """Create IAM role for workflow handler Lambda functions."""
        role = iam.Role(
            self,
            "WorkflowHandlerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add S3 permissions for content operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:CopyObject",
                    "s3:PutObject",
                    "s3:PutObjectMetadata",
                ],
                resources=[
                    self.content_bucket.arn_for_objects("*"),
                    self.approved_bucket.arn_for_objects("*"),
                    self.rejected_bucket.arn_for_objects("*"),
                ],
            )
        )
        
        # Add SNS permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.sns_topic.topic_arn],
            )
        )
        
        return role

    def _create_content_analysis_function(self) -> lambda_.Function:
        """Create Lambda function for content analysis using Bedrock."""
        return lambda_.Function(
            self,
            "ContentAnalysisFunction",
            function_name=f"{self.stack_prefix}-content-analysis",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_content_analysis_code()),
            role=self.content_analysis_role,
            timeout=Duration.minutes(2),
            memory_size=512,
            environment={
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
                "CONTENT_BUCKET": self.content_bucket.bucket_name,
            },
            retry_attempts=2,
        )

    def _create_approved_handler_function(self) -> lambda_.Function:
        """Create Lambda function for handling approved content."""
        return lambda_.Function(
            self,
            "ApprovedHandlerFunction",
            function_name=f"{self.stack_prefix}-approved-handler",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(
                self._get_workflow_handler_code("approved", self.approved_bucket.bucket_name)
            ),
            role=self.workflow_handler_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            environment={
                "TARGET_BUCKET": self.approved_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "WORKFLOW_TYPE": "approved",
            },
        )

    def _create_rejected_handler_function(self) -> lambda_.Function:
        """Create Lambda function for handling rejected content."""
        return lambda_.Function(
            self,
            "RejectedHandlerFunction",
            function_name=f"{self.stack_prefix}-rejected-handler",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(
                self._get_workflow_handler_code("rejected", self.rejected_bucket.bucket_name)
            ),
            role=self.workflow_handler_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            environment={
                "TARGET_BUCKET": self.rejected_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "WORKFLOW_TYPE": "rejected",
            },
        )

    def _create_review_handler_function(self) -> lambda_.Function:
        """Create Lambda function for handling content requiring human review."""
        return lambda_.Function(
            self,
            "ReviewHandlerFunction",
            function_name=f"{self.stack_prefix}-review-handler",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(
                self._get_workflow_handler_code("review", self.rejected_bucket.bucket_name)
            ),
            role=self.workflow_handler_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            environment={
                "TARGET_BUCKET": self.rejected_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "WORKFLOW_TYPE": "review",
            },
        )

    def _configure_s3_notifications(self) -> None:
        """Configure S3 bucket notifications to trigger content analysis."""
        self.content_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.content_analysis_function),
            s3.NotificationKeyFilter(suffix=".txt"),
        )

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for routing moderation decisions."""
        # Rule for approved content
        approved_rule = events.Rule(
            self,
            "ApprovedContentRule",
            rule_name=f"{self.stack_prefix}-approved-rule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["content.moderation"],
                detail_type=["Content Approved"],
            ),
        )
        approved_rule.add_target(targets.LambdaFunction(self.approved_handler_function))

        # Rule for rejected content
        rejected_rule = events.Rule(
            self,
            "RejectedContentRule",
            rule_name=f"{self.stack_prefix}-rejected-rule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["content.moderation"],
                detail_type=["Content Rejected"],
            ),
        )
        rejected_rule.add_target(targets.LambdaFunction(self.rejected_handler_function))

        # Rule for content requiring review
        review_rule = events.Rule(
            self,
            "ReviewContentRule",
            rule_name=f"{self.stack_prefix}-review-rule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["content.moderation"],
                detail_type=["Content Review"],
            ),
        )
        review_rule.add_target(targets.LambdaFunction(self.review_handler_function))

    def _create_bedrock_guardrail(self) -> bedrock.CfnGuardrail:
        """Create Bedrock Guardrail for enhanced content safety."""
        return bedrock.CfnGuardrail(
            self,
            "ContentModerationGuardrail",
            name="ContentModerationGuardrail",
            description="Guardrail for content moderation to prevent harmful content",
            blocked_input_messaging="This content violates our content policy.",
            blocked_outputs_messaging="I cannot provide that type of content.",
            content_policy_config=bedrock.CfnGuardrail.ContentPolicyConfigProperty(
                filters_config=[
                    bedrock.CfnGuardrail.ContentFilterConfigProperty(
                        type="SEXUAL",
                        input_strength="HIGH",
                        output_strength="HIGH",
                    ),
                    bedrock.CfnGuardrail.ContentFilterConfigProperty(
                        type="VIOLENCE",
                        input_strength="HIGH",
                        output_strength="HIGH",
                    ),
                    bedrock.CfnGuardrail.ContentFilterConfigProperty(
                        type="HATE",
                        input_strength="HIGH",
                        output_strength="HIGH",
                    ),
                    bedrock.CfnGuardrail.ContentFilterConfigProperty(
                        type="INSULTS",
                        input_strength="MEDIUM",
                        output_strength="MEDIUM",
                    ),
                    bedrock.CfnGuardrail.ContentFilterConfigProperty(
                        type="MISCONDUCT",
                        input_strength="HIGH",
                        output_strength="HIGH",
                    ),
                ]
            ),
            topic_policy_config=bedrock.CfnGuardrail.TopicPolicyConfigProperty(
                topics_config=[
                    bedrock.CfnGuardrail.TopicConfigProperty(
                        name="IllegalActivities",
                        definition="Content promoting or instructing illegal activities",
                        examples=["How to make illegal substances", "Tax evasion strategies"],
                        type="DENY",
                    )
                ]
            ),
            sensitive_information_policy_config=bedrock.CfnGuardrail.SensitiveInformationPolicyConfigProperty(
                pii_entities_config=[
                    bedrock.CfnGuardrail.PiiEntityConfigProperty(
                        type="EMAIL",
                        action="ANONYMIZE",
                    ),
                    bedrock.CfnGuardrail.PiiEntityConfigProperty(
                        type="PHONE",
                        action="ANONYMIZE",
                    ),
                    bedrock.CfnGuardrail.PiiEntityConfigProperty(
                        type="CREDIT_DEBIT_CARD_NUMBER",
                        action="BLOCK",
                    ),
                ]
            ),
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "ContentBucketName",
            value=self.content_bucket.bucket_name,
            description="Name of the content upload bucket",
        )
        
        CfnOutput(
            self,
            "ApprovedBucketName",
            value=self.approved_bucket.bucket_name,
            description="Name of the approved content bucket",
        )
        
        CfnOutput(
            self,
            "RejectedBucketName",
            value=self.rejected_bucket.bucket_name,
            description="Name of the rejected content bucket",
        )
        
        CfnOutput(
            self,
            "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Name of the custom EventBridge bus",
        )
        
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS notification topic",
        )
        
        CfnOutput(
            self,
            "GuardrailId",
            value=self.guardrail.attr_guardrail_id,
            description="ID of the Bedrock Guardrail",
        )

    def _get_content_analysis_code(self) -> str:
        """Return the Lambda function code for content analysis."""
        return '''
import json
import boto3
import urllib.parse
import os
from datetime import datetime
from typing import Dict, Any

bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for content analysis using Amazon Bedrock.
    
    Processes S3 upload events, analyzes content using Claude models,
    and publishes results to EventBridge for downstream processing.
    """
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        print(f"Processing content: s3://{bucket}/{key}")
        
        # Get content from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Limit content length for processing
        content_to_analyze = content[:2000] if len(content) > 2000 else content
        
        # Prepare moderation prompt
        prompt = f"""Human: Please analyze the following content for policy violations. 
Consider harmful content including hate speech, violence, harassment, 
inappropriate sexual content, misinformation, and spam.

Content to analyze:
{content_to_analyze}

Respond with a JSON object containing:
- "decision": "approved", "rejected", or "review"
- "confidence": score from 0.0 to 1.0
- "reason": brief explanation
- "categories": array of policy categories if violations found
        
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
        moderation_result = json.loads(response_body['content'][0]['text'])
        
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
'''

    def _get_workflow_handler_code(self, workflow_type: str, target_bucket: str) -> str:
        """Return the Lambda function code for workflow handlers."""
        return f'''
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for content workflow processing.
    
    Handles approved, rejected, or review content based on moderation decisions.
    """
    try:
        detail = event['detail']
        source_bucket = detail['bucket']
        source_key = detail['key']
        
        # Determine target key based on workflow type
        target_key = f"{workflow_type}/{{datetime.utcnow().strftime('%Y/%m/%d')}}/{{source_key}}"
        
        # Copy content to appropriate bucket
        copy_source = {{'Bucket': source_bucket, 'Key': source_key}}
        s3.copy_object(
            CopySource=copy_source,
            Bucket=os.environ['TARGET_BUCKET'],
            Key=target_key,
            MetadataDirective='REPLACE',
            Metadata={{
                'moderation-decision': detail['decision'],
                'moderation-confidence': str(detail['confidence']),
                'moderation-reason': detail['reason'],
                'processed-timestamp': datetime.utcnow().isoformat()
            }}
        )
        
        # Send notification
        message = f"""
Content Moderation Result: {{detail['decision'].upper()}}

File: {{source_key}}
Confidence: {{detail['confidence']:.2f}}
Reason: {{detail['reason']}}
Categories: {{', '.join(detail.get('categories', []))}}
Timestamp: {{detail['timestamp']}}

Target Location: s3://{{os.environ['TARGET_BUCKET']}}/{{target_key}}
        """
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'Content {{detail["decision"].title()}}: {{source_key}}',
            Message=message
        )
        
        return {{
            'statusCode': 200,
            'body': json.dumps({{
                'message': f'Content processed for {workflow_type}',
                'target_location': f's3://{{os.environ["TARGET_BUCKET"]}}/{{target_key}}'
            }})
        }}
        
    except Exception as e:
        print(f"Error in {workflow_type} handler: {{str(e)}}")
        return {{
            'statusCode': 500,
            'body': json.dumps({{'error': str(e)}})
        }}
'''


class ContentModerationApp(cdk.App):
    """CDK App for Content Moderation System."""

    def __init__(self):
        super().__init__()
        
        # Create the content moderation stack
        ContentModerationStack(
            self,
            "ContentModerationStack",
            description="Intelligent Content Moderation with Amazon Bedrock and EventBridge",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION"),
            ),
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = ContentModerationApp()
    app.synth()


if __name__ == "__main__":
    main()