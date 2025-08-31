#!/usr/bin/env python3
"""
CDK Python application for Performance Monitoring AI Agents with AgentCore and CloudWatch.

This CDK application creates a comprehensive monitoring system using AWS Bedrock AgentCore's
built-in observability features, CloudWatch metrics and dashboards, and automated Lambda-based
performance optimization alerts.
"""

import os
from aws_cdk import (
    App,
    Environment,
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_s3 as s3,
    aws_s3_notifications as s3n,
)
from constructs import Construct
from typing import Dict, Any


class PerformanceMonitoringStack(Stack):
    """
    CDK Stack for Performance Monitoring AI Agents with AgentCore and CloudWatch.
    
    This stack creates:
    - IAM roles for AgentCore with observability permissions
    - CloudWatch log groups for comprehensive logging
    - Performance monitoring Lambda function
    - CloudWatch dashboard for visualization
    - CloudWatch alarms for performance thresholds
    - S3 bucket for monitoring data storage
    - Custom metrics collection configuration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get context values or use defaults
        self.agent_name = self.node.try_get_context("agent_name") or "ai-agent-demo"
        self.random_suffix = self.node.try_get_context("random_suffix") or "abc123"
        
        # Create S3 bucket for monitoring data storage
        self.monitoring_bucket = self._create_monitoring_bucket()
        
        # Create IAM role for AgentCore with observability permissions
        self.agentcore_role = self._create_agentcore_role()
        
        # Create CloudWatch log groups
        self.log_groups = self._create_log_groups()
        
        # Create performance monitoring Lambda function
        self.performance_lambda = self._create_performance_lambda()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Create CloudWatch alarms
        self.alarms = self._create_cloudwatch_alarms()
        
        # Create custom metrics collection
        self._create_custom_metrics()
        
        # Create outputs
        self._create_outputs()

    def _create_monitoring_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing monitoring data and performance reports."""
        bucket = s3.Bucket(
            self,
            "MonitoringDataBucket",
            bucket_name=f"agent-monitoring-data-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="PerformanceReportsLifecycle",
                    prefix="performance-reports/",
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
                    ]
                )
            ]
        )
        
        return bucket

    def _create_agentcore_role(self) -> iam.Role:
        """Create IAM role for AgentCore with comprehensive observability permissions."""
        role = iam.Role(
            self,
            "AgentCoreMonitoringRole",
            role_name=f"AgentCoreMonitoringRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("bedrock.amazonaws.com"),
            description="IAM role for AgentCore with observability permissions",
            inline_policies={
                "AgentCoreObservabilityPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogGroups",
                                "logs:DescribeLogStreams"
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/bedrock/agentcore/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["cloudwatch:PutMetricData"],
                            resources=["*"],
                            conditions={
                                "StringEquals": {
                                    "cloudwatch:namespace": "AWS/BedrockAgentCore"
                                }
                            }
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_log_groups(self) -> Dict[str, logs.LogGroup]:
        """Create CloudWatch log groups for comprehensive agent observability."""
        log_groups = {}
        
        # Main AgentCore log group
        log_groups["main"] = logs.LogGroup(
            self,
            "AgentCoreMainLogGroup",
            log_group_name=f"/aws/bedrock/agentcore/{self.agent_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Memory operations log group
        log_groups["memory"] = logs.LogGroup(
            self,
            "AgentCoreMemoryLogGroup",
            log_group_name=f"/aws/bedrock/agentcore/memory/{self.agent_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Gateway operations log group
        log_groups["gateway"] = logs.LogGroup(
            self,
            "AgentCoreGatewayLogGroup",
            log_group_name=f"/aws/bedrock/agentcore/gateway/{self.agent_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_groups

    def _create_performance_lambda(self) -> lambda_.Function:
        """Create Lambda function for performance monitoring and optimization."""
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "LambdaPerformanceMonitorRole",
            role_name=f"LambdaPerformanceMonitorRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchReadOnlyAccess"
                )
            ]
        )
        
        # Grant S3 permissions to Lambda role
        self.monitoring_bucket.grant_read_write(lambda_role)
        
        # Create Lambda function
        performance_lambda = lambda_.Function(
            self,
            "PerformanceMonitoringFunction",
            function_name=f"agent-performance-optimizer-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            environment={
                "AGENT_NAME": self.agent_name,
                "S3_BUCKET_NAME": self.monitoring_bucket.bucket_name
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import os
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    \"\"\"
    Monitor AgentCore performance metrics and trigger optimization actions
    \"\"\"
    try:
        # Handle direct CloudWatch alarm format
        if 'Records' in event:
            # SNS message format
            message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = message.get('AlarmName', 'Unknown')
            alarm_description = message.get('AlarmDescription', '')
            new_state = message.get('NewStateValue', 'UNKNOWN')
        else:
            # Direct invocation format
            alarm_name = event.get('AlarmName', 'TestAlarm')
            alarm_description = event.get('AlarmDescription', 'Test alarm')
            new_state = event.get('NewStateValue', 'ALARM')
        
        # Get performance metrics for the last 5 minutes
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Query AgentCore metrics
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/BedrockAgentCore',
                MetricName='Latency',
                Dimensions=[
                    {'Name': 'AgentId', 'Value': os.environ['AGENT_NAME']}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=60,
                Statistics=['Average', 'Maximum']
            )
        except Exception as metric_error:
            print(f"Warning: Could not retrieve metrics - {str(metric_error)}")
            response = {'Datapoints': []}
        
        # Analyze performance and create report
        performance_report = {
            'timestamp': end_time.isoformat(),
            'alarm_triggered': alarm_name,
            'alarm_description': alarm_description,
            'new_state': new_state,
            'metrics': response['Datapoints'],
            'optimization_actions': []
        }
        
        # Add optimization recommendations based on metrics
        if response['Datapoints']:
            avg_latency = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            max_latency = max((dp['Maximum'] for dp in response['Datapoints']), default=0)
            
            if avg_latency > 30000:  # 30 seconds
                performance_report['optimization_actions'].append({
                    'action': 'increase_memory_allocation',
                    'reason': f'High average latency detected: {avg_latency:.2f}ms'
                })
            
            if max_latency > 60000:  # 60 seconds
                performance_report['optimization_actions'].append({
                    'action': 'investigate_timeout_issues',
                    'reason': f'Maximum latency threshold exceeded: {max_latency:.2f}ms'
                })
        else:
            performance_report['optimization_actions'].append({
                'action': 'verify_agent_health',
                'reason': 'No metric data available for analysis'
            })
        
        # Store performance report in S3
        report_key = f"performance-reports/{datetime.now().strftime('%Y/%m/%d')}/{alarm_name}-{context.aws_request_id}.json"
        s3.put_object(
            Bucket=os.environ['S3_BUCKET_NAME'],
            Key=report_key,
            Body=json.dumps(performance_report, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'report_location': f"s3://{os.environ['S3_BUCKET_NAME']}/{report_key}",
                'optimization_actions': len(performance_report['optimization_actions'])
            })
        }
        
    except Exception as e:
        print(f"Error processing performance alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
""")
        )
        
        return performance_lambda

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create comprehensive CloudWatch dashboard for agent performance visualization."""
        dashboard = cloudwatch.Dashboard(
            self,
            "AgentCorePerformanceDashboard",
            dashboard_name=f"AgentCore-Performance-{self.random_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Agent Performance Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/BedrockAgentCore",
                                metric_name="Latency",
                                dimensions_map={"AgentId": self.agent_name},
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/BedrockAgentCore",
                                metric_name="Invocations",
                                dimensions_map={"AgentId": self.agent_name},
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/BedrockAgentCore",
                                metric_name="SessionCount",
                                dimensions_map={"AgentId": self.agent_name},
                                statistic="Average"
                            )
                        ],
                        width=12,
                        height=6,
                        period=Duration.minutes(5)
                    ),
                    cloudwatch.GraphWidget(
                        title="Error and Throttle Rates",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/BedrockAgentCore",
                                metric_name="UserErrors",
                                dimensions_map={"AgentId": self.agent_name},
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/BedrockAgentCore",
                                metric_name="SystemErrors",
                                dimensions_map={"AgentId": self.agent_name},
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/BedrockAgentCore",
                                metric_name="Throttles",
                                dimensions_map={"AgentId": self.agent_name},
                                statistic="Sum"
                            )
                        ],
                        width=12,
                        height=6,
                        period=Duration.minutes(5)
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Recent Agent Errors",
                        log_groups=[self.log_groups["main"]],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /ERROR/",
                            "sort @timestamp desc",
                            "limit 20"
                        ],
                        width=24,
                        height=6
                    )
                ]
            ]
        )
        
        return dashboard

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """Create CloudWatch alarms for performance threshold monitoring."""
        alarms = {}
        
        # High latency alarm
        alarms["high_latency"] = cloudwatch.Alarm(
            self,
            "AgentCoreHighLatencyAlarm",
            alarm_name=f"AgentCore-HighLatency-{self.random_suffix}",
            alarm_description="Alert when agent latency exceeds 30 seconds",
            metric=cloudwatch.Metric(
                namespace="AWS/BedrockAgentCore",
                metric_name="Latency",
                dimensions_map={"AgentId": self.agent_name},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=30000,  # 30 seconds in milliseconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        
        # High system errors alarm
        alarms["high_system_errors"] = cloudwatch.Alarm(
            self,
            "AgentCoreHighSystemErrorsAlarm",
            alarm_name=f"AgentCore-HighSystemErrors-{self.random_suffix}",
            alarm_description="Alert when system errors exceed threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/BedrockAgentCore",
                metric_name="SystemErrors",
                dimensions_map={"AgentId": self.agent_name},
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # High throttles alarm
        alarms["high_throttles"] = cloudwatch.Alarm(
            self,
            "AgentCoreHighThrottlesAlarm",
            alarm_name=f"AgentCore-HighThrottles-{self.random_suffix}",
            alarm_description="Alert when throttling occurs frequently",
            metric=cloudwatch.Metric(
                namespace="AWS/BedrockAgentCore",
                metric_name="Throttles",
                dimensions_map={"AgentId": self.agent_name},
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=10,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add Lambda function as alarm action
        for alarm in alarms.values():
            alarm.add_alarm_action(
                cloudwatch.SnsAction.create(
                    lambda_.Function.from_function_arn(
                        self,
                        f"LambdaAction{alarm.alarm_name}",
                        self.performance_lambda.function_arn
                    )
                )
            )
        
        # Grant CloudWatch permission to invoke Lambda
        self.performance_lambda.add_permission(
            "AllowCloudWatchAlarms",
            principal=iam.ServicePrincipal("cloudwatch.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_account=self.account
        )
        
        return alarms

    def _create_custom_metrics(self) -> None:
        """Create custom metric filters for advanced analytics."""
        # Agent response time metric filter
        logs.MetricFilter(
            self,
            "AgentResponseTimeMetricFilter",
            log_group=self.log_groups["main"],
            filter_pattern=logs.FilterPattern.literal(
                '[timestamp, requestId, level=INFO, metric="response_time", value]'
            ),
            metric_namespace="CustomAgentMetrics",
            metric_name="AgentResponseTime",
            metric_value="$value",
            default_value=0
        )
        
        # Conversation quality score metric filter
        logs.MetricFilter(
            self,
            "ConversationQualityMetricFilter",
            log_group=self.log_groups["main"],
            filter_pattern=logs.FilterPattern.literal(
                '[timestamp, requestId, level=INFO, metric="quality_score", score]'
            ),
            metric_namespace="CustomAgentMetrics",
            metric_name="ConversationQuality",
            metric_value="$score",
            default_value=0
        )
        
        # Business outcome success metric filter
        logs.MetricFilter(
            self,
            "BusinessOutcomeMetricFilter",
            log_group=self.log_groups["main"],
            filter_pattern=logs.FilterPattern.literal(
                '[timestamp, requestId, level=INFO, outcome="SUCCESS"]'
            ),
            metric_namespace="CustomAgentMetrics",
            metric_name="BusinessOutcomeSuccess",
            metric_value="1",
            default_value=0
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "AgentCoreRoleArn",
            description="ARN of the AgentCore IAM role with observability permissions",
            value=self.agentcore_role.role_arn,
            export_name=f"{self.stack_name}-AgentCoreRoleArn"
        )
        
        CfnOutput(
            self,
            "MonitoringBucketName",
            description="S3 bucket name for storing monitoring data",
            value=self.monitoring_bucket.bucket_name,
            export_name=f"{self.stack_name}-MonitoringBucketName"
        )
        
        CfnOutput(
            self,
            "PerformanceLambdaFunctionName",
            description="Lambda function name for performance monitoring",
            value=self.performance_lambda.function_name,
            export_name=f"{self.stack_name}-PerformanceLambdaFunctionName"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            description="CloudWatch dashboard URL for performance visualization",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            export_name=f"{self.stack_name}-DashboardUrl"
        )
        
        CfnOutput(
            self,
            "MainLogGroupName",
            description="Main CloudWatch log group for AgentCore",
            value=self.log_groups["main"].log_group_name,
            export_name=f"{self.stack_name}-MainLogGroupName"
        )


def main():
    """Main entry point for the CDK application."""
    app = App()
    
    # Get AWS environment from context or environment variables
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )
    
    # Create the stack
    PerformanceMonitoringStack(
        app,
        "PerformanceMonitoringStack",
        env=env,
        description="Performance Monitoring AI Agents with AgentCore and CloudWatch",
        tags={
            "Project": "AgentCore-Performance-Monitoring",
            "Environment": "Development",
            "Owner": "AI-Team"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()