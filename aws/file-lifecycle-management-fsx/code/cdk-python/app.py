#!/usr/bin/env python3
"""
CDK Python application for implementing automated file lifecycle management
with Amazon FSx Intelligent-Tiering and Lambda.

This application creates a comprehensive solution for managing file lifecycle
in Amazon FSx for OpenZFS using serverless automation.
"""

import os
from aws_cdk import (
    App,
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_fsx as fsx,
    aws_lambda as _lambda,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_sns as sns,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_ec2 as ec2,
    aws_logs as logs,
)
from constructs import Construct


class FsxLifecycleManagementStack(Stack):
    """
    Stack for implementing automated file lifecycle management with Amazon FSx
    Intelligent-Tiering and Lambda automation.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for storing cost reports
        self.reports_bucket = s3.Bucket(
            self, "FsxLifecycleReportsBucket",
            bucket_name=f"fsx-lifecycle-reports-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create SNS topic for notifications
        self.notification_topic = sns.Topic(
            self, "FsxLifecycleAlerts",
            topic_name="fsx-lifecycle-alerts",
            display_name="FSx Lifecycle Management Alerts",
        )

        # Get default VPC or create one
        self.vpc = ec2.Vpc.from_lookup(
            self, "DefaultVPC",
            is_default=True
        )

        # Create security group for FSx
        self.fsx_security_group = ec2.SecurityGroup(
            self, "FsxSecurityGroup",
            vpc=self.vpc,
            description="Security group for FSx file system",
            allow_all_outbound=False,
        )

        # Add NFS rule to security group
        self.fsx_security_group.add_ingress_rule(
            peer=self.fsx_security_group,
            connection=ec2.Port.tcp(2049),
            description="NFS access within security group"
        )

        # Create FSx for OpenZFS file system
        self.create_fsx_file_system()

        # Create IAM role for Lambda functions
        self.lambda_role = self.create_lambda_role()

        # Create Lambda functions
        self.lifecycle_policy_function = self.create_lifecycle_policy_function()
        self.cost_reporting_function = self.create_cost_reporting_function()
        self.alert_handler_function = self.create_alert_handler_function()

        # Create EventBridge rules for scheduled execution
        self.create_eventbridge_rules()

        # Create CloudWatch alarms for FSx monitoring
        self.create_cloudwatch_alarms()

        # Create CloudWatch dashboard
        self.create_dashboard()

        # Subscribe alert handler to SNS topic
        self.notification_topic.add_subscription(
            sns.LambdaSubscription(self.alert_handler_function)
        )

        # Create outputs
        self.create_outputs()

    def create_fsx_file_system(self) -> None:
        """Create Amazon FSx for OpenZFS file system with intelligent tiering configuration."""
        # Get first available subnet in the VPC
        subnet = self.vpc.private_subnets[0] if self.vpc.private_subnets else self.vpc.public_subnets[0]

        # Create FSx file system
        self.fsx_file_system = fsx.CfnFileSystem(
            self, "FsxOpenZfsFileSystem",
            file_system_type="OpenZFS",
            storage_capacity=64,  # Minimum for OpenZFS
            storage_type="SSD",
            subnet_ids=[subnet.subnet_id],
            security_group_ids=[self.fsx_security_group.security_group_id],
            open_zfs_configuration=fsx.CfnFileSystem.OpenZFSConfigurationProperty(
                throughput_capacity=64,  # Minimum throughput
                automatic_backup_retention_days=7,
                copy_tags_to_backups=True,
                copy_tags_to_volumes=True,
                daily_automatic_backup_start_time="03:00",
                deployment_type="SINGLE_AZ_1",
                weekly_maintenance_start_time="1:05:00",
                disk_iops_configuration=fsx.CfnFileSystem.DiskIopsConfigurationProperty(
                    mode="AUTOMATIC"
                ),
            ),
            tags=[
                {
                    "key": "Name",
                    "value": "FSx-Lifecycle-Management"
                },
                {
                    "key": "Purpose",
                    "value": "Automated lifecycle management demo"
                }
            ]
        )

    def create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with necessary permissions."""
        role = iam.Role(
            self, "FsxLifecycleLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "FsxLifecyclePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "fsx:DescribeFileSystems",
                                "fsx:DescribeVolumes",
                                "fsx:PutFileSystemPolicy",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:PutMetricData",
                                "sns:Publish",
                                "s3:PutObject",
                                "s3:GetObject",
                            ],
                            resources=["*"],
                        )
                    ]
                )
            },
        )

        return role

    def create_lifecycle_policy_function(self) -> _lambda.Function:
        """Create Lambda function for lifecycle policy management."""
        function = _lambda.Function(
            self, "FsxLifecyclePolicyFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lifecycle_policy_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "FSX_FILE_SYSTEM_ID": self.fsx_file_system.ref,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Monitor FSx metrics and adjust lifecycle policies based on access patterns",
        )

        return function

    def create_cost_reporting_function(self) -> _lambda.Function:
        """Create Lambda function for cost reporting and analysis."""
        function = _lambda.Function(
            self, "FsxCostReportingFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_cost_reporting_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(2),
            memory_size=512,
            environment={
                "S3_BUCKET_NAME": self.reports_bucket.bucket_name,
                "FSX_FILE_SYSTEM_ID": self.fsx_file_system.ref,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Generate cost optimization reports for FSx file systems",
        )

        return function

    def create_alert_handler_function(self) -> _lambda.Function:
        """Create Lambda function for handling CloudWatch alarms."""
        function = _lambda.Function(
            self, "FsxAlertHandlerFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_alert_handler_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "FSX_FILE_SYSTEM_ID": self.fsx_file_system.ref,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Handle CloudWatch alarms and provide intelligent analysis",
        )

        return function

    def create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for scheduled Lambda execution."""
        # Rule for periodic lifecycle policy analysis
        lifecycle_rule = events.Rule(
            self, "FsxLifecyclePolicySchedule",
            schedule=events.Schedule.rate(Duration.hours(1)),
            description="Trigger lifecycle policy analysis every hour",
        )

        lifecycle_rule.add_target(
            targets.LambdaFunction(self.lifecycle_policy_function)
        )

        # Rule for daily cost reporting
        cost_reporting_rule = events.Rule(
            self, "FsxCostReportingSchedule",
            schedule=events.Schedule.rate(Duration.hours(24)),
            description="Generate cost reports daily",
        )

        cost_reporting_rule.add_target(
            targets.LambdaFunction(self.cost_reporting_function)
        )

    def create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for FSx monitoring."""
        # Alarm for low cache hit ratio
        low_cache_alarm = cloudwatch.Alarm(
            self, "FsxLowCacheHitRatio",
            metric=cloudwatch.Metric(
                namespace="AWS/FSx",
                metric_name="FileServerCacheHitRatio",
                dimensions_map={
                    "FileSystemId": self.fsx_file_system.ref
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=70,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            alarm_description="Alert when FSx cache hit ratio is below 70%",
        )

        low_cache_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )

        # Alarm for high storage utilization
        high_storage_alarm = cloudwatch.Alarm(
            self, "FsxHighStorageUtilization",
            metric=cloudwatch.Metric(
                namespace="AWS/FSx",
                metric_name="StorageUtilization",
                dimensions_map={
                    "FileSystemId": self.fsx_file_system.ref
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=85,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            alarm_description="Alert when FSx storage utilization exceeds 85%",
        )

        high_storage_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )

        # Alarm for high network throughput utilization
        high_network_alarm = cloudwatch.Alarm(
            self, "FsxHighNetworkUtilization",
            metric=cloudwatch.Metric(
                namespace="AWS/FSx",
                metric_name="NetworkThroughputUtilization",
                dimensions_map={
                    "FileSystemId": self.fsx_file_system.ref
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=90,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            alarm_description="Alert when FSx network utilization exceeds 90%",
        )

        high_network_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )

    def create_dashboard(self) -> None:
        """Create CloudWatch dashboard for FSx monitoring."""
        dashboard = cloudwatch.Dashboard(
            self, "FsxLifecycleDashboard",
            dashboard_name="FSx-Lifecycle-Management",
        )

        # Performance metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="FSx Performance Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/FSx",
                        metric_name="FileServerCacheHitRatio",
                        dimensions_map={
                            "FileSystemId": self.fsx_file_system.ref
                        },
                        label="Cache Hit Ratio (%)"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/FSx",
                        metric_name="StorageUtilization",
                        dimensions_map={
                            "FileSystemId": self.fsx_file_system.ref
                        },
                        label="Storage Utilization (%)"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/FSx",
                        metric_name="NetworkThroughputUtilization",
                        dimensions_map={
                            "FileSystemId": self.fsx_file_system.ref
                        },
                        label="Network Utilization (%)"
                    ),
                ],
                width=12,
                height=6,
            )
        )

        # Data transfer metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="FSx Data Transfer",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/FSx",
                        metric_name="DataReadBytes",
                        dimensions_map={
                            "FileSystemId": self.fsx_file_system.ref
                        },
                        label="Data Read Bytes",
                        statistic="Sum"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/FSx",
                        metric_name="DataWriteBytes",
                        dimensions_map={
                            "FileSystemId": self.fsx_file_system.ref
                        },
                        label="Data Write Bytes",
                        statistic="Sum"
                    ),
                ],
                width=12,
                height=6,
            )
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "FsxFileSystemId",
            value=self.fsx_file_system.ref,
            description="FSx file system ID",
            export_name=f"{self.stack_name}-FsxFileSystemId",
        )

        CfnOutput(
            self, "FsxDnsName",
            value=self.fsx_file_system.attr_dns_name,
            description="FSx file system DNS name",
            export_name=f"{self.stack_name}-FsxDnsName",
        )

        CfnOutput(
            self, "ReportsBucketName",
            value=self.reports_bucket.bucket_name,
            description="S3 bucket for cost reports",
            export_name=f"{self.stack_name}-ReportsBucket",
        )

        CfnOutput(
            self, "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications",
            export_name=f"{self.stack_name}-NotificationTopic",
        )

        CfnOutput(
            self, "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=FSx-Lifecycle-Management",
            description="CloudWatch dashboard URL",
        )

    def _get_lifecycle_policy_code(self) -> str:
        """Get the Lambda function code for lifecycle policy management."""
        return """
import json
import boto3
import datetime
from typing import Dict, List

def lambda_handler(event, context):
    \"\"\"
    Monitor FSx metrics and adjust lifecycle policies based on access patterns
    \"\"\"
    fsx_client = boto3.client('fsx')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Get FSx file system information
        file_systems = fsx_client.describe_file_systems()
        
        for fs in file_systems['FileSystems']:
            if fs['FileSystemType'] == 'OpenZFS':
                fs_id = fs['FileSystemId']
                
                # Get cache hit ratio metric
                cache_metrics = get_cache_metrics(cloudwatch, fs_id)
                
                # Get storage utilization metrics
                storage_metrics = get_storage_metrics(cloudwatch, fs_id)
                
                # Analyze access patterns
                recommendations = analyze_access_patterns(cache_metrics, storage_metrics)
                
                # Send recommendations via SNS
                send_notifications(sns, fs_id, recommendations)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Lifecycle policy analysis completed')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def get_cache_metrics(cloudwatch, file_system_id: str) -> Dict:
    \"\"\"Get FSx cache hit ratio metrics\"\"\"
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='FileServerCacheHitRatio',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        return response['Datapoints']
    except Exception as e:
        print(f"Error getting cache metrics: {e}")
        return []

def get_storage_metrics(cloudwatch, file_system_id: str) -> Dict:
    \"\"\"Get FSx storage utilization metrics\"\"\"
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='StorageUtilization',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        return response['Datapoints']
    except Exception as e:
        print(f"Error getting storage metrics: {e}")
        return []

def analyze_access_patterns(cache_metrics: List[Dict], storage_metrics: List[Dict]) -> Dict:
    \"\"\"Analyze metrics to generate recommendations\"\"\"
    recommendations = {
        'cache_recommendation': 'No data available',
        'storage_recommendation': 'No data available',
        'actions': []
    }
    
    # Analyze cache hit ratio
    if cache_metrics:
        avg_cache_hit = sum(point['Average'] for point in cache_metrics) / len(cache_metrics)
        recommendations['cache_hit_ratio'] = avg_cache_hit
        
        if avg_cache_hit < 70:
            recommendations['cache_recommendation'] = 'Consider increasing SSD cache size'
            recommendations['actions'].append('scale_cache')
        elif avg_cache_hit > 95:
            recommendations['cache_recommendation'] = 'Cache size may be oversized'
            recommendations['actions'].append('optimize_cache')
        else:
            recommendations['cache_recommendation'] = 'Cache performance optimal'
            recommendations['actions'].append('maintain')
    
    # Analyze storage utilization
    if storage_metrics:
        avg_storage = sum(point['Average'] for point in storage_metrics) / len(storage_metrics)
        recommendations['storage_utilization'] = avg_storage
        
        if avg_storage > 85:
            recommendations['storage_recommendation'] = 'High storage utilization detected'
            recommendations['actions'].append('monitor_capacity')
        elif avg_storage < 30:
            recommendations['storage_recommendation'] = 'Low storage utilization - consider downsizing'
            recommendations['actions'].append('optimize_capacity')
        else:
            recommendations['storage_recommendation'] = 'Storage utilization optimal'
    
    return recommendations

def send_notifications(sns, file_system_id: str, recommendations: Dict):
    \"\"\"Send recommendations via SNS\"\"\"
    import os
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if topic_arn:
        message = f\"\"\"
        FSx File System: {file_system_id}
        
        Cache Recommendation: {recommendations['cache_recommendation']}
        Storage Recommendation: {recommendations['storage_recommendation']}
        
        Cache Hit Ratio: {recommendations.get('cache_hit_ratio', 'N/A')}%
        Storage Utilization: {recommendations.get('storage_utilization', 'N/A')}%
        
        Suggested Actions: {', '.join(recommendations.get('actions', []))}
        \"\"\"
        
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject='FSx Lifecycle Policy Recommendation'
        )
"""

    def _get_cost_reporting_code(self) -> str:
        """Get the Lambda function code for cost reporting."""
        return """
import json
import boto3
import datetime
import csv
from io import StringIO

def lambda_handler(event, context):
    \"\"\"
    Generate cost optimization reports for FSx file systems
    \"\"\"
    fsx_client = boto3.client('fsx')
    cloudwatch = boto3.client('cloudwatch')
    s3 = boto3.client('s3')
    
    try:
        # Get FSx file systems
        file_systems = fsx_client.describe_file_systems()
        
        for fs in file_systems['FileSystems']:
            if fs['FileSystemType'] == 'OpenZFS':
                fs_id = fs['FileSystemId']
                
                # Collect usage metrics
                usage_data = collect_usage_metrics(cloudwatch, fs_id)
                
                # Generate cost report
                report = generate_cost_report(fs, usage_data)
                
                # Save report to S3
                save_report_to_s3(s3, fs_id, report)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Cost reports generated successfully')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def collect_usage_metrics(cloudwatch, file_system_id: str) -> dict:
    \"\"\"Collect various usage metrics for cost analysis\"\"\"
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(days=7)
    
    metrics = {}
    
    # Storage capacity and utilization metrics
    for metric_name in ['StorageUtilization', 'FileServerCacheHitRatio']:
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/FSx',
                MetricName=metric_name,
                Dimensions=[
                    {
                        'Name': 'FileSystemId',
                        'Value': file_system_id
                    }
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,
                Statistics=['Average']
            )
            metrics[metric_name] = response['Datapoints']
        except Exception as e:
            print(f"Error collecting {metric_name}: {e}")
            metrics[metric_name] = []
    
    return metrics

def generate_cost_report(file_system: dict, usage_data: dict) -> dict:
    \"\"\"Generate comprehensive cost optimization report\"\"\"
    fs_id = file_system['FileSystemId']
    storage_capacity = file_system['StorageCapacity']
    throughput_capacity = file_system['OpenZFSConfiguration']['ThroughputCapacity']
    
    # Calculate estimated costs based on current pricing
    # Base throughput cost: approximately $0.30 per MBps/month
    base_throughput_cost = throughput_capacity * 0.30
    
    # Storage cost: approximately $0.15 per GiB/month for SSD
    storage_cost = storage_capacity * 0.15
    
    monthly_cost = base_throughput_cost + storage_cost
    
    # Storage efficiency analysis
    storage_metrics = usage_data.get('StorageUtilization', [])
    avg_utilization = 0
    if storage_metrics:
        avg_utilization = sum(point['Average'] for point in storage_metrics) / len(storage_metrics)
    
    # Cache performance analysis
    cache_metrics = usage_data.get('FileServerCacheHitRatio', [])
    avg_cache_hit = 0
    if cache_metrics:
        avg_cache_hit = sum(point['Average'] for point in cache_metrics) / len(cache_metrics)
    
    report = {
        'file_system_id': fs_id,
        'report_date': datetime.datetime.utcnow().isoformat(),
        'storage_capacity_gb': storage_capacity,
        'throughput_capacity_mbps': throughput_capacity,
        'estimated_monthly_cost': monthly_cost,
        'storage_efficiency': {
            'average_utilization': avg_utilization,
            'cache_hit_ratio': avg_cache_hit,
            'optimization_potential': max(0, 100 - avg_utilization)
        },
        'recommendations': []
    }
    
    # Generate recommendations
    if avg_utilization < 50:
        potential_savings = storage_capacity * 0.15 * 0.3  # 30% potential savings
        report['recommendations'].append({
            'type': 'storage_optimization',
            'description': 'Low storage utilization - consider reducing capacity',
            'potential_savings': f"${potential_savings:.2f}/month"
        })
    
    if avg_cache_hit < 70:
        report['recommendations'].append({
            'type': 'cache_optimization',
            'description': 'Low cache hit ratio - consider increasing cache size',
            'impact': 'Improved performance and reduced latency'
        })
    
    if avg_utilization > 90:
        report['recommendations'].append({
            'type': 'capacity_expansion',
            'description': 'High storage utilization - consider increasing capacity',
            'impact': 'Prevent capacity issues and maintain performance'
        })
    
    return report

def save_report_to_s3(s3, file_system_id: str, report: dict):
    \"\"\"Save cost report to S3\"\"\"
    import os
    
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    if not bucket_name:
        return
    
    # Create CSV report
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    
    writer.writerow(['Metric', 'Value'])
    writer.writerow(['File System ID', report['file_system_id']])
    writer.writerow(['Report Date', report['report_date']])
    writer.writerow(['Storage Capacity (GB)', report['storage_capacity_gb']])
    writer.writerow(['Throughput Capacity (MBps)', report['throughput_capacity_mbps']])
    writer.writerow(['Estimated Monthly Cost', f"${report['estimated_monthly_cost']:.2f}"])
    writer.writerow(['Average Utilization (%)', f"{report['storage_efficiency']['average_utilization']:.1f}"])
    writer.writerow(['Cache Hit Ratio (%)', f"{report['storage_efficiency']['cache_hit_ratio']:.1f}"])
    
    # Add recommendations
    writer.writerow([])
    writer.writerow(['Recommendations'])
    for rec in report['recommendations']:
        writer.writerow([rec['type'], rec['description']])
    
    # Save to S3
    timestamp = datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    key = f"cost-reports/{file_system_id}/report_{timestamp}.csv"
    
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=csv_buffer.getvalue(),
        ContentType='text/csv'
    )
    
    print(f"Report saved to s3://{bucket_name}/{key}")
"""

    def _get_alert_handler_code(self) -> str:
        """Get the Lambda function code for alert handling."""
        return """
import json
import boto3
import urllib.parse

def lambda_handler(event, context):
    \"\"\"
    Handle CloudWatch alarms and provide intelligent analysis
    \"\"\"
    fsx_client = boto3.client('fsx')
    sns = boto3.client('sns')
    
    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message['AlarmName']
        new_state = sns_message['NewStateValue']
        
        if new_state == 'ALARM':
            if 'Low-Cache-Hit-Ratio' in alarm_name:
                handle_low_cache_hit_ratio(fsx_client, sns, alarm_name)
            elif 'High-Storage-Utilization' in alarm_name:
                handle_high_storage_utilization(fsx_client, sns, alarm_name)
            elif 'High-Network-Utilization' in alarm_name:
                handle_high_network_utilization(fsx_client, sns, alarm_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Alert processed successfully')
        }
        
    except Exception as e:
        print(f"Error processing alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_low_cache_hit_ratio(fsx_client, sns, alarm_name):
    \"\"\"Handle low cache hit ratio alarm\"\"\"
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    # Get throughput configuration
    throughput_capacity = fs['OpenZFSConfiguration']['ThroughputCapacity']
    
    message = f\"\"\"
    Performance Alert: Low Cache Hit Ratio Detected
    
    File System: {fs_id}
    Throughput Capacity: {throughput_capacity} MBps
    
    Recommendations:
    1. Consider increasing throughput capacity to improve cache performance
    2. Analyze workload patterns to optimize access patterns
    3. Review client access patterns for optimization opportunities
    
    Impact: Low cache hit ratio may indicate increased latency and reduced throughput
    
    Next Steps: Review FSx performance metrics and consider performance optimization
    \"\"\"
    
    send_notification(sns, message, 'FSx Cache Performance Alert')

def handle_high_storage_utilization(fsx_client, sns, alarm_name):
    \"\"\"Handle high storage utilization alarm\"\"\"
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    storage_capacity = fs['StorageCapacity']
    
    message = f\"\"\"
    Capacity Alert: High Storage Utilization Detected
    
    File System: {fs_id}
    Storage Capacity: {storage_capacity} GiB
    Utilization: Above 85% threshold
    
    Recommendations:
    1. Review data retention policies and archive old files
    2. Consider increasing storage capacity if needed
    3. Implement file lifecycle management policies
    4. Analyze storage usage patterns for optimization
    
    Impact: High utilization may affect performance and prevent new file creation
    
    Next Steps: Review storage usage and plan capacity expansion if needed
    \"\"\"
    
    send_notification(sns, message, 'FSx Storage Capacity Alert')

def handle_high_network_utilization(fsx_client, sns, alarm_name):
    \"\"\"Handle high network utilization alarm\"\"\"
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    throughput_capacity = fs['OpenZFSConfiguration']['ThroughputCapacity']
    
    message = f\"\"\"
    Performance Alert: High Network Utilization Detected
    
    File System: {fs_id}
    Throughput Capacity: {throughput_capacity} MBps
    Utilization: Above 90% threshold
    
    Recommendations:
    1. Consider increasing throughput capacity for better performance
    2. Optimize client access patterns and connection pooling
    3. Review workload distribution across multiple clients
    4. Implement caching strategies at the client level
    
    Impact: High network utilization may cause performance bottlenecks
    
    Next Steps: Monitor performance trends and consider scaling throughput capacity
    \"\"\"
    
    send_notification(sns, message, 'FSx Network Performance Alert')

def get_file_system_id():
    \"\"\"Get file system ID from environment\"\"\"
    import os
    return os.environ.get('FSX_FILE_SYSTEM_ID', 'unknown')

def send_notification(sns, message, subject):
    \"\"\"Send notification via SNS\"\"\"
    import os
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if topic_arn:
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=subject
        )
"""


# CDK App
app = App()

# Create the stack
FsxLifecycleManagementStack(
    app, "FsxLifecycleManagementStack",
    env=Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION")
    ),
    description="Automated file lifecycle management with Amazon FSx Intelligent-Tiering and Lambda"
)

app.synth()