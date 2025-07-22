#!/usr/bin/env python3
"""
AWS CDK Python Application for Proactive Application Resilience Monitoring
with AWS Resilience Hub and EventBridge

This CDK application deploys a complete proactive resilience monitoring solution
including AWS Resilience Hub, EventBridge, Lambda functions, CloudWatch dashboards,
and supporting infrastructure for automated resilience monitoring and remediation.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    Tags,
    CfnOutput,
    RemovalPolicy,
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_sns as sns
from aws_cdk import aws_sns_subscriptions as subscriptions
from aws_cdk import aws_logs as logs
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_rds as rds
from aws_cdk import aws_resiliencehub as resiliencehub
from constructs import Construct


class ResilienceMonitoringStack(Stack):
    """
    CDK Stack for deploying proactive application resilience monitoring
    with AWS Resilience Hub and EventBridge integration.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        app_name: str,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.app_name = app_name
        self.notification_email = notification_email

        # Create core infrastructure
        self.vpc = self._create_vpc()
        self.demo_instance = self._create_demo_instance()
        self.demo_database = self._create_demo_database()

        # Create IAM roles
        self.automation_role = self._create_automation_role()
        self.lambda_role = self._create_lambda_role()

        # Create resilience monitoring components
        self.resilience_policy = self._create_resilience_policy()
        self.resilience_app = self._create_resilience_application()
        
        # Create event processing infrastructure
        self.sns_topic = self._create_sns_topic()
        self.lambda_function = self._create_lambda_function()
        self.eventbridge_rule = self._create_eventbridge_rule()

        # Create monitoring infrastructure
        self.cloudwatch_dashboard = self._create_cloudwatch_dashboard()
        self.cloudwatch_alarms = self._create_cloudwatch_alarms()

        # Add tags to all resources
        self._add_tags()

        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets across multiple AZs."""
        vpc = ec2.Vpc(
            self,
            "ResilienceDemoVpc",
            vpc_name=f"{self.app_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add VPC Flow Logs for monitoring
        vpc.add_flow_log(
            "VpcFlowLogs",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self,
                    "VpcFlowLogsGroup",
                    log_group_name=f"/aws/vpc/flowlogs/{self.app_name}",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY,
                )
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )

        return vpc

    def _create_demo_instance(self) -> ec2.Instance:
        """Create demo EC2 instance for resilience assessment."""
        # Create security group for demo instance
        instance_sg = ec2.SecurityGroup(
            self,
            "DemoInstanceSecurityGroup",
            vpc=self.vpc,
            description="Security group for resilience demo instance",
            allow_all_outbound=True,
        )

        # Create IAM role for EC2 instance with SSM permissions
        instance_role = iam.Role(
            self,
            "DemoInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchAgentServerPolicy"
                ),
            ],
        )

        # Create EC2 instance
        instance = ec2.Instance(
            self,
            "DemoInstance",
            vpc=self.vpc,
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.AmazonLinuxImage(
                generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
            ),
            security_group=instance_sg,
            role=instance_role,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            user_data=ec2.UserData.for_linux(),
        )

        # Install CloudWatch agent
        instance.user_data.add_commands(
            "yum update -y",
            "yum install -y amazon-cloudwatch-agent",
            "systemctl enable amazon-cloudwatch-agent",
            "systemctl start amazon-cloudwatch-agent",
        )

        return instance

    def _create_demo_database(self) -> rds.DatabaseInstance:
        """Create demo RDS database for resilience assessment."""
        # Create security group for database
        db_sg = ec2.SecurityGroup(
            self,
            "DemoDatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for resilience demo database",
            allow_all_outbound=False,
        )

        # Allow access from demo instance
        db_sg.add_ingress_rule(
            peer=self.demo_instance.connections.security_groups[0],
            connection=ec2.Port.tcp(3306),
            description="MySQL access from demo instance",
        )

        # Create subnet group
        subnet_group = rds.SubnetGroup(
            self,
            "DemoDbSubnetGroup",
            description="Subnet group for resilience demo database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )

        # Create RDS instance with Multi-AZ for resilience
        database = rds.DatabaseInstance(
            self,
            "DemoDatabase",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
            ),
            credentials=rds.Credentials.from_generated_secret(
                "admin",
                secret_name=f"{self.app_name}-db-credentials",
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\@",
            ),
            vpc=self.vpc,
            subnet_group=subnet_group,
            security_groups=[db_sg],
            multi_az=True,
            storage_encrypted=True,
            backup_retention=Duration.days(7),
            deletion_protection=False,
            delete_automated_backups=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return database

    def _create_automation_role(self) -> iam.Role:
        """Create IAM role for automation workflows."""
        role = iam.Role(
            self,
            "AutomationRole",
            role_name=f"ResilienceAutomationRole-{self.app_name}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("ssm.amazonaws.com"),
                iam.ServicePrincipal("lambda.amazonaws.com"),
            ),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMAutomationRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchAgentServerPolicy"
                ),
            ],
        )

        # Add custom policies for resilience monitoring
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "resiliencehub:*",
                    "cloudwatch:PutMetricData",
                    "cloudwatch:GetMetricStatistics",
                    "sns:Publish",
                    "ssm:StartAutomationExecution",
                    "ssm:GetAutomationExecution",
                    "events:PutEvents",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda function."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )

        # Add permissions for resilience monitoring
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "cloudwatch:GetMetricStatistics",
                    "ssm:StartAutomationExecution",
                    "ssm:GetAutomationExecution",
                    "sns:Publish",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_resilience_policy(self) -> resiliencehub.CfnResiliencyPolicy:
        """Create AWS Resilience Hub policy with mission-critical requirements."""
        policy = resiliencehub.CfnResiliencyPolicy(
            self,
            "ResiliencePolicy",
            policy_name=f"{self.app_name}-resilience-policy",
            policy_description="Mission-critical resilience policy for demo application monitoring",
            tier="MissionCritical",
            policy={
                "AZ": {
                    "rtoInSecs": 300,  # 5 minutes
                    "rpoInSecs": 60,   # 1 minute
                },
                "Hardware": {
                    "rtoInSecs": 600,  # 10 minutes
                    "rpoInSecs": 300,  # 5 minutes
                },
                "Software": {
                    "rtoInSecs": 300,  # 5 minutes
                    "rpoInSecs": 60,   # 1 minute
                },
                "Region": {
                    "rtoInSecs": 3600,  # 1 hour
                    "rpoInSecs": 1800,  # 30 minutes
                },
            },
            tags={
                "Environment": "demo",
                "Purpose": "resilience-monitoring",
                "Application": self.app_name,
            },
        )

        return policy

    def _create_resilience_application(self) -> resiliencehub.CfnApp:
        """Create AWS Resilience Hub application."""
        # Create application template with resources
        app_template = {
            "AWSTemplateFormatVersion": "2010-09-09",
            "Description": "Resilience Hub application template for demo application",
            "Resources": {
                "WebTierInstance": {
                    "Type": "AWS::EC2::Instance",
                    "Properties": {
                        "InstanceId": self.demo_instance.instance_id
                    }
                },
                "DatabaseInstance": {
                    "Type": "AWS::RDS::DBInstance",
                    "Properties": {
                        "DBInstanceIdentifier": self.demo_database.instance_identifier
                    }
                }
            }
        }

        app = resiliencehub.CfnApp(
            self,
            "ResilienceApp",
            app_name=self.app_name,
            description="Demo application for proactive resilience monitoring",
            app_template_body=cdk.Fn.to_json_string(app_template),
            resiliency_policy_arn=self.resilience_policy.attr_policy_arn,
            tags={
                "Environment": "demo",
                "Purpose": "resilience-monitoring",
                "Application": self.app_name,
            },
        )

        # Ensure policy is created before app
        app.add_dependency(self.resilience_policy)

        return app

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for resilience alerts."""
        topic = sns.Topic(
            self,
            "ResilienceAlertsTopic",
            topic_name="resilience-alerts",
            display_name="Resilience Monitoring Alerts",
        )

        # Add email subscription if provided
        if self.notification_email:
            topic.add_subscription(
                subscriptions.EmailSubscription(self.notification_email)
            )

        return topic

    def _create_lambda_function(self) -> lambda_.Function:
        """Create Lambda function for processing resilience events."""
        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process EventBridge events from AWS Resilience Hub and trigger
    appropriate remediation actions based on resilience scores.
    """
    logger.info(f"Received resilience event: {json.dumps(event)}")
    
    ssm = boto3.client('ssm')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Parse EventBridge event
        event_detail = event.get('detail', {})
        app_name = event_detail.get('applicationName', 'unknown')
        assessment_status = event_detail.get('assessmentStatus', 'UNKNOWN')
        resilience_score = event_detail.get('resilienceScore', 0)
        
        # Log resilience metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='ResilienceHub/Monitoring',
            MetricData=[
                {
                    'MetricName': 'ResilienceScore',
                    'Dimensions': [
                        {
                            'Name': 'ApplicationName',
                            'Value': app_name
                        }
                    ],
                    'Value': resilience_score,
                    'Unit': 'Percent',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'AssessmentEvents',
                    'Dimensions': [
                        {
                            'Name': 'ApplicationName',
                            'Value': app_name
                        },
                        {
                            'Name': 'Status',
                            'Value': assessment_status
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        # Trigger remediation if score below threshold
        if resilience_score < 80:
            logger.info(f"Resilience score {resilience_score}% below threshold, triggering remediation")
            
            # Create SNS message with detailed information
            message = {
                'application': app_name,
                'resilience_score': resilience_score,
                'status': assessment_status,
                'timestamp': datetime.utcnow().isoformat(),
                'action': 'remediation_required'
            }
            
            # Publish to SNS topic
            sns = boto3.client('sns')
            topic_arn = f'arn:aws:sns:{boto3.Session().region_name}:{context.invoked_function_arn.split(":")[4]}:resilience-alerts'
            
            try:
                sns.publish(
                    TopicArn=topic_arn,
                    Message=json.dumps(message, indent=2),
                    Subject=f'Resilience Alert: {app_name} Score Below Threshold'
                )
                logger.info(f"Published remediation alert to SNS topic")
            except Exception as sns_error:
                logger.error(f"Failed to publish SNS message: {str(sns_error)}")
        else:
            logger.info(f"Resilience score {resilience_score}% above threshold, no action required")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'application': app_name,
                'resilience_score': resilience_score,
                'assessment_status': assessment_status
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        
        # Log error metric
        try:
            cloudwatch.put_metric_data(
                Namespace='ResilienceHub/Monitoring',
                MetricData=[
                    {
                        'MetricName': 'ProcessingErrors',
                        'Value': 1,
                        'Unit': 'Count',
                        'Timestamp': datetime.utcnow()
                    }
                ]
            )
        except Exception as cw_error:
            logger.error(f"Failed to log error metric: {str(cw_error)}")
        
        raise e
'''

        function = lambda_.Function(
            self,
            "ResilienceEventProcessor",
            function_name=f"resilience-processor-{self.app_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            environment={
                "LOG_LEVEL": "INFO",
                "APP_NAME": self.app_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Grant SNS publish permissions
        self.sns_topic.grant_publish(function)

        return function

    def _create_eventbridge_rule(self) -> events.Rule:
        """Create EventBridge rule for resilience events."""
        rule = events.Rule(
            self,
            "ResilienceHubAssessmentRule",
            rule_name="ResilienceHubAssessmentRule",
            description="Comprehensive rule for Resilience Hub assessment events",
            event_pattern=events.EventPattern(
                source=["aws.resiliencehub"],
                detail_type=[
                    "Resilience Assessment State Change",
                    "Application Assessment Completed",
                    "Policy Compliance Change",
                ],
                detail={
                    "state": [
                        "ASSESSMENT_COMPLETED",
                        "ASSESSMENT_FAILED",
                        "ASSESSMENT_IN_PROGRESS",
                    ]
                },
            ),
            enabled=True,
        )

        # Add Lambda function as target with input transformation
        rule.add_target(
            targets.LambdaFunction(
                self.lambda_function,
                event=events.RuleTargetInput.from_object({
                    "applicationName": events.EventField.from_path("$.detail.applicationName"),
                    "assessmentStatus": events.EventField.from_path("$.detail.state"),
                    "resilienceScore": events.EventField.from_path("$.detail.resilienceScore"),
                }),
            )
        )

        return rule

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for resilience monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "ResilienceMonitoringDashboard",
            dashboard_name="Application-Resilience-Monitoring",
        )

        # Resilience score metric widget
        resilience_score_widget = cloudwatch.GraphWidget(
            title="Application Resilience Score Trend",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="ResilienceHub/Monitoring",
                    metric_name="ResilienceScore",
                    dimensions_map={"ApplicationName": self.app_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                )
            ],
            left_y_axis=cloudwatch.YAxisProps(min=0, max=100),
            left_annotations=[
                cloudwatch.HorizontalAnnotation(
                    value=80, label="Critical Threshold", color=cloudwatch.Color.RED
                )
            ],
        )

        # Assessment events widget
        assessment_events_widget = cloudwatch.GraphWidget(
            title="Assessment Events and Processing Status",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="ResilienceHub/Monitoring",
                    metric_name="AssessmentEvents",
                    dimensions_map={
                        "ApplicationName": self.app_name,
                        "Status": "ASSESSMENT_COMPLETED",
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="ResilienceHub/Monitoring",
                    metric_name="AssessmentEvents",
                    dimensions_map={
                        "ApplicationName": self.app_name,
                        "Status": "ASSESSMENT_FAILED",
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="ResilienceHub/Monitoring",
                    metric_name="ProcessingErrors",
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
            ],
        )

        # Lambda function metrics widget
        lambda_metrics_widget = cloudwatch.GraphWidget(
            title="Lambda Function Performance",
            width=24,
            height=6,
            left=[
                self.lambda_function.metric_invocations(
                    statistic="Sum", period=Duration.minutes(5)
                ),
                self.lambda_function.metric_errors(
                    statistic="Sum", period=Duration.minutes(5)
                ),
                self.lambda_function.metric_duration(
                    statistic="Average", period=Duration.minutes(5)
                ),
            ],
        )

        # Add widgets to dashboard
        dashboard.add_widgets(resilience_score_widget, assessment_events_widget)
        dashboard.add_widgets(lambda_metrics_widget)

        return dashboard

    def _create_cloudwatch_alarms(self) -> List[cloudwatch.Alarm]:
        """Create CloudWatch alarms for proactive monitoring."""
        alarms = []

        # Critical low resilience score alarm
        critical_alarm = cloudwatch.Alarm(
            self,
            "CriticalLowResilienceScore",
            alarm_name="Critical-Low-Resilience-Score",
            alarm_description="Critical alert when resilience score drops below 70%",
            metric=cloudwatch.Metric(
                namespace="ResilienceHub/Monitoring",
                metric_name="ResilienceScore",
                dimensions_map={"ApplicationName": self.app_name},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=70,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            datapoints_to_alarm=1,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        critical_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        critical_alarm.add_ok_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        alarms.append(critical_alarm)

        # Warning low resilience score alarm
        warning_alarm = cloudwatch.Alarm(
            self,
            "WarningLowResilienceScore",
            alarm_name="Warning-Low-Resilience-Score",
            alarm_description="Warning when resilience score drops below 80%",
            metric=cloudwatch.Metric(
                namespace="ResilienceHub/Monitoring",
                metric_name="ResilienceScore",
                dimensions_map={"ApplicationName": self.app_name},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            datapoints_to_alarm=2,
            evaluation_periods=3,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        warning_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        alarms.append(warning_alarm)

        # Assessment failures alarm
        failure_alarm = cloudwatch.Alarm(
            self,
            "ResilienceAssessmentFailures",
            alarm_name="Resilience-Assessment-Failures",
            alarm_description="Alert when resilience assessments fail repeatedly",
            metric=cloudwatch.Metric(
                namespace="ResilienceHub/Monitoring",
                metric_name="AssessmentEvents",
                dimensions_map={
                    "ApplicationName": self.app_name,
                    "Status": "ASSESSMENT_FAILED",
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            datapoints_to_alarm=1,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        alarms.append(failure_alarm)

        # Lambda function error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaProcessingErrors",
            alarm_name="Lambda-Processing-Errors",
            alarm_description="Alert when Lambda function experiences errors",
            metric=self.lambda_function.metric_errors(
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            datapoints_to_alarm=1,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        lambda_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        alarms.append(lambda_error_alarm)

        return alarms

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Application", self.app_name)
        Tags.of(self).add("Environment", "demo")
        Tags.of(self).add("Purpose", "resilience-monitoring")
        Tags.of(self).add("ManagedBy", "AWS-CDK")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for the resilience demo environment",
        )

        CfnOutput(
            self,
            "DemoInstanceId",
            value=self.demo_instance.instance_id,
            description="EC2 Instance ID for resilience assessment",
        )

        CfnOutput(
            self,
            "DemoDatabaseEndpoint",
            value=self.demo_database.instance_endpoint.hostname,
            description="RDS Database endpoint for resilience assessment",
        )

        CfnOutput(
            self,
            "ResiliencePolicyArn",
            value=self.resilience_policy.attr_policy_arn,
            description="AWS Resilience Hub Policy ARN",
        )

        CfnOutput(
            self,
            "ResilienceApplicationArn",
            value=self.resilience_app.attr_app_arn,
            description="AWS Resilience Hub Application ARN",
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="Lambda function ARN for event processing",
        )

        CfnOutput(
            self,
            "SnsTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for resilience alerts",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=Application-Resilience-Monitoring",
            description="CloudWatch Dashboard URL for resilience monitoring",
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()

    # Get configuration from context or environment variables
    app_name = app.node.try_get_context("app_name") or os.environ.get("APP_NAME", "resilience-demo")
    notification_email = app.node.try_get_context("notification_email") or os.environ.get("NOTIFICATION_EMAIL")
    
    # Create the stack
    ResilienceMonitoringStack(
        app,
        "ResilienceMonitoringStack",
        app_name=app_name,
        notification_email=notification_email,
        description="Proactive Application Resilience Monitoring with AWS Resilience Hub and EventBridge",
    )

    app.synth()


if __name__ == "__main__":
    main()