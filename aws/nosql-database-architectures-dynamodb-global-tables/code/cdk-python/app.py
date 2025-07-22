#!/usr/bin/env python3
"""
CDK Python application for DynamoDB Global Tables Recipe
This app creates a globally distributed NoSQL database architecture using DynamoDB Global Tables
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_kms as kms,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_backup as backup,
    aws_events as events,
    aws_events_targets as targets,
)
from constructs import Construct


class DynamoDBGlobalTablesStack(Stack):
    """
    Stack for creating DynamoDB Global Tables with comprehensive security,
    monitoring, and backup capabilities
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        table_name: str,
        regions: List[str],
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.table_name = table_name
        self.regions = regions
        self.current_region = self.region

        # Create KMS key for encryption
        self.kms_key = self._create_kms_key()

        # Create IAM role for DynamoDB access
        self.dynamodb_role = self._create_dynamodb_role()

        # Create the DynamoDB table with Global Tables configuration
        self.dynamodb_table = self._create_dynamodb_table()

        # Create Lambda function for testing Global Tables
        self.test_lambda = self._create_test_lambda()

        # Create CloudWatch monitoring
        self._create_monitoring()

        # Create backup configuration
        self._create_backup_plan()

        # Create outputs
        self._create_outputs()

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for DynamoDB encryption"""
        key = kms.Key(
            self,
            "DynamoDBGlobalTablesKMSKey",
            description=f"KMS key for DynamoDB Global Tables encryption in {self.current_region}",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create alias for easier reference
        kms.Alias(
            self,
            "DynamoDBGlobalTablesKMSAlias",
            alias_name=f"alias/dynamodb-global-tables-{self.current_region}",
            target_key=key,
        )

        return key

    def _create_dynamodb_role(self) -> iam.Role:
        """Create IAM role for DynamoDB Global Tables access"""
        role = iam.Role(
            self,
            "DynamoDBGlobalTablesRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("lambda.amazonaws.com"),
                iam.ServicePrincipal("ec2.amazonaws.com"),
            ),
            description="Role for accessing DynamoDB Global Tables",
        )

        # Add comprehensive DynamoDB permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                    "dynamodb:BatchGetItem",
                    "dynamodb:BatchWriteItem",
                    "dynamodb:ConditionCheckItem",
                ],
                resources=[
                    f"arn:aws:dynamodb:*:{self.account}:table/{self.table_name}",
                    f"arn:aws:dynamodb:*:{self.account}:table/{self.table_name}/index/*",
                ],
            )
        )

        # Add table description and stream permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:DescribeTable",
                    "dynamodb:DescribeStream",
                    "dynamodb:ListStreams",
                    "dynamodb:DescribeGlobalTable",
                ],
                resources=["*"],
            )
        )

        # Add CloudWatch Logs permissions
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )

        return role

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """Create DynamoDB table with Global Tables configuration"""
        table = dynamodb.Table(
            self,
            "GlobalAppTable",
            table_name=self.table_name,
            partition_key=dynamodb.Attribute(
                name="PK", type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="SK", type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=10,
            write_capacity=10,
            encryption=dynamodb.TableEncryption.CUSTOMER_MANAGED,
            encryption_key=self.kms_key,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            point_in_time_recovery=True,
            deletion_protection=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Add Global Secondary Index
        table.add_global_secondary_index(
            index_name="GSI1",
            partition_key=dynamodb.Attribute(
                name="GSI1PK", type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="GSI1SK", type=dynamodb.AttributeType.STRING
            ),
            read_capacity=5,
            write_capacity=5,
            projection_type=dynamodb.ProjectionType.ALL,
        )

        # Configure Global Tables replication
        if len(self.regions) > 1:
            for region in self.regions:
                if region != self.current_region:
                    table.add_replica(
                        region=region,
                        encryption_key=kms.Key.from_lookup(
                            self,
                            f"ReplicaKey{region}",
                            alias_name=f"alias/dynamodb-global-tables-{region}",
                        ),
                        point_in_time_recovery=True,
                    )

        return table

    def _create_test_lambda(self) -> lambda_.Function:
        """Create Lambda function for testing Global Tables functionality"""
        test_function = lambda_.Function(
            self,
            "GlobalTablesTestFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(
                """
import json
import boto3
import os
from datetime import datetime, timezone
import uuid

def lambda_handler(event, context):
    table_name = os.environ['TABLE_NAME']
    regions = os.environ['REGIONS'].split(',')
    
    results = {}
    
    for region in regions:
        try:
            dynamodb = boto3.resource('dynamodb', region_name=region)
            table = dynamodb.Table(table_name)
            
            # Test write operation in each region
            test_item = {
                'PK': f'TEST#{uuid.uuid4()}',
                'SK': 'LAMBDA_TEST',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'region': region,
                'test_data': f'Test from Lambda in {region}'
            }
            
            table.put_item(Item=test_item)
            
            # Test read operation to verify data accessibility
            response = table.scan(
                FilterExpression='attribute_exists(#r)',
                ExpressionAttributeNames={'#r': 'region'},
                Limit=5
            )
            
            results[region] = {
                'write_success': True,
                'items_count': response['Count'],
                'sample_items': response['Items'][:2]  # First 2 items
            }
            
        except Exception as e:
            results[region] = {
                'error': str(e),
                'write_success': False
            }
    
    return {
        'statusCode': 200,
        'body': json.dumps(results, default=str)
    }
