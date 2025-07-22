#!/usr/bin/env python3
"""
AWS CDK Application for Carbon Footprint Optimization

This CDK application creates an automated carbon footprint optimization system
that integrates AWS Customer Carbon Footprint Tool data with Cost Explorer insights
through EventBridge and Lambda. The system analyzes monthly carbon emissions
alongside cost patterns and identifies optimization opportunities.

Author: AWS CDK Team
Version: 1.0.0
"""

import os
from typing import Dict, List, Optional
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
    aws_dynamodb as dynamodb,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_s3 as s3,
    aws_scheduler as scheduler,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_ssm as ssm,
)
from constructs import Construct


class CarbonFootprintOptimizationStack(Stack):
    """
    CDK Stack for Carbon Footprint Optimization System
    
    This stack creates the complete infrastructure for automated carbon footprint
    optimization including Lambda functions, DynamoDB tables, S3 buckets,
    EventBridge schedules, and SNS notifications.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: Optional[str] = None,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Set default project name if not provided
        self.project_name = project_name or "carbon-optimizer"
        self.notification_email = notification_email
        
        # Create foundational resources
        self.data_bucket = self._create_data_bucket()
        self.metrics_table = self._create_metrics_table()
        self.notification_topic = self._create_notification_topic()
        
        # Create Lambda function and IAM role
        self.lambda_role = self._create_lambda_role()
        self.analyzer_function = self._create_analyzer_function()
        
        # Create automation schedules
        self._create_automation_schedules()
        
        # Create SSM parameters for configuration
        self._create_ssm_parameters()
        
        # Create Cost and Usage Report configuration
        self._create_cur_configuration()
        
        # Add tags to all resources
        self._add_resource_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_data_bucket(self) -> s3.Bucket:
        """Create S3 bucket for data storage with security best practices"""
        bucket = s3.Bucket(
            self,
            "DataBucket",
            bucket_name=f"{self.project_name}-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="CostOptimizationLifecycle",
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
        
        # Add bucket notification for automated processing
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            targets.LambdaFunction(self.analyzer_function) if hasattr(self, 'analyzer_function') else None
        )
        
        return bucket

    def _create_metrics_table(self) -> dynamodb.Table:
        """Create DynamoDB table for storing carbon footprint metrics"""
        table = dynamodb.Table(
            self,
            "MetricsTable",
            table_name=f"{self.project_name}-metrics",
            partition_key=dynamodb.Attribute(
                name="MetricType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )
        
        # Add Global Secondary Index for service-based queries
        table.add_global_secondary_index(
            index_name="ServiceCarbonIndex",
            partition_key=dynamodb.Attribute(
                name="ServiceName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="CarbonIntensity",
                type=dynamodb.AttributeType.NUMBER
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )
        
        return table

    def _create_notification_topic(self) -> sns.Topic:
        """Create SNS topic for optimization notifications"""
        topic = sns.Topic(
            self,
            "NotificationTopic",
            topic_name=f"{self.project_name}-notifications",
            display_name="Carbon Footprint Optimization Notifications"
        )
        
        # Add email subscription if email is provided
        if self.notification_email:
            topic.add_subscription(
                subscriptions.EmailSubscription(self.notification_email)
            )
        
        return topic

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda function with comprehensive permissions"""
        role = iam.Role(
            self,
            "LambdaRole",
            role_name=f"{self.project_name}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add custom policy for carbon footprint optimization
        policy_document = iam.PolicyDocument(
            statements=[
                # Cost Explorer permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ce:GetCostAndUsage",
                        "ce:GetDimensions",
                        "ce:GetUsageReport",
                        "ce:ListCostCategoryDefinitions",
                        "cur:DescribeReportDefinitions"
                    ],
                    resources=["*"]
                ),
                # S3 permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket"
                    ],
                    resources=[
                        self.data_bucket.bucket_arn,
                        f"{self.data_bucket.bucket_arn}/*"
                    ]
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
                    resources=[
                        self.metrics_table.table_arn,
                        f"{self.metrics_table.table_arn}/index/*"
                    ]
                ),
                # SNS permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sns:Publish"],
                    resources=[self.notification_topic.topic_arn]
                ),
                # SSM permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ssm:GetParameter",
                        "ssm:PutParameter",
                        "ssm:GetParameters"
                    ],
                    resources=[f"arn:aws:ssm:{self.region}:{self.account}:parameter/{self.project_name}/*"]
                )
            ]
        )
        
        role.attach_inline_policy(
            iam.Policy(
                self,
                "CarbonOptimizationPolicy",
                document=policy_document
            )
        )
        
        return role

    def _create_analyzer_function(self) -> lambda_.Function:
        """Create Lambda function for carbon footprint analysis"""
        function = lambda_.Function(
            self,
            "AnalyzerFunction",
            function_name=f"{self.project_name}-analyzer",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "DYNAMODB_TABLE": self.metrics_table.table_name,
                "S3_BUCKET": self.data_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "PROJECT_NAME": self.project_name
            },
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            log_retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for carbon footprint analysis"""
        return '''
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ce_client = boto3.client('ce')
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
ssm_client = boto3.client('ssm')

# Environment variables
TABLE_NAME = os.environ['DYNAMODB_TABLE']
S3_BUCKET = os.environ['S3_BUCKET']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
PROJECT_NAME = os.environ['PROJECT_NAME']

table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    """
    Main handler for carbon footprint optimization analysis
    """
    try:
        logger.info("Starting carbon footprint optimization analysis")
        
        # Get current date range for analysis
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=30)
        
        # Fetch cost and usage data
        cost_data = get_cost_and_usage_data(start_date, end_date)
        
        # Analyze carbon footprint correlations
        carbon_analysis = analyze_carbon_footprint(cost_data)
        
        # Store metrics in DynamoDB
        store_metrics(carbon_analysis)
        
        # Generate optimization recommendations
        recommendations = generate_recommendations(carbon_analysis)
        
        # Send notifications if significant findings
        if recommendations['high_impact_actions']:
            send_optimization_notifications(recommendations)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Carbon footprint analysis completed successfully',
                'recommendations_count': len(recommendations['all_actions']),
                'high_impact_count': len(recommendations['high_impact_actions'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error in carbon footprint analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_cost_and_usage_data(start_date, end_date):
    """
    Retrieve cost and usage data from Cost Explorer
    """
    try:
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'REGION'}
            ]
        )
        
        return response['ResultsByTime']
        
    except Exception as e:
        logger.error(f"Error retrieving cost data: {str(e)}")
        raise

def analyze_carbon_footprint(cost_data):
    """
    Analyze carbon footprint patterns based on cost and usage data
    """
    analysis = {
        'total_cost': 0,
        'estimated_carbon_kg': 0,
        'services': {},
        'regions': {},
        'optimization_potential': 0
    }
    
    # Carbon intensity factors (kg CO2e per USD) by service type
    carbon_factors = {
        'Amazon Elastic Compute Cloud': 0.5,
        'Amazon Simple Storage Service': 0.1,
        'Amazon Relational Database Service': 0.7,
        'AWS Lambda': 0.05,
        'Amazon CloudFront': 0.02
    }
    
    # Regional carbon intensity factors (kg CO2e per kWh)
    regional_factors = {
        'us-east-1': 0.4,
        'us-west-2': 0.2,
        'eu-west-1': 0.3,
        'ap-southeast-2': 0.8
    }
    
    for time_period in cost_data:
        for group in time_period.get('Groups', []):
            service = group['Keys'][0]
            region = group['Keys'][1] if len(group['Keys']) > 1 else 'global'
            
            cost = float(group['Metrics']['BlendedCost']['Amount'])
            analysis['total_cost'] += cost
            
            # Calculate estimated carbon footprint
            service_factor = carbon_factors.get(service, 0.3)
            regional_factor = regional_factors.get(region, 0.5)
            
            estimated_carbon = cost * service_factor * regional_factor
            analysis['estimated_carbon_kg'] += estimated_carbon
            
            # Track by service
            if service not in analysis['services']:
                analysis['services'][service] = {
                    'cost': 0, 'carbon_kg': 0, 'optimization_score': 0
                }
            
            analysis['services'][service]['cost'] += cost
            analysis['services'][service]['carbon_kg'] += estimated_carbon
            
            # Calculate optimization score
            analysis['services'][service]['optimization_score'] = (
                estimated_carbon / cost if cost > 0 else 0
            )
    
    return analysis

def generate_recommendations(analysis):
    """
    Generate carbon footprint optimization recommendations
    """
    recommendations = {
        'all_actions': [],
        'high_impact_actions': [],
        'estimated_savings': {'cost': 0, 'carbon_kg': 0}
    }
    
    # Analyze services with high carbon intensity
    for service, metrics in analysis['services'].items():
        if metrics['optimization_score'] > 0.5:
            recommendation = {
                'service': service,
                'current_cost': metrics['cost'],
                'current_carbon_kg': metrics['carbon_kg'],
                'action': determine_optimization_action(service, metrics),
                'estimated_cost_savings': metrics['cost'] * 0.2,
                'estimated_carbon_reduction': metrics['carbon_kg'] * 0.3
            }
            
            recommendations['all_actions'].append(recommendation)
            
            if metrics['cost'] > 100:
                recommendations['high_impact_actions'].append(recommendation)
                recommendations['estimated_savings']['cost'] += recommendation['estimated_cost_savings']
                recommendations['estimated_savings']['carbon_kg'] += recommendation['estimated_carbon_reduction']
    
    return recommendations

def determine_optimization_action(service, metrics):
    """
    Determine specific optimization action for a service
    """
    action_map = {
        'Amazon Elastic Compute Cloud': 'Consider rightsizing instances or migrating to Graviton processors',
        'Amazon Simple Storage Service': 'Implement Intelligent Tiering and lifecycle policies',
        'Amazon Relational Database Service': 'Evaluate Aurora Serverless or instance rightsizing',
        'AWS Lambda': 'Optimize memory allocation and enable Provisioned Concurrency',
        'Amazon CloudFront': 'Review caching strategies and origin optimization'
    }
    
    return action_map.get(service, 'Review resource utilization and consider sustainable alternatives')

def store_metrics(analysis):
    """
    Store analysis results in DynamoDB
    """
    timestamp = datetime.now().isoformat()
    
    # Store overall metrics
    table.put_item(
        Item={
            'MetricType': 'OVERALL_ANALYSIS',
            'Timestamp': timestamp,
            'TotalCost': Decimal(str(analysis['total_cost'])),
            'EstimatedCarbonKg': Decimal(str(analysis['estimated_carbon_kg'])),
            'ServiceCount': len(analysis['services'])
        }
    )
    
    # Store service-specific metrics
    for service, metrics in analysis['services'].items():
        table.put_item(
            Item={
                'MetricType': f'SERVICE_{service.replace(" ", "_").upper()}',
                'Timestamp': timestamp,
                'ServiceName': service,
                'Cost': Decimal(str(metrics['cost'])),
                'CarbonKg': Decimal(str(metrics['carbon_kg'])),
                'CarbonIntensity': Decimal(str(metrics['optimization_score']))
            }
        )

def send_optimization_notifications(recommendations):
    """
    Send notifications about optimization opportunities
    """
    message = f"""
