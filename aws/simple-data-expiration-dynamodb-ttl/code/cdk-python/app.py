#!/usr/bin/env python3
"""
AWS CDK Python application for DynamoDB TTL Data Expiration Automation

This CDK application creates a DynamoDB table with Time-To-Live (TTL) enabled
for automatic data expiration, along with CloudWatch monitoring and sample
data population for testing.

Architecture:
- DynamoDB table with composite primary key (user_id, session_id)
- TTL attribute configured for automatic item expiration
- CloudWatch dashboard for monitoring TTL operations
- Lambda function for inserting sample data with various TTL values
- IAM roles and policies for secure resource access

Author: AWS CDK Generator
Version: 1.0
"""

import os
from datetime import datetime, timedelta
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from aws_cdk import aws_dynamodb as dynamodb
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_iam as iam
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_logs as logs
from constructs import Construct


class DynamoDbTtlStack(Stack):
    """
    CDK Stack for DynamoDB TTL Data Expiration Automation
    
    This stack creates all necessary resources for demonstrating
    DynamoDB's Time-To-Live feature for automatic data lifecycle management.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-6:].lower()

        # Create DynamoDB table with TTL enabled
        self.table = self._create_dynamodb_table(unique_suffix)
        
        # Create Lambda function for sample data population
        self.sample_data_function = self._create_sample_data_function(unique_suffix)
        
        # Create CloudWatch dashboard for monitoring
        self._create_monitoring_dashboard(unique_suffix)
        
        # Create stack outputs
        self._create_outputs()

    def _create_dynamodb_table(self, suffix: str) -> dynamodb.Table:
        """
        Create DynamoDB table with TTL configuration
        
        Args:
            suffix (str): Unique suffix for resource naming
            
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self,
            "SessionDataTable",
            table_name=f"session-data-{suffix}",
            partition_key=dynamodb.Attribute(
                name="user_id",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="session_id", 
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.ON_DEMAND,
            time_to_live_attribute="expires_at",
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=False,  # Not needed for demo purposes
        )

        # Add tags for cost tracking and resource management
        cdk.Tags.of(table).add("Project", "DynamoDB-TTL-Demo")
        cdk.Tags.of(table).add("Environment", "Development")
        cdk.Tags.of(table).add("CostCenter", "Engineering")

        return table

    def _create_sample_data_function(self, suffix: str) -> lambda_.Function:
        """
        Create Lambda function to populate table with sample data
        
        Args:
            suffix (str): Unique suffix for resource naming
            
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "SampleDataFunctionRole",
            role_name=f"dynamodb-ttl-sample-data-role-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant DynamoDB permissions to Lambda role
        self.table.grant_write_data(lambda_role)

        # Create Lambda function
        function = lambda_.Function(
            self,
            "SampleDataFunction",
            function_name=f"dynamodb-ttl-sample-data-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            environment={
                "TABLE_NAME": self.table.table_name,
                "TTL_ATTRIBUTE": "expires_at"
            },
            timeout=Duration.seconds(30),
            memory_size=128,
            description="Function to populate DynamoDB table with sample TTL data",
        )

        # Create log group with retention policy
        logs.LogGroup(
            self,
            "SampleDataFunctionLogGroup",
            log_group_name=f"/aws/lambda/{function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return function

    def _get_lambda_code(self) -> str:
        """
        Generate Lambda function code for sample data population
        
        Returns:
            str: Lambda function code as a string
        """
        return '''
import json
import boto3
import os
import time
from datetime import datetime, timedelta
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Lambda function to populate DynamoDB table with sample TTL data
    """
    table_name = os.environ['TABLE_NAME']
    ttl_attribute = os.environ['TTL_ATTRIBUTE']
    
    table = dynamodb.Table(table_name)
    current_time = int(time.time())
    
    # Sample data with various TTL values
    sample_items = [
        {
            'user_id': 'user123',
            'session_id': 'session_active',
            'login_time': datetime.utcnow().isoformat() + 'Z',
            'last_activity': datetime.utcnow().isoformat() + 'Z',
            'session_type': 'active',
            ttl_attribute: current_time + 1800  # 30 minutes from now
        },
        {
            'user_id': 'user456', 
            'session_id': 'session_temp',
            'login_time': datetime.utcnow().isoformat() + 'Z',
            'session_type': 'temporary',
            ttl_attribute: current_time + 300   # 5 minutes from now
        },
        {
            'user_id': 'user789',
            'session_id': 'session_expired',
            'login_time': (datetime.utcnow() - timedelta(hours=2)).isoformat() + 'Z',
            'session_type': 'expired',
            ttl_attribute: current_time - 3600  # 1 hour ago (expired)
        },
        {
            'user_id': 'user101',
            'session_id': 'session_long',
            'login_time': datetime.utcnow().isoformat() + 'Z',
            'session_type': 'extended',
            'user_preferences': {'theme': 'dark', 'language': 'en'},
            ttl_attribute: current_time + 3600  # 1 hour from now
        }
    ]
    
    # Insert items into DynamoDB
    inserted_count = 0
    for item in sample_items:
        try:
            table.put_item(Item=item)
            inserted_count += 1
        except Exception as e:
            print(f"Error inserting item {item['user_id']}/{item['session_id']}: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Successfully inserted {inserted_count} sample items',
            'table_name': table_name,
            'current_timestamp': current_time
        })
    }
