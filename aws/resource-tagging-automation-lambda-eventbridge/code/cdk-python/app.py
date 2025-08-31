#!/usr/bin/env python3
"""
CDK Python application for Resource Tagging Automation with Lambda and EventBridge.

This application deploys an automated tagging system that uses EventBridge to capture
resource creation events via CloudTrail and triggers Lambda functions to immediately
apply standardized organizational tags.

Architecture:
- EventBridge Rule to capture CloudTrail resource creation events
- Lambda Function to process events and apply tags
- IAM Role with appropriate permissions
- Resource Group for tagged resources
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_iam as iam,
    aws_resourcegroups as resource_groups,
    aws_logs as logs,
)
from constructs import Construct


class ResourceTaggingAutomationStack(Stack):
    """
    CDK Stack for automated resource tagging using Lambda and EventBridge.
    
    This stack creates:
    - Lambda function for automated tagging
    - EventBridge rule to capture resource creation events
    - IAM role with necessary permissions
    - Resource group for tagged resources
    - CloudWatch log group for Lambda function
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "auto"
        
        # Standard organizational tags applied by the Lambda function
        self.standard_tags: Dict[str, str] = {
            "AutoTagged": "true",
            "Environment": self.node.try_get_context("environment") or "production",
            "CostCenter": self.node.try_get_context("cost_center") or "engineering",
            "ManagedBy": "automation",
            "Project": "resource-tagging-automation"
        }

        # Create IAM role for Lambda function
        self.lambda_role = self._create_lambda_role(unique_suffix)
        
        # Create Lambda function for automated tagging
        self.tagging_function = self._create_lambda_function(unique_suffix)
        
        # Create EventBridge rule for resource creation events
        self.event_rule = self._create_eventbridge_rule(unique_suffix)
        
        # Create Resource Group for tagged resources
        self.resource_group = self._create_resource_group(unique_suffix)
        
        # Apply standard tags to stack resources
        self._apply_tags_to_stack()

    def _create_lambda_role(self, unique_suffix: str) -> iam.Role:
        """
        Create IAM role for Lambda function with necessary permissions.
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            IAM Role for Lambda function
        """
        role = iam.Role(
            self,
            "AutoTaggerRole",
            role_name=f"AutoTaggerRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for automated resource tagging Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add custom policy for resource tagging permissions
        tagging_policy = iam.PolicyDocument(
            statements=[
                # CloudWatch Logs permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                    ],
                    resources=["arn:aws:logs:*:*:*"]
                ),
                # EC2 tagging permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:CreateTags",
                        "ec2:DescribeInstances",
                        "ec2:DescribeImages",
                        "ec2:DescribeVolumes"
                    ],
                    resources=["*"]
                ),
                # S3 tagging permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:PutBucketTagging",
                        "s3:GetBucketTagging"
                    ],
                    resources=["*"]
                ),
                # RDS tagging permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "rds:AddTagsToResource",
                        "rds:ListTagsForResource"
                    ],
                    resources=["*"]
                ),
                # Lambda tagging permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "lambda:TagResource",
                        "lambda:ListTags"
                    ],
                    resources=["*"]
                ),
                # Resource Groups and tagging permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "resource-groups:Tag",
                        "resource-groups:GetTags",
                        "tag:GetResources",
                        "tag:TagResources"
                    ],
                    resources=["*"]
                )
            ]
        )

        role.attach_inline_policy(
            iam.Policy(
                self,
                "AutoTaggingPolicy",
                policy_name="AutoTaggingPolicy",
                document=tagging_policy
            )
        )

        return role

    def _create_lambda_function(self, unique_suffix: str) -> _lambda.Function:
        """
        Create Lambda function for automated resource tagging.
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            Lambda Function for automated tagging
        """
        # Create CloudWatch log group with retention policy
        log_group = logs.LogGroup(
            self,
            "AutoTaggerLogGroup",
            log_group_name=f"/aws/lambda/auto-tagger-{unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process CloudTrail events and apply tags to newly created resources.
    
    Args:
        event: EventBridge event containing CloudTrail data
        context: Lambda context object
        
    Returns:
        Response dictionary with status and message
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', '')
        source_ip_address = detail.get('sourceIPAddress', 'unknown')
        user_identity = detail.get('userIdentity', {})
        user_name = user_identity.get('userName', user_identity.get('type', 'unknown'))
        aws_region = detail.get('awsRegion', 'us-east-1')
        
        logger.info(f"Processing event: {event_name} by user: {user_name} in region: {aws_region}")
        
        # Define standard tags to apply
        standard_tags = {
            'AutoTagged': 'true',
            'Environment': 'production',
            'CostCenter': 'engineering',
            'CreatedBy': user_name,
            'CreatedDate': datetime.now().strftime('%Y-%m-%d'),
            'ManagedBy': 'automation',
            'Project': 'resource-tagging-automation'
        }
        
        # Process different resource types
        resources_tagged = 0
        
        if event_name == 'RunInstances':
            resources_tagged += tag_ec2_instances(detail, standard_tags, aws_region)
        elif event_name == 'CreateBucket':
            resources_tagged += tag_s3_bucket(detail, standard_tags)
        elif event_name == 'CreateDBInstance':
            resources_tagged += tag_rds_instance(detail, standard_tags, aws_region)
        elif event_name == 'CreateFunction20150331':
            resources_tagged += tag_lambda_function(detail, standard_tags, aws_region)
        else:
            logger.warning(f"Unhandled event type: {event_name}")
        
        logger.info(f"Successfully tagged {resources_tagged} resources")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Tagged {resources_tagged} resources',
                'event': event_name,
                'user': user_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'event': event.get('detail', {}).get('eventName', 'unknown')
            })
        }

