#!/usr/bin/env python3
"""
AWS CDK Python application for VPC Flow Logs Network Monitoring

This application creates a comprehensive network monitoring solution using VPC Flow Logs
integrated with CloudWatch for real-time alerting, S3 for cost-effective storage,
and Athena for advanced analytics.

Architecture Components:
- VPC Flow Logs with dual destinations (CloudWatch Logs and S3)
- CloudWatch custom metrics and alarms for automated alerting
- S3 bucket with lifecycle policies for cost optimization
- Lambda function for advanced anomaly detection
- SNS topic for notification distribution
- Athena workgroup for advanced analytics
- CloudWatch dashboard for visualization
"""

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    aws_ec2 as ec2,
    aws_s3 as s3,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_lambda as lambda_,
    aws_athena as athena,
    aws_events as events,
    aws_events_targets as targets,
    CfnOutput,
)
from constructs import Construct
import json


class NetworkMonitoringStack(Stack):
    """
    CDK Stack for VPC Flow Logs Network Monitoring Solution
    
    This stack creates a comprehensive network monitoring system that:
    - Captures VPC Flow Logs for network traffic analysis
    - Provides real-time alerting through CloudWatch
    - Stores data cost-effectively in S3
    - Enables advanced analytics with Athena
    - Sends notifications via SNS
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get the default VPC or create monitoring VPC
        vpc = self._get_or_create_vpc()
        
        # Create S3 bucket for flow logs storage
        flow_logs_bucket = self._create_flow_logs_bucket()
        
        # Create IAM role for VPC Flow Logs
        flow_logs_role = self._create_flow_logs_role()
        
        # Create CloudWatch Log Group
        log_group = self._create_log_group()
        
        # Create SNS topic for alerting
        sns_topic = self._create_sns_topic()
        
        # Create VPC Flow Logs with dual destinations
        self._create_vpc_flow_logs(vpc, log_group, flow_logs_bucket, flow_logs_role)
        
        # Create custom CloudWatch metrics and alarms
        self._create_cloudwatch_metrics_and_alarms(log_group, sns_topic)
        
        # Create Lambda function for advanced analysis
        lambda_function = self._create_anomaly_detection_lambda(sns_topic)
        
        # Create subscription filter for Lambda
        self._create_log_subscription(log_group, lambda_function)
        
        # Create Athena workgroup for analytics
        athena_workgroup = self._create_athena_workgroup(flow_logs_bucket)
        
        # Create CloudWatch dashboard
        self._create_dashboard(log_group)
        
        # Add outputs
        self._add_outputs(vpc, flow_logs_bucket, log_group, sns_topic, athena_workgroup)

    def _get_or_create_vpc(self) -> ec2.IVpc:
        """Get the default VPC or create a new one for monitoring"""
        try:
            # Try to use the default VPC
            vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)
            return vpc
        except:
            # If no default VPC exists, create a new one
            vpc = ec2.Vpc(
                self, "MonitoringVPC",
                ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
                max_azs=2,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        name="Public",
                        subnet_type=ec2.SubnetType.PUBLIC,
                        cidr_mask=24
                    ),
                    ec2.SubnetConfiguration(
                        name="Private",
                        subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                        cidr_mask=24
                    )
                ],
                enable_dns_hostnames=True,
                enable_dns_support=True
            )
            
            # Add tags for identification
            cdk.Tags.of(vpc).add("Purpose", "NetworkMonitoring")
            return vpc

    def _create_flow_logs_bucket(self) -> s3.Bucket:
        """Create S3 bucket for VPC Flow Logs storage with cost optimization"""
        bucket = s3.Bucket(
            self, "VPCFlowLogsBucket",
            bucket_name=f"vpc-flow-logs-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="FlowLogsLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        )
                    ],
                    expiration=Duration.days(2555)  # 7 years for compliance
                )
            ]
        )
        
        # Add tags for cost tracking
        cdk.Tags.of(bucket).add("Purpose", "NetworkMonitoring")
        cdk.Tags.of(bucket).add("DataType", "VPCFlowLogs")
        
        return bucket

    def _create_flow_logs_role(self) -> iam.Role:
        """Create IAM role for VPC Flow Logs service"""
        role = iam.Role(
            self, "VPCFlowLogsRole",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            description="Role for VPC Flow Logs to write to CloudWatch Logs",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/VPCFlowLogsDeliveryRolePolicy"
                )
            ]
        )
        
        return role

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch Log Group for VPC Flow Logs"""
        log_group = logs.LogGroup(
            self, "VPCFlowLogsGroup",
            log_group_name="/aws/vpc/flowlogs",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Add tags
        cdk.Tags.of(log_group).add("Purpose", "NetworkMonitoring")
        cdk.Tags.of(log_group).add("Environment", "Production")
        
        return log_group

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for network monitoring alerts"""
        topic = sns.Topic(
            self, "NetworkMonitoringAlerts",
            topic_name="network-monitoring-alerts",
            display_name="Network Monitoring Alerts",
            description="SNS topic for VPC Flow Logs network monitoring alerts"
        )
        
        return topic

    def _create_vpc_flow_logs(
        self, 
        vpc: ec2.IVpc, 
        log_group: logs.LogGroup, 
        bucket: s3.Bucket, 
        role: iam.Role
    ) -> None:
        """Create VPC Flow Logs with dual destinations"""
        
        # Flow logs to CloudWatch for real-time monitoring
        cloudwatch_flow_log = ec2.FlowLog(
            self, "VPCFlowLogsCloudWatch",
            resource_type=ec2.FlowLogResourceType.from_vpc(vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(log_group, role),
            traffic_type=ec2.FlowLogTrafficType.ALL,
            max_aggregation_interval=ec2.FlowLogMaxAggregationInterval.ONE_MINUTE
        )
        
        # Flow logs to S3 for long-term storage and analytics
        s3_flow_log = ec2.FlowLog(
            self, "VPCFlowLogsS3",
            resource_type=ec2.FlowLogResourceType.from_vpc(vpc),
            destination=ec2.FlowLogDestination.to_s3(
                bucket, 
                "vpc-flow-logs/",
                log_format=ec2.FlowLogFormat.custom([
                    ec2.FlowLogField.VERSION,
                    ec2.FlowLogField.ACCOUNT_ID,
                    ec2.FlowLogField.INTERFACE_ID,
                    ec2.FlowLogField.SRCADDR,
                    ec2.FlowLogField.DSTADDR,
                    ec2.FlowLogField.SRCPORT,
                    ec2.FlowLogField.DSTPORT,
                    ec2.FlowLogField.PROTOCOL,
                    ec2.FlowLogField.PACKETS,
                    ec2.FlowLogField.BYTES,
                    ec2.FlowLogField.WINDOWSTART,
                    ec2.FlowLogField.WINDOWEND,
                    ec2.FlowLogField.ACTION,
                    ec2.FlowLogField.FLOWLOGSTATUS,
                    ec2.FlowLogField.VPC_ID,
                    ec2.FlowLogField.SUBNET_ID,
                    ec2.FlowLogField.INSTANCE_ID,
                    ec2.FlowLogField.TCP_FLAGS,
                    ec2.FlowLogField.TYPE,
                    ec2.FlowLogField.PKT_SRCADDR,
                    ec2.FlowLogField.PKT_DSTADDR
                ])
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
            max_aggregation_interval=ec2.FlowLogMaxAggregationInterval.ONE_MINUTE
        )

    def _create_cloudwatch_metrics_and_alarms(
        self, 
        log_group: logs.LogGroup, 
        sns_topic: sns.Topic
    ) -> None:
        """Create custom CloudWatch metrics and alarms for network monitoring"""
        
        # Metric filter for rejected connections
        rejected_connections_filter = logs.MetricFilter(
            self, "RejectedConnectionsFilter",
            log_group=log_group,
            metric_namespace="VPC/FlowLogs",
            metric_name="RejectedConnections",
            filter_pattern=logs.FilterPattern.space_delimited(
                "version", "account", "eni", "source", "destination", 
                "srcport", "destport", "protocol", "packets", "bytes", 
                "windowstart", "windowend", "action", "flowlogstatus"
            ).where_string("action").eq("REJECT"),
            metric_value="1"
        )
        
        # Metric filter for high data transfer
        high_data_transfer_filter = logs.MetricFilter(
            self, "HighDataTransferFilter",
            log_group=log_group,
            metric_namespace="VPC/FlowLogs",
            metric_name="HighDataTransfer",
            filter_pattern=logs.FilterPattern.space_delimited(
                "version", "account", "eni", "source", "destination", 
                "srcport", "destport", "protocol", "packets", "bytes", 
                "windowstart", "windowend", "action", "flowlogstatus"
            ).where_number("bytes").gt(10000000),  # >10MB
            metric_value="1"
        )
        
        # Metric filter for external connections
        external_connections_filter = logs.MetricFilter(
            self, "ExternalConnectionsFilter",
            log_group=log_group,
            metric_namespace="VPC/FlowLogs",
            metric_name="ExternalConnections",
            filter_pattern=logs.FilterPattern.literal(
                '[version, account, eni, source!="10.*" && source!="172.16.*" && source!="192.168.*", destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action, flowlogstatus]'
            ),
            metric_value="1"
        )
        
        # Alarm for excessive rejected connections
        rejected_connections_alarm = cloudwatch.Alarm(
            self, "HighRejectedConnectionsAlarm",
            alarm_name="VPC-High-Rejected-Connections",
            alarm_description="Alert when rejected connections exceed threshold",
            metric=cloudwatch.Metric(
                namespace="VPC/FlowLogs",
                metric_name="RejectedConnections",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=50,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        rejected_connections_alarm.add_alarm_action(
            cloudwatch.SnsAction(sns_topic)
        )
        
        # Alarm for high data transfer
        high_data_transfer_alarm = cloudwatch.Alarm(
            self, "HighDataTransferAlarm",
            alarm_name="VPC-High-Data-Transfer",
            alarm_description="Alert when high data transfer detected",
            metric=cloudwatch.Metric(
                namespace="VPC/FlowLogs",
                metric_name="HighDataTransfer",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=10,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        high_data_transfer_alarm.add_alarm_action(
            cloudwatch.SnsAction(sns_topic)
        )
        
        # Alarm for external connections
        external_connections_alarm = cloudwatch.Alarm(
            self, "ExternalConnectionsAlarm",
            alarm_name="VPC-External-Connections",
            alarm_description="Alert when external connections exceed threshold",
            metric=cloudwatch.Metric(
                namespace="VPC/FlowLogs",
                metric_name="ExternalConnections",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=100,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        external_connections_alarm.add_alarm_action(
            cloudwatch.SnsAction(sns_topic)
        )

    def _create_anomaly_detection_lambda(self, sns_topic: sns.Topic) -> lambda_.Function:
        """Create Lambda function for advanced network anomaly detection"""
        
        # Lambda function code
        lambda_code = '''
import json
import boto3
import gzip
import base64
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Advanced anomaly detection for VPC Flow Logs
    Analyzes log events and detects suspicious patterns
    """
    try:
        # Decode and decompress CloudWatch Logs data
        compressed_payload = base64.b64decode(event['awslogs']['data'])
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_data = json.loads(uncompressed_payload)
        
        anomalies = []
        
        for log_event in log_data['logEvents']:
            message = log_event['message']
            fields = message.split(' ')
            
            if len(fields) >= 14:
                srcaddr = fields[3]
                dstaddr = fields[4]
                srcport = fields[5]
                dstport = fields[6]
                protocol = fields[7]
                bytes_transferred = int(fields[9]) if fields[9].isdigit() else 0
                action = fields[12]
                
                # Detect potential anomalies
                if bytes_transferred > 50000000:  # >50MB
                    anomalies.append({
                        'type': 'high_data_transfer',
                        'source': srcaddr,
                        'destination': dstaddr,
                        'bytes': bytes_transferred,
                        'timestamp': log_event['timestamp']
                    })
                
                if action == 'REJECT' and protocol == '6':  # TCP rejects
                    anomalies.append({
                        'type': 'rejected_tcp',
                        'source': srcaddr,
                        'destination': dstaddr,
                        'port': dstport,
                        'timestamp': log_event['timestamp']
                    })
                
                # Detect port scanning (multiple rejected connections from same source)
                if action == 'REJECT' and srcaddr and dstport:
                    # This is a simplified check - in production, you'd maintain state
                    anomalies.append({
                        'type': 'potential_port_scan',
                        'source': srcaddr,
                        'destination': dstaddr,
                        'port': dstport,
                        'timestamp': log_event['timestamp']
                    })
        
        # Send notifications for anomalies
        if anomalies:
            sns = boto3.client('sns')
            message = f"Network anomalies detected:\\n{json.dumps(anomalies, indent=2)}"
            
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=message,
                Subject=f'Network Anomaly Alert - {len(anomalies)} anomalies detected'
            )
            
            print(f"Published {len(anomalies)} anomalies to SNS")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Analysis complete',
                'anomalies_detected': len(anomalies)
            })
        }
        
    except Exception as e:
        print(f"Error processing log event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''
        
        # Create Lambda function
        lambda_function = lambda_.Function(
            self, "NetworkAnomalyDetector",
            function_name="network-anomaly-detector",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            description="Advanced anomaly detection for VPC Flow Logs",
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": sns_topic.topic_arn
            }
        )
        
        # Grant permissions to publish to SNS
        sns_topic.grant_publish(lambda_function)
        
        return lambda_function

    def _create_log_subscription(
        self, 
        log_group: logs.LogGroup, 
        lambda_function: lambda_.Function
    ) -> None:
        """Create subscription filter to send logs to Lambda"""
        
        # Grant CloudWatch Logs permission to invoke Lambda
        lambda_function.add_permission(
            "AllowCloudWatchLogs",
            principal=iam.ServicePrincipal("logs.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"arn:aws:logs:{self.region}:{self.account}:log-group:{log_group.log_group_name}:*"
        )
        
        # Create subscription filter
        subscription_filter = logs.SubscriptionFilter(
            self, "LogSubscriptionFilter",
            log_group=log_group,
            destination=logs.LambdaDestination(lambda_function),
            filter_pattern=logs.FilterPattern.all_terms()
        )

    def _create_athena_workgroup(self, bucket: s3.Bucket) -> athena.CfnWorkGroup:
        """Create Athena workgroup for VPC Flow Logs analytics"""
        
        workgroup = athena.CfnWorkGroup(
            self, "VPCFlowLogsWorkGroup",
            name="vpc-flow-logs-workgroup",
            description="Workgroup for VPC Flow Logs analysis",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{bucket.bucket_name}/athena-results/"
                ),
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics=True
            )
        )
        
        return workgroup

    def _create_dashboard(self, log_group: logs.LogGroup) -> None:
        """Create CloudWatch dashboard for network monitoring visualization"""
        
        dashboard = cloudwatch.Dashboard(
            self, "NetworkMonitoringDashboard",
            dashboard_name="VPC-Flow-Logs-Monitoring",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Network Security Metrics",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="VPC/FlowLogs",
                                metric_name="RejectedConnections",
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="VPC/FlowLogs", 
                                metric_name="HighDataTransfer",
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="VPC/FlowLogs",
                                metric_name="ExternalConnections", 
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ]
                    ),
                    cloudwatch.LogQueryWidget(
                        title="Rejected Connections Over Time",
                        width=12,
                        height=6,
                        log_groups=[log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "| filter @message like /REJECT/",
                            "| stats count() by bin(5m)"
                        ]
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Top Source IPs by Traffic Volume",
                        width=12,
                        height=6,
                        log_groups=[log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "| parse @message /(?<srcaddr>\\d+\\.\\d+\\.\\d+\\.\\d+).*?(?<bytes>\\d+)/",
                            "| filter bytes > 1000000",
                            "| stats sum(bytes) as total_bytes by srcaddr",
                            "| sort total_bytes desc",
                            "| limit 10"
                        ]
                    ),
                    cloudwatch.LogQueryWidget(
                        title="Traffic by Protocol",
                        width=12,
                        height=6,
                        log_groups=[log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "| parse @message /.*?(\\d+).*?ACCEPT|REJECT/",
                            "| stats count() by protocol",
                            "| sort count desc"
                        ]
                    )
                ]
            ]
        )

    def _add_outputs(
        self,
        vpc: ec2.IVpc,
        bucket: s3.Bucket,
        log_group: logs.LogGroup,
        sns_topic: sns.Topic,
        athena_workgroup: athena.CfnWorkGroup
    ) -> None:
        """Add CloudFormation outputs for key resources"""
        
        CfnOutput(
            self, "VPCId",
            description="VPC ID being monitored",
            value=vpc.vpc_id
        )
        
        CfnOutput(
            self, "FlowLogsBucketName",
            description="S3 bucket storing VPC Flow Logs",
            value=bucket.bucket_name
        )
        
        CfnOutput(
            self, "LogGroupName",
            description="CloudWatch Log Group for VPC Flow Logs",
            value=log_group.log_group_name
        )
        
        CfnOutput(
            self, "SNSTopicArn",
            description="SNS topic for network monitoring alerts",
            value=sns_topic.topic_arn
        )
        
        CfnOutput(
            self, "AthenaWorkGroup",
            description="Athena workgroup for flow logs analytics",
            value=athena_workgroup.name
        )
        
        CfnOutput(
            self, "DashboardURL",
            description="CloudWatch dashboard URL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=VPC-Flow-Logs-Monitoring"
        )


# CDK App
app = cdk.App()

# Create the network monitoring stack
NetworkMonitoringStack(
    app, "NetworkMonitoringStack",
    description="VPC Flow Logs Network Monitoring Solution with CloudWatch, S3, and Athena",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

app.synth()