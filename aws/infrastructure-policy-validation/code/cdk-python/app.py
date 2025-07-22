#!/usr/bin/env python3
"""
AWS CDK application for Infrastructure Policy Validation with CloudFormation Guard.

This CDK application creates a comprehensive policy validation infrastructure that includes:
- S3 bucket for storing Guard rules and validation reports
- IAM roles and policies for CloudFormation Guard operations
- Lambda function for automated template validation
- EventBridge rules for triggering validations
- CloudWatch logs for monitoring and auditing

The infrastructure follows AWS Well-Architected principles and implements
security best practices for policy-as-code governance.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    Duration,
    RemovalPolicy,
    CfnOutput
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as aws_lambda
from aws_cdk import aws_logs as logs
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from aws_cdk import aws_cloudformation as cfn
from constructs import Construct


class CloudFormationGuardStack(Stack):
    """
    Stack for CloudFormation Guard policy validation infrastructure.
    
    This stack creates all necessary resources for implementing automated
    infrastructure policy validation using CloudFormation Guard rules.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment_name: str = "dev",
        **kwargs
    ) -> None:
        """
        Initialize the CloudFormation Guard stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            environment_name: Environment name for resource naming
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name
        
        # Create S3 bucket for Guard rules and reports
        self.guard_rules_bucket = self._create_guard_rules_bucket()
        
        # Create IAM role for Guard validation
        self.validation_role = self._create_validation_role()
        
        # Create Lambda function for automated validation
        self.validation_function = self._create_validation_lambda()
        
        # Create EventBridge rule for automated triggering
        self.validation_event_rule = self._create_event_rule()
        
        # Create CloudWatch log group for validation logs
        self.validation_log_group = self._create_log_group()
        
        # Create outputs for integration
        self._create_outputs()
        
        # Add common tags to all resources
        self._tag_resources()

    def _create_guard_rules_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing Guard rules, test cases, and validation reports.
        
        Returns:
            S3 bucket with versioning, encryption, and public access blocked
        """
        bucket = s3.Bucket(
            self,
            "GuardRulesBucket",
            bucket_name=f"cfn-guard-policies-{self.environment_name}-{self.account}-{self.region}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldReports",
                    prefix="reports/",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    expiration=Duration.days(2555)  # 7 years retention
                )
            ]
        )
        
        # Add bucket notification configuration for validation events
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            targets.LambdaFunction(self.validation_function) if hasattr(self, 'validation_function') else None,
            s3.NotificationKeyFilter(prefix="templates/")
        )
        
        return bucket

    def _create_validation_role(self) -> iam.Role:
        """
        Create IAM role for CloudFormation Guard validation operations.
        
        Returns:
            IAM role with necessary permissions for Guard operations
        """
        # Create assume role policy for Lambda and CodeBuild
        assume_role_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[
                        iam.ServicePrincipal("lambda.amazonaws.com"),
                        iam.ServicePrincipal("codebuild.amazonaws.com")
                    ],
                    actions=["sts:AssumeRole"]
                )
            ]
        )
        
        role = iam.Role(
            self,
            "ValidationRole",
            role_name=f"CloudFormationGuardValidationRole-{self.environment_name}",
            assume_role_policy=assume_role_policy,
            path="/guard-validation/",
            description="Role for CloudFormation Guard validation operations"
        )
        
        # Add managed policy for basic Lambda execution
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )
        
        # Create custom policy for Guard operations
        guard_policy = iam.PolicyDocument(
            statements=[
                # S3 permissions for accessing Guard rules and storing reports
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:GetObjectVersion",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket"
                    ],
                    resources=[
                        self.guard_rules_bucket.bucket_arn,
                        f"{self.guard_rules_bucket.bucket_arn}/*"
                    ]
                ),
                # CloudFormation permissions for template validation
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudformation:ValidateTemplate",
                        "cloudformation:GetTemplate",
                        "cloudformation:DescribeStacks",
                        "cloudformation:DescribeStackResources"
                    ],
                    resources=["*"]
                ),
                # CloudWatch Logs permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                    ],
                    resources=[f"arn:aws:logs:{self.region}:{self.account}:*"]
                ),
                # EventBridge permissions for triggering validations
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "events:PutEvents"
                    ],
                    resources=[f"arn:aws:events:{self.region}:{self.account}:event-bus/*"]
                )
            ]
        )
        
        # Attach the custom policy to the role
        iam.Policy(
            self,
            "GuardValidationPolicy",
            policy_name=f"GuardValidationPolicy-{self.environment_name}",
            policy_document=guard_policy,
            roles=[role]
        )
        
        return role

    def _create_validation_lambda(self) -> aws_lambda.Function:
        """
        Create Lambda function for automated CloudFormation Guard validation.
        
        Returns:
            Lambda function configured for Guard validation operations
        """
        # Lambda function code for Guard validation
        function_code = '''
import json
import boto3
import subprocess
import tempfile
import os
import logging
from typing import Dict, Any, List
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client('s3')
events_client = boto3.client('events')

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for CloudFormation Guard validation.
    
    Args:
        event: Lambda event (S3 object creation or direct invocation)
        context: Lambda context
        
    Returns:
        Validation results and status
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Handle S3 event or direct invocation
        if 'Records' in event and event['Records']:
            # S3 event
            record = event['Records'][0]
            bucket_name = record['s3']['bucket']['name']
            object_key = unquote_plus(record['s3']['object']['key'])
        else:
            # Direct invocation
            bucket_name = event.get('bucket_name')
            object_key = event.get('object_key')
            
        if not bucket_name or not object_key:
            raise ValueError("Missing bucket_name or object_key in event")
            
        logger.info(f"Processing template: s3://{bucket_name}/{object_key}")
        
        # Download template and Guard rules
        template_content = download_s3_object(bucket_name, object_key)
        guard_rules = download_guard_rules(bucket_name)
        
        # Validate template against Guard rules
        validation_results = validate_with_guard(template_content, guard_rules)
        
        # Upload validation report
        report_key = f"reports/{object_key.replace('/', '-')}-validation-{context.aws_request_id}.json"
        upload_validation_report(bucket_name, report_key, validation_results)
        
        # Send validation event
        send_validation_event(validation_results, bucket_name, object_key)
        
        logger.info(f"Validation completed. Report: s3://{bucket_name}/{report_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Validation completed successfully',
                'template': f's3://{bucket_name}/{object_key}',
                'report': f's3://{bucket_name}/{report_key}',
                'validation_passed': validation_results['summary']['passed'],
                'violations': validation_results['summary']['violations']
            })
        }
        
    except Exception as e:
        logger.error(f"Validation failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Validation failed'
            })
        }

def download_s3_object(bucket_name: str, object_key: str) -> str:
    """Download object content from S3."""
    response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
    return response['Body'].read().decode('utf-8')

def download_guard_rules(bucket_name: str) -> List[str]:
    """Download all Guard rule files from S3."""
    guard_rules = []
    
    try:
        # List all Guard rule files
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix='guard-rules/',
            Delimiter='/'
        )
        
        for obj in response.get('Contents', []):
            if obj['Key'].endswith('.guard'):
                rule_content = download_s3_object(bucket_name, obj['Key'])
                guard_rules.append(rule_content)
                logger.info(f"Downloaded Guard rule: {obj['Key']}")
                
    except Exception as e:
        logger.warning(f"Failed to download Guard rules: {str(e)}")
        
    return guard_rules

def validate_with_guard(template_content: str, guard_rules: List[str]) -> Dict[str, Any]:
    """
    Validate CloudFormation template against Guard rules.
    
    Note: This is a simplified validation. In production, you would:
    1. Install cfn-guard in the Lambda layer or container
    2. Use subprocess to call cfn-guard CLI
    3. Parse the actual Guard validation output
    """
    validation_results = {
        'timestamp': context.aws_request_id,
        'summary': {
            'passed': True,
            'violations': 0,
            'rules_checked': len(guard_rules)
        },
        'details': [],
        'template_analyzed': True
    }
    
    # Simplified validation logic (replace with actual cfn-guard execution)
    try:
        template_json = json.loads(template_content) if template_content.strip().startswith('{') else None
        
        if template_json and 'Resources' in template_json:
            # Check for basic security requirements
            s3_buckets = [r for r in template_json['Resources'].values() 
                         if r.get('Type') == 'AWS::S3::Bucket']
            
            for bucket in s3_buckets:
                props = bucket.get('Properties', {})
                
                # Check versioning
                if not props.get('VersioningConfiguration', {}).get('Status') == 'Enabled':
                    validation_results['details'].append({
                        'rule': 's3_bucket_versioning_enabled',
                        'status': 'FAIL',
                        'message': 'S3 bucket must have versioning enabled'
                    })
                    validation_results['summary']['violations'] += 1
                    validation_results['summary']['passed'] = False
                
                # Check encryption
                if not props.get('BucketEncryption'):
                    validation_results['details'].append({
                        'rule': 's3_bucket_encryption_enabled',
                        'status': 'FAIL',
                        'message': 'S3 bucket must have encryption enabled'
                    })
                    validation_results['summary']['violations'] += 1
                    validation_results['summary']['passed'] = False
                    
    except json.JSONDecodeError:
        logger.info("Template is not JSON format, skipping detailed validation")
        
    return validation_results

def upload_validation_report(bucket_name: str, report_key: str, results: Dict[str, Any]) -> None:
    """Upload validation report to S3."""
    s3_client.put_object(
        Bucket=bucket_name,
        Key=report_key,
        Body=json.dumps(results, indent=2),
        ContentType='application/json',
        ServerSideEncryption='AES256'
    )

def send_validation_event(results: Dict[str, Any], bucket_name: str, object_key: str) -> None:
    """Send validation completion event to EventBridge."""
    try:
        events_client.put_events(
            Entries=[
                {
                    'Source': 'cloudformation.guard.validation',
                    'DetailType': 'Template Validation Completed',
                    'Detail': json.dumps({
                        'template': f's3://{bucket_name}/{object_key}',
                        'validation_passed': results['summary']['passed'],
                        'violations': results['summary']['violations'],
                        'timestamp': results['timestamp']
                    })
                }
            ]
        )
    except Exception as e:
        logger.warning(f"Failed to send validation event: {str(e)}")
'''
        
        function = aws_lambda.Function(
            self,
            "ValidationFunction",
            function_name=f"cfn-guard-validation-{self.environment_name}",
            runtime=aws_lambda.Runtime.PYTHON_3_9,
            handler="index.handler",
            code=aws_lambda.Code.from_inline(function_code),
            role=self.validation_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "GUARD_RULES_BUCKET": self.guard_rules_bucket.bucket_name,
                "ENVIRONMENT": self.environment_name,
                "LOG_LEVEL": "INFO"
            },
            description="CloudFormation Guard template validation function",
            retry_attempts=2
        )
        
        # Grant S3 permissions to Lambda
        self.guard_rules_bucket.grant_read_write(function)
        
        return function

    def _create_event_rule(self) -> events.Rule:
        """
        Create EventBridge rule for automated validation triggering.
        
        Returns:
            EventBridge rule for S3 template uploads
        """
        rule = events.Rule(
            self,
            "ValidationEventRule",
            rule_name=f"cfn-guard-validation-trigger-{self.environment_name}",
            description="Trigger CloudFormation Guard validation on template uploads",
            event_pattern=events.EventPattern(
                source=["aws.s3"],
                detail_type=["Object Created"],
                detail={
                    "bucket": {"name": [self.guard_rules_bucket.bucket_name]},
                    "object": {"key": [{"prefix": "templates/"}]}
                }
            )
        )
        
        # Add Lambda target
        rule.add_target(targets.LambdaFunction(self.validation_function))
        
        return rule

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for validation logs.
        
        Returns:
            CloudWatch log group for centralized logging
        """
        log_group = logs.LogGroup(
            self,
            "ValidationLogGroup",
            log_group_name=f"/aws/lambda/cfn-guard-validation-{self.environment_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for integration."""
        CfnOutput(
            self,
            "GuardRulesBucketName",
            value=self.guard_rules_bucket.bucket_name,
            description="S3 bucket for storing Guard rules and validation reports",
            export_name=f"{self.stack_name}-GuardRulesBucket"
        )
        
        CfnOutput(
            self,
            "ValidationFunctionArn",
            value=self.validation_function.function_arn,
            description="Lambda function ARN for Guard validation",
            export_name=f"{self.stack_name}-ValidationFunction"
        )
        
        CfnOutput(
            self,
            "ValidationRoleArn",
            value=self.validation_role.role_arn,
            description="IAM role ARN for Guard validation operations",
            export_name=f"{self.stack_name}-ValidationRole"
        )
        
        CfnOutput(
            self,
            "ValidationLogGroupName",
            value=self.validation_log_group.log_group_name,
            description="CloudWatch log group for validation logs",
            export_name=f"{self.stack_name}-ValidationLogGroup"
        )

    def _tag_resources(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "CloudFormation-Guard-Validation")
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("Owner", "Infrastructure-Team")
        Tags.of(self).add("CostCenter", "DevOps")
        Tags.of(self).add("Compliance", "Policy-as-Code")


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get environment configuration
    environment_name = app.node.try_get_context("environment") or "dev"
    aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    aws_region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    # Create environment
    env = Environment(
        account=aws_account,
        region=aws_region
    )
    
    # Create the stack
    stack = CloudFormationGuardStack(
        app,
        f"CloudFormationGuardStack-{environment_name}",
        environment_name=environment_name,
        env=env,
        description=f"CloudFormation Guard policy validation infrastructure for {environment_name} environment"
    )
    
    app.synth()


if __name__ == "__main__":
    main()