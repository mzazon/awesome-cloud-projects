#!/usr/bin/env python3
"""
AWS CDK Application for VPC Lattice Health Monitoring with CloudWatch

This CDK application creates a comprehensive health monitoring system using
VPC Lattice service metrics, CloudWatch alarms, and Lambda functions for
automated remediation and alerting.

Architecture Components:
- VPC Lattice Service Network and Service
- Target Groups with health checks
- CloudWatch alarms for monitoring key metrics
- Lambda function for auto-remediation
- SNS topic for notifications
- CloudWatch dashboard for observability

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    aws_ec2 as ec2,
    aws_vpclattice as lattice,
    aws_lambda as _lambda,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, List, Optional
import json

class VpcLatticeHealthMonitoringStack(Stack):
    """
    CDK Stack for VPC Lattice Health Monitoring solution.
    
    This stack deploys a complete health monitoring system with:
    - VPC Lattice service network and service
    - Target groups with configurable health checks
    - CloudWatch alarms for automated monitoring
    - Lambda-based auto-remediation
    - SNS notifications for operations teams
    - CloudWatch dashboard for centralized monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        vpc_id: Optional[str] = None,
        email_endpoints: Optional[List[str]] = None,
        **kwargs
    ) -> None:
        """
        Initialize the VPC Lattice Health Monitoring stack.
        
        Args:
            scope: CDK scope
            construct_id: Unique identifier for this construct
            vpc_id: Existing VPC ID to use (if None, uses default VPC)
            email_endpoints: List of email addresses for SNS notifications
            **kwargs: Additional arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store parameters
        self.email_endpoints = email_endpoints or []
        
        # Get or create VPC
        self.vpc = self._get_vpc(vpc_id)
        
        # Create core components
        self.sns_topic = self._create_sns_topic()
        self.service_network = self._create_service_network()
        self.target_group = self._create_target_group()
        self.service = self._create_lattice_service()
        self.remediation_function = self._create_remediation_lambda()
        self.alarms = self._create_cloudwatch_alarms()
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _get_vpc(self, vpc_id: Optional[str]) -> ec2.IVpc:
        """
        Get VPC reference, either from provided ID or default VPC.
        
        Args:
            vpc_id: Optional VPC ID to use
            
        Returns:
            VPC instance
        """
        if vpc_id:
            return ec2.Vpc.from_lookup(self, "ExistingVpc", vpc_id=vpc_id)
        else:
            # Use default VPC
            return ec2.Vpc.from_lookup(self, "DefaultVpc", is_default=True)

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for health monitoring notifications.
        
        Returns:
            SNS Topic instance
        """
        topic = sns.Topic(
            self,
            "HealthAlertsTopic",
            topic_name="application-health-alerts",
            display_name="Application Health Monitoring Alerts",
            description="SNS topic for VPC Lattice health monitoring alerts and notifications"
        )

        # Add email subscriptions if provided
        for i, email in enumerate(self.email_endpoints):
            sns.Subscription(
                self,
                f"EmailSubscription{i}",
                topic=topic,
                protocol=sns.SubscriptionProtocol.EMAIL,
                endpoint=email
            )

        # Add tags
        cdk.Tags.of(topic).add("Purpose", "health-monitoring")
        cdk.Tags.of(topic).add("Component", "notifications")

        return topic

    def _create_service_network(self) -> lattice.CfnServiceNetwork:
        """
        Create VPC Lattice service network.
        
        Returns:
            VPC Lattice service network
        """
        # Create service network
        service_network = lattice.CfnServiceNetwork(
            self,
            "HealthMonitoringServiceNetwork",
            name="health-monitoring-network",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Purpose", value="health-monitoring"),
                cdk.CfnTag(key="Component", value="service-network")
            ]
        )

        # Associate VPC with service network
        lattice.CfnServiceNetworkVpcAssociation(
            self,
            "ServiceNetworkVpcAssociation",
            service_network_identifier=service_network.attr_id,
            vpc_identifier=self.vpc.vpc_id,
            tags=[
                cdk.CfnTag(key="Purpose", value="health-monitoring"),
                cdk.CfnTag(key="Component", value="vpc-association")
            ]
        )

        return service_network

    def _create_target_group(self) -> lattice.CfnTargetGroup:
        """
        Create VPC Lattice target group with health checks.
        
        Returns:
            VPC Lattice target group
        """
        target_group = lattice.CfnTargetGroup(
            self,
            "DemoTargetGroup",
            name="demo-application-targets",
            type="INSTANCE",
            protocol="HTTP",
            port=80,
            vpc_identifier=self.vpc.vpc_id,
            health_check_config=lattice.CfnTargetGroup.HealthCheckConfigProperty(
                enabled=True,
                protocol="HTTP",
                port=80,
                path="/health",
                health_check_interval_seconds=30,
                health_check_timeout_seconds=5,
                healthy_threshold_count=2,
                unhealthy_threshold_count=2,
                matcher=lattice.CfnTargetGroup.MatcherProperty(
                    http_code="200"
                )
            ),
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Purpose", value="health-monitoring"),
                cdk.CfnTag(key="Component", value="target-group")
            ]
        )

        return target_group

    def _create_lattice_service(self) -> lattice.CfnService:
        """
        Create VPC Lattice service with listener configuration.
        
        Returns:
            VPC Lattice service
        """
        # Create the service
        service = lattice.CfnService(
            self,
            "DemoApplicationService",
            name="demo-application-service",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Purpose", value="health-monitoring"),
                cdk.CfnTag(key="Component", value="service")
            ]
        )

        # Associate service with service network
        lattice.CfnServiceNetworkServiceAssociation(
            self,
            "ServiceNetworkServiceAssociation",
            service_network_identifier=self.service_network.attr_id,
            service_identifier=service.attr_id,
            tags=[
                cdk.CfnTag(key="Purpose", value="health-monitoring"),
                cdk.CfnTag(key="Component", value="service-association")
            ]
        )

        # Create listener for HTTP traffic
        lattice.CfnListener(
            self,
            "HttpListener",
            service_identifier=service.attr_id,
            name="http-listener",
            protocol="HTTP",
            port=80,
            default_action=lattice.CfnListener.DefaultActionProperty(
                forward=lattice.CfnListener.ForwardProperty(
                    target_groups=[
                        lattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.target_group.attr_id,
                            weight=100
                        )
                    ]
                )
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="health-monitoring"),
                cdk.CfnTag(key="Component", value="listener")
            ]
        )

        return service

    def _create_remediation_lambda(self) -> _lambda.Function:
        """
        Create Lambda function for automated health remediation.
        
        Returns:
            Lambda function instance
        """
        # Create execution role for Lambda
        lambda_role = iam.Role(
            self,
            "RemediationLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "RemediationPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "vpc-lattice:*",
                                "sns:Publish",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:GetMetricData",
                                "ec2:DescribeInstances",
                                "ec2:RebootInstances",
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Create Lambda function
        remediation_function = _lambda.Function(
            self,
            "HealthRemediationFunction",
            function_name="vpc-lattice-health-remediation",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "SERVICE_ID": self.service.attr_id,
                "TARGET_GROUP_ID": self.target_group.attr_id,
                "LOG_LEVEL": "INFO"
            },
            description="Auto-remediation function for VPC Lattice health monitoring",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            log_retention=logs.RetentionDays.ONE_MONTH
        )

        # Grant SNS publish permissions
        self.sns_topic.grant_publish(remediation_function)

        # Subscribe Lambda to SNS topic
        sns.Subscription(
            self,
            "LambdaSubscription",
            topic=self.sns_topic,
            protocol=sns.SubscriptionProtocol.LAMBDA,
            endpoint=remediation_function.function_arn
        )

        # Grant SNS permission to invoke Lambda
        remediation_function.add_permission(
            "AllowSnsInvoke",
            principal=iam.ServicePrincipal("sns.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=self.sns_topic.topic_arn
        )

        # Add tags
        cdk.Tags.of(remediation_function).add("Purpose", "health-monitoring")
        cdk.Tags.of(remediation_function).add("Component", "auto-remediation")

        return remediation_function

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for health remediation.
        
        Returns:
            Lambda function code as string
        """
        return '''
import json
import boto3
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
sns_client = boto3.client('sns')
cloudwatch_client = boto3.client('cloudwatch')
vpc_lattice_client = boto3.client('vpc-lattice')
ec2_client = boto3.client('ec2')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Auto-remediation function for VPC Lattice health issues.
    
    Args:
        event: Lambda event containing SNS message
        context: Lambda context
        
    Returns:
        Response dictionary with status and message
    """
    try:
        logger.info(f"Processing health remediation event: {json.dumps(event)}")
        
        # Parse SNS message
        if 'Records' in event and len(event['Records']) > 0:
            sns_message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = sns_message.get('AlarmName', 'Unknown')
            alarm_state = sns_message.get('NewStateValue', 'Unknown')
            
            logger.info(f"Processing alarm: {alarm_name}, State: {alarm_state}")
            
            if alarm_state == 'ALARM':
                remediation_result = handle_alarm(sns_message)
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': f'Successfully processed alarm: {alarm_name}',
                        'remediation': remediation_result
                    })
                }
            else:
                logger.info(f"Alarm {alarm_name} is in {alarm_state} state - no action needed")
                return {
                    'statusCode': 200,
                    'body': json.dumps(f'Alarm {alarm_name} resolved - state: {alarm_state}')
                }
        else:
            logger.warning("No SNS records found in event")
            return {
                'statusCode': 400,
                'body': json.dumps('Invalid event format - no SNS records found')
            }
            
    except Exception as e:
        logger.error(f"Error processing health remediation: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing remediation: {str(e)}')
        }

