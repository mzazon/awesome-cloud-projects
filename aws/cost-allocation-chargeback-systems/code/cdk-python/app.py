#!/usr/bin/env python3
"""
CDK Python application for AWS Cost Allocation and Chargeback Systems

This application creates a comprehensive cost allocation and chargeback system
using AWS native billing and cost management tools.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_sns as sns,
    aws_events as events,
    aws_events_targets as targets,
    aws_budgets as budgets,
    aws_ce as ce,
    Duration,
    CfnOutput,
    RemovalPolicy,
)
from constructs import Construct
import os
from typing import Dict, List


class CostAllocationStack(Stack):
    """
    Stack for implementing cost allocation and chargeback systems.
    
    This stack creates:
    - S3 bucket for cost reports
    - SNS topic for notifications
    - Lambda function for cost processing
    - Budgets for departments
    - Cost categories for standardization
    - Anomaly detection for unusual spending
    - EventBridge schedule for automation
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for cost reports
        self.cost_bucket = self._create_cost_bucket()
        
        # Create SNS topic for notifications
        self.sns_topic = self._create_sns_topic()
        
        # Create cost processing Lambda function
        self.cost_processor = self._create_cost_processor_lambda()
        
        # Create cost categories for standardization
        self._create_cost_categories()
        
        # Create department budgets
        self._create_department_budgets()
        
        # Create EventBridge schedule for automation
        self._create_cost_processing_schedule()
        
        # Create outputs
        self._create_outputs()

    def _create_cost_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing cost reports and processed data."""
        bucket = s3.Bucket(
            self,
            "CostAllocationBucket",
            bucket_name=f"cost-allocation-reports-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldReports",
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
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )
        
        # Tag the bucket for cost allocation
        cdk.Tags.of(bucket).add("Department", "Finance")
        cdk.Tags.of(bucket).add("Purpose", "CostAllocation")
        cdk.Tags.of(bucket).add("Environment", "Production")
        
        return bucket

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for cost allocation notifications."""
        topic = sns.Topic(
            self,
            "CostAllocationTopic",
            topic_name="cost-allocation-alerts",
            display_name="Cost Allocation Alerts",
            description="Notifications for cost allocation, budget alerts, and anomaly detection"
        )
        
        # Create topic policy for AWS Budgets access
        topic.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("budgets.amazonaws.com")],
                actions=["sns:Publish"],
                resources=[topic.topic_arn]
            )
        )
        
        # Create topic policy for Cost Anomaly Detection
        topic.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("costalerts.amazonaws.com")],
                actions=["sns:Publish"],
                resources=[topic.topic_arn]
            )
        )
        
        # Tag the topic
        cdk.Tags.of(topic).add("Department", "Finance")
        cdk.Tags.of(topic).add("Purpose", "CostAllocation")
        
        return topic

    def _create_cost_processor_lambda(self) -> _lambda.Function:
        """Create Lambda function for processing cost allocation data."""
        
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self,
            "CostProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSBillingReadOnlyAccess")
            ],
            inline_policies={
                "CostAllocationPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.cost_bucket.bucket_arn,
                                f"{self.cost_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.sns_topic.topic_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ce:GetCostAndUsage",
                                "ce:GetDimensionValues",
                                "ce:GetReservationCoverage",
                                "ce:GetReservationPurchaseRecommendation",
                                "ce:GetReservationUtilization",
                                "ce:GetUsageReport"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Lambda function code
        lambda_code = '''
import json
import boto3
import csv
from datetime import datetime, timedelta
from decimal import Decimal
import os

def lambda_handler(event, context):
    """
    Process cost allocation data and generate chargeback reports.
    
    This function queries AWS Cost Explorer API for department-specific
    spending data, processes it into structured reports, and sends
    notifications via SNS.
    """
    ce_client = boto3.client('ce')
    sns_client = boto3.client('sns')
    s3_client = boto3.client('s3')
    
    # Configuration from environment variables
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    s3_bucket = os.environ['S3_BUCKET']
    
    # Get cost data for the last 30 days
    end_date = datetime.now().strftime('%Y-%m-%d')
    start_date = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
    
    try:
        # Query costs by department
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost', 'UnblendedCost'],
            GroupBy=[
                {
                    'Type': 'TAG',
                    'Key': 'Department'
                }
            ]
        )
        
        # Process cost data
        department_costs = {}
        for result in response['ResultsByTime']:
            for group in result['Groups']:
                dept = group['Keys'][0] if group['Keys'][0] != 'No Department' else 'Untagged'
                blended_cost = float(group['Metrics']['BlendedCost']['Amount'])
                unblended_cost = float(group['Metrics']['UnblendedCost']['Amount'])
                
                if dept not in department_costs:
                    department_costs[dept] = {
                        'blended_cost': 0,
                        'unblended_cost': 0
                    }
                
                department_costs[dept]['blended_cost'] += blended_cost
                department_costs[dept]['unblended_cost'] += unblended_cost
        
        # Create detailed chargeback report
        report = {
            'report_date': end_date,
            'period': f"{start_date} to {end_date}",
            'department_costs': department_costs,
            'total_blended_cost': sum(dept['blended_cost'] for dept in department_costs.values()),
            'total_unblended_cost': sum(dept['unblended_cost'] for dept in department_costs.values())
        }
        
        # Save detailed report to S3
        report_key = f"cost-reports/monthly-chargeback-{end_date}.json"
        s3_client.put_object(
            Bucket=s3_bucket,
            Key=report_key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json'
        )
        
        # Generate CSV for finance systems
        csv_data = []
        csv_data.append(['Department', 'Blended Cost', 'Unblended Cost', 'Period'])
        for dept, costs in department_costs.items():
            csv_data.append([
                dept,
                f"{costs['blended_cost']:.2f}",
                f"{costs['unblended_cost']:.2f}",
                f"{start_date} to {end_date}"
            ])
        
        # Save CSV report to S3
        csv_content = '\\n'.join([','.join(row) for row in csv_data])
        csv_key = f"cost-reports/monthly-chargeback-{end_date}.csv"
        s3_client.put_object(
            Bucket=s3_bucket,
            Key=csv_key,
            Body=csv_content,
            ContentType='text/csv'
        )
        
        # Send notification with summary
        message = f"""
Cost Allocation Report Generated - {end_date}

Report Period: {start_date} to {end_date}

Department Breakdown (Blended Costs):
"""
        for dept, costs in sorted(department_costs.items()):
            message += f"• {dept}: ${costs['blended_cost']:.2f}\\n"
        
        message += f"""
Total Blended Cost: ${report['total_blended_cost']:.2f}
Total Unblended Cost: ${report['total_unblended_cost']:.2f}

Reports saved to:
- JSON: s3://{s3_bucket}/{report_key}
- CSV: s3://{s3_bucket}/{csv_key}

Download reports for detailed analysis and chargeback processing.
"""
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject=f'Monthly Cost Allocation Report - {end_date}',
            Message=message
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost allocation processing completed successfully',
                'report': report,
                'report_location': f"s3://{s3_bucket}/{report_key}"
            }, default=str)
        }
        
    except Exception as e:
        error_message = f"Error processing cost allocation: {str(e)}"
        print(error_message)
        
        # Send error notification
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject='Cost Allocation Processing Error',
            Message=f"Error occurred during cost allocation processing:\\n\\n{error_message}"
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message
            })
        }
'''

        # Create Lambda function
        function = _lambda.Function(
            self,
            "CostProcessorFunction",
            function_name="cost-allocation-processor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "S3_BUCKET": self.cost_bucket.bucket_name
            },
            description="Process cost allocation data and generate chargeback reports"
        )
        
        # Tag the function
        cdk.Tags.of(function).add("Department", "Finance")
        cdk.Tags.of(function).add("Purpose", "CostAllocation")
        
        return function

    def _create_cost_categories(self) -> None:
        """Create AWS Cost Categories for standardized cost allocation."""
        
        # Cost category rules for department standardization
        department_rules = [
            {
                "value": "Engineering",
                "rule": {
                    "tags": {
                        "key": "Department",
                        "values": ["Engineering", "Development", "DevOps", "Platform"]
                    }
                }
            },
            {
                "value": "Marketing",
                "rule": {
                    "tags": {
                        "key": "Department", 
                        "values": ["Marketing", "Sales", "Customer Success", "Growth"]
                    }
                }
            },
            {
                "value": "Operations",
                "rule": {
                    "tags": {
                        "key": "Department",
                        "values": ["Operations", "Finance", "HR", "Legal", "Admin"]
                    }
                }
            },
            {
                "value": "Product",
                "rule": {
                    "tags": {
                        "key": "Department",
                        "values": ["Product", "Design", "Research", "Analytics"]
                    }
                }
            }
        ]
        
        # Create cost category definition
        cost_category = ce.CfnCostCategory(
            self,
            "DepartmentCostCategory",
            name="Department-CostCenter",
            rule_version="CostCategoryExpression.v1",
            rules=[
                ce.CfnCostCategory.CategoryRuleProperty(
                    value=rule["value"],
                    rule=ce.CfnCostCategory.ExpressionProperty(
                        tags=ce.CfnCostCategory.TagsProperty(
                            key=rule["rule"]["tags"]["key"],
                            values=rule["rule"]["tags"]["values"]
                        )
                    )
                ) for rule in department_rules
            ],
            default_value="Unallocated"
        )

    def _create_department_budgets(self) -> None:
        """Create AWS Budgets for department cost monitoring."""
        
        # Department budget configurations
        departments = [
            {"name": "Engineering", "amount": "2000", "threshold": 80},
            {"name": "Marketing", "amount": "800", "threshold": 75},
            {"name": "Operations", "amount": "500", "threshold": 85},
            {"name": "Product", "amount": "600", "threshold": 80}
        ]
        
        for dept in departments:
            # Create budget for department
            budget = budgets.CfnBudget(
                self,
                f"{dept['name']}Budget",
                budget=budgets.CfnBudget.BudgetDataProperty(
                    budget_name=f"{dept['name']}-Monthly-Budget",
                    budget_limit=budgets.CfnBudget.SpendProperty(
                        amount=dept["amount"],
                        unit="USD"
                    ),
                    time_unit="MONTHLY",
                    budget_type="COST",
                    cost_filters=budgets.CfnBudget.CostFiltersProperty(
                        tag_key=["Department"],
                        tag_value=[dept["name"]]
                    )
                ),
                notifications_with_subscribers=[
                    budgets.CfnBudget.NotificationWithSubscribersProperty(
                        notification=budgets.CfnBudget.NotificationProperty(
                            notification_type="ACTUAL",
                            comparison_operator="GREATER_THAN",
                            threshold=dept["threshold"],
                            threshold_type="PERCENTAGE"
                        ),
                        subscribers=[
                            budgets.CfnBudget.SubscriberProperty(
                                subscription_type="SNS",
                                address=self.sns_topic.topic_arn
                            )
                        ]
                    ),
                    budgets.CfnBudget.NotificationWithSubscribersProperty(
                        notification=budgets.CfnBudget.NotificationProperty(
                            notification_type="FORECASTED",
                            comparison_operator="GREATER_THAN", 
                            threshold=95,
                            threshold_type="PERCENTAGE"
                        ),
                        subscribers=[
                            budgets.CfnBudget.SubscriberProperty(
                                subscription_type="SNS",
                                address=self.sns_topic.topic_arn
                            )
                        ]
                    )
                ]
            )

    def _create_cost_processing_schedule(self) -> None:
        """Create EventBridge rule for automated cost processing."""
        
        # Create EventBridge rule for monthly processing
        rule = events.Rule(
            self,
            "CostProcessingSchedule",
            rule_name="cost-allocation-monthly-processing",
            description="Monthly cost allocation processing on the 1st of each month",
            schedule=events.Schedule.cron(
                minute="0",
                hour="9", 
                day="1",
                month="*",
                year="*"
            )
        )
        
        # Add Lambda target to rule
        rule.add_target(
            targets.LambdaFunction(self.cost_processor)
        )
        
        # Tag the rule
        cdk.Tags.of(rule).add("Department", "Finance")
        cdk.Tags.of(rule).add("Purpose", "CostAllocation")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "CostBucketName",
            value=self.cost_bucket.bucket_name,
            description="S3 bucket for cost allocation reports",
            export_name=f"{self.stack_name}-CostBucket"
        )
        
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic for cost allocation notifications",
            export_name=f"{self.stack_name}-SNSTopic"
        )
        
        CfnOutput(
            self,
            "CostProcessorFunctionName",
            value=self.cost_processor.function_name,
            description="Lambda function for cost processing",
            export_name=f"{self.stack_name}-CostProcessor"
        )
        
        CfnOutput(
            self,
            "CostProcessorFunctionArn",
            value=self.cost_processor.function_arn,
            description="Lambda function ARN for cost processing",
            export_name=f"{self.stack_name}-CostProcessorArn"
        )


# CDK Application
app = cdk.App()

# Get environment from context or default to us-east-1
env = cdk.Environment(
    account=os.getenv('CDK_DEFAULT_ACCOUNT'),
    region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
)

# Create the cost allocation stack
CostAllocationStack(
    app,
    "CostAllocationStack",
    env=env,
    description="AWS Cost Allocation and Chargeback System - CDK Python Implementation",
    tags={
        "Project": "CostAllocation",
        "Environment": "Production",
        "Owner": "Finance",
        "ManagedBy": "CDK"
    }
)

app.synth()