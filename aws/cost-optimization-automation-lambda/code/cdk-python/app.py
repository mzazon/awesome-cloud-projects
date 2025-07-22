#!/usr/bin/env python3
"""
CDK Python application for Cost Optimization Automation with Lambda and Trusted Advisor APIs

This application creates an automated cost optimization system that:
- Uses AWS Lambda functions to analyze Trusted Advisor recommendations
- Implements automated remediation for approved cost-saving actions
- Sends notifications through SNS for cost optimization opportunities
- Tracks optimization activities in DynamoDB
- Provides CloudWatch monitoring and alerting

Architecture Components:
- Lambda functions for analysis and remediation
- DynamoDB table for tracking optimization activities
- SNS topic for notifications
- EventBridge schedules for automated execution
- CloudWatch dashboard for monitoring
- S3 bucket for reports and logs
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    RemovalPolicy,
    Duration,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_dynamodb as dynamodb,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_s3 as s3,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_scheduler as scheduler,
)
from constructs import Construct
from typing import Dict, List, Optional
import json


class CostOptimizationStack(Stack):
    """
    Main stack for Cost Optimization Automation infrastructure
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters
        self.notification_email = self.node.try_get_context("notification_email") or "admin@example.com"
        self.slack_webhook_url = self.node.try_get_context("slack_webhook_url")
        self.auto_remediation_enabled = self.node.try_get_context("auto_remediation_enabled") or False

        # Create S3 bucket for reports and Lambda deployment packages
        self.reports_bucket = self._create_s3_bucket()
        
        # Create DynamoDB table for tracking optimization activities
        self.optimization_table = self._create_dynamodb_table()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_sns_topic()
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda functions
        self.cost_analysis_function = self._create_cost_analysis_lambda()
        self.remediation_function = self._create_remediation_lambda()
        
        # Create EventBridge schedules for automated execution
        self._create_event_schedules()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Output important resources
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """Create S3 bucket for cost optimization reports and logs"""
        bucket = s3.Bucket(
            self,
            "CostOptimizationBucket",
            bucket_name=f"cost-optimization-reports-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ReportRetention",
                    enabled=True,
                    expiration=Duration.days(90),
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
        )
        
        # Add bucket policy for secure access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, f"{bucket.bucket_arn}/*"],
                conditions={
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            )
        )
        
        return bucket

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """Create DynamoDB table for tracking cost optimization activities"""
        table = dynamodb.Table(
            self,
            "CostOptimizationTable",
            table_name="cost-optimization-tracking",
            partition_key=dynamodb.Attribute(
                name="ResourceId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="CheckId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add GSI for querying by timestamp
        table.add_global_secondary_index(
            index_name="TimestampIndex",
            partition_key=dynamodb.Attribute(
                name="CheckId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            ),
        )
        
        # Add GSI for querying by remediation status
        table.add_global_secondary_index(
            index_name="RemediationStatusIndex",
            partition_key=dynamodb.Attribute(
                name="RemediationStatus",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            ),
        )
        
        return table

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for cost optimization notifications"""
        topic = sns.Topic(
            self,
            "CostOptimizationTopic",
            topic_name="cost-optimization-alerts",
            display_name="Cost Optimization Alerts",
            master_key=None,  # Use default AWS managed key
        )
        
        # Add email subscription
        topic.add_subscription(
            subscriptions.EmailSubscription(self.notification_email)
        )
        
        # Add Slack subscription if webhook URL is provided
        if self.slack_webhook_url:
            topic.add_subscription(
                subscriptions.UrlSubscription(self.slack_webhook_url)
            )
        
        return topic

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with comprehensive permissions"""
        role = iam.Role(
            self,
            "CostOptimizationLambdaRole",
            role_name="CostOptimizationLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add comprehensive cost optimization permissions
        role.add_to_policy(
            iam.PolicyStatement(
                sid="TrustedAdvisorAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "support:DescribeTrustedAdvisorChecks",
                    "support:DescribeTrustedAdvisorCheckResult",
                    "support:RefreshTrustedAdvisorCheck",
                ],
                resources=["*"],
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                sid="CostExplorerAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "ce:GetCostAndUsage",
                    "ce:GetDimensionValues",
                    "ce:GetUsageReport",
                    "ce:GetReservationCoverage",
                    "ce:GetReservationPurchaseRecommendation",
                    "ce:GetReservationUtilization",
                    "ce:GetSavingsPlansUtilization",
                    "ce:GetRightsizingRecommendation",
                ],
                resources=["*"],
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                sid="RemediationAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "ec2:DescribeInstances",
                    "ec2:StopInstances",
                    "ec2:TerminateInstances",
                    "ec2:ModifyInstanceAttribute",
                    "ec2:DescribeVolumes",
                    "ec2:ModifyVolume",
                    "ec2:CreateSnapshot",
                    "ec2:DeleteVolume",
                    "rds:DescribeDBInstances",
                    "rds:ModifyDBInstance",
                    "rds:StopDBInstance",
                    "rds:DeleteDBInstance",
                    "elasticache:DescribeCacheClusters",
                    "elasticache:ModifyCacheCluster",
                    "elasticache:DeleteCacheCluster",
                ],
                resources=["*"],
            )
        )
        
        # Grant access to DynamoDB table
        self.optimization_table.grant_read_write_data(role)
        
        # Grant access to SNS topic
        self.notification_topic.grant_publish(role)
        
        # Grant access to S3 bucket
        self.reports_bucket.grant_read_write(role)
        
        # Grant Lambda invoke permissions
        role.add_to_policy(
            iam.PolicyStatement(
                sid="LambdaInvokeAccess",
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=[
                    f"arn:aws:lambda:{self.region}:{self.account}:function:cost-optimization-*"
                ],
            )
        )
        
        return role

    def _create_cost_analysis_lambda(self) -> _lambda.Function:
        """Create Lambda function for cost analysis using Trusted Advisor APIs"""
        function = _lambda.Function(
            self,
            "CostAnalysisFunction",
            function_name="cost-optimization-analysis",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self._get_cost_analysis_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "COST_OPT_TABLE": self.optimization_table.table_name,
                "REMEDIATION_FUNCTION_NAME": "cost-optimization-remediation",
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "REPORTS_BUCKET": self.reports_bucket.bucket_name,
                "AUTO_REMEDIATION_ENABLED": str(self.auto_remediation_enabled),
            },
            reserved_concurrent_executions=10,
            log_retention=logs.RetentionDays.ONE_MONTH,
        )
        
        # Add CloudWatch Insights queries for this function
        log_group = logs.LogGroup.from_log_group_name(
            self,
            "CostAnalysisLogGroup",
            log_group_name=f"/aws/lambda/{function.function_name}"
        )
        
        return function

    def _create_remediation_lambda(self) -> _lambda.Function:
        """Create Lambda function for automated remediation actions"""
        function = _lambda.Function(
            self,
            "RemediationFunction",
            function_name="cost-optimization-remediation",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self._get_remediation_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "COST_OPT_TABLE": self.optimization_table.table_name,
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "REPORTS_BUCKET": self.reports_bucket.bucket_name,
            },
            reserved_concurrent_executions=5,
            log_retention=logs.RetentionDays.ONE_MONTH,
        )
        
        return function

    def _create_event_schedules(self) -> None:
        """Create EventBridge schedules for automated cost optimization"""
        # Daily cost analysis schedule
        events.Rule(
            self,
            "DailyCostAnalysisRule",
            rule_name="daily-cost-analysis",
            description="Daily cost optimization analysis",
            schedule=events.Schedule.rate(Duration.days(1)),
            targets=[
                targets.LambdaFunction(
                    self.cost_analysis_function,
                    event=events.RuleTargetInput.from_object({
                        "scheduled_analysis": True,
                        "analysis_type": "daily"
                    })
                )
            ],
        )
        
        # Weekly comprehensive analysis schedule
        events.Rule(
            self,
            "WeeklyCostAnalysisRule",
            rule_name="weekly-comprehensive-analysis",
            description="Weekly comprehensive cost optimization analysis",
            schedule=events.Schedule.rate(Duration.days(7)),
            targets=[
                targets.LambdaFunction(
                    self.cost_analysis_function,
                    event=events.RuleTargetInput.from_object({
                        "scheduled_analysis": True,
                        "analysis_type": "comprehensive"
                    })
                )
            ],
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring cost optimization system"""
        dashboard = cloudwatch.Dashboard(
            self,
            "CostOptimizationDashboard",
            dashboard_name="CostOptimization",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Performance",
                        width=12,
                        height=6,
                        left=[
                            self.cost_analysis_function.metric_duration(
                                label="Analysis Duration",
                                statistic="Average"
                            ),
                            self.remediation_function.metric_duration(
                                label="Remediation Duration",
                                statistic="Average"
                            ),
                        ],
                        right=[
                            self.cost_analysis_function.metric_invocations(
                                label="Analysis Invocations"
                            ),
                            self.remediation_function.metric_invocations(
                                label="Remediation Invocations"
                            ),
                        ],
                    ),
                    cloudwatch.GraphWidget(
                        title="Lambda Function Errors",
                        width=12,
                        height=6,
                        left=[
                            self.cost_analysis_function.metric_errors(
                                label="Analysis Errors"
                            ),
                            self.remediation_function.metric_errors(
                                label="Remediation Errors"
                            ),
                        ],
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="DynamoDB Operations",
                        width=12,
                        height=6,
                        left=[
                            self.optimization_table.metric_consumed_read_capacity_units(
                                label="Read Capacity"
                            ),
                            self.optimization_table.metric_consumed_write_capacity_units(
                                label="Write Capacity"
                            ),
                        ],
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Total Cost Opportunities",
                        width=12,
                        height=6,
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/DynamoDB",
                                metric_name="ItemCount",
                                dimensions_map={
                                    "TableName": self.optimization_table.table_name
                                },
                                statistic="Average",
                            )
                        ],
                    ),
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Recent Cost Optimization Activities",
                        width=24,
                        height=6,
                        log_groups=[
                            logs.LogGroup.from_log_group_name(
                                self,
                                "CostAnalysisLogs",
                                log_group_name=f"/aws/lambda/{self.cost_analysis_function.function_name}"
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /optimization/",
                            "sort @timestamp desc",
                            "limit 100"
                        ],
                    ),
                ],
            ],
        )

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring system health"""
        # Alarm for Lambda function errors
        cloudwatch.Alarm(
            self,
            "CostAnalysisErrorAlarm",
            alarm_name="cost-optimization-analysis-errors",
            alarm_description="Alert when cost analysis function has errors",
            metric=self.cost_analysis_function.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        ).add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        
        # Alarm for Lambda function duration
        cloudwatch.Alarm(
            self,
            "CostAnalysisDurationAlarm",
            alarm_name="cost-optimization-analysis-duration",
            alarm_description="Alert when cost analysis function takes too long",
            metric=self.cost_analysis_function.metric_duration(
                period=Duration.minutes(5),
                statistic="Average"
            ),
            threshold=240000,  # 4 minutes in milliseconds
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        ).add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

    def _create_outputs(self) -> None:
        """Create stack outputs for important resources"""
        cdk.CfnOutput(
            self,
            "CostOptimizationTableName",
            value=self.optimization_table.table_name,
            description="DynamoDB table name for cost optimization tracking",
        )
        
        cdk.CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for cost optimization notifications",
        )
        
        cdk.CfnOutput(
            self,
            "ReportsBucketName",
            value=self.reports_bucket.bucket_name,
            description="S3 bucket name for cost optimization reports",
        )
        
        cdk.CfnOutput(
            self,
            "CostAnalysisFunctionName",
            value=self.cost_analysis_function.function_name,
            description="Lambda function name for cost analysis",
        )
        
        cdk.CfnOutput(
            self,
            "RemediationFunctionName",
            value=self.remediation_function.function_name,
            description="Lambda function name for automated remediation",
        )
        
        cdk.CfnOutput(
            self,
            "CloudWatchDashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=CostOptimization",
            description="CloudWatch dashboard URL for monitoring",
        )

    def _get_cost_analysis_code(self) -> str:
        """Get the cost analysis Lambda function code"""
        return '''
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Main handler for cost analysis using Trusted Advisor APIs
    """
    print("Starting cost optimization analysis...")
    
    # Initialize AWS clients
    support_client = boto3.client('support', region_name='us-east-1')
    ce_client = boto3.client('ce')
    dynamodb = boto3.resource('dynamodb')
    lambda_client = boto3.client('lambda')
    s3_client = boto3.client('s3')
    
    # Get environment variables
    table_name = os.environ['COST_OPT_TABLE']
    remediation_function = os.environ['REMEDIATION_FUNCTION_NAME']
    reports_bucket = os.environ['REPORTS_BUCKET']
    auto_remediation_enabled = os.environ.get('AUTO_REMEDIATION_ENABLED', 'False').lower() == 'true'
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get list of cost optimization checks
        cost_checks = get_cost_optimization_checks(support_client)
        
        # Process each check
        optimization_opportunities = []
        for check in cost_checks:
            print(f"Processing check: {check['name']}")
            
            # Get check results
            check_result = support_client.describe_trusted_advisor_check_result(
                checkId=check['id'],
                language='en'
            )
            
            # Process flagged resources
            flagged_resources = check_result['result']['flaggedResources']
            
            for resource in flagged_resources:
                opportunity = {
                    'check_id': check['id'],
                    'check_name': check['name'],
                    'resource_id': resource['resourceId'],
                    'status': resource['status'],
                    'metadata': resource['metadata'],
                    'estimated_savings': extract_estimated_savings(resource),
                    'timestamp': datetime.now().isoformat()
                }
                
                # Store in DynamoDB
                store_optimization_opportunity(table, opportunity)
                
                # Add to opportunities list
                optimization_opportunities.append(opportunity)
        
        # Get additional cost insights from Cost Explorer
        cost_insights = get_cost_explorer_insights(ce_client)
        
        # Trigger remediation for auto-approved actions
        auto_remediation_results = []
        if auto_remediation_enabled:
            for opportunity in optimization_opportunities:
                if should_auto_remediate(opportunity):
                    print(f"Triggering auto-remediation for: {opportunity['resource_id']}")
                    
                    remediation_payload = {
                        'opportunity': opportunity,
                        'action': 'auto_remediate'
                    }
                    
                    response = lambda_client.invoke(
                        FunctionName=remediation_function,
                        InvocationType='Event',
                        Payload=json.dumps(remediation_payload)
                    )
                    
                    auto_remediation_results.append({
                        'resource_id': opportunity['resource_id'],
                        'remediation_triggered': True
                    })
        
        # Generate and store summary report
        report = generate_cost_optimization_report(
            optimization_opportunities, 
            cost_insights, 
            auto_remediation_results
        )
        
        # Store report in S3
        report_key = f"cost-optimization-reports/{datetime.now().strftime('%Y/%m/%d')}/report-{datetime.now().strftime('%H-%M-%S')}.json"
        s3_client.put_object(
            Bucket=reports_bucket,
            Key=report_key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization analysis completed successfully',
                'opportunities_found': len(optimization_opportunities),
                'auto_remediations_triggered': len(auto_remediation_results),
                'total_potential_savings': calculate_total_savings(optimization_opportunities),
                'report_location': f"s3://{reports_bucket}/{report_key}"
            }, default=str)
        }
        
    except Exception as e:
        print(f"Error in cost analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def get_cost_optimization_checks(support_client):
    """Get all cost optimization related Trusted Advisor checks"""
    response = support_client.describe_trusted_advisor_checks(language='en')
    
    cost_checks = []
    for check in response['checks']:
        if 'cost' in check['category'].lower():
            cost_checks.append({
                'id': check['id'],
                'name': check['name'],
                'category': check['category'],
                'description': check['description']
            })
    
    return cost_checks

def extract_estimated_savings(resource):
    """Extract estimated savings from resource metadata"""
    try:
        metadata = resource.get('metadata', [])
        
        for item in metadata:
            if '$' in str(item) and any(keyword in str(item).lower() 
                                     for keyword in ['save', 'saving', 'cost']):
                import re
                savings_match = re.search(r'\\$[\\d,]+\\.?\\d*', str(item))
                if savings_match:
                    return float(savings_match.group().replace('$', '').replace(',', ''))
        
        return 0.0
    except:
        return 0.0

def store_optimization_opportunity(table, opportunity):
    """Store optimization opportunity in DynamoDB"""
    table.put_item(
        Item={
            'ResourceId': opportunity['resource_id'],
            'CheckId': opportunity['check_id'],
            'CheckName': opportunity['check_name'],
            'Status': opportunity['status'],
            'EstimatedSavings': Decimal(str(opportunity['estimated_savings'])),
            'Timestamp': opportunity['timestamp'],
            'Metadata': json.dumps(opportunity['metadata']),
            'RemediationStatus': 'pending'
        }
    )

def get_cost_explorer_insights(ce_client):
    """Get additional cost insights from Cost Explorer"""
    end_date = datetime.now()
    start_date = end_date - timedelta(days=30)
    
    try:
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'}
            ]
        )
        
        return response['ResultsByTime']
    except Exception as e:
        print(f"Error getting Cost Explorer insights: {str(e)}")
        return []

def should_auto_remediate(opportunity):
    """Determine if opportunity should be auto-remediated"""
    auto_remediate_checks = [
        'Amazon EBS Under-Provisioned Volumes',
        'Amazon EBS Unattached Volumes',
        'Amazon RDS Idle DB Instances'
    ]
    
    return (opportunity['check_name'] in auto_remediate_checks and 
            opportunity['status'] == 'warning')

def generate_cost_optimization_report(opportunities, cost_insights, auto_remediations):
    """Generate comprehensive cost optimization report"""
    report = {
        'summary': {
            'total_opportunities': len(opportunities),
            'total_potential_savings': calculate_total_savings(opportunities),
            'auto_remediations_applied': len(auto_remediations),
            'analysis_date': datetime.now().isoformat()
        },
        'top_opportunities': sorted(opportunities, 
                                  key=lambda x: x['estimated_savings'], 
                                  reverse=True)[:10],
        'savings_by_category': categorize_savings(opportunities),
        'cost_trends': cost_insights,
        'auto_remediations': auto_remediations
    }
    
    return report

def calculate_total_savings(opportunities):
    """Calculate total potential savings"""
    return sum(op['estimated_savings'] for op in opportunities)

def categorize_savings(opportunities):
    """Categorize savings by service type"""
    categories = {}
    for op in opportunities:
        service = extract_service_from_check(op['check_name'])
        if service not in categories:
            categories[service] = {'count': 0, 'total_savings': 0}
        categories[service]['count'] += 1
        categories[service]['total_savings'] += op['estimated_savings']
    
    return categories

def extract_service_from_check(check_name):
    """Extract AWS service from check name"""
    if 'EC2' in check_name:
        return 'EC2'
    elif 'RDS' in check_name:
        return 'RDS'
    elif 'EBS' in check_name:
        return 'EBS'
    elif 'S3' in check_name:
        return 'S3'
    elif 'ElastiCache' in check_name:
        return 'ElastiCache'
    else:
        return 'Other'
        '''

    def _get_remediation_code(self) -> str:
        """Get the remediation Lambda function code"""
        return '''
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Handle cost optimization remediation actions
    """
    print("Starting cost optimization remediation...")
    
    # Initialize AWS clients
    ec2_client = boto3.client('ec2')
    rds_client = boto3.client('rds')
    s3_client = boto3.client('s3')
    sns_client = boto3.client('sns')
    dynamodb = boto3.resource('dynamodb')
    
    # Get environment variables
    table_name = os.environ['COST_OPT_TABLE']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Parse the incoming opportunity
        opportunity = event['opportunity']
        action = event.get('action', 'manual')
        
        print(f"Processing remediation for: {opportunity['resource_id']}")
        print(f"Check: {opportunity['check_name']}")
        
        # Route to appropriate remediation handler
        remediation_result = None
        
        if 'EC2' in opportunity['check_name']:
            remediation_result = handle_ec2_remediation(
                ec2_client, opportunity, action
            )
        elif 'RDS' in opportunity['check_name']:
            remediation_result = handle_rds_remediation(
                rds_client, opportunity, action
            )
        elif 'EBS' in opportunity['check_name']:
            remediation_result = handle_ebs_remediation(
                ec2_client, opportunity, action
            )
        elif 'S3' in opportunity['check_name']:
            remediation_result = handle_s3_remediation(
                s3_client, opportunity, action
            )
        else:
            remediation_result = {
                'status': 'skipped',
                'message': f"No automated remediation available for: {opportunity['check_name']}"
            }
        
        # Update tracking record
        update_remediation_tracking(table, opportunity, remediation_result)
        
        # Send notification
        send_remediation_notification(
            sns_client, sns_topic_arn, opportunity, remediation_result
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': opportunity['resource_id'],
                'remediation_result': remediation_result
            }, default=str)
        }
        
    except Exception as e:
        print(f"Error in remediation: {str(e)}")
        
        # Send error notification
        error_notification = {
            'resource_id': opportunity.get('resource_id', 'unknown'),
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(error_notification, indent=2),
            Subject='Cost Optimization Remediation Error'
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def handle_ec2_remediation(ec2_client, opportunity, action):
    """Handle EC2-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'stopped' in check_name.lower():
            return {
                'status': 'recommendation',
                'action': 'terminate',
                'message': f'Recommend terminating stopped instance {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        elif 'underutilized' in check_name.lower():
            return {
                'status': 'recommendation',
                'action': 'downsize',
                'message': f'Recommend downsizing underutilized instance {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling EC2 remediation: {str(e)}'
        }

def handle_rds_remediation(rds_client, opportunity, action):
    """Handle RDS-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'idle' in check_name.lower():
            if action == 'auto_remediate':
                rds_client.stop_db_instance(
                    DBInstanceIdentifier=resource_id
                )
                
                return {
                    'status': 'remediated',
                    'action': 'stopped',
                    'message': f'Stopped idle RDS instance {resource_id}',
                    'estimated_savings': opportunity['estimated_savings']
                }
            else:
                return {
                    'status': 'recommendation',
                    'action': 'stop',
                    'message': f'Recommend stopping idle RDS instance {resource_id}',
                    'estimated_savings': opportunity['estimated_savings']
                }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling RDS remediation: {str(e)}'
        }

def handle_ebs_remediation(ec2_client, opportunity, action):
    """Handle EBS-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'unattached' in check_name.lower():
            if action == 'auto_remediate':
                # Create snapshot before deletion
                snapshot_response = ec2_client.create_snapshot(
                    VolumeId=resource_id,
                    Description=f'Automated snapshot before deleting unattached volume {resource_id}'
                )
                
                # Delete unattached volume
                ec2_client.delete_volume(VolumeId=resource_id)
                
                return {
                    'status': 'remediated',
                    'action': 'deleted',
                    'message': f'Deleted unattached EBS volume {resource_id}, snapshot: {snapshot_response["SnapshotId"]}',
                    'estimated_savings': opportunity['estimated_savings']
                }
            else:
                return {
                    'status': 'recommendation',
                    'action': 'delete',
                    'message': f'Recommend deleting unattached EBS volume {resource_id}',
                    'estimated_savings': opportunity['estimated_savings']
                }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling EBS remediation: {str(e)}'
        }

def handle_s3_remediation(s3_client, opportunity, action):
    """Handle S3-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'lifecycle' in check_name.lower():
            return {
                'status': 'recommendation',
                'action': 'configure_lifecycle',
                'message': f'Recommend configuring lifecycle policy for S3 bucket {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling S3 remediation: {str(e)}'
        }

def update_remediation_tracking(table, opportunity, remediation_result):
    """Update DynamoDB tracking record with remediation results"""
    table.update_item(
        Key={
            'ResourceId': opportunity['resource_id'],
            'CheckId': opportunity['check_id']
        },
        UpdateExpression='SET RemediationStatus = :status, RemediationResult = :result, RemediationTimestamp = :timestamp',
        ExpressionAttributeValues={
            ':status': remediation_result['status'],
            ':result': json.dumps(remediation_result),
            ':timestamp': datetime.now().isoformat()
        }
    )

def send_remediation_notification(sns_client, topic_arn, opportunity, remediation_result):
    """Send notification about remediation action"""
    notification = {
        'resource_id': opportunity['resource_id'],
        'check_name': opportunity['check_name'],
        'remediation_status': remediation_result['status'],
        'remediation_action': remediation_result.get('action', 'none'),
        'estimated_savings': opportunity['estimated_savings'],
        'message': remediation_result.get('message', ''),
        'timestamp': datetime.now().isoformat()
    }
    
    subject = f"Cost Optimization: {remediation_result['status'].title()} - {opportunity['check_name']}"
    
    sns_client.publish(
        TopicArn=topic_arn,
        Message=json.dumps(notification, indent=2),
        Subject=subject
    )
        '''


def main():
    """Main function to deploy the CDK application"""
    app = App()
    
    # Get environment from context or use default
    env = Environment(
        account=app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )
    
    # Create the main stack
    CostOptimizationStack(
        app,
        "CostOptimizationStack",
        env=env,
        description="Cost Optimization Automation with Lambda and Trusted Advisor APIs"
    )
    
    app.synth()


if __name__ == "__main__":
    main()