'''

    def _create_monitoring_dashboard(self, suffix: str) -> None:
        """
        Create CloudWatch dashboard for monitoring TTL operations
        
        Args:
            suffix (str): Unique suffix for resource naming
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "DynamoDbTtlDashboard",
            dashboard_name=f"DynamoDB-TTL-Monitoring-{suffix}",
        )

        # TTL Deletion Metrics Widget
        ttl_deletions_widget = cloudwatch.GraphWidget(
            title="TTL Deleted Items",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="TimeToLiveDeletedItemCount",
                    dimensions_map={"TableName": self.table.table_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6,
        )

        # Table Metrics Widget
        table_metrics_widget = cloudwatch.GraphWidget(
            title="Table Operations",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="ConsumedReadCapacityUnits",
                    dimensions_map={"TableName": self.table.table_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB", 
                    metric_name="ConsumedWriteCapacityUnits",
                    dimensions_map={"TableName": self.table.table_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6,
        )

        # Add widgets to dashboard
        dashboard.add_widgets(ttl_deletions_widget)
        dashboard.add_widgets(table_metrics_widget)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for the stack"""
        CfnOutput(
            self,
            "TableName",
            value=self.table.table_name,
            description="DynamoDB table name with TTL enabled",
            export_name=f"{self.stack_name}-TableName"
        )

        CfnOutput(
            self,
            "TableArn", 
            value=self.table.table_arn,
            description="DynamoDB table ARN",
            export_name=f"{self.stack_name}-TableArn"
        )

        CfnOutput(
            self,
            "SampleDataFunctionName",
            value=self.sample_data_function.function_name,
            description="Lambda function for populating sample data",
            export_name=f"{self.stack_name}-SampleDataFunction"
        )
        
        CfnOutput(
            self,
            "TtlAttribute",
            value="expires_at",
            description="TTL attribute name configured on the table",
            export_name=f"{self.stack_name}-TtlAttribute"
        )


def main() -> None:
    """Main application entry point"""
    app = App()

    # Get environment configuration
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

    # Create the stack
    DynamoDbTtlStack(
        app,
        "DynamoDbTtlStack",
        env=cdk.Environment(account=account, region=region),
        description="DynamoDB TTL Data Expiration Automation Stack",
    )

    # Add application-level tags
    cdk.Tags.of(app).add("Application", "DynamoDB-TTL-Demo")
    cdk.Tags.of(app).add("Owner", "Development-Team")

    app.synth()


if __name__ == "__main__":
    main()