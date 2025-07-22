#!/usr/bin/env python3
"""
AWS CDK Python application for DynamoDB Global Tables Multi-Region setup.

This application creates a comprehensive multi-region DynamoDB Global Tables
architecture with monitoring, Lambda functions, and CloudWatch dashboards.
"""

import os
from typing import List, Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    RemovalPolicy,
    Duration,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class DynamoDBGlobalTablesStack(Stack):
    """
    Stack for DynamoDB Global Tables with multi-region replication.
    
    This stack creates:
    - DynamoDB table with global table configuration
    - Lambda functions for testing global table operations
    - CloudWatch monitoring and alarms
    - IAM roles and policies
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        table_name: str,
        replica_regions: List[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the DynamoDB Global Tables stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            table_name: Name of the DynamoDB table
            replica_regions: List of regions for replicas
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Set default replica regions if not provided
        if replica_regions is None:
            replica_regions = ["eu-west-1", "ap-northeast-1"]

        # Store configuration
        self.table_name = table_name
        self.replica_regions = replica_regions
        self.current_region = self.region

        # Create DynamoDB table with global table configuration
        self.dynamodb_table = self._create_dynamodb_table()

        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()

        # Create Lambda function for testing global table operations
        self.lambda_function = self._create_lambda_function()

        # Create CloudWatch monitoring
        self._create_cloudwatch_monitoring()

        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()

        # Output important information
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table with global table configuration.
        
        Returns:
            DynamoDB table construct
        """
        # Create replica configurations
        replicas = []
        for region in self.replica_regions:
            replica_config = dynamodb.ReplicaTableProps(
                region=region,
                global_secondary_indexes=[
                    dynamodb.ReplicaGlobalSecondaryIndexProps(
                        index_name="EmailIndex",
                        projection_type=dynamodb.ProjectionType.ALL,
                    )
                ],
                point_in_time_recovery=True,
                deletion_protection=False,  # Set to True for production
                table_class=dynamodb.TableClass.STANDARD,
            )
            replicas.append(replica_config)

        # Create the main table
        table = dynamodb.Table(
            self,
            "GlobalUserProfilesTable",
            table_name=self.table_name,
            partition_key=dynamodb.Attribute(
                name="UserId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="ProfileType",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            point_in_time_recovery=True,
            deletion_protection=False,  # Set to True for production
            table_class=dynamodb.TableClass.STANDARD,
            replicas=replicas,
        )

        # Add Global Secondary Index
        table.add_global_secondary_index(
            index_name="EmailIndex",
            partition_key=dynamodb.Attribute(
                name="Email",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )

        # Add tags for cost allocation and management
        cdk.Tags.of(table).add("Project", "GlobalTablesDemo")
        cdk.Tags.of(table).add("Environment", "Development")
        cdk.Tags.of(table).add("Owner", "CloudEngineering")

        return table

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with necessary permissions.
        
        Returns:
            IAM role for Lambda functions
        """
        role = iam.Role(
            self,
            "GlobalTableLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Global Table Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )

        # Add DynamoDB permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:BatchGetItem",
                    "dynamodb:BatchWriteItem",
                    "dynamodb:DescribeTable",
                    "dynamodb:DescribeTimeToLive",
                    "dynamodb:ListTables",
                    "dynamodb:ListTagsOfResource",
                ],
                resources=[
                    self.dynamodb_table.table_arn,
                    f"{self.dynamodb_table.table_arn}/*",
                ],
            )
        )

        return role

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for testing global table operations.
        
        Returns:
            Lambda function construct
        """
        # Lambda function code
        lambda_code = '''
import json
import boto3
import os
import time
from datetime import datetime, timezone
from typing import Dict, Any, Optional

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Global Table operations.
    
    Supports operations: put, get, scan, query
    """
    try:
        # Get region from environment or context
        region = os.environ.get('AWS_REGION', context.invoked_function_arn.split(':')[3])
        
        # Initialize DynamoDB client
        dynamodb = boto3.resource('dynamodb', region_name=region)
        table = dynamodb.Table(os.environ['TABLE_NAME'])
        
        # Process the operation
        operation = event.get('operation', 'put')
        
        if operation == 'put':
            return handle_put_operation(table, event, region)
        elif operation == 'get':
            return handle_get_operation(table, event, region)
        elif operation == 'scan':
            return handle_scan_operation(table, event, region)
        elif operation == 'query':
            return handle_query_operation(table, event, region)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unsupported operation: {operation}'
                })
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'region': region
            })
        }

def handle_put_operation(table: Any, event: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Handle PUT operation for creating/updating items."""
    user_id = event.get('userId', f'user-{int(time.time())}')
    profile_type = event.get('profileType', 'standard')
    
    item = {
        'UserId': user_id,
        'ProfileType': profile_type,
        'Name': event.get('name', 'Test User'),
        'Email': event.get('email', 'test@example.com'),
        'Region': region,
        'CreatedAt': datetime.now(timezone.utc).isoformat(),
        'LastModified': datetime.now(timezone.utc).isoformat(),
        'Preferences': event.get('preferences', {}),
        'Status': event.get('status', 'active')
    }
    
    response = table.put_item(Item=item)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Item created/updated in {region}',
            'userId': user_id,
            'profileType': profile_type,
            'timestamp': item['LastModified']
        })
    }

def handle_get_operation(table: Any, event: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Handle GET operation for retrieving items."""
    user_id = event.get('userId')
    profile_type = event.get('profileType', 'standard')
    
    if not user_id:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'userId is required for get operation'
            })
        }
    
    response = table.get_item(
        Key={
            'UserId': user_id,
            'ProfileType': profile_type
        }
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Item retrieved from {region}',
            'item': response.get('Item'),
            'found': 'Item' in response
        })
    }

def handle_scan_operation(table: Any, event: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Handle SCAN operation for retrieving multiple items."""
    limit = event.get('limit', 10)
    
    response = table.scan(
        ProjectionExpression='UserId, ProfileType, #r, #n, Email, #s',
        ExpressionAttributeNames={
            '#r': 'Region',
            '#n': 'Name',
            '#s': 'Status'
        },
        Limit=limit
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Items scanned from {region}',
            'count': response['Count'],
            'items': response.get('Items', [])
        })
    }

def handle_query_operation(table: Any, event: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Handle QUERY operation using GSI."""
    email = event.get('email')
    
    if not email:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'email is required for query operation'
            })
        }
    
    response = table.query(
        IndexName='EmailIndex',
        KeyConditionExpression='Email = :email',
        ExpressionAttributeValues={
            ':email': email
        }
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Query executed from {region}',
            'count': response['Count'],
            'items': response.get('Items', [])
        })
    }
'''

        function = lambda_.Function(
            self,
            "GlobalTableProcessor",
            function_name=f"GlobalTableProcessor-{self.table_name}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "TABLE_NAME": self.dynamodb_table.table_name,
                "REGION": self.current_region,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Lambda function for Global Table operations testing",
        )

        # Add tags
        cdk.Tags.of(function).add("Project", "GlobalTablesDemo")
        cdk.Tags.of(function).add("Environment", "Development")

        return function

    def _create_cloudwatch_monitoring(self) -> None:
        """Create CloudWatch alarms for monitoring global table performance."""
        
        # Create alarm for replication latency
        for region in self.replica_regions:
            replication_latency_alarm = cloudwatch.Alarm(
                self,
                f"ReplicationLatencyAlarm-{region}",
                alarm_name=f"GlobalTable-ReplicationLatency-{self.table_name}-{region}",
                alarm_description=f"Monitor replication latency for {self.table_name} to {region}",
                metric=cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="ReplicationLatency",
                    dimensions_map={
                        "TableName": self.table_name,
                        "ReceivingRegion": region
                    },
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                threshold=10000,  # 10 seconds in milliseconds
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                evaluation_periods=2,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            )

        # Create alarm for user errors
        user_errors_alarm = cloudwatch.Alarm(
            self,
            "UserErrorsAlarm",
            alarm_name=f"GlobalTable-UserErrors-{self.table_name}",
            alarm_description=f"Monitor user errors for {self.table_name}",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="UserErrors",
                dimensions_map={
                    "TableName": self.table_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Create alarm for throttled requests
        throttled_requests_alarm = cloudwatch.Alarm(
            self,
            "ThrottledRequestsAlarm",
            alarm_name=f"GlobalTable-ThrottledRequests-{self.table_name}",
            alarm_description=f"Monitor throttled requests for {self.table_name}",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="ThrottledRequests",
                dimensions_map={
                    "TableName": self.table_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring global table metrics."""
        
        dashboard = cloudwatch.Dashboard(
            self,
            "GlobalTableDashboard",
            dashboard_name=f"GlobalTable-{self.table_name}",
            start="-PT1H",  # Show last 1 hour
        )

        # Add capacity metrics widget
        capacity_widget = cloudwatch.GraphWidget(
            title="Read/Write Capacity",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="ConsumedReadCapacityUnits",
                    dimensions_map={"TableName": self.table_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="ConsumedWriteCapacityUnits",
                    dimensions_map={"TableName": self.table_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ]
        )

        # Add replication latency widget
        replication_metrics = []
        for region in self.replica_regions:
            replication_metrics.append(
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="ReplicationLatency",
                    dimensions_map={
                        "TableName": self.table_name,
                        "ReceivingRegion": region
                    },
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            )

        replication_widget = cloudwatch.GraphWidget(
            title="Replication Latency",
            width=12,
            height=6,
            left=replication_metrics
        )

        # Add error metrics widget
        error_widget = cloudwatch.GraphWidget(
            title="Errors and Throttles",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="UserErrors",
                    dimensions_map={"TableName": self.table_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="SystemErrors",
                    dimensions_map={"TableName": self.table_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/DynamoDB",
                    metric_name="ThrottledRequests",
                    dimensions_map={"TableName": self.table_name},
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ]
        )

        # Add widgets to dashboard
        dashboard.add_widgets(capacity_widget, replication_widget, error_widget)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        # Table name
        cdk.CfnOutput(
            self,
            "TableName",
            value=self.dynamodb_table.table_name,
            description="Name of the DynamoDB Global Table"
        )

        # Table ARN
        cdk.CfnOutput(
            self,
            "TableArn",
            value=self.dynamodb_table.table_arn,
            description="ARN of the DynamoDB Global Table"
        )

        # Lambda function name
        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function for testing"
        )

        # Replica regions
        cdk.CfnOutput(
            self,
            "ReplicaRegions",
            value=", ".join(self.replica_regions),
            description="Regions where table replicas are created"
        )

        # Dashboard URL
        cdk.CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=GlobalTable-{self.table_name}",
            description="URL to the CloudWatch dashboard"
        )


class GlobalTablesApp:
    """
    Main application class for deploying Global Tables across multiple regions.
    """
    
    def __init__(self):
        """Initialize the Global Tables application."""
        self.app = cdk.App()
        
        # Get configuration from context or environment
        self.table_name = self.app.node.try_get_context("tableName") or "GlobalUserProfiles"
        self.primary_region = self.app.node.try_get_context("primaryRegion") or "us-east-1"
        self.replica_regions = self.app.node.try_get_context("replicaRegions") or ["eu-west-1", "ap-northeast-1"]
        
        # Get account ID
        self.account = os.environ.get("CDK_DEFAULT_ACCOUNT", "123456789012")
        
        # Create the primary stack
        self.primary_stack = self._create_primary_stack()
        
        # Create replica stacks (Lambda functions only)
        self.replica_stacks = self._create_replica_stacks()

    def _create_primary_stack(self) -> DynamoDBGlobalTablesStack:
        """Create the primary stack with the global table."""
        return DynamoDBGlobalTablesStack(
            self.app,
            "DynamoDBGlobalTablesStack",
            stack_name=f"DynamoDBGlobalTables-{self.table_name}",
            env=Environment(
                account=self.account,
                region=self.primary_region
            ),
            table_name=self.table_name,
            replica_regions=self.replica_regions,
            description="Primary stack for DynamoDB Global Tables with monitoring"
        )

    def _create_replica_stacks(self) -> List[Stack]:
        """Create replica stacks for Lambda functions in other regions."""
        replica_stacks = []
        
        for region in self.replica_regions:
            # Create a simple stack with just Lambda function for testing
            replica_stack = Stack(
                self.app,
                f"DynamoDBGlobalTablesReplica-{region}",
                stack_name=f"DynamoDBGlobalTablesReplica-{self.table_name}-{region}",
                env=Environment(
                    account=self.account,
                    region=region
                ),
                description=f"Replica stack for Global Tables testing in {region}"
            )
            
            # Create IAM role for Lambda in this region
            lambda_role = iam.Role(
                replica_stack,
                "ReplicaLambdaRole",
                assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
                managed_policies=[
                    iam.ManagedPolicy.from_aws_managed_policy_name(
                        "service-role/AWSLambdaBasicExecutionRole"
                    )
                ]
            )
            
            # Add DynamoDB permissions for the table in this region
            lambda_role.add_to_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:Query",
                        "dynamodb:Scan",
                        "dynamodb:UpdateItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:BatchGetItem",
                        "dynamodb:BatchWriteItem",
                        "dynamodb:DescribeTable",
                    ],
                    resources=[
                        f"arn:aws:dynamodb:{region}:{self.account}:table/{self.table_name}",
                        f"arn:aws:dynamodb:{region}:{self.account}:table/{self.table_name}/*",
                    ]
                )
            )
            
            # Create Lambda function in replica region
            replica_function = lambda_.Function(
                replica_stack,
                "ReplicaLambdaFunction",
                function_name=f"GlobalTableProcessor-{self.table_name}",
                runtime=lambda_.Runtime.PYTHON_3_11,
                handler="index.lambda_handler",
                code=lambda_.Code.from_inline(self._get_lambda_code()),
                role=lambda_role,
                timeout=Duration.seconds(30),
                memory_size=256,
                environment={
                    "TABLE_NAME": self.table_name,
                    "REGION": region,
                },
                log_retention=logs.RetentionDays.ONE_WEEK,
                description=f"Lambda function for Global Table operations in {region}",
            )
            
            # Add output for Lambda function
            cdk.CfnOutput(
                replica_stack,
                "ReplicaLambdaFunctionName",
                value=replica_function.function_name,
                description=f"Lambda function name in {region}"
            )
            
            replica_stacks.append(replica_stack)
        
        return replica_stacks

    def _get_lambda_code(self) -> str:
        """Get the Lambda function code (same as in primary stack)."""
        return '''
import json
import boto3
import os
import time
from datetime import datetime, timezone
from typing import Dict, Any, Optional

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for Global Table operations.
    
    Supports operations: put, get, scan, query
    """
    try:
        # Get region from environment or context
        region = os.environ.get('AWS_REGION', context.invoked_function_arn.split(':')[3])
        
        # Initialize DynamoDB client
        dynamodb = boto3.resource('dynamodb', region_name=region)
        table = dynamodb.Table(os.environ['TABLE_NAME'])
        
        # Process the operation
        operation = event.get('operation', 'put')
        
        if operation == 'put':
            return handle_put_operation(table, event, region)
        elif operation == 'get':
            return handle_get_operation(table, event, region)
        elif operation == 'scan':
            return handle_scan_operation(table, event, region)
        elif operation == 'query':
            return handle_query_operation(table, event, region)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unsupported operation: {operation}'
                })
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'region': region
            })
        }

def handle_put_operation(table: Any, event: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Handle PUT operation for creating/updating items."""
    user_id = event.get('userId', f'user-{int(time.time())}')
    profile_type = event.get('profileType', 'standard')
    
    item = {
        'UserId': user_id,
        'ProfileType': profile_type,
        'Name': event.get('name', 'Test User'),
        'Email': event.get('email', 'test@example.com'),
        'Region': region,
        'CreatedAt': datetime.now(timezone.utc).isoformat(),
        'LastModified': datetime.now(timezone.utc).isoformat(),
        'Preferences': event.get('preferences', {}),
        'Status': event.get('status', 'active')
    }
    
    response = table.put_item(Item=item)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Item created/updated in {region}',
            'userId': user_id,
            'profileType': profile_type,
            'timestamp': item['LastModified']
        })
    }

def handle_get_operation(table: Any, event: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Handle GET operation for retrieving items."""
    user_id = event.get('userId')
    profile_type = event.get('profileType', 'standard')
    
    if not user_id:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'userId is required for get operation'
            })
        }
    
    response = table.get_item(
        Key={
            'UserId': user_id,
            'ProfileType': profile_type
        }
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Item retrieved from {region}',
            'item': response.get('Item'),
            'found': 'Item' in response
        })
    }

def handle_scan_operation(table: Any, event: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Handle SCAN operation for retrieving multiple items."""
    limit = event.get('limit', 10)
    
    response = table.scan(
        ProjectionExpression='UserId, ProfileType, #r, #n, Email, #s',
        ExpressionAttributeNames={
            '#r': 'Region',
            '#n': 'Name',
            '#s': 'Status'
        },
        Limit=limit
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Items scanned from {region}',
            'count': response['Count'],
            'items': response.get('Items', [])
        })
    }

def handle_query_operation(table: Any, event: Dict[str, Any], region: str) -> Dict[str, Any]:
    """Handle QUERY operation using GSI."""
    email = event.get('email')
    
    if not email:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'email is required for query operation'
            })
        }
    
    response = table.query(
        IndexName='EmailIndex',
        KeyConditionExpression='Email = :email',
        ExpressionAttributeValues={
            ':email': email
        }
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Query executed from {region}',
            'count': response['Count'],
            'items': response.get('Items', [])
        })
    }
'''

    def deploy(self) -> None:
        """Deploy the application."""
        self.app.synth()


def main() -> None:
    """Main entry point for the CDK application."""
    app = GlobalTablesApp()
    app.deploy()


if __name__ == "__main__":
    main()