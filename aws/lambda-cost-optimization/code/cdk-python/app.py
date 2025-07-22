#!/usr/bin/env python3
"""
AWS CDK application for Lambda Cost Compute Optimizer

This CDK application deploys infrastructure to support AWS Lambda cost optimization
using AWS Compute Optimizer. It includes CloudWatch dashboards, SNS notifications,
and IAM roles needed for the optimization workflow.

Author: AWS Recipes
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_cloudwatch as cloudwatch,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, Any


class LambdaCostOptimizerStack(Stack):
    """
    CDK Stack for Lambda Cost Optimization using AWS Compute Optimizer
    
    This stack creates:
    - IAM roles and policies for Compute Optimizer access
    - Lambda function for automated optimization
    - SNS topic for notifications
    - CloudWatch dashboard for monitoring
    - EventBridge rule for scheduled optimization
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create SNS topic for optimization notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create IAM role for Lambda optimization function
        self.optimization_role = self._create_optimization_role()
        
        # Create Lambda function for automated optimization
        self.optimization_function = self._create_optimization_function()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Create EventBridge rule for scheduled optimization
        self.schedule_rule = self._create_schedule_rule()
        
        # Create IAM role for Compute Optimizer enrollment
        self.compute_optimizer_role = self._create_compute_optimizer_role()

    def _create_notification_topic(self) -> sns.Topic:
        """Create SNS topic for optimization notifications"""
        topic = sns.Topic(
            self, "LambdaOptimizationNotifications",
            display_name="Lambda Cost Optimization Notifications",
            topic_name="lambda-cost-optimization-alerts"
        )
        
        # Add CloudFormation output for topic ARN
        cdk.CfnOutput(
            self, "NotificationTopicArn",
            value=topic.topic_arn,
            description="SNS Topic ARN for Lambda optimization notifications",
            export_name="LambdaOptimization-NotificationTopicArn"
        )
        
        return topic

    def _create_compute_optimizer_role(self) -> iam.Role:
        """Create IAM role for Compute Optimizer enrollment and access"""
        role = iam.Role(
            self, "ComputeOptimizerRole",
            assumed_by=iam.ServicePrincipal("compute-optimizer.amazonaws.com"),
            description="Role for AWS Compute Optimizer to analyze Lambda functions",
            role_name="LambdaOptimization-ComputeOptimizerRole"
        )
        
        # Add managed policy for Compute Optimizer
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("ComputeOptimizerReadOnlyAccess")
        )
        
        # Add CloudWatch read permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:GetMetricData",
                "cloudwatch:ListMetrics"
            ],
            resources=["*"]
        ))
        
        return role

    def _create_optimization_role(self) -> iam.Role:
        """Create IAM role for Lambda optimization function"""
        role = iam.Role(
            self, "LambdaOptimizationRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Lambda function to perform cost optimization",
            role_name="LambdaOptimization-ExecutionRole"
        )
        
        # Add basic Lambda execution policy
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
        )
        
        # Add Compute Optimizer permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "compute-optimizer:GetLambdaFunctionRecommendations",
                "compute-optimizer:GetEnrollmentStatus",
                "compute-optimizer:PutEnrollmentStatus"
            ],
            resources=["*"]
        ))
        
        # Add Lambda function management permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "lambda:ListFunctions",
                "lambda:GetFunctionConfiguration",
                "lambda:UpdateFunctionConfiguration",
                "lambda:GetFunction",
                "lambda:TagResource",
                "lambda:UntagResource"
            ],
            resources=["*"]
        ))
        
        # Add CloudWatch permissions for metrics and alarms
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:GetMetricData",
                "cloudwatch:PutMetricAlarm",
                "cloudwatch:DeleteAlarms",
                "cloudwatch:DescribeAlarms"
            ],
            resources=["*"]
        ))
        
        # Add SNS permissions for notifications
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "sns:Publish"
            ],
            resources=[self.notification_topic.topic_arn]
        ))
        
        # Add Cost Explorer permissions for cost analysis
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ce:GetCostAndUsage",
                "ce:GetUsageReport"
            ],
            resources=["*"]
        ))
        
        return role

    def _create_optimization_function(self) -> _lambda.Function:
        """Create Lambda function for automated cost optimization"""
        function = _lambda.Function(
            self, "LambdaOptimizationFunction",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=self.optimization_role,
            function_name="lambda-cost-optimizer",
            description="Automated Lambda cost optimization using Compute Optimizer",
            timeout=Duration.minutes(15),
            memory_size=512,
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "SAVINGS_THRESHOLD": "1.00",  # Minimum monthly savings to apply optimization
                "DRY_RUN": "false",  # Set to true to only analyze without applying changes
                "LOG_LEVEL": "INFO"
            },
            code=_lambda.Code.from_inline(self._get_lambda_code())
        )
        
        # Create log group with retention policy
        logs.LogGroup(
            self, "OptimizationFunctionLogGroup",
            log_group_name=f"/aws/lambda/{function.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Add CloudFormation output for function ARN
        cdk.CfnOutput(
            self, "OptimizationFunctionArn",
            value=function.function_arn,
            description="Lambda function ARN for cost optimization",
            export_name="LambdaOptimization-FunctionArn"
        )
        
        return function

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring Lambda optimization"""
        dashboard = cloudwatch.Dashboard(
            self, "LambdaOptimizationDashboard",
            dashboard_name="Lambda-Cost-Optimization",
            period_override=cloudwatch.PeriodOverride.AUTO
        )
        
        # Add Lambda invocation metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Invocations",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Invocations",
                        statistic="Sum",
                        period=Duration.hours(1)
                    )
                ],
                width=12,
                height=6
            )
        )
        
        # Add Lambda duration metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Duration",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Duration",
                        statistic="Average",
                        period=Duration.hours(1)
                    )
                ],
                width=12,
                height=6
            )
        )
        
        # Add Lambda error metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Errors",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Errors",
                        statistic="Sum",
                        period=Duration.hours(1)
                    )
                ],
                width=12,
                height=6
            )
        )
        
        # Add optimization function specific metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Optimization Function Performance",
                left=[
                    self.optimization_function.metric_invocations(
                        statistic="Sum",
                        period=Duration.hours(1)
                    ),
                    self.optimization_function.metric_errors(
                        statistic="Sum",
                        period=Duration.hours(1)
                    ),
                    self.optimization_function.metric_duration(
                        statistic="Average",
                        period=Duration.hours(1)
                    )
                ],
                width=12,
                height=6
            )
        )
        
        return dashboard

    def _create_schedule_rule(self) -> events.Rule:
        """Create EventBridge rule for scheduled optimization"""
        rule = events.Rule(
            self, "OptimizationScheduleRule",
            description="Scheduled rule for Lambda cost optimization",
            rule_name="lambda-cost-optimization-schedule",
            schedule=events.Schedule.cron(
                minute="0",
                hour="9",  # 9 AM UTC
                day="*",
                month="*",
                week_day="MON"  # Every Monday
            )
        )
        
        # Add Lambda function as target
        rule.add_target(
            targets.LambdaFunction(
                self.optimization_function,
                event=events.RuleTargetInput.from_object({
                    "source": "scheduled-optimization",
                    "detail": {
                        "automated": True
                    }
                })
            )
        )
        
        return rule

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for cost optimization"""
        return '''
import json
import boto3
import os
import logging
from typing import Dict, List, Any
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Lambda handler for automated cost optimization using Compute Optimizer
    """
    logger.info(f"Starting Lambda cost optimization process")
    logger.info(f"Event: {json.dumps(event)}")
    
    # Initialize AWS clients
    compute_optimizer = boto3.client('compute-optimizer')
    lambda_client = boto3.client('lambda')
    sns_client = boto3.client('sns')
    cloudwatch = boto3.client('cloudwatch')
    
    # Get configuration from environment variables
    sns_topic_arn = os.getenv('SNS_TOPIC_ARN')
    savings_threshold = float(os.getenv('SAVINGS_THRESHOLD', '1.00'))
    dry_run = os.getenv('DRY_RUN', 'false').lower() == 'true'
    
    try:
        # Check Compute Optimizer enrollment status
        enrollment_status = compute_optimizer.get_enrollment_status()
        if enrollment_status['status'] != 'Active':
            logger.warning("Compute Optimizer is not active. Enabling it now...")
            compute_optimizer.put_enrollment_status(status='Active')
            
        # Get Lambda function recommendations
        recommendations = compute_optimizer.get_lambda_function_recommendations()
        
        optimization_results = process_recommendations(
            recommendations, 
            lambda_client, 
            savings_threshold, 
            dry_run
        )
        
        # Send notification with results
        if sns_topic_arn:
            send_notification(sns_client, sns_topic_arn, optimization_results, dry_run)
        
        # Create CloudWatch custom metrics
        put_custom_metrics(cloudwatch, optimization_results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Optimization process completed successfully',
                'results': optimization_results,
                'dry_run': dry_run
            })
        }
        
    except Exception as e:
        logger.error(f"Error during optimization process: {str(e)}")
        
        # Send error notification
        if sns_topic_arn:
            send_error_notification(sns_client, sns_topic_arn, str(e))
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Optimization process failed'
            })
        }

def process_recommendations(recommendations: Dict, lambda_client, savings_threshold: float, dry_run: bool) -> Dict:
    """Process Compute Optimizer recommendations and apply optimizations"""
    results = {
        'total_functions_analyzed': 0,
        'optimizable_functions': 0,
        'optimizations_applied': 0,
        'total_potential_savings': 0.0,
        'applied_savings': 0.0,
        'functions_processed': []
    }
    
    lambda_recommendations = recommendations.get('lambdaFunctionRecommendations', [])
    results['total_functions_analyzed'] = len(lambda_recommendations)
    
    for recommendation in lambda_recommendations:
        function_name = recommendation['functionName']
        finding = recommendation['finding']
        current_memory = recommendation['currentMemorySize']
        
        function_result = {
            'function_name': function_name,
            'current_memory': current_memory,
            'finding': finding,
            'action_taken': 'none',
            'savings': 0.0
        }
        
        if finding != 'Optimized' and 'memorySizeRecommendationOptions' in recommendation:
            results['optimizable_functions'] += 1
            
            best_option = recommendation['memorySizeRecommendationOptions'][0]
            recommended_memory = best_option['memorySize']
            estimated_savings = best_option.get('estimatedMonthlySavings', {}).get('value', 0)
            
            results['total_potential_savings'] += estimated_savings
            function_result['recommended_memory'] = recommended_memory
            function_result['estimated_savings'] = estimated_savings
            
            if estimated_savings >= savings_threshold:
                if not dry_run:
                    try:
                        # Apply the optimization
                        lambda_client.update_function_configuration(
                            FunctionName=function_name,
                            MemorySize=recommended_memory
                        )
                        
                        function_result['action_taken'] = 'optimized'
                        results['optimizations_applied'] += 1
                        results['applied_savings'] += estimated_savings
                        
                        logger.info(f"Optimized {function_name}: {current_memory}MB -> {recommended_memory}MB")
                        
                    except Exception as e:
                        function_result['action_taken'] = f'failed: {str(e)}'
                        logger.error(f"Failed to optimize {function_name}: {str(e)}")
                else:
                    function_result['action_taken'] = 'dry_run_only'
            else:
                function_result['action_taken'] = f'savings_below_threshold ({estimated_savings:.2f} < {savings_threshold})'
        
        results['functions_processed'].append(function_result)
    
    return results

def send_notification(sns_client, topic_arn: str, results: Dict, dry_run: bool) -> None:
    """Send optimization results notification via SNS"""
    subject = f"Lambda Cost Optimization Report - {'DRY RUN' if dry_run else 'APPLIED'}"
    
    message = f"""
Lambda Cost Optimization Report
Generated: {datetime.utcnow().isoformat()}Z
Mode: {'DRY RUN (no changes applied)' if dry_run else 'LIVE (changes applied)'}

SUMMARY:
- Functions Analyzed: {results['total_functions_analyzed']}
- Functions with Optimization Opportunities: {results['optimizable_functions']}
- Optimizations Applied: {results['optimizations_applied']}
- Total Potential Monthly Savings: ${results['total_potential_savings']:.2f}
- Applied Monthly Savings: ${results['applied_savings']:.2f}

DETAILED RESULTS:
"""
    
    for func in results['functions_processed']:
        if func['action_taken'] != 'none':
            message += f"""
Function: {func['function_name']}
  Current Memory: {func['current_memory']} MB
  Recommended Memory: {func.get('recommended_memory', 'N/A')} MB
  Estimated Savings: ${func.get('estimated_savings', 0):.2f}/month
  Action: {func['action_taken']}
"""
    
    sns_client.publish(
        TopicArn=topic_arn,
        Subject=subject,
        Message=message
    )

def send_error_notification(sns_client, topic_arn: str, error_message: str) -> None:
    """Send error notification via SNS"""
    subject = "Lambda Cost Optimization - ERROR"
    message = f"""
Lambda Cost Optimization Process Failed

Error occurred at: {datetime.utcnow().isoformat()}Z
Error details: {error_message}

Please check CloudWatch logs for more information.
"""
    
    sns_client.publish(
        TopicArn=topic_arn,
        Subject=subject,
        Message=message
    )

def put_custom_metrics(cloudwatch, results: Dict) -> None:
    """Put custom CloudWatch metrics for optimization tracking"""
    namespace = 'Lambda/CostOptimization'
    
    metrics = [
        {
            'MetricName': 'FunctionsAnalyzed',
            'Value': results['total_functions_analyzed'],
            'Unit': 'Count'
        },
        {
            'MetricName': 'OptimizableFunctions',
            'Value': results['optimizable_functions'],
            'Unit': 'Count'
        },
        {
            'MetricName': 'OptimizationsApplied',
            'Value': results['optimizations_applied'],
            'Unit': 'Count'
        },
        {
            'MetricName': 'PotentialMonthlySavings',
            'Value': results['total_potential_savings'],
            'Unit': 'None'
        },
        {
            'MetricName': 'AppliedMonthlySavings',
            'Value': results['applied_savings'],
            'Unit': 'None'
        }
    ]
    
    for metric in metrics:
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=[{
                'MetricName': metric['MetricName'],
                'Value': metric['Value'],
                'Unit': metric['Unit'],
                'Timestamp': datetime.utcnow()
            }]
        )
'''


app = App()

# Create the Lambda Cost Optimizer stack
LambdaCostOptimizerStack(
    app, "LambdaCostOptimizerStack",
    description="Infrastructure for AWS Lambda cost optimization using Compute Optimizer",
    env=Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

app.synth()