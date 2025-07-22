#!/usr/bin/env python3
"""
CDK Python application for Database Performance Monitoring with RDS Insights.

This application creates a comprehensive database performance monitoring system using:
- RDS MySQL instance with Performance Insights enabled
- Lambda functions for automated performance analysis
- CloudWatch alarms and custom metrics
- S3 storage for performance reports
- SNS notifications for alerts
- EventBridge scheduling for automation

Author: AWS CDK Generator
Version: 1.0.0
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_rds as rds,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_ec2 as ec2,
    CfnParameter,
    CfnOutput,
)
import os


class DatabasePerformanceMonitoringStack(Stack):
    """
    CDK Stack for Database Performance Monitoring with RDS Performance Insights.
    
    This stack creates a comprehensive monitoring solution that includes:
    - RDS MySQL instance with Performance Insights
    - Lambda-based performance analysis
    - CloudWatch monitoring and alerting
    - S3 storage for reports
    - SNS notifications
    - EventBridge automation
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.email_address = CfnParameter(
            self, "EmailAddress",
            type="String",
            description="Email address for performance alerts",
            constraint_description="Must be a valid email address",
            default="admin@example.com"
        )

        self.db_instance_class = CfnParameter(
            self, "DBInstanceClass",
            type="String",
            description="RDS instance class",
            default="db.t3.small",
            allowed_values=["db.t3.micro", "db.t3.small", "db.t3.medium", "db.t3.large"]
        )

        self.performance_insights_retention = CfnParameter(
            self, "PerformanceInsightsRetention",
            type="Number",
            description="Performance Insights retention period in days",
            default=7,
            allowed_values=[7, 31, 93, 186, 365, 731]
        )

        # Create VPC and networking components
        self._create_vpc()
        
        # Create IAM roles
        self._create_iam_roles()
        
        # Create S3 bucket for reports
        self._create_s3_bucket()
        
        # Create SNS topic for alerts
        self._create_sns_topic()
        
        # Create RDS instance with Performance Insights
        self._create_rds_instance()
        
        # Create Lambda functions
        self._create_lambda_functions()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create EventBridge scheduling
        self._create_eventbridge_automation()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> None:
        """Create VPC and networking components for RDS."""
        self.vpc = ec2.Vpc(
            self, "DatabaseVPC",
            max_azs=2,
            nat_gateways=0,  # Cost optimization - using private subnets with VPC endpoints
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ]
        )

        # Create VPC endpoints for AWS services
        self.vpc.add_interface_endpoint(
            "S3VpcEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.S3
        )
        
        self.vpc.add_interface_endpoint(
            "CloudWatchVpcEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH
        )

        # Security group for RDS
        self.rds_security_group = ec2.SecurityGroup(
            self, "RDSSecurityGroup",
            vpc=self.vpc,
            description="Security group for RDS Performance Insights demo",
            allow_all_outbound=False
        )

        # Security group for Lambda
        self.lambda_security_group = ec2.SecurityGroup(
            self, "LambdaSecurityGroup",
            vpc=self.vpc,
            description="Security group for Lambda functions",
            allow_all_outbound=True
        )

        # Allow Lambda to connect to RDS
        self.rds_security_group.add_ingress_rule(
            peer=self.lambda_security_group,
            connection=ec2.Port.tcp(3306),
            description="Allow Lambda to connect to MySQL"
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for RDS enhanced monitoring and Lambda functions."""
        # Enhanced monitoring role for RDS
        self.enhanced_monitoring_role = iam.Role(
            self, "RDSEnhancedMonitoringRole",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ]
        )

        # Lambda execution role for performance analysis
        self.lambda_role = iam.Role(
            self, "PerformanceAnalyzerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaVPCAccessExecutionRole"
                )
            ]
        )

        # Add custom policies for Performance Insights and other services
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "pi:DescribeDimensionKeys",
                    "pi:GetResourceMetrics",
                    "pi:ListAvailableResourceDimensions",
                    "pi:ListAvailableResourceMetrics",
                    "rds:DescribeDBInstances",
                    "s3:PutObject",
                    "s3:GetObject",
                    "cloudwatch:PutMetricData",
                    "sns:Publish"
                ],
                resources=["*"]
            )
        )

    def _create_s3_bucket(self) -> None:
        """Create S3 bucket for storing performance analysis reports."""
        self.reports_bucket = s3.Bucket(
            self, "PerformanceReportsBucket",
            bucket_name=f"db-performance-reports-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldReports",
                    enabled=True,
                    expiration=Duration.days(30),
                    noncurrent_version_expiration=Duration.days(7)
                )
            ]
        )

    def _create_sns_topic(self) -> None:
        """Create SNS topic for performance alerts."""
        self.alerts_topic = sns.Topic(
            self, "PerformanceAlertsTopic",
            topic_name="db-performance-alerts",
            display_name="Database Performance Alerts"
        )

        # Subscribe email address to topic
        self.alerts_topic.add_subscription(
            sns_subscriptions.EmailSubscription(
                email_address=self.email_address.value_as_string
            )
        )

    def _create_rds_instance(self) -> None:
        """Create RDS MySQL instance with Performance Insights enabled."""
        # Create subnet group
        self.db_subnet_group = rds.SubnetGroup(
            self, "DatabaseSubnetGroup",
            description="Subnet group for Performance Insights demo",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            )
        )

        # Create parameter group for MySQL optimization
        self.db_parameter_group = rds.ParameterGroup(
            self, "DatabaseParameterGroup",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            description="Parameter group for Performance Insights demo",
            parameters={
                "slow_query_log": "1",
                "long_query_time": "1",
                "general_log": "1",
                "innodb_buffer_pool_size": "{DBInstanceClassMemory*3/4}"
            }
        )

        # Create RDS instance
        self.database = rds.DatabaseInstance(
            self, "PerformanceTestDatabase",
            instance_identifier="performance-test-db",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            instance_type=ec2.InstanceType(self.db_instance_class.value_as_string),
            allocated_storage=20,
            storage_type=rds.StorageType.GP2,
            storage_encrypted=True,
            multi_az=False,  # Single AZ for demo/cost optimization
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.rds_security_group],
            parameter_group=self.db_parameter_group,
            credentials=rds.Credentials.from_generated_secret(
                username="admin",
                secret_name="rds-performance-demo-credentials"
            ),
            backup_retention=Duration.days(1),  # Minimal backup for demo
            delete_automated_backups=True,
            deletion_protection=False,
            # Performance Insights configuration
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.of(
                self.performance_insights_retention.value_as_number
            ),
            # Enhanced monitoring
            monitoring_interval=Duration.minutes(1),
            monitoring_role=self.enhanced_monitoring_role,
            # CloudWatch logs
            cloudwatch_logs_exports=["error", "general", "slow-query"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for performance analysis."""
        # Performance analyzer Lambda function
        self.performance_analyzer = lambda_.Function(
            self, "PerformanceAnalyzer",
            function_name="database-performance-analyzer",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_role,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
            security_groups=[self.lambda_security_group],
            environment={
                "PI_RESOURCE_ID": self.database.instance_resource_id,
                "S3_BUCKET_NAME": self.reports_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.alerts_topic.topic_arn,
                "DB_INSTANCE_ID": self.database.instance_identifier
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Grant permissions to Lambda
        self.reports_bucket.grant_read_write(self.performance_analyzer)
        self.alerts_topic.grant_publish(self.performance_analyzer)

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for database performance monitoring."""
        # High database connections alarm
        cloudwatch.Alarm(
            self, "HighDatabaseConnectionsAlarm",
            alarm_name=f"RDS-HighDatabaseLoad-{self.database.instance_identifier}",
            alarm_description="High database connections detected",
            metric=self.database.metric_database_connections(
                statistic=cloudwatch.Statistic.AVERAGE,
                period=Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_actions=[self.alerts_topic]
        )

        # High CPU utilization alarm
        cloudwatch.Alarm(
            self, "HighCPUUtilizationAlarm",
            alarm_name=f"RDS-HighCPUUtilization-{self.database.instance_identifier}",
            alarm_description="High CPU utilization on RDS instance",
            metric=self.database.metric_cpu_utilization(
                statistic=cloudwatch.Statistic.AVERAGE,
                period=Duration.minutes(5)
            ),
            threshold=75,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_actions=[self.alerts_topic]
        )

        # Custom metrics alarms for Performance Insights analysis
        high_load_events_metric = cloudwatch.Metric(
            namespace="RDS/PerformanceInsights",
            metric_name="HighLoadEvents",
            statistic=cloudwatch.Statistic.SUM,
            period=Duration.minutes(5)
        )

        cloudwatch.Alarm(
            self, "HighLoadEventsAlarm",
            alarm_name=f"RDS-HighLoadEvents-{self.database.instance_identifier}",
            alarm_description="High number of database load events detected",
            metric=high_load_events_metric,
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_actions=[self.alerts_topic]
        )

        problematic_queries_metric = cloudwatch.Metric(
            namespace="RDS/PerformanceInsights",
            metric_name="ProblematicQueries",
            statistic=cloudwatch.Statistic.SUM,
            period=Duration.minutes(5)
        )

        cloudwatch.Alarm(
            self, "ProblematicQueriesAlarm",
            alarm_name=f"RDS-ProblematicQueries-{self.database.instance_identifier}",
            alarm_description="High number of problematic SQL queries detected",
            metric=problematic_queries_metric,
            threshold=3,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_actions=[self.alerts_topic]
        )

    def _create_eventbridge_automation(self) -> None:
        """Create EventBridge rule for automated performance analysis."""
        # Create EventBridge rule to trigger Lambda every 15 minutes
        self.analysis_rule = events.Rule(
            self, "PerformanceAnalysisTrigger",
            rule_name=f"PerformanceAnalysisTrigger-{self.database.instance_identifier}",
            description="Trigger performance analysis Lambda function",
            schedule=events.Schedule.rate(Duration.minutes(15)),
            enabled=True
        )

        # Add Lambda function as target
        self.analysis_rule.add_target(
            events_targets.LambdaFunction(
                handler=self.performance_analyzer,
                retry_attempts=2
            )
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for performance monitoring."""
        self.dashboard = cloudwatch.Dashboard(
            self, "PerformanceDashboard",
            dashboard_name=f"RDS-Performance-{self.database.instance_identifier}"
        )

        # Add widgets for core RDS metrics
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="RDS Core Performance Metrics",
                left=[
                    self.database.metric_database_connections(),
                    self.database.metric_cpu_utilization(),
                    self.database.metric_read_latency(),
                    self.database.metric_write_latency()
                ],
                width=12,
                height=6
            ),
            cloudwatch.GraphWidget(
                title="Performance Insights Analysis Results",
                left=[
                    cloudwatch.Metric(
                        namespace="RDS/PerformanceInsights",
                        metric_name="HighLoadEvents",
                        statistic=cloudwatch.Statistic.SUM
                    ),
                    cloudwatch.Metric(
                        namespace="RDS/PerformanceInsights",
                        metric_name="ProblematicQueries",
                        statistic=cloudwatch.Statistic.SUM
                    )
                ],
                width=12,
                height=6
            )
        )

        # Add I/O performance metrics
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="I/O Performance Metrics",
                left=[
                    self.database.metric_read_iops(),
                    self.database.metric_write_iops(),
                    self.database.metric_read_throughput(),
                    self.database.metric_write_throughput()
                ],
                width=12,
                height=6
            ),
            cloudwatch.LogQueryWidget(
                title="Recent Slow Query Log Entries",
                log_groups=[
                    logs.LogGroup.from_log_group_name(
                        self, "SlowQueryLogGroup",
                        log_group_name=f"/aws/rds/instance/{self.database.instance_identifier}/slowquery"
                    )
                ],
                query_lines=[
                    "fields @timestamp, @message",
                    "sort @timestamp desc",
                    "limit 20"
                ],
                width=12,
                height=6
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "DatabaseEndpoint",
            description="RDS database endpoint",
            value=self.database.instance_endpoint.hostname
        )

        CfnOutput(
            self, "DatabaseInstanceIdentifier",
            description="RDS database instance identifier",
            value=self.database.instance_identifier
        )

        CfnOutput(
            self, "PerformanceInsightsResourceId",
            description="Performance Insights resource ID",
            value=self.database.instance_resource_id
        )

        CfnOutput(
            self, "ReportsBucketName",
            description="S3 bucket name for performance reports",
            value=self.reports_bucket.bucket_name
        )

        CfnOutput(
            self, "AlertsTopicArn",
            description="SNS topic ARN for alerts",
            value=self.alerts_topic.topic_arn
        )

        CfnOutput(
            self, "LambdaFunctionName",
            description="Performance analyzer Lambda function name",
            value=self.performance_analyzer.function_name
        )

        CfnOutput(
            self, "DashboardUrl",
            description="CloudWatch dashboard URL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}"
        )

        CfnOutput(
            self, "PerformanceInsightsUrl",
            description="Performance Insights dashboard URL",
            value=f"https://{self.region}.console.aws.amazon.com/rds/home?region={self.region}#performance-insights-v20206:/resourceId/{self.database.instance_resource_id}"
        )

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for performance analysis."""
        return '''
import json
import boto3
import datetime
import os
from decimal import Decimal


def lambda_handler(event, context):
    """
    Lambda function to analyze RDS Performance Insights data and generate reports.
    
    This function:
    1. Retrieves Performance Insights metrics
    2. Analyzes performance patterns and anomalies
    3. Stores analysis results in S3
    4. Publishes custom metrics to CloudWatch
    5. Sends alerts for significant issues
    """
    pi_client = boto3.client('pi')
    s3_client = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    sns_client = boto3.client('sns')
    
    # Get environment variables
    resource_id = os.environ.get('PI_RESOURCE_ID')
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    db_instance_id = os.environ.get('DB_INSTANCE_ID')
    
    # Define time range for analysis (last hour)
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        # Get database load metrics
        response = pi_client.get_resource_metrics(
            ServiceType='RDS',
            Identifier=resource_id,
            StartTime=start_time,
            EndTime=end_time,
            PeriodInSeconds=300,
            MetricQueries=[
                {
                    'Metric': 'db.load.avg',
                    'GroupBy': {'Group': 'db.wait_event', 'Limit': 10}
                },
                {
                    'Metric': 'db.load.avg',
                    'GroupBy': {'Group': 'db.sql_tokenized', 'Limit': 10}
                }
            ]
        )
        
        # Analyze performance patterns
        analysis_results = analyze_performance_data(response, db_instance_id)
        
        # Store results in S3
        report_key = f"performance-reports/{datetime.datetime.utcnow().strftime('%Y/%m/%d/%H')}/analysis-{int(datetime.datetime.utcnow().timestamp())}.json"
        s3_client.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(analysis_results, default=str),
            ContentType='application/json'
        )
        
        # Send custom metrics to CloudWatch
        publish_custom_metrics(cloudwatch, analysis_results)
        
        # Send alerts if significant issues detected
        if analysis_results['alert_level'] > 0:
            send_alert(sns_client, sns_topic_arn, analysis_results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'report_location': f's3://{bucket_name}/{report_key}',
                'alert_level': analysis_results['alert_level']
            })
        }
        
    except Exception as e:
        print(f"Error in performance analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def analyze_performance_data(response, db_instance_id):
    """Analyze Performance Insights data for anomalies and patterns."""
    analysis = {
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'db_instance_id': db_instance_id,
        'metrics_analyzed': len(response['MetricList']),
        'high_load_events': [],
        'problematic_queries': [],
        'recommendations': [],
        'alert_level': 0  # 0=info, 1=warning, 2=critical
    }
    
    total_load = 0
    max_load = 0
    
    for metric in response['MetricList']:
        if not metric['DataPoints']:
            continue
            
        avg_load = sum(dp['Value'] for dp in metric['DataPoints']) / len(metric['DataPoints'])
        max_metric_load = max(dp['Value'] for dp in metric['DataPoints'])
        total_load += avg_load
        max_load = max(max_load, max_metric_load)
        
        if 'Dimensions' in metric['Key']:
            # Analyze wait events
            if 'db.wait_event.name' in metric['Key']['Dimensions']:
                wait_event = metric['Key']['Dimensions']['db.wait_event.name']
                
                if avg_load > 1.0:  # High load threshold
                    analysis['high_load_events'].append({
                        'wait_event': wait_event,
                        'average_load': round(avg_load, 3),
                        'max_load': round(max_metric_load, 3)
                    })
                    
                    if avg_load > 2.0:
                        analysis['alert_level'] = max(analysis['alert_level'], 2)
                    elif avg_load > 1.5:
                        analysis['alert_level'] = max(analysis['alert_level'], 1)
            
            # Analyze SQL queries
            if 'db.sql_tokenized.statement' in metric['Key']['Dimensions']:
                sql_statement = metric['Key']['Dimensions']['db.sql_tokenized.statement']
                
                if avg_load > 0.5:  # Problematic query threshold
                    analysis['problematic_queries'].append({
                        'sql_statement': sql_statement[:200] + '...' if len(sql_statement) > 200 else sql_statement,
                        'average_load': round(avg_load, 3),
                        'max_load': round(max_metric_load, 3)
                    })
                    
                    if avg_load > 1.5:
                        analysis['alert_level'] = max(analysis['alert_level'], 2)
                    elif avg_load > 1.0:
                        analysis['alert_level'] = max(analysis['alert_level'], 1)
    
    # Overall performance assessment
    analysis['total_database_load'] = round(total_load, 3)
    analysis['max_database_load'] = round(max_load, 3)
    
    # Generate recommendations
    if analysis['high_load_events']:
        analysis['recommendations'].append("Investigate high wait events - consider query optimization or resource scaling")
    
    if analysis['problematic_queries']:
        analysis['recommendations'].append("Review and optimize high-load SQL queries - consider adding indexes or query rewrites")
    
    if max_load > 3.0:
        analysis['recommendations'].append("Critical: Database load exceeds 3.0 - immediate action required")
        analysis['alert_level'] = 2
    elif max_load > 2.0:
        analysis['recommendations'].append("Warning: Database load exceeds 2.0 - monitor closely")
        analysis['alert_level'] = max(analysis['alert_level'], 1)
    
    return analysis


def publish_custom_metrics(cloudwatch, analysis):
    """Publish custom metrics to CloudWatch."""
    try:
        metric_data = [
            {
                'MetricName': 'HighLoadEvents',
                'Value': len(analysis['high_load_events']),
                'Unit': 'Count',
                'Timestamp': datetime.datetime.utcnow()
            },
            {
                'MetricName': 'ProblematicQueries',
                'Value': len(analysis['problematic_queries']),
                'Unit': 'Count',
                'Timestamp': datetime.datetime.utcnow()
            },
            {
                'MetricName': 'TotalDatabaseLoad',
                'Value': analysis['total_database_load'],
                'Unit': 'Count',
                'Timestamp': datetime.datetime.utcnow()
            },
            {
                'MetricName': 'MaxDatabaseLoad',
                'Value': analysis['max_database_load'],
                'Unit': 'Count',
                'Timestamp': datetime.datetime.utcnow()
            }
        ]
        
        cloudwatch.put_metric_data(
            Namespace='RDS/PerformanceInsights',
            MetricData=metric_data
        )
    except Exception as e:
        print(f"Error publishing custom metrics: {str(e)}")


def send_alert(sns_client, topic_arn, analysis):
    """Send alert notification for significant performance issues."""
    try:
        alert_levels = {0: "INFO", 1: "WARNING", 2: "CRITICAL"}
        level = alert_levels.get(analysis['alert_level'], "UNKNOWN")
        
        subject = f"Database Performance Alert - {level}"
        
        message = f"""
Database Performance Analysis Alert

Instance: {analysis['db_instance_id']}
Timestamp: {analysis['timestamp']}
Alert Level: {level}

Performance Summary:
- Total Database Load: {analysis['total_database_load']}
- Max Database Load: {analysis['max_database_load']}
- High Load Events: {len(analysis['high_load_events'])}
- Problematic Queries: {len(analysis['problematic_queries'])}

Recommendations:
{chr(10).join(f"- {rec}" for rec in analysis['recommendations'])}

High Load Events:
{chr(10).join(f"- {event['wait_event']}: {event['average_load']}" for event in analysis['high_load_events'][:5])}

Review the full analysis report in S3 and Performance Insights dashboard for detailed investigation.
"""
        
        sns_client.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message
        )
    except Exception as e:
        print(f"Error sending alert: {str(e)}")
'''


app = cdk.App()
DatabasePerformanceMonitoringStack(
    app, 
    "DatabasePerformanceMonitoringStack",
    description="Database Performance Monitoring with RDS Performance Insights - CDK Python Implementation"
)
app.synth()