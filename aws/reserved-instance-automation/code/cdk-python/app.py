#!/usr/bin/env python3
"""
Reserved Instance Management Automation CDK Application

This CDK application deploys infrastructure for automated Reserved Instance (RI) 
management including utilization analysis, purchase recommendations, and expiration 
monitoring using AWS Cost Explorer, Lambda, EventBridge, and notification services.

Architecture Components:
- Lambda functions for RI analysis, recommendations, and monitoring
- EventBridge schedules for automated execution
- S3 bucket for report storage
- DynamoDB table for RI tracking
- SNS topic for notifications
- IAM roles with least privilege permissions
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_events as events,
    aws_events_targets as targets,
    aws_s3 as s3,
    aws_dynamodb as dynamodb,
    aws_sns as sns,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
import os


class ReservedInstanceManagementStack(Stack):
    """
    CDK Stack for Reserved Instance Management Automation
    
    This stack creates all the necessary infrastructure for automated RI management
    including Lambda functions, EventBridge schedules, storage, and notification services.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters for customization
        project_name = self.node.try_get_context("project_name") or "ri-management"
        notification_email = self.node.try_get_context("notification_email")
        
        # Generate unique suffix for resource names
        unique_suffix = self.account[-6:]  # Last 6 digits of account ID
        
        # Create S3 bucket for storing RI reports
        self.reports_bucket = s3.Bucket(
            self,
            "RIReportsBucket",
            bucket_name=f"ri-reports-{self.account}-{unique_suffix}",
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

        # Create DynamoDB table for RI tracking
        self.ri_tracking_table = dynamodb.Table(
            self,
            "RITrackingTable",
            table_name=f"ri-tracking-{unique_suffix}",
            partition_key=dynamodb.Attribute(
                name="ReservationId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create SNS topic for notifications
        self.notifications_topic = sns.Topic(
            self,
            "RINotificationsTopic",
            topic_name=f"ri-alerts-{unique_suffix}",
            display_name="Reserved Instance Management Alerts"
        )

        # Subscribe email to SNS topic if provided
        if notification_email:
            sns.Subscription(
                self,
                "EmailSubscription",
                topic=self.notifications_topic,
                endpoint=notification_email,
                protocol=sns.SubscriptionProtocol.EMAIL
            )

        # Create IAM role for Lambda functions
        self.lambda_role = iam.Role(
            self,
            "RILambdaRole",
            role_name=f"{project_name}-lambda-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "RIManagementPolicy": iam.PolicyDocument(
                    statements=[
                        # Cost Explorer permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ce:GetDimensionValues",
                                "ce:GetUsageAndCosts",
                                "ce:GetReservationCoverage",
                                "ce:GetReservationPurchaseRecommendation",
                                "ce:GetReservationUtilization",
                                "ce:GetRightsizingRecommendation"
                            ],
                            resources=["*"]
                        ),
                        # EC2 permissions for RI monitoring
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ec2:DescribeReservedInstances",
                                "ec2:DescribeInstances"
                            ],
                            resources=["*"]
                        ),
                        # S3 permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject"
                            ],
                            resources=[f"{self.reports_bucket.bucket_arn}/*"]
                        ),
                        # DynamoDB permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:PutItem",
                                "dynamodb:GetItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:Query",
                                "dynamodb:Scan"
                            ],
                            resources=[self.ri_tracking_table.table_arn]
                        ),
                        # SNS permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.notifications_topic.topic_arn]
                        )
                    ]
                )
            }
        )

        # Create Lambda function for RI utilization analysis
        self.utilization_lambda = self._create_utilization_lambda(unique_suffix)

        # Create Lambda function for RI recommendations
        self.recommendations_lambda = self._create_recommendations_lambda(unique_suffix)

        # Create Lambda function for RI monitoring
        self.monitoring_lambda = self._create_monitoring_lambda(unique_suffix)

        # Create EventBridge schedules
        self._create_eventbridge_schedules(unique_suffix)

        # Output important resource information
        cdk.CfnOutput(
            self,
            "ReportsBucketName",
            value=self.reports_bucket.bucket_name,
            description="S3 bucket for RI reports"
        )

        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notifications_topic.topic_arn,
            description="SNS topic for RI notifications"
        )

        cdk.CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.ri_tracking_table.table_name,
            description="DynamoDB table for RI tracking"
        )

    def _create_utilization_lambda(self, unique_suffix: str) -> _lambda.Function:
        """
        Create Lambda function for RI utilization analysis
        
        This function analyzes Reserved Instance utilization using Cost Explorer API
        and generates alerts for underperforming reservations.
        """
        return _lambda.Function(
            self,
            "RIUtilizationLambda",
            function_name=f"ri-utilization-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import boto3
import datetime
from decimal import Decimal
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get environment variables
    bucket_name = os.environ['S3_BUCKET_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    # Calculate date range (last 30 days)
    end_date = datetime.date.today()
    start_date = end_date - datetime.timedelta(days=30)
    
    try:
        # Get RI utilization data
        response = ce.get_reservation_utilization(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        # Process utilization data
        utilization_data = []
        alerts = []
        
        for result in response['UtilizationsByTime']:
            for group in result['Groups']:
                service = group['Keys'][0]
                utilization = group['Attributes']['UtilizationPercentage']
                
                utilization_data.append({
                    'service': service,
                    'utilization_percentage': float(utilization),
                    'period': result['TimePeriod']['Start'],
                    'total_actual_hours': group['Attributes']['TotalActualHours'],
                    'unused_hours': group['Attributes']['UnusedHours']
                })
                
                # Check for low utilization (below 80%)
                if float(utilization) < 80:
                    alerts.append({
                        'service': service,
                        'utilization': utilization,
                        'type': 'LOW_UTILIZATION',
                        'message': f'Low RI utilization for {service}: {utilization}%'
                    })
        
        # Save report to S3
        report_key = f"ri-utilization-reports/{start_date.strftime('%Y-%m-%d')}.json"
        s3.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps({
                'report_date': end_date.strftime('%Y-%m-%d'),
                'period': f"{start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}",
                'utilization_data': utilization_data,
                'alerts': alerts
            }, indent=2)
        )
        
        # Send alerts if any
        if alerts:
            message = f"RI Utilization Alert Report\\n\\n"
            for alert in alerts:
                message += f"- {alert['message']}\\n"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Utilization Alert",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI utilization analysis completed',
                'report_location': f"s3://{bucket_name}/{report_key}",
                'alerts_generated': len(alerts)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
            """),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "S3_BUCKET_NAME": self.reports_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.notifications_topic.topic_arn
            },
            log_retention=logs.RetentionDays.ONE_MONTH
        )

    def _create_recommendations_lambda(self, unique_suffix: str) -> _lambda.Function:
        """
        Create Lambda function for RI purchase recommendations
        
        This function retrieves RI purchase recommendations from Cost Explorer API
        and generates reports with potential savings opportunities.
        """
        return _lambda.Function(
            self,
            "RIRecommendationsLambda",
            function_name=f"ri-recommendations-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get environment variables
    bucket_name = os.environ['S3_BUCKET_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Get RI recommendations for EC2
        ec2_response = ce.get_reservation_purchase_recommendation(
            Service='Amazon Elastic Compute Cloud - Compute',
            LookbackPeriodInDays='SIXTY_DAYS',
            TermInYears='ONE_YEAR',
            PaymentOption='PARTIAL_UPFRONT'
        )
        
        # Get RI recommendations for RDS
        rds_response = ce.get_reservation_purchase_recommendation(
            Service='Amazon Relational Database Service',
            LookbackPeriodInDays='SIXTY_DAYS',
            TermInYears='ONE_YEAR',
            PaymentOption='PARTIAL_UPFRONT'
        )
        
        # Process recommendations
        recommendations = []
        total_estimated_savings = 0
        
        # Process EC2 recommendations
        for recommendation in ec2_response['Recommendations']:
            rec_data = {
                'service': 'EC2',
                'instance_type': recommendation['InstanceDetails']['EC2InstanceDetails']['InstanceType'],
                'region': recommendation['InstanceDetails']['EC2InstanceDetails']['Region'],
                'recommended_instances': recommendation['RecommendationDetails']['RecommendedNumberOfInstancesToPurchase'],
                'estimated_monthly_savings': float(recommendation['RecommendationDetails']['EstimatedMonthlySavingsAmount']),
                'estimated_monthly_on_demand_cost': float(recommendation['RecommendationDetails']['EstimatedMonthlyOnDemandCost']),
                'upfront_cost': float(recommendation['RecommendationDetails']['UpfrontCost']),
                'recurring_cost': float(recommendation['RecommendationDetails']['RecurringStandardMonthlyCost'])
            }
            recommendations.append(rec_data)
            total_estimated_savings += rec_data['estimated_monthly_savings']
        
        # Process RDS recommendations
        for recommendation in rds_response['Recommendations']:
            rec_data = {
                'service': 'RDS',
                'instance_type': recommendation['InstanceDetails']['RDSInstanceDetails']['InstanceType'],
                'database_engine': recommendation['InstanceDetails']['RDSInstanceDetails']['DatabaseEngine'],
                'region': recommendation['InstanceDetails']['RDSInstanceDetails']['Region'],
                'recommended_instances': recommendation['RecommendationDetails']['RecommendedNumberOfInstancesToPurchase'],
                'estimated_monthly_savings': float(recommendation['RecommendationDetails']['EstimatedMonthlySavingsAmount']),
                'estimated_monthly_on_demand_cost': float(recommendation['RecommendationDetails']['EstimatedMonthlyOnDemandCost']),
                'upfront_cost': float(recommendation['RecommendationDetails']['UpfrontCost']),
                'recurring_cost': float(recommendation['RecommendationDetails']['RecurringStandardMonthlyCost'])
            }
            recommendations.append(rec_data)
            total_estimated_savings += rec_data['estimated_monthly_savings']
        
        # Save recommendations to S3
        today = datetime.date.today()
        report_key = f"ri-recommendations/{today.strftime('%Y-%m-%d')}.json"
        
        report_data = {
            'report_date': today.strftime('%Y-%m-%d'),
            'total_recommendations': len(recommendations),
            'total_estimated_monthly_savings': total_estimated_savings,
            'recommendations': recommendations
        }
        
        s3.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(report_data, indent=2)
        )
        
        # Send notification if there are recommendations
        if recommendations:
            message = f"RI Purchase Recommendations Report\\n\\n"
            message += f"Total Recommendations: {len(recommendations)}\\n"
            message += f"Estimated Monthly Savings: ${total_estimated_savings:.2f}\\n\\n"
            
            for rec in recommendations[:5]:  # Show top 5
                message += f"- {rec['service']}: {rec['instance_type']} "
                message += f"(${rec['estimated_monthly_savings']:.2f}/month savings)\\n"
            
            if len(recommendations) > 5:
                message += f"... and {len(recommendations) - 5} more recommendations\\n"
            
            message += f"\\nFull report: s3://{bucket_name}/{report_key}"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Purchase Recommendations",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI recommendations analysis completed',
                'report_location': f"s3://{bucket_name}/{report_key}",
                'recommendations_count': len(recommendations),
                'estimated_savings': total_estimated_savings
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
            """),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "S3_BUCKET_NAME": self.reports_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.notifications_topic.topic_arn
            },
            log_retention=logs.RetentionDays.ONE_MONTH
        )

    def _create_monitoring_lambda(self, unique_suffix: str) -> _lambda.Function:
        """
        Create Lambda function for RI monitoring and expiration tracking
        
        This function monitors Reserved Instance lifecycles and sends alerts
        for upcoming expirations to enable proactive renewal planning.
        """
        return _lambda.Function(
            self,
            "RIMonitoringLambda",
            function_name=f"ri-monitoring-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    ec2 = boto3.client('ec2')
    dynamodb = boto3.resource('dynamodb')
    sns = boto3.client('sns')
    
    # Get environment variables
    table_name = os.environ['DYNAMODB_TABLE_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get EC2 Reserved Instances
        response = ec2.describe_reserved_instances(
            Filters=[
                {
                    'Name': 'state',
                    'Values': ['active']
                }
            ]
        )
        
        alerts = []
        current_time = datetime.datetime.utcnow()
        
        for ri in response['ReservedInstances']:
            ri_id = ri['ReservedInstancesId']
            end_date = ri['End']
            
            # Calculate days until expiration
            days_until_expiration = (end_date.replace(tzinfo=None) - current_time).days
            
            # Store RI data in DynamoDB
            table.put_item(
                Item={
                    'ReservationId': ri_id,
                    'Timestamp': int(current_time.timestamp()),
                    'InstanceType': ri['InstanceType'],
                    'InstanceCount': ri['InstanceCount'],
                    'State': ri['State'],
                    'Start': ri['Start'].isoformat(),
                    'End': ri['End'].isoformat(),
                    'Duration': ri['Duration'],
                    'OfferingClass': ri['OfferingClass'],
                    'OfferingType': ri['OfferingType'],
                    'DaysUntilExpiration': days_until_expiration,
                    'AvailabilityZone': ri.get('AvailabilityZone', 'N/A'),
                    'Region': ri['AvailabilityZone'][:-1] if ri.get('AvailabilityZone') else 'N/A'
                }
            )
            
            # Check for expiration alerts
            if days_until_expiration <= 90:  # 90 days warning
                alert_type = 'EXPIRING_SOON' if days_until_expiration > 30 else 'EXPIRING_VERY_SOON'
                alerts.append({
                    'reservation_id': ri_id,
                    'instance_type': ri['InstanceType'],
                    'instance_count': ri['InstanceCount'],
                    'days_until_expiration': days_until_expiration,
                    'end_date': ri['End'].strftime('%Y-%m-%d'),
                    'alert_type': alert_type
                })
        
        # Send alerts if any
        if alerts:
            message = f"Reserved Instance Expiration Alert\\n\\n"
            
            for alert in alerts:
                urgency = "URGENT" if alert['days_until_expiration'] <= 30 else "WARNING"
                message += f"[{urgency}] RI {alert['reservation_id']}\\n"
                message += f"  Instance Type: {alert['instance_type']}\\n"
                message += f"  Count: {alert['instance_count']}\\n"
                message += f"  Expires: {alert['end_date']} ({alert['days_until_expiration']} days)\\n\\n"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Expiration Alert",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI monitoring completed',
                'total_reservations': len(response['ReservedInstances']),
                'expiration_alerts': len(alerts)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
            """),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "DYNAMODB_TABLE_NAME": self.ri_tracking_table.table_name,
                "SNS_TOPIC_ARN": self.notifications_topic.topic_arn
            },
            log_retention=logs.RetentionDays.ONE_MONTH
        )

    def _create_eventbridge_schedules(self, unique_suffix: str) -> None:
        """
        Create EventBridge schedules for automated Lambda execution
        
        Sets up scheduled triggers for RI analysis, recommendations, and monitoring
        to ensure consistent and automated RI management operations.
        """
        # Daily RI utilization analysis at 8 AM UTC
        daily_utilization_rule = events.Rule(
            self,
            "DailyUtilizationRule",
            rule_name=f"ri-daily-utilization-{unique_suffix}",
            description="Daily RI utilization analysis at 8 AM UTC",
            schedule=events.Schedule.cron(
                minute="0",
                hour="8",
                month="*",
                week_day="*",
                year="*"
            )
        )
        daily_utilization_rule.add_target(
            targets.LambdaFunction(self.utilization_lambda)
        )

        # Weekly RI recommendations on Monday at 9 AM UTC
        weekly_recommendations_rule = events.Rule(
            self,
            "WeeklyRecommendationsRule",
            rule_name=f"ri-weekly-recommendations-{unique_suffix}",
            description="Weekly RI recommendations on Monday at 9 AM UTC",
            schedule=events.Schedule.cron(
                minute="0",
                hour="9",
                month="*",
                week_day="MON",
                year="*"
            )
        )
        weekly_recommendations_rule.add_target(
            targets.LambdaFunction(self.recommendations_lambda)
        )

        # Weekly RI monitoring on Monday at 10 AM UTC
        weekly_monitoring_rule = events.Rule(
            self,
            "WeeklyMonitoringRule",
            rule_name=f"ri-weekly-monitoring-{unique_suffix}",
            description="Weekly RI monitoring on Monday at 10 AM UTC",
            schedule=events.Schedule.cron(
                minute="0",
                hour="10",
                month="*",
                week_day="MON",
                year="*"
            )
        )
        weekly_monitoring_rule.add_target(
            targets.LambdaFunction(self.monitoring_lambda)
        )


# CDK App
app = cdk.App()

# Create the stack
ReservedInstanceManagementStack(
    app,
    "ReservedInstanceManagementStack",
    description="Automated Reserved Instance management with Cost Explorer, Lambda, and EventBridge",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION")
    )
)

app.synth()