Carbon Footprint Optimization Report

High-Impact Opportunities Found: {len(recommendations['high_impact_actions'])}

Estimated Monthly Savings:
- Cost: ${recommendations['estimated_savings']['cost']:.2f}
- Carbon: {recommendations['estimated_savings']['carbon_kg']:.2f} kg CO2e

Top Recommendations:
"""
    
    for i, action in enumerate(recommendations['high_impact_actions'][:3], 1):
        message += f"""
{i}. {action['service']}
   Current Cost: ${action['current_cost']:.2f}
   Carbon Impact: {action['current_carbon_kg']:.2f} kg CO2e
   Action: {action['action']}
"""
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='Carbon Footprint Optimization Report',
            Message=message
        )
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
'''

    def _create_automation_schedules(self) -> None:
        """Create EventBridge schedules for automated analysis"""
        # Create schedule group for better organization
        schedule_group = scheduler.CfnScheduleGroup(
            self,
            "ScheduleGroup",
            name=f"{self.project_name}-schedules"
        )
        
        # Monthly comprehensive analysis
        monthly_schedule = scheduler.CfnSchedule(
            self,
            "MonthlyAnalysisSchedule",
            schedule_expression="rate(30 days)",
            target=scheduler.CfnSchedule.TargetProperty(
                arn=self.analyzer_function.function_arn,
                role_arn=self.lambda_role.role_arn
            ),
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="OFF"
            ),
            group_name=schedule_group.name,
            description="Monthly carbon footprint optimization analysis"
        )
        
        # Weekly trend monitoring
        weekly_schedule = scheduler.CfnSchedule(
            self,
            "WeeklyTrendsSchedule", 
            schedule_expression="rate(7 days)",
            target=scheduler.CfnSchedule.TargetProperty(
                arn=self.analyzer_function.function_arn,
                role_arn=self.lambda_role.role_arn
            ),
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="OFF"
            ),
            group_name=schedule_group.name,
            description="Weekly carbon footprint trend monitoring"
        )

    def _create_ssm_parameters(self) -> None:
        """Create SSM parameters for configuration management"""
        # Sustainability scanner configuration
        scanner_config = {
            "rules": [
                "ec2-instance-types",
                "storage-optimization", 
                "graviton-processors",
                "regional-efficiency"
            ],
            "severity": "medium",
            "auto-fix": False
        }
        
        ssm.StringParameter(
            self,
            "ScannerConfigParameter",
            parameter_name=f"/{self.project_name}/scanner-config",
            string_value=json.dumps(scanner_config),
            description="Sustainability Scanner configuration"
        )
        
        # Carbon intensity factors parameter
        carbon_factors = {
            "services": {
                "Amazon Elastic Compute Cloud": 0.5,
                "Amazon Simple Storage Service": 0.1,
                "Amazon Relational Database Service": 0.7,
                "AWS Lambda": 0.05,
                "Amazon CloudFront": 0.02
            },
            "regions": {
                "us-east-1": 0.4,
                "us-west-2": 0.2,
                "eu-west-1": 0.3,
                "ap-southeast-2": 0.8
            }
        }
        
        ssm.StringParameter(
            self,
            "CarbonFactorsParameter",
            parameter_name=f"/{self.project_name}/carbon-factors",
            string_value=json.dumps(carbon_factors),
            description="Carbon intensity factors for services and regions"
        )

    def _create_cur_configuration(self) -> None:
        """Create Cost and Usage Report configuration"""
        # Note: CUR must be created in us-east-1, but we'll create a parameter
        # with the configuration for manual setup or automation
        cur_config = {
            "ReportName": f"{self.project_name}-detailed-report",
            "TimeUnit": "DAILY",
            "Format": "Parquet",
            "Compression": "GZIP",
            "AdditionalSchemaElements": ["RESOURCES", "SPLIT_COST_ALLOCATION_DATA"],
            "S3Bucket": self.data_bucket.bucket_name,
            "S3Prefix": "cost-usage-reports/",
            "S3Region": self.region,
            "AdditionalArtifacts": ["ATHENA"],
            "RefreshClosedReports": True,
            "ReportVersioning": "OVERWRITE_REPORT"
        }
        
        ssm.StringParameter(
            self,
            "CurConfigParameter",
            parameter_name=f"/{self.project_name}/cur-config",
            string_value=json.dumps(cur_config),
            description="Cost and Usage Report configuration for enhanced analysis"
        )

    def _add_resource_tags(self) -> None:
        """Add consistent tags to all resources"""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Purpose", "CarbonFootprintOptimization")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ManagedBy", "CDK")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for carbon footprint data storage"
        )
        
        CfnOutput(
            self,
            "MetricsTableName", 
            value=self.metrics_table.table_name,
            description="DynamoDB table for storing carbon footprint metrics"
        )
        
        CfnOutput(
            self,
            "AnalyzerFunctionName",
            value=self.analyzer_function.function_name,
            description="Lambda function for carbon footprint analysis"
        )
        
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic for optimization notifications"
        )
        
        if self.notification_email:
            CfnOutput(
                self,
                "NotificationEmail",
                value=self.notification_email,
                description="Email address for optimization notifications"
            )


def main():
    """Main application entry point"""
    app = App()
    
    # Get configuration from context or environment variables
    project_name = app.node.try_get_context("project_name") or os.environ.get("PROJECT_NAME", "carbon-optimizer")
    notification_email = app.node.try_get_context("notification_email") or os.environ.get("NOTIFICATION_EMAIL")
    
    # Create the stack with explicit environment
    CarbonFootprintOptimizationStack(
        app,
        "CarbonFootprintOptimizationStack",
        project_name=project_name,
        notification_email=notification_email,
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        ),
        description="Automated Carbon Footprint Optimization with AWS Sustainability Scanner and Cost Explorer"
    )
    
    app.synth()


if __name__ == "__main__":
    main()