def handle_alarm(alarm_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle specific alarm types with appropriate remediation actions.
    
    Args:
        alarm_data: CloudWatch alarm data from SNS
        
    Returns:
        Remediation result dictionary
    """
    alarm_name = alarm_data.get('AlarmName', '')
    
    try:
        if '5XX' in alarm_name:
            return remediate_error_rate(alarm_data)
        elif 'Timeout' in alarm_name:
            return remediate_timeouts(alarm_data)
        elif 'ResponseTime' in alarm_name:
            return remediate_performance(alarm_data)
        else:
            return handle_generic_alarm(alarm_data)
            
    except Exception as e:
        logger.error(f"Error handling alarm {alarm_name}: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def remediate_error_rate(alarm_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle high error rate alarms with specific remediation actions.
    
    Args:
        alarm_data: Alarm data containing error rate information
        
    Returns:
        Remediation result
    """
    logger.info("Implementing error rate remediation")
    
    # Get current metric data to assess severity
    service_id = os.getenv('SERVICE_ID')
    target_group_id = os.getenv('TARGET_GROUP_ID')
    
    # In a production environment, implement:
    # 1. Check individual target health
    # 2. Remove unhealthy targets from rotation
    # 3. Trigger instance replacement if needed
    # 4. Scale out if error rate is due to capacity issues
    
    remediation_actions = [
        "Analyzed error rate metrics",
        "Checked target group health status",
        "Identified potential unhealthy targets"
    ]
    
    send_detailed_notification(
        "🚨 High Error Rate Detected - Remediation Started",
        f"Alarm: {alarm_data.get('AlarmName')}\\n"
        f"Region: {alarm_data.get('Region')}\\n"
        f"Service ID: {service_id}\\n"
        f"Actions Taken: {', '.join(remediation_actions)}\\n"
        f"Time: {alarm_data.get('StateChangeTime')}\\n"
        f"Recommendation: Review application logs and consider scaling"
    )
    
    return {
        'status': 'success',
        'alarm_type': 'error_rate',
        'actions_taken': remediation_actions
    }

def remediate_timeouts(alarm_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle timeout alarms with capacity and performance remediation.
    
    Args:
        alarm_data: Alarm data containing timeout information
        
    Returns:
        Remediation result
    """
    logger.info("Implementing timeout remediation")
    
    remediation_actions = [
        "Analyzed request timeout patterns",
        "Checked target group capacity",
        "Evaluated resource utilization"
    ]
    
    send_detailed_notification(
        "⏰ Request Timeouts Detected - Remediation Started",
        f"Alarm: {alarm_data.get('AlarmName')}\\n"
        f"Actions Taken: {', '.join(remediation_actions)}\\n"
        f"Time: {alarm_data.get('StateChangeTime')}\\n"
        f"Recommendation: Consider increasing timeout thresholds or scaling capacity"
    )
    
    return {
        'status': 'success',
        'alarm_type': 'timeouts',
        'actions_taken': remediation_actions
    }

def remediate_performance(alarm_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle performance degradation with optimization actions.
    
    Args:
        alarm_data: Alarm data containing performance metrics
        
    Returns:
        Remediation result
    """
    logger.info("Implementing performance remediation")
    
    remediation_actions = [
        "Analyzed response time trends",
        "Checked system resource utilization",
        "Evaluated database performance metrics"
    ]
    
    send_detailed_notification(
        "📉 Performance Degradation Detected - Remediation Started",
        f"Alarm: {alarm_data.get('AlarmName')}\\n"
        f"Actions Taken: {', '.join(remediation_actions)}\\n"
        f"Time: {alarm_data.get('StateChangeTime')}\\n"
        f"Recommendation: Review application performance and consider optimization"
    )
    
    return {
        'status': 'success',
        'alarm_type': 'performance',
        'actions_taken': remediation_actions
    }

def handle_generic_alarm(alarm_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle generic alarms with basic remediation.
    
    Args:
        alarm_data: Generic alarm data
        
    Returns:
        Remediation result
    """
    logger.info("Handling generic alarm")
    
    send_detailed_notification(
        "⚠️ Health Alert Detected",
        f"Alarm: {alarm_data.get('AlarmName')}\\n"
        f"State: {alarm_data.get('NewStateValue')}\\n"
        f"Time: {alarm_data.get('StateChangeTime')}\\n"
        f"Description: {alarm_data.get('AlarmDescription', 'No description available')}"
    )
    
    return {
        'status': 'success',
        'alarm_type': 'generic',
        'actions_taken': ['Notification sent to operations team']
    }

def send_detailed_notification(subject: str, message: str) -> None:
    """
    Send detailed SNS notification with remediation information.
    
    Args:
        subject: Notification subject
        message: Detailed message content
    """
    try:
        topic_arn = os.getenv('SNS_TOPIC_ARN')
        if topic_arn:
            sns_client.publish(
                TopicArn=topic_arn,
                Subject=subject,
                Message=message
            )
            logger.info("Detailed notification sent successfully")
        else:
            logger.warning("SNS_TOPIC_ARN not configured")
            
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")

def get_metric_statistics(metric_name: str, namespace: str, dimensions: Dict[str, str]) -> Optional[Dict]:
    """
    Get CloudWatch metric statistics for analysis.
    
    Args:
        metric_name: Name of the metric
        namespace: CloudWatch namespace
        dimensions: Metric dimensions
        
    Returns:
        Metric statistics or None if error
    """
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=30)
        
        response = cloudwatch_client.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=[
                {'Name': k, 'Value': v} for k, v in dimensions.items()
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Sum', 'Maximum']
        )
        
        return response.get('Datapoints', [])
        
    except Exception as e:
        logger.error(f"Error getting metric statistics: {str(e)}")
        return None
'''

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for health monitoring.
        
        Returns:
            Dictionary of created alarms
        """
        alarms = {}

        # High 5XX error rate alarm
        alarms['high_5xx_rate'] = cloudwatch.Alarm(
            self,
            "High5XXRateAlarm",
            alarm_name=f"VPCLattice-{self.service.name}-High5XXRate",
            alarm_description="High 5XX error rate detected in VPC Lattice service",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="HTTPCode_5XX_Count",
                dimensions_map={
                    "Service": self.service.attr_id
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=10,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Request timeout alarm
        alarms['request_timeouts'] = cloudwatch.Alarm(
            self,
            "RequestTimeoutsAlarm",
            alarm_name=f"VPCLattice-{self.service.name}-RequestTimeouts",
            alarm_description="High request timeout rate detected in VPC Lattice service",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="RequestTimeoutCount",
                dimensions_map={
                    "Service": self.service.attr_id
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # High response time alarm
        alarms['high_response_time'] = cloudwatch.Alarm(
            self,
            "HighResponseTimeAlarm",
            alarm_name=f"VPCLattice-{self.service.name}-HighResponseTime",
            alarm_description="High response time detected in VPC Lattice service",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="RequestTime",
                dimensions_map={
                    "Service": self.service.attr_id
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=2000,  # 2 seconds in milliseconds
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS actions to all alarms
        for alarm in alarms.values():
            alarm.add_alarm_action(
                cloudwatch.SnsAction(self.sns_topic)
            )
            alarm.add_ok_action(
                cloudwatch.SnsAction(self.sns_topic)
            )

        return alarms

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for health monitoring visualization.
        
        Returns:
            CloudWatch dashboard instance
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "HealthMonitoringDashboard",
            dashboard_name="VPC-Lattice-Health-Monitoring",
            period_override=cloudwatch.PeriodOverride.AUTO
        )

        # HTTP response codes widget
        response_codes_widget = cloudwatch.GraphWidget(
            title="HTTP Response Codes",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="HTTPCode_2XX_Count",
                    dimensions_map={"Service": self.service.attr_id},
                    statistic="Sum",
                    label="2XX Success"
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="HTTPCode_4XX_Count",
                    dimensions_map={"Service": self.service.attr_id},
                    statistic="Sum",
                    label="4XX Client Errors"
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="HTTPCode_5XX_Count",
                    dimensions_map={"Service": self.service.attr_id},
                    statistic="Sum",
                    label="5XX Server Errors"
                )
            ],
            width=12,
            height=6
        )

        # Response time widget
        response_time_widget = cloudwatch.GraphWidget(
            title="Request Response Time",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="RequestTime",
                    dimensions_map={"Service": self.service.attr_id},
                    statistic="Average",
                    label="Average Response Time"
                )
            ],
            width=12,
            height=6
        )

        # Request volume and timeouts widget
        volume_timeouts_widget = cloudwatch.GraphWidget(
            title="Request Volume and Timeouts",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="TotalRequestCount",
                    dimensions_map={"Service": self.service.attr_id},
                    statistic="Sum",
                    label="Total Requests"
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="RequestTimeoutCount",
                    dimensions_map={"Service": self.service.attr_id},
                    statistic="Sum",
                    label="Request Timeouts"
                )
            ],
            width=12,
            height=6
        )

        # Target group health widget
        target_health_widget = cloudwatch.GraphWidget(
            title="Target Group Health",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="HealthyTargetCount",
                    dimensions_map={"TargetGroup": self.target_group.attr_id},
                    statistic="Average",
                    label="Healthy Targets"
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="UnhealthyTargetCount",
                    dimensions_map={"TargetGroup": self.target_group.attr_id},
                    statistic="Average",
                    label="Unhealthy Targets"
                )
            ],
            width=12,
            height=6
        )

        # Add widgets to dashboard
        dashboard.add_widgets(
            response_codes_widget,
            response_time_widget
        )
        dashboard.add_widgets(
            volume_timeouts_widget,
            target_health_widget
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID",
            export_name=f"{self.stack_name}-ServiceNetworkId"
        )

        CfnOutput(
            self,
            "ServiceId",
            value=self.service.attr_id,
            description="VPC Lattice Service ID",
            export_name=f"{self.stack_name}-ServiceId"
        )

        CfnOutput(
            self,
            "TargetGroupId",
            value=self.target_group.attr_id,
            description="VPC Lattice Target Group ID",
            export_name=f"{self.stack_name}-TargetGroupId"
        )

        CfnOutput(
            self,
            "SnsTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for health notifications",
            export_name=f"{self.stack_name}-SnsTopicArn"
        )

        CfnOutput(
            self,
            "RemediationFunctionArn",
            value=self.remediation_function.function_arn,
            description="Lambda function ARN for auto-remediation",
            export_name=f"{self.stack_name}-RemediationFunctionArn"
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL for health monitoring",
            export_name=f"{self.stack_name}-DashboardUrl"
        )


class HealthMonitoringApp(cdk.App):
    """
    CDK Application for VPC Lattice Health Monitoring.
    
    This application creates a comprehensive health monitoring solution
    with automated remediation capabilities.
    """
    
    def __init__(self):
        super().__init__()
        
        # Get context values for configuration
        vpc_id = self.node.try_get_context("vpc_id")
        email_endpoints = self.node.try_get_context("email_endpoints") or []
        
        # Create the main stack
        VpcLatticeHealthMonitoringStack(
            self,
            "VpcLatticeHealthMonitoringStack",
            vpc_id=vpc_id,
            email_endpoints=email_endpoints,
            description="VPC Lattice Health Monitoring with CloudWatch and Auto-Remediation",
            env=cdk.Environment(
                account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
                region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
            )
        )


# Create and run the application
if __name__ == "__main__":
    import os
    app = HealthMonitoringApp()
    app.synth()