def tag_ec2_instances(detail: Dict[str, Any], tags: Dict[str, str], region: str) -> int:
    """Tag EC2 instances from RunInstances event."""
    try:
        ec2 = boto3.client('ec2', region_name=region)
        instance_ids = []
        
        # Extract instance IDs from response elements
        response_elements = detail.get('responseElements', {})
        instances = response_elements.get('instancesSet', {}).get('items', [])
        
        for instance in instances:
            instance_id = instance.get('instanceId')
            if instance_id:
                instance_ids.append(instance_id)
        
        if instance_ids:
            tag_list = [{'Key': k, 'Value': v} for k, v in tags.items()]
            ec2.create_tags(Resources=instance_ids, Tags=tag_list)
            logger.info(f"Tagged EC2 instances: {instance_ids}")
            return len(instance_ids)
        
        return 0
    except Exception as e:
        logger.error(f"Error tagging EC2 instances: {str(e)}")
        return 0

def tag_s3_bucket(detail: Dict[str, Any], tags: Dict[str, str]) -> int:
    """Tag S3 bucket from CreateBucket event."""
    try:
        s3 = boto3.client('s3')
        
        # Extract bucket name
        request_params = detail.get('requestParameters', {})
        bucket_name = request_params.get('bucketName')
        
        if bucket_name:
            tag_set = [{'Key': k, 'Value': v} for k, v in tags.items()]
            s3.put_bucket_tagging(
                Bucket=bucket_name,
                Tagging={'TagSet': tag_set}
            )
            logger.info(f"Tagged S3 bucket: {bucket_name}")
            return 1
        
        return 0
    except Exception as e:
        logger.error(f"Error tagging S3 bucket: {str(e)}")
        return 0

def tag_rds_instance(detail: Dict[str, Any], tags: Dict[str, str], region: str) -> int:
    """Tag RDS instance from CreateDBInstance event."""
    try:
        rds = boto3.client('rds', region_name=region)
        
        # Extract DB instance identifier
        response_elements = detail.get('responseElements', {})
        db_instance = response_elements.get('dBInstance', {})
        db_instance_arn = db_instance.get('dBInstanceArn')
        
        if db_instance_arn:
            tag_list = [{'Key': k, 'Value': v} for k, v in tags.items()]
            rds.add_tags_to_resource(
                ResourceName=db_instance_arn,
                Tags=tag_list
            )
            logger.info(f"Tagged RDS instance: {db_instance_arn}")
            return 1
        
        return 0
    except Exception as e:
        logger.error(f"Error tagging RDS instance: {str(e)}")
        return 0

