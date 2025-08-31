#!/usr/bin/env python3
"""
AWS CDK Application for Simple Log Retention Management with CloudWatch and Lambda

This CDK application creates:
- Lambda function for automated log retention management
- IAM role with proper permissions for CloudWatch Logs operations
- EventBridge rule for scheduled execution
- Lambda permission for EventBridge invocation

The solution implements automated log retention policies based on log group naming patterns
to optimize storage costs and ensure compliance with data retention requirements.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    CfnOutput,
    Tags,
)
from constructs import Construct


class LogRetentionManagerStack(Stack):
    """
    CDK Stack for Log Retention Management Solution
    
    This stack creates all the necessary AWS resources for automated log retention
    management using Lambda functions and EventBridge scheduling.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Stack parameters
        self.default_retention_days = self.node.try_get_context("default_retention_days") or "30"
        self.schedule_rate = self.node.try_get_context("schedule_rate") or "rate(7 days)"
        
        # Create IAM role for Lambda function
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda function
        self.lambda_function = self._create_lambda_function()
        
        # Create EventBridge rule and target
        self.event_rule = self._create_eventbridge_schedule()
        
        # Add tags to all resources
        self._add_stack_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with CloudWatch Logs permissions
        
        Returns:
            iam.Role: The IAM role for Lambda execution
        """
        role = iam.Role(
            self,
            "LogRetentionManagerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for automated log retention management Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
        )
        
        # Add custom policy for CloudWatch Logs operations
        logs_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "logs:DescribeLogGroups",
                "logs:PutRetentionPolicy"
            ],
            resources=["*"],
        )
        
        role.add_to_policy(logs_policy)
        
        return role

    def _create_lambda_function(self) -> _lambda.Function:
        """
        Create the Lambda function for log retention management
        
        Returns:
            _lambda.Function: The Lambda function
        """
        # Lambda function code
        lambda_code = """
import json
import boto3
import logging
import os
from typing import Dict, List, Any, Optional
from botocore.exceptions import ClientError

# Initialize CloudWatch Logs client
logs_client = boto3.client('logs')

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def apply_retention_policy(log_group_name: str, retention_days: int) -> bool:
    \"\"\"
    Apply retention policy to a specific log group
    
    Args:
        log_group_name: Name of the log group
        retention_days: Number of days to retain logs
        
    Returns:
        bool: True if successful, False otherwise
    \"\"\"
    try:
        logs_client.put_retention_policy(
            logGroupName=log_group_name,
            retentionInDays=retention_days
        )
        logger.info(f"Applied {retention_days} day retention to {log_group_name}")
        return True
    except ClientError as e:
        logger.error(f"Failed to set retention for {log_group_name}: {e}")
        return False

def get_retention_days(log_group_name: str) -> int:
    \"\"\"
    Determine appropriate retention period based on log group name patterns
    
    Args:
        log_group_name: Name of the log group
        
    Returns:
        int: Number of days for retention policy
    \"\"\"
    # Define retention rules based on log group naming patterns
    retention_rules = {
        '/aws/lambda/': 30,       # Lambda logs: 30 days
        '/aws/apigateway/': 90,   # API Gateway logs: 90 days  
        '/aws/codebuild/': 14,    # CodeBuild logs: 14 days
        '/aws/ecs/': 60,          # ECS logs: 60 days
        '/aws/stepfunctions/': 90, # Step Functions: 90 days
        '/application/': 180,     # Application logs: 180 days
        '/system/': 365,          # System logs: 1 year
    }
    
    # Check log group name against patterns
    for pattern, days in retention_rules.items():
        if pattern in log_group_name:
            return days
    
    # Default retention for unmatched patterns
    return int(os.environ.get('DEFAULT_RETENTION_DAYS', '30'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Main Lambda handler for log retention management
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing execution results and statistics
    \"\"\"
    try:
        processed_groups = 0
        updated_groups = 0
        errors: List[str] = []
        
        # Get all log groups (paginated)
        paginator = logs_client.get_paginator('describe_log_groups')
        
        for page in paginator.paginate():
            for log_group in page['logGroups']:
                log_group_name = log_group['logGroupName']
                current_retention = log_group.get('retentionInDays')
                
                # Determine appropriate retention period
                target_retention = get_retention_days(log_group_name)
                
                processed_groups += 1
                
                # Apply retention policy if needed
                if current_retention != target_retention:
                    if apply_retention_policy(log_group_name, target_retention):
                        updated_groups += 1
                    else:
                        errors.append(log_group_name)
                else:
                    logger.info(f"Log group {log_group_name} already has correct retention: {current_retention} days")
        
        # Return summary
        result = {
            'statusCode': 200,
            'message': f'Processed {processed_groups} log groups, updated {updated_groups} retention policies',
            'processedGroups': processed_groups,
            'updatedGroups': updated_groups,
            'errors': errors
        }
        
        logger.info(json.dumps(result))
        return result
        
    except Exception as e:
        logger.error(f"Error in log retention management: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
"""
        
        function = _lambda.Function(
            self,
            "LogRetentionManagerFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Automated CloudWatch Logs retention management function",
            environment={
                "DEFAULT_RETENTION_DAYS": self.default_retention_days
            },
            retry_attempts=0,  # Disable automatic retries for this use case
        )
        
        return function

    def _create_eventbridge_schedule(self) -> events.Rule:
        """
        Create EventBridge rule for scheduled Lambda execution
        
        Returns:
            events.Rule: The EventBridge rule
        """
        rule = events.Rule(
            self,
            "LogRetentionScheduleRule",
            description="Weekly schedule for log retention policy management",
            schedule=events.Schedule.expression(self.schedule_rate),
            enabled=True,
        )
        
        # Add Lambda function as target
        rule.add_target(
            targets.LambdaFunction(
                self.lambda_function,
                retry_attempts=2,
            )
        )
        
        return rule

    def _add_stack_tags(self) -> None:
        """Add common tags to all resources in the stack"""
        Tags.of(self).add("Project", "LogRetentionManagement")
        Tags.of(self).add("Purpose", "Cost-Optimization")
        Tags.of(self).add("Environment", self.node.try_get_context("environment") or "production")
        Tags.of(self).add("ManagedBy", "CDK")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the log retention management Lambda function",
            export_name=f"{self.stack_name}-LambdaFunctionName",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the log retention management Lambda function",
            export_name=f"{self.stack_name}-LambdaFunctionArn",
        )
        
        CfnOutput(
            self,
            "EventBridgeRuleName",
            value=self.event_rule.rule_name,
            description="Name of the EventBridge rule for scheduling",
            export_name=f"{self.stack_name}-EventBridgeRuleName",
        )
        
        CfnOutput(
            self,
            "IAMRoleArn",
            value=self.lambda_role.role_arn,
            description="ARN of the Lambda execution role",
            export_name=f"{self.stack_name}-IAMRoleArn",
        )


class LogRetentionApp(cdk.App):
    """CDK Application for Log Retention Management"""

    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION"),
        )
        
        # Create the main stack
        LogRetentionManagerStack(
            self,
            "LogRetentionManagerStack",
            env=env,
            description="Automated CloudWatch Logs retention management solution using Lambda and EventBridge",
            tags={
                "Application": "LogRetentionManagement",
                "Version": "1.0",
                "CostCenter": "Operations"
            }
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = LogRetentionApp()
    app.synth()