#!/usr/bin/env python3
"""
Aurora DSQL Multi-Region Disaster Recovery CDK Application

This CDK application deploys a comprehensive multi-region disaster recovery solution
using Aurora DSQL with active-active architecture, EventBridge-orchestrated monitoring,
and Lambda-based health checks across multiple AWS regions.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags
)
from aws_cdk import (
    aws_dsql as dsql,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_logs as logs
)
from constructs import Construct


class AuroraDsqlDisasterRecoveryStack(Stack):
    """
    CDK Stack for Aurora DSQL Multi-Region Disaster Recovery
    
    This stack creates:
    - Aurora DSQL clusters in multiple regions
    - Lambda functions for health monitoring
    - EventBridge rules for automated monitoring
    - SNS topics for alerting
    - CloudWatch alarms and dashboard
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "production",
        primary_region: str = "us-east-1",
        secondary_region: str = "us-west-2",
        witness_region: str = "us-west-1",
        monitoring_email: str = "ops-team@company.com",
        cluster_prefix: str = "dr-dsql",
        monitoring_frequency_minutes: int = 2,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.environment_name = environment_name
        self.primary_region = primary_region
        self.secondary_region = secondary_region
        self.witness_region = witness_region
        self.monitoring_email = monitoring_email
        self.cluster_prefix = cluster_prefix
        self.monitoring_frequency = monitoring_frequency_minutes

        # Generate unique suffix for resource naming
        self.unique_suffix = cdk.Fn.select(2, cdk.Fn.split("-", cdk.Fn.ref("AWS::StackId")))

        # Create Aurora DSQL clusters
        self.create_aurora_dsql_clusters()

        # Create SNS topics for alerting
        self.create_sns_topics()

        # Create Lambda functions for monitoring
        self.create_monitoring_lambda()

        # Create EventBridge rules
        self.create_eventbridge_rules()

        # Create CloudWatch alarms and dashboard
        self.create_cloudwatch_monitoring()

        # Add stack-level tags
        self.add_tags()

    def create_aurora_dsql_clusters(self) -> None:
        """Create Aurora DSQL clusters in primary and secondary regions"""
        
        # Primary Aurora DSQL cluster
        self.primary_cluster = dsql.CfnCluster(
            self,
            "PrimaryDsqlCluster",
            cluster_identifier=f"{self.cluster_prefix}-primary-{self.unique_suffix}",
            multi_region_properties=dsql.CfnCluster.MultiRegionPropertiesProperty(
                witness_region=self.witness_region
            ),
            tags=[
                cdk.CfnTag(key="Project", value="DisasterRecovery"),
                cdk.CfnTag(key="Environment", value=self.environment_name),
                cdk.CfnTag(key="CostCenter", value="Infrastructure"),
                cdk.CfnTag(key="Region", value="Primary"),
                cdk.CfnTag(key="ManagedBy", value="CDK")
            ]
        )

        # Store cluster identifiers for cross-stack references
        self.primary_cluster_id = self.primary_cluster.cluster_identifier
        self.primary_cluster_arn = self.primary_cluster.attr_arn

        # Output primary cluster information
        CfnOutput(
            self,
            "PrimaryClusterIdentifier",
            description="Aurora DSQL Primary Cluster Identifier",
            value=self.primary_cluster_id,
            export_name=f"{self.stack_name}-PrimaryClusterIdentifier"
        )

        CfnOutput(
            self,
            "PrimaryClusterArn",
            description="Aurora DSQL Primary Cluster ARN",
            value=self.primary_cluster_arn,
            export_name=f"{self.stack_name}-PrimaryClusterArn"
        )

    def create_sns_topics(self) -> None:
        """Create SNS topics for disaster recovery alerting"""
        
        # Primary region SNS topic
        self.primary_sns_topic = sns.Topic(
            self,
            "PrimarySNSTopic",
            topic_name=f"dr-alerts-primary-{self.unique_suffix}",
            display_name="DR Alerts Primary",
            master_key=None  # Use default AWS managed key
        )

        # Add email subscription
        self.primary_sns_topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.monitoring_email)
        )

        # Output SNS topic ARN
        CfnOutput(
            self,
            "PrimarySNSTopicArn",
            description="Primary SNS Topic ARN for disaster recovery alerts",
            value=self.primary_sns_topic.topic_arn,
            export_name=f"{self.stack_name}-PrimarySNSTopicArn"
        )

    def create_monitoring_lambda(self) -> None:
        """Create Lambda functions for Aurora DSQL health monitoring"""
        
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"aurora-dsql-monitor-role-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "AuroraDSQLAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dsql:GetCluster",
                                "dsql:ListClusters",
                                "dsql:DescribeCluster"
                            ],
                            resources=["*"]
                        )
                    ]
                ),
                "SNSPublish": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.primary_sns_topic.topic_arn]
                        )
                    ]
                ),
                "CloudWatchMetrics": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Create CloudWatch Log Group for Lambda function
        log_group = logs.LogGroup(
            self,
            "LambdaLogGroup",
            log_group_name=f"/aws/lambda/aurora-dsql-monitor-{self.unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Lambda function code
        lambda_code = """
import json
import boto3
import os
import time
from datetime import datetime
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    \"\"\"
    Monitor Aurora DSQL cluster health and send alerts
    \"\"\"
    dsql_client = boto3.client('dsql')
    sns_client = boto3.client('sns')
    cloudwatch_client = boto3.client('cloudwatch')
    
    cluster_id = os.environ['CLUSTER_ID']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    region = os.environ['AWS_REGION']
    
    try:
        # Check cluster status with retry logic
        max_retries = 3
        for attempt in range(max_retries):
            try:
                response = dsql_client.get_cluster(identifier=cluster_id)
                break
            except ClientError as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                    continue
                raise e
        
        cluster_status = response['status']
        cluster_arn = response['arn']
        
        # Create comprehensive health report
        health_report = {
            'timestamp': datetime.now().isoformat(),
            'region': region,
            'cluster_id': cluster_id,
            'cluster_arn': cluster_arn,
            'status': cluster_status,
            'healthy': cluster_status == 'ACTIVE',
            'function_name': context.function_name,
            'request_id': context.aws_request_id
        }
        
        # Publish custom CloudWatch metric
        cloudwatch_client.put_metric_data(
            Namespace='Aurora/DSQL/DisasterRecovery',
            MetricData=[
                {
                    'MetricName': 'ClusterHealth',
                    'Value': 1.0 if cluster_status == 'ACTIVE' else 0.0,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'ClusterID',
                            'Value': cluster_id
                        },
                        {
                            'Name': 'Region',
                            'Value': region
                        }
                    ]
                }
            ]
        )
        
        # Send alert if cluster is not healthy
        if cluster_status != 'ACTIVE':
            alert_message = f\"\"\"
ALERT: Aurora DSQL Cluster Health Issue

Region: {region}
Cluster ID: {cluster_id}
Cluster ARN: {cluster_arn}
Status: {cluster_status}
Timestamp: {health_report['timestamp']}
Function: {context.function_name}
Request ID: {context.aws_request_id}

Immediate investigation required.
Check Aurora DSQL console for detailed status information.
\"\"\"
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Alert - {region}',
                Message=alert_message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f\"\"\"
ERROR: Aurora DSQL Health Check Failed

Region: {region}
Cluster ID: {cluster_id}
Error: {str(e)}
Error Type: {type(e).__name__}
Timestamp: {datetime.now().isoformat()}
Function: {context.function_name}
Request ID: {context.aws_request_id}

This error indicates a potential issue with the monitoring infrastructure.
Verify Lambda function permissions and Aurora DSQL cluster accessibility.
\"\"\"
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Health Check Error - {region}',
                Message=error_message
            )
        except Exception as sns_error:
            print(f"Failed to send SNS alert: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__,
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
"""

        # Create Lambda function
        self.monitoring_lambda = lambda_.Function(
            self,
            "MonitoringLambda",
            function_name=f"aurora-dsql-monitor-{self.unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "CLUSTER_ID": self.primary_cluster_id,
                "SNS_TOPIC_ARN": self.primary_sns_topic.topic_arn
            },
            log_group=log_group,
            reserved_concurrent_executions=10,
            description="Aurora DSQL health monitoring function for disaster recovery"
        )

        # Output Lambda function ARN
        CfnOutput(
            self,
            "MonitoringLambdaArn",
            description="Aurora DSQL Monitoring Lambda Function ARN",
            value=self.monitoring_lambda.function_arn,
            export_name=f"{self.stack_name}-MonitoringLambdaArn"
        )

    def create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for automated monitoring"""
        
        # EventBridge rule for scheduled monitoring
        self.monitoring_rule = events.Rule(
            self,
            "MonitoringRule",
            rule_name=f"aurora-dsql-health-monitor-{self.unique_suffix}",
            description="Aurora DSQL health monitoring for disaster recovery",
            schedule=events.Schedule.rate(Duration.minutes(self.monitoring_frequency)),
            enabled=True
        )

        # Add Lambda function as target with retry configuration
        self.monitoring_rule.add_target(
            targets.LambdaFunction(
                handler=self.monitoring_lambda,
                retry_attempts=3,
                max_event_age=Duration.hours(1)
            )
        )

        # Output EventBridge rule ARN
        CfnOutput(
            self,
            "MonitoringRuleArn",
            description="EventBridge Monitoring Rule ARN",
            value=self.monitoring_rule.rule_arn,
            export_name=f"{self.stack_name}-MonitoringRuleArn"
        )

    def create_cloudwatch_monitoring(self) -> None:
        """Create CloudWatch alarms and dashboard for monitoring"""
        
        # Lambda function error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"Aurora-DSQL-Lambda-Errors-{self.unique_suffix}",
            alarm_description="Alert when Lambda function errors occur",
            metric=self.monitoring_lambda.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS topic as alarm action
        lambda_error_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.primary_sns_topic)
        )

        # Aurora DSQL cluster health alarm
        cluster_health_alarm = cloudwatch.Alarm(
            self,
            "ClusterHealthAlarm",
            alarm_name=f"Aurora-DSQL-Cluster-Health-{self.unique_suffix}",
            alarm_description="Alert when Aurora DSQL cluster health degrades",
            metric=cloudwatch.Metric(
                namespace="Aurora/DSQL/DisasterRecovery",
                metric_name="ClusterHealth",
                dimensions_map={
                    "ClusterID": self.primary_cluster_id,
                    "Region": self.primary_region
                },
                period=Duration.minutes(5),
                statistic="Average"
            ),
            threshold=0.5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

        # Add SNS topic as alarm action
        cluster_health_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.primary_sns_topic)
        )

        # EventBridge rule failure alarm
        eventbridge_failure_alarm = cloudwatch.Alarm(
            self,
            "EventBridgeFailureAlarm",
            alarm_name=f"Aurora-DSQL-EventBridge-Failures-{self.unique_suffix}",
            alarm_description="Alert when EventBridge rules fail to execute",
            metric=cloudwatch.Metric(
                namespace="AWS/Events",
                metric_name="FailedInvocations",
                dimensions_map={
                    "RuleName": self.monitoring_rule.rule_name
                },
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS topic as alarm action
        eventbridge_failure_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.primary_sns_topic)
        )

        # Create CloudWatch Dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "DisasterRecoveryDashboard",
            dashboard_name=f"Aurora-DSQL-DR-Dashboard-{self.unique_suffix}",
            default_interval=Duration.hours(1)
        )

        # Add Lambda metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Invocations",
                left=[
                    self.monitoring_lambda.metric_invocations(
                        period=Duration.minutes(5),
                        statistic="Sum"
                    )
                ],
                width=12,
                height=6
            ),
            cloudwatch.GraphWidget(
                title="Lambda Function Errors and Duration",
                left=[
                    self.monitoring_lambda.metric_errors(
                        period=Duration.minutes(5),
                        statistic="Sum"
                    )
                ],
                right=[
                    self.monitoring_lambda.metric_duration(
                        period=Duration.minutes(5),
                        statistic="Average"
                    )
                ],
                width=12,
                height=6
            )
        )

        # Add EventBridge metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="EventBridge Rule Executions",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Events",
                        metric_name="MatchedEvents",
                        dimensions_map={
                            "RuleName": self.monitoring_rule.rule_name
                        },
                        period=Duration.minutes(5),
                        statistic="Sum"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Events",
                        metric_name="SuccessfulInvocations",
                        dimensions_map={
                            "RuleName": self.monitoring_rule.rule_name
                        },
                        period=Duration.minutes(5),
                        statistic="Sum"
                    )
                ],
                width=24,
                height=6
            )
        )

        # Add Aurora DSQL health metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Aurora DSQL Cluster Health Status",
                left=[
                    cloudwatch.Metric(
                        namespace="Aurora/DSQL/DisasterRecovery",
                        metric_name="ClusterHealth",
                        dimensions_map={
                            "ClusterID": self.primary_cluster_id,
                            "Region": self.primary_region
                        },
                        period=Duration.minutes(5),
                        statistic="Average"
                    )
                ],
                left_y_axis=cloudwatch.YAxisProps(
                    min=0,
                    max=1
                ),
                width=24,
                height=6
            )
        )

        # Output alarm ARNs
        CfnOutput(
            self,
            "LambdaErrorAlarmArn",
            description="Lambda Error Alarm ARN",
            value=lambda_error_alarm.alarm_arn
        )

        CfnOutput(
            self,
            "ClusterHealthAlarmArn",
            description="Cluster Health Alarm ARN",
            value=cluster_health_alarm.alarm_arn
        )

        CfnOutput(
            self,
            "EventBridgeFailureAlarmArn",
            description="EventBridge Failure Alarm ARN",
            value=eventbridge_failure_alarm.alarm_arn
        )

        CfnOutput(
            self,
            "DashboardUrl",
            description="CloudWatch Dashboard URL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={dashboard.dashboard_name}"
        )

    def add_tags(self) -> None:
        """Add comprehensive tags to all resources in the stack"""
        tags_to_add = {
            "Project": "DisasterRecovery",
            "Environment": self.environment_name,
            "CostCenter": "Infrastructure",
            "Owner": "DevOps",
            "Application": "Aurora-DSQL-DR",
            "Version": "1.0",
            "ManagedBy": "CDK",
            "Purpose": "Multi-Region-Disaster-Recovery"
        }

        for key, value in tags_to_add.items():
            Tags.of(self).add(key, value)


class AuroraDsqlSecondaryRegionStack(Stack):
    """
    Secondary region stack for Aurora DSQL Multi-Region Disaster Recovery
    
    This stack is deployed in the secondary region and creates:
    - Secondary Aurora DSQL cluster
    - Lambda function for health monitoring
    - EventBridge rule for automated monitoring
    - SNS topic for alerting
    - CloudWatch alarms
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        primary_cluster_arn: str,
        environment_name: str = "production",
        witness_region: str = "us-west-1",
        monitoring_email: str = "ops-team@company.com",
        cluster_prefix: str = "dr-dsql",
        monitoring_frequency_minutes: int = 2,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.primary_cluster_arn = primary_cluster_arn
        self.environment_name = environment_name
        self.witness_region = witness_region
        self.monitoring_email = monitoring_email
        self.cluster_prefix = cluster_prefix
        self.monitoring_frequency = monitoring_frequency_minutes

        # Generate unique suffix for resource naming
        self.unique_suffix = cdk.Fn.select(2, cdk.Fn.split("-", cdk.Fn.ref("AWS::StackId")))

        # Create secondary Aurora DSQL cluster
        self.create_secondary_aurora_dsql_cluster()

        # Create SNS topic for alerting
        self.create_sns_topic()

        # Create Lambda function for monitoring
        self.create_monitoring_lambda()

        # Create EventBridge rule
        self.create_eventbridge_rule()

        # Create CloudWatch alarms
        self.create_cloudwatch_alarms()

        # Add stack-level tags
        self.add_tags()

    def create_secondary_aurora_dsql_cluster(self) -> None:
        """Create secondary Aurora DSQL cluster and establish peering"""
        
        # Secondary Aurora DSQL cluster
        self.secondary_cluster = dsql.CfnCluster(
            self,
            "SecondaryDsqlCluster",
            cluster_identifier=f"{self.cluster_prefix}-secondary-{self.unique_suffix}",
            multi_region_properties=dsql.CfnCluster.MultiRegionPropertiesProperty(
                witness_region=self.witness_region,
                clusters=[self.primary_cluster_arn]
            ),
            tags=[
                cdk.CfnTag(key="Project", value="DisasterRecovery"),
                cdk.CfnTag(key="Environment", value=self.environment_name),
                cdk.CfnTag(key="CostCenter", value="Infrastructure"),
                cdk.CfnTag(key="Region", value="Secondary"),
                cdk.CfnTag(key="ManagedBy", value="CDK")
            ]
        )

        # Store cluster identifiers
        self.secondary_cluster_id = self.secondary_cluster.cluster_identifier
        self.secondary_cluster_arn = self.secondary_cluster.attr_arn

        # Output secondary cluster information
        CfnOutput(
            self,
            "SecondaryClusterIdentifier",
            description="Aurora DSQL Secondary Cluster Identifier",
            value=self.secondary_cluster_id,
            export_name=f"{self.stack_name}-SecondaryClusterIdentifier"
        )

        CfnOutput(
            self,
            "SecondaryClusterArn",
            description="Aurora DSQL Secondary Cluster ARN",
            value=self.secondary_cluster_arn,
            export_name=f"{self.stack_name}-SecondaryClusterArn"
        )

    def create_sns_topic(self) -> None:
        """Create SNS topic for secondary region alerting"""
        
        # Secondary region SNS topic
        self.secondary_sns_topic = sns.Topic(
            self,
            "SecondarySNSTopic",
            topic_name=f"dr-alerts-secondary-{self.unique_suffix}",
            display_name="DR Alerts Secondary",
            master_key=None  # Use default AWS managed key
        )

        # Add email subscription
        self.secondary_sns_topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.monitoring_email)
        )

        # Output SNS topic ARN
        CfnOutput(
            self,
            "SecondarySNSTopicArn",
            description="Secondary SNS Topic ARN for disaster recovery alerts",
            value=self.secondary_sns_topic.topic_arn,
            export_name=f"{self.stack_name}-SecondarySNSTopicArn"
        )

    def create_monitoring_lambda(self) -> None:
        """Create Lambda function for secondary region monitoring"""
        
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "SecondaryLambdaExecutionRole",
            role_name=f"aurora-dsql-monitor-secondary-role-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "AuroraDSQLAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dsql:GetCluster",
                                "dsql:ListClusters",
                                "dsql:DescribeCluster"
                            ],
                            resources=["*"]
                        )
                    ]
                ),
                "SNSPublish": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.secondary_sns_topic.topic_arn]
                        )
                    ]
                ),
                "CloudWatchMetrics": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Create CloudWatch Log Group for Lambda function
        log_group = logs.LogGroup(
            self,
            "SecondaryLambdaLogGroup",
            log_group_name=f"/aws/lambda/aurora-dsql-monitor-secondary-{self.unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Lambda function code (same as primary)
        lambda_code = """
import json
import boto3
import os
import time
from datetime import datetime
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    \"\"\"
    Monitor Aurora DSQL cluster health and send alerts
    \"\"\"
    dsql_client = boto3.client('dsql')
    sns_client = boto3.client('sns')
    cloudwatch_client = boto3.client('cloudwatch')
    
    cluster_id = os.environ['CLUSTER_ID']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    region = os.environ['AWS_REGION']
    
    try:
        # Check cluster status with retry logic
        max_retries = 3
        for attempt in range(max_retries):
            try:
                response = dsql_client.get_cluster(identifier=cluster_id)
                break
            except ClientError as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                    continue
                raise e
        
        cluster_status = response['status']
        cluster_arn = response['arn']
        
        # Create comprehensive health report
        health_report = {
            'timestamp': datetime.now().isoformat(),
            'region': region,
            'cluster_id': cluster_id,
            'cluster_arn': cluster_arn,
            'status': cluster_status,
            'healthy': cluster_status == 'ACTIVE',
            'function_name': context.function_name,
            'request_id': context.aws_request_id
        }
        
        # Publish custom CloudWatch metric
        cloudwatch_client.put_metric_data(
            Namespace='Aurora/DSQL/DisasterRecovery',
            MetricData=[
                {
                    'MetricName': 'ClusterHealth',
                    'Value': 1.0 if cluster_status == 'ACTIVE' else 0.0,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'ClusterID',
                            'Value': cluster_id
                        },
                        {
                            'Name': 'Region',
                            'Value': region
                        }
                    ]
                }
            ]
        )
        
        # Send alert if cluster is not healthy
        if cluster_status != 'ACTIVE':
            alert_message = f\"\"\"
ALERT: Aurora DSQL Cluster Health Issue

Region: {region}
Cluster ID: {cluster_id}
Cluster ARN: {cluster_arn}
Status: {cluster_status}
Timestamp: {health_report['timestamp']}
Function: {context.function_name}
Request ID: {context.aws_request_id}

Immediate investigation required.
Check Aurora DSQL console for detailed status information.
\"\"\"
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Alert - {region}',
                Message=alert_message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f\"\"\"
ERROR: Aurora DSQL Health Check Failed

Region: {region}
Cluster ID: {cluster_id}
Error: {str(e)}
Error Type: {type(e).__name__}
Timestamp: {datetime.now().isoformat()}
Function: {context.function_name}
Request ID: {context.aws_request_id}

This error indicates a potential issue with the monitoring infrastructure.
Verify Lambda function permissions and Aurora DSQL cluster accessibility.
\"\"\"
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Health Check Error - {region}',
                Message=error_message
            )
        except Exception as sns_error:
            print(f"Failed to send SNS alert: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__,
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
"""

        # Create Lambda function
        self.monitoring_lambda = lambda_.Function(
            self,
            "SecondaryMonitoringLambda",
            function_name=f"aurora-dsql-monitor-secondary-{self.unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "CLUSTER_ID": self.secondary_cluster_id,
                "SNS_TOPIC_ARN": self.secondary_sns_topic.topic_arn
            },
            log_group=log_group,
            reserved_concurrent_executions=10,
            description="Aurora DSQL health monitoring function for secondary region disaster recovery"
        )

        # Output Lambda function ARN
        CfnOutput(
            self,
            "SecondaryMonitoringLambdaArn",
            description="Aurora DSQL Secondary Monitoring Lambda Function ARN",
            value=self.monitoring_lambda.function_arn,
            export_name=f"{self.stack_name}-SecondaryMonitoringLambdaArn"
        )

    def create_eventbridge_rule(self) -> None:
        """Create EventBridge rule for automated monitoring in secondary region"""
        
        # EventBridge rule for scheduled monitoring
        self.monitoring_rule = events.Rule(
            self,
            "SecondaryMonitoringRule",
            rule_name=f"aurora-dsql-health-monitor-secondary-{self.unique_suffix}",
            description="Aurora DSQL health monitoring for secondary region disaster recovery",
            schedule=events.Schedule.rate(Duration.minutes(self.monitoring_frequency)),
            enabled=True
        )

        # Add Lambda function as target with retry configuration
        self.monitoring_rule.add_target(
            targets.LambdaFunction(
                handler=self.monitoring_lambda,
                retry_attempts=3,
                max_event_age=Duration.hours(1)
            )
        )

        # Output EventBridge rule ARN
        CfnOutput(
            self,
            "SecondaryMonitoringRuleArn",
            description="Secondary EventBridge Monitoring Rule ARN",
            value=self.monitoring_rule.rule_arn,
            export_name=f"{self.stack_name}-SecondaryMonitoringRuleArn"
        )

    def create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for secondary region monitoring"""
        
        # Lambda function error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "SecondaryLambdaErrorAlarm",
            alarm_name=f"Aurora-DSQL-Lambda-Errors-Secondary-{self.unique_suffix}",
            alarm_description="Alert when Lambda function errors occur in secondary region",
            metric=self.monitoring_lambda.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS topic as alarm action
        lambda_error_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.secondary_sns_topic)
        )

        # Aurora DSQL cluster health alarm
        cluster_health_alarm = cloudwatch.Alarm(
            self,
            "SecondaryClusterHealthAlarm",
            alarm_name=f"Aurora-DSQL-Cluster-Health-Secondary-{self.unique_suffix}",
            alarm_description="Alert when Aurora DSQL secondary cluster health degrades",
            metric=cloudwatch.Metric(
                namespace="Aurora/DSQL/DisasterRecovery",
                metric_name="ClusterHealth",
                dimensions_map={
                    "ClusterID": self.secondary_cluster_id,
                    "Region": self.region
                },
                period=Duration.minutes(5),
                statistic="Average"
            ),
            threshold=0.5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

        # Add SNS topic as alarm action
        cluster_health_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.secondary_sns_topic)
        )

        # Output alarm ARNs
        CfnOutput(
            self,
            "SecondaryLambdaErrorAlarmArn",
            description="Secondary Lambda Error Alarm ARN",
            value=lambda_error_alarm.alarm_arn
        )

        CfnOutput(
            self,
            "SecondaryClusterHealthAlarmArn",
            description="Secondary Cluster Health Alarm ARN",
            value=cluster_health_alarm.alarm_arn
        )

    def add_tags(self) -> None:
        """Add comprehensive tags to all resources in the secondary stack"""
        tags_to_add = {
            "Project": "DisasterRecovery",
            "Environment": self.environment_name,
            "CostCenter": "Infrastructure",
            "Owner": "DevOps",
            "Application": "Aurora-DSQL-DR",
            "Version": "1.0",
            "ManagedBy": "CDK",
            "Purpose": "Multi-Region-Disaster-Recovery",
            "Region": "Secondary"
        }

        for key, value in tags_to_add.items():
            Tags.of(self).add(key, value)


def main() -> None:
    """
    Main CDK application entry point
    """
    app = cdk.App()

    # Get configuration from CDK context or environment variables
    environment_name = app.node.try_get_context("environment") or os.environ.get("ENVIRONMENT", "production")
    primary_region = app.node.try_get_context("primaryRegion") or os.environ.get("PRIMARY_REGION", "us-east-1")
    secondary_region = app.node.try_get_context("secondaryRegion") or os.environ.get("SECONDARY_REGION", "us-west-2")
    witness_region = app.node.try_get_context("witnessRegion") or os.environ.get("WITNESS_REGION", "us-west-1")
    monitoring_email = app.node.try_get_context("monitoringEmail") or os.environ.get("MONITORING_EMAIL", "ops-team@company.com")

    # Create primary region stack
    primary_stack = AuroraDsqlDisasterRecoveryStack(
        app,
        f"AuroraDsqlDR-Primary-{environment_name}",
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=primary_region
        ),
        environment_name=environment_name,
        primary_region=primary_region,
        secondary_region=secondary_region,
        witness_region=witness_region,
        monitoring_email=monitoring_email,
        description=f"Aurora DSQL Multi-Region Disaster Recovery - Primary Region ({primary_region})"
    )

    # Create secondary region stack
    secondary_stack = AuroraDsqlSecondaryRegionStack(
        app,
        f"AuroraDsqlDR-Secondary-{environment_name}",
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=secondary_region
        ),
        primary_cluster_arn=primary_stack.primary_cluster_arn,
        environment_name=environment_name,
        witness_region=witness_region,
        monitoring_email=monitoring_email,
        description=f"Aurora DSQL Multi-Region Disaster Recovery - Secondary Region ({secondary_region})"
    )

    # Add dependency to ensure primary stack deploys first
    secondary_stack.add_dependency(primary_stack)

    # Add application-level tags
    app_tags = {
        "Application": "Aurora-DSQL-Multi-Region-DR",
        "Repository": "aws-recipes",
        "Recipe": "building-multi-region-disaster-recovery-with-aurora-dsql-and-eventbridge",
        "Version": "1.0",
        "Owner": "DevOps-Team"
    }

    for key, value in app_tags.items():
        Tags.of(app).add(key, value)

    # Synthesize the CDK app
    app.synth()


if __name__ == "__main__":
    main()