def tag_lambda_function(detail: Dict[str, Any], tags: Dict[str, str], region: str) -> int:
    """Tag Lambda function from CreateFunction event."""
    try:
        lambda_client = boto3.client('lambda', region_name=region)
        
        # Extract function name
        response_elements = detail.get('responseElements', {})
        function_arn = response_elements.get('functionArn')
        
        if function_arn:
            lambda_client.tag_resource(
                Resource=function_arn,
                Tags=tags
            )
            logger.info(f"Tagged Lambda function: {function_arn}")
            return 1
        
        return 0
    except Exception as e:
        logger.error(f"Error tagging Lambda function: {str(e)}")
        return 0
'''

        function = _lambda.Function(
            self,
            "AutoTaggerFunction",
            function_name=f"auto-tagger-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Automated resource tagging function triggered by EventBridge",
            log_group=log_group,
            environment={
                "STACK_NAME": self.stack_name,
                "REGION": self.region
            }
        )

        return function

    def _create_eventbridge_rule(self, unique_suffix: str) -> events.Rule:
        """
        Create EventBridge rule to capture resource creation events.
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            EventBridge Rule for resource creation events
        """
        # Event pattern to capture resource creation events
        event_pattern = {
            "source": ["aws.ec2", "aws.s3", "aws.rds", "aws.lambda"],
            "detail-type": ["AWS API Call via CloudTrail"],
            "detail": {
                "eventName": [
                    "RunInstances",
                    "CreateBucket", 
                    "CreateDBInstance",
                    "CreateFunction20150331"
                ],
                "eventSource": [
                    "ec2.amazonaws.com",
                    "s3.amazonaws.com", 
                    "rds.amazonaws.com",
                    "lambda.amazonaws.com"
                ]
            }
        }

        rule = events.Rule(
            self,
            "ResourceCreationRule",
            rule_name=f"resource-creation-rule-{unique_suffix}",
            description="Trigger tagging for new AWS resources",
            event_pattern=event_pattern,
            enabled=True
        )

        # Add Lambda function as target
        rule.add_target(
            events_targets.LambdaFunction(
                self.tagging_function,
                retry_policy=events_targets.RetryPolicy(
                    maximum_retry_attempts=3,
                    maximum_event_age=Duration.hours(1)
                )
            )
        )

        return rule

    def _create_resource_group(self, unique_suffix: str) -> resource_groups.CfnGroup:
        """
        Create Resource Group for tagged resources.
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            Resource Group for auto-tagged resources
        """
        # Resource query for auto-tagged resources
        resource_query = {
            "Type": "TAG_FILTERS_1_0",
            "Query": {
                "ResourceTypeFilters": ["AWS::AllSupported"],
                "TagFilters": [
                    {
                        "Key": "AutoTagged",
                        "Values": ["true"]
                    }
                ]
            }
        }

        resource_group = resource_groups.CfnGroup(
            self,
            "AutoTaggedResourceGroup",
            name=f"auto-tagged-resources-{unique_suffix}",
            description="Resources automatically tagged by Lambda function",
            resource_query=resource_query,
            tags=[
                {"key": "Environment", "value": "production"},
                {"key": "Purpose", "value": "automation"},
                {"key": "ManagedBy", "value": "cdk"}
            ]
        )

        return resource_group

    def _apply_tags_to_stack(self) -> None:
        """Apply standard tags to all stack resources."""
        for key, value in self.standard_tags.items():
            cdk.Tags.of(self).add(key, value)


class ResourceTaggingAutomationApp(cdk.App):
    """CDK Application for Resource Tagging Automation."""

    def __init__(self) -> None:
        super().__init__()

        # Get deployment configuration from context
        env_config = {
            "account": os.environ.get("CDK_DEFAULT_ACCOUNT"),
            "region": os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        }

        # Create the main stack
        ResourceTaggingAutomationStack(
            self,
            "ResourceTaggingAutomationStack",
            env=cdk.Environment(**env_config),
            description="Automated resource tagging system using Lambda and EventBridge",
            stack_name="resource-tagging-automation"
        )


# Create and synthesize the CDK application
if __name__ == "__main__":
    app = ResourceTaggingAutomationApp()
    app.synth()