"""
            ),
            environment={
                "TABLE_NAME": self.dynamodb_table.table_name,
                "REGIONS": ",".join(self.regions),
            },
            role=self.dynamodb_role,
            timeout=Duration.seconds(60),
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        return test_function

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms"""
        # Read throttling alarm
        read_throttle_alarm = cloudwatch.Alarm(
            self,
            "ReadThrottleAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="ReadThrottledEvents",
                dimensions_map={"TableName": self.dynamodb_table.table_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=2,
            alarm_description=f"High read throttling on {self.dynamodb_table.table_name}",
        )

        # Write throttling alarm
        write_throttle_alarm = cloudwatch.Alarm(
            self,
            "WriteThrottleAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="WriteThrottledEvents",
                dimensions_map={"TableName": self.dynamodb_table.table_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=2,
            alarm_description=f"High write throttling on {self.dynamodb_table.table_name}",
        )

        # Replication delay alarm
        replication_delay_alarm = cloudwatch.Alarm(
            self,
            "ReplicationDelayAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="ReplicationDelay",
                dimensions_map={
                    "TableName": self.dynamodb_table.table_name,
                    "ReceivingRegion": self.current_region,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=1000,  # 1 second in milliseconds
            evaluation_periods=2,
            alarm_description=f"High replication delay on {self.dynamodb_table.table_name}",
        )

    def _create_backup_plan(self) -> None:
        """Create AWS Backup plan for DynamoDB table"""
        # Create backup vault
        backup_vault = backup.BackupVault(
            self,
            "DynamoDBGlobalBackupVault",
            backup_vault_name=f"DynamoDB-Global-Backup-{self.current_region}",
            encryption_key=self.kms_key,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create backup plan
        backup_plan = backup.BackupPlan(
            self,
            "DynamoDBGlobalBackupPlan",
            backup_plan_name=f"DynamoDB-Global-Backup-Plan-{self.current_region}",
            backup_vault=backup_vault,
        )

        # Add backup rule
        backup_plan.add_rule(
            backup.BackupPlanRule(
                backup_vault=backup_vault,
                rule_name="DailyBackups",
                schedule_expression=events.Schedule.cron(
                    hour="2", minute="0"
                ),  # Daily at 2 AM
                start_window=Duration.minutes(60),
                completion_window=Duration.minutes(120),
                delete_after=Duration.days(30),
            )
        )

        # Add backup selection
        backup_plan.add_selection(
            "DynamoDBGlobalBackupSelection",
            resources=[
                backup.BackupResource.from_dynamodb_table(self.dynamodb_table)
            ],
            backup_selection_name="DynamoDB-Global-Selection",
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        CfnOutput(
            self,
            "TableName",
            value=self.dynamodb_table.table_name,
            description="Name of the DynamoDB Global Table",
        )

        CfnOutput(
            self,
            "TableArn",
            value=self.dynamodb_table.table_arn,
            description="ARN of the DynamoDB Global Table",
        )

        CfnOutput(
            self,
            "TableStreamArn",
            value=self.dynamodb_table.table_stream_arn or "No stream configured",
            description="ARN of the DynamoDB table stream",
        )

        CfnOutput(
            self,
            "KMSKeyId",
            value=self.kms_key.key_id,
            description="ID of the KMS key used for encryption",
        )

        CfnOutput(
            self,
            "IAMRoleArn",
            value=self.dynamodb_role.role_arn,
            description="ARN of the IAM role for DynamoDB access",
        )

        CfnOutput(
            self,
            "TestLambdaArn",
            value=self.test_lambda.function_arn,
            description="ARN of the Lambda function for testing Global Tables",
        )

        CfnOutput(
            self,
            "CurrentRegion",
            value=self.current_region,
            description="Current AWS region where resources are deployed",
        )

        CfnOutput(
            self,
            "ReplicaRegions",
            value=",".join([r for r in self.regions if r != self.current_region]),
            description="List of replica regions for Global Tables",
        )


class DynamoDBGlobalTablesApp(cdk.App):
    """
    CDK App for DynamoDB Global Tables recipe
    """

    def __init__(self):
        super().__init__()

        # Get configuration from environment variables or context
        table_name = self.get_config("table_name", "global-app-data")
        regions = self.get_config("regions", "us-east-1,eu-west-1,ap-southeast-1").split(",")
        
        # Create stack for each region
        for region in regions:
            env = Environment(region=region)
            
            DynamoDBGlobalTablesStack(
                self,
                f"DynamoDBGlobalTablesStack-{region}",
                table_name=table_name,
                regions=regions,
                env=env,
            )

    def get_config(self, key: str, default: str) -> str:
        """Get configuration value from context or environment"""
        # Try CDK context first
        context_value = self.node.try_get_context(key)
        if context_value:
            return context_value
        
        # Try environment variable
        env_value = os.environ.get(key.upper())
        if env_value:
            return env_value
        
        # Return default
        return default


def main():
    """Main entry point for the CDK application"""
    app = DynamoDBGlobalTablesApp()
    app.synth()


if __name__ == "__main__":
    main()