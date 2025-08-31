#!/usr/bin/env python3
"""
AWS CDK Python application for Network Troubleshooting VPC Lattice with Network Insights
This application deploys a comprehensive network troubleshooting platform that combines 
VPC Lattice service mesh monitoring with automated path analysis and proactive alerting.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_ssm as ssm,
    aws_vpclattice as lattice,
)
from constructs import Construct
import json


class NetworkTroubleshootingStack(Stack):
    """
    CDK Stack for deploying VPC Lattice Network Troubleshooting infrastructure
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-6:].lower()

        # Get default VPC for testing
        default_vpc = ec2.Vpc.from_lookup(
            self, "DefaultVPC",
            is_default=True
        )

        # Create IAM roles
        self._create_iam_roles(unique_suffix)

        # Create VPC Lattice service network
        self._create_vpc_lattice_service_network(default_vpc, unique_suffix)

        # Create test EC2 infrastructure
        self._create_test_infrastructure(default_vpc, unique_suffix)

        # Create CloudWatch monitoring
        self._create_monitoring_dashboard(unique_suffix)

        # Create SNS topic and alarms
        self._create_alerting_infrastructure(unique_suffix)

        # Create Lambda function for automated troubleshooting
        self._create_lambda_function(unique_suffix)

        # Create Systems Manager automation document
        self._create_automation_document(unique_suffix)

        # Create outputs
        self._create_outputs()

    def _create_iam_roles(self, unique_suffix: str) -> None:
        """Create IAM roles for automation and Lambda functions"""
        
        # Create automation role for Systems Manager
        self.automation_role = iam.Role(
            self, "AutomationRole",
            role_name=f"NetworkTroubleshootingRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("ssm.amazonaws.com"),
            description="Role for Systems Manager automation to perform network analysis",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMAutomationRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonVPCFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchReadOnlyAccess"),
            ]
        )

        # Create Lambda execution role
        self.lambda_role = iam.Role(
            self, "LambdaRole",
            role_name=f"NetworkTroubleshootingLambdaRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Lambda function to trigger network troubleshooting",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMFullAccess"),
            ]
        )

    def _create_vpc_lattice_service_network(self, vpc: ec2.IVpc, unique_suffix: str) -> None:
        """Create VPC Lattice service network and VPC association"""
        
        # Create VPC Lattice service network
        self.service_network = lattice.CfnServiceNetwork(
            self, "ServiceNetwork",
            name=f"troubleshooting-network-{unique_suffix}",
            auth_type="AWS_IAM"
        )

        # Associate VPC with service network
        self.vpc_association = lattice.CfnServiceNetworkVpcAssociation(
            self, "VpcAssociation",
            service_network_identifier=self.service_network.attr_id,
            vpc_identifier=vpc.vpc_id
        )

    def _create_test_infrastructure(self, vpc: ec2.IVpc, unique_suffix: str) -> None:
        """Create test EC2 instances and security groups for network analysis"""
        
        # Create security group for test instances
        self.test_security_group = ec2.SecurityGroup(
            self, "TestSecurityGroup",
            vpc=vpc,
            description="Security group for VPC Lattice testing",
            security_group_name=f"lattice-test-sg-{unique_suffix}",
            allow_all_outbound=True
        )

        # Add inbound rules
        self.test_security_group.add_ingress_rule(
            peer=self.test_security_group,
            connection=ec2.Port.tcp(80),
            description="HTTP traffic from same security group"
        )

        self.test_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(22),
            description="SSH access from private networks"
        )

        # Create test EC2 instance
        self.test_instance = ec2.Instance(
            self, "TestInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, 
                ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2023(),
            vpc=vpc,
            security_group=self.test_security_group,
            associate_public_ip_address=True,
            instance_name=f"lattice-test-{unique_suffix}"
        )

    def _create_monitoring_dashboard(self, unique_suffix: str) -> None:
        """Create CloudWatch dashboard for VPC Lattice monitoring"""
        
        # Create CloudWatch log group for VPC Lattice access logs
        self.log_group = logs.LogGroup(
            self, "VpcLatticeLogGroup",
            log_group_name=f"/aws/vpclattice/servicenetwork/{self.service_network.attr_id}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self, "NetworkTroubleshootingDashboard",
            dashboard_name=f"VPCLatticeNetworkTroubleshooting-{unique_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="VPC Lattice Performance Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="RequestCount",
                                dimensions_map={
                                    "ServiceNetwork": self.service_network.attr_id
                                },
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="TargetResponseTime",
                                dimensions_map={
                                    "ServiceNetwork": self.service_network.attr_id
                                },
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="ActiveConnectionCount",
                                dimensions_map={
                                    "ServiceNetwork": self.service_network.attr_id
                                },
                                statistic="Average"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="VPC Lattice Response Codes",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="HTTPCode_Target_2XX_Count",
                                dimensions_map={
                                    "ServiceNetwork": self.service_network.attr_id
                                },
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="HTTPCode_Target_4XX_Count",
                                dimensions_map={
                                    "ServiceNetwork": self.service_network.attr_id
                                },
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="HTTPCode_Target_5XX_Count",
                                dimensions_map={
                                    "ServiceNetwork": self.service_network.attr_id
                                },
                                statistic="Sum"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

    def _create_alerting_infrastructure(self, unique_suffix: str) -> None:
        """Create SNS topic and CloudWatch alarms for network alerting"""
        
        # Create SNS topic for network alerts
        self.sns_topic = sns.Topic(
            self, "NetworkAlertsTopic",
            topic_name=f"network-alerts-{unique_suffix}",
            display_name="Network Troubleshooting Alerts"
        )

        # Create CloudWatch alarm for VPC Lattice errors
        self.error_alarm = cloudwatch.Alarm(
            self, "HighErrorRateAlarm",
            alarm_name=f"VPCLattice-HighErrorRate-{unique_suffix}",
            alarm_description="Alarm for high VPC Lattice 5XX error rate",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="HTTPCode_Target_5XX_Count",
                dimensions_map={
                    "ServiceNetwork": self.service_network.attr_id
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=10,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Create CloudWatch alarm for high latency
        self.latency_alarm = cloudwatch.Alarm(
            self, "HighLatencyAlarm",
            alarm_name=f"VPCLattice-HighLatency-{unique_suffix}",
            alarm_description="Alarm for high VPC Lattice response time",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="TargetResponseTime",
                dimensions_map={
                    "ServiceNetwork": self.service_network.attr_id
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5000,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Add SNS topic as alarm action
        self.error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        self.latency_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _create_lambda_function(self, unique_suffix: str) -> None:
        """Create Lambda function for automated network troubleshooting"""
        
        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to automatically trigger network troubleshooting
    when CloudWatch alarms are triggered via SNS
    """
    ssm_client = boto3.client('ssm')
    
    try:
        # Parse SNS message
        if 'Records' in event:
            for record in event['Records']:
                if record['EventSource'] == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    alarm_name = message.get('AlarmName', '')
                    
                    logger.info(f"Processing alarm: {alarm_name}")
                    
                    # Get environment variables with defaults
                    automation_role = os.environ.get('AUTOMATION_ROLE_ARN', '')
                    default_instance = os.environ.get('DEFAULT_INSTANCE_ID', '')
                    document_name = os.environ.get('DOCUMENT_NAME', '')
                    
                    if not automation_role or not default_instance or not document_name:
                        logger.error("Missing required environment variables")
                        return {
                            'statusCode': 400,
                            'body': json.dumps({'error': 'Missing environment variables'})
                        }
                    
                    # Trigger automated troubleshooting
                    response = ssm_client.start_automation_execution(
                        DocumentName=document_name,
                        Parameters={
                            'SourceId': [default_instance],
                            'DestinationId': [default_instance],
                            'AutomationAssumeRole': [automation_role]
                        }
                    )
                    
                    logger.info(f"Started automation execution: {response['AutomationExecutionId']}")
                    
                    return {
                        'statusCode': 200,
                        'body': json.dumps({
                            'message': 'Network troubleshooting automation started',
                            'execution_id': response['AutomationExecutionId'],
                            'alarm_name': alarm_name
                        })
                    }
            
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'No SNS records to process'})
        }
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

        # Create Lambda function
        self.troubleshooting_lambda = lambda_.Function(
            self, "TroubleshootingLambda",
            function_name=f"network-troubleshooting-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            description="Automated network troubleshooting function"
        )

        # Subscribe Lambda to SNS topic
        self.sns_topic.add_subscription(
            sns.LambdaSubscription(self.troubleshooting_lambda)
        )

    def _create_automation_document(self, unique_suffix: str) -> None:
        """Create Systems Manager automation document for network analysis"""
        
        # Automation document content
        automation_document = {
            "schemaVersion": "0.3",
            "description": "Automated VPC Reachability Analysis for Network Troubleshooting",
            "assumeRole": "{{ AutomationAssumeRole }}",
            "parameters": {
                "SourceId": {
                    "type": "String",
                    "description": "Source instance ID or ENI ID"
                },
                "DestinationId": {
                    "type": "String",
                    "description": "Destination instance ID or ENI ID"
                },
                "AutomationAssumeRole": {
                    "type": "String",
                    "description": "IAM role for automation execution"
                }
            },
            "mainSteps": [
                {
                    "name": "CreateNetworkInsightsPath",
                    "action": "aws:executeAwsApi",
                    "description": "Create a network insights path for reachability analysis",
                    "inputs": {
                        "Service": "ec2",
                        "Api": "CreateNetworkInsightsPath",
                        "Source": "{{ SourceId }}",
                        "Destination": "{{ DestinationId }}",
                        "Protocol": "tcp",
                        "DestinationPort": 80,
                        "TagSpecifications": [
                            {
                                "ResourceType": "network-insights-path",
                                "Tags": [
                                    {
                                        "Key": "Name",
                                        "Value": "AutomatedTroubleshooting"
                                    }
                                ]
                            }
                        ]
                    },
                    "outputs": [
                        {
                            "Name": "NetworkInsightsPathId",
                            "Selector": "$.NetworkInsightsPath.NetworkInsightsPathId",
                            "Type": "String"
                        }
                    ]
                },
                {
                    "name": "StartNetworkInsightsAnalysis",
                    "action": "aws:executeAwsApi",
                    "description": "Start the network insights analysis",
                    "inputs": {
                        "Service": "ec2",
                        "Api": "StartNetworkInsightsAnalysis",
                        "NetworkInsightsPathId": "{{ CreateNetworkInsightsPath.NetworkInsightsPathId }}",
                        "TagSpecifications": [
                            {
                                "ResourceType": "network-insights-analysis",
                                "Tags": [
                                    {
                                        "Key": "Name",
                                        "Value": "AutomatedAnalysis"
                                    }
                                ]
                            }
                        ]
                    },
                    "outputs": [
                        {
                            "Name": "NetworkInsightsAnalysisId",
                            "Selector": "$.NetworkInsightsAnalysis.NetworkInsightsAnalysisId",
                            "Type": "String"
                        }
                    ]
                },
                {
                    "name": "WaitForAnalysisCompletion",
                    "action": "aws:waitForAwsResourceProperty",
                    "description": "Wait for the analysis to complete",
                    "inputs": {
                        "Service": "ec2",
                        "Api": "DescribeNetworkInsightsAnalyses",
                        "NetworkInsightsAnalysisIds": [
                            "{{ StartNetworkInsightsAnalysis.NetworkInsightsAnalysisId }}"
                        ],
                        "PropertySelector": "$.NetworkInsightsAnalyses[0].Status",
                        "DesiredValues": [
                            "succeeded",
                            "failed"
                        ]
                    }
                }
            ]
        }

        # Create automation document
        self.automation_document = ssm.CfnDocument(
            self, "AutomationDocument",
            name=f"NetworkReachabilityAnalysis-{unique_suffix}",
            document_type="Automation",
            document_format="JSON",
            content=automation_document
        )

        # Update Lambda environment variables with document name
        self.troubleshooting_lambda.add_environment(
            "AUTOMATION_ROLE_ARN", self.automation_role.role_arn
        )
        self.troubleshooting_lambda.add_environment(
            "DEFAULT_INSTANCE_ID", self.test_instance.instance_id
        )
        self.troubleshooting_lambda.add_environment(
            "DOCUMENT_NAME", self.automation_document.name
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self, "ServiceNetworkId",
            description="VPC Lattice Service Network ID",
            value=self.service_network.attr_id
        )

        CfnOutput(
            self, "ServiceNetworkArn",
            description="VPC Lattice Service Network ARN",
            value=self.service_network.attr_arn
        )

        CfnOutput(
            self, "TestInstanceId",
            description="Test EC2 Instance ID",
            value=self.test_instance.instance_id
        )

        CfnOutput(
            self, "SecurityGroupId",
            description="Test Security Group ID",
            value=self.test_security_group.security_group_id
        )

        CfnOutput(
            self, "SNSTopicArn",
            description="SNS Topic ARN for network alerts",
            value=self.sns_topic.topic_arn
        )

        CfnOutput(
            self, "DashboardName",
            description="CloudWatch Dashboard Name",
            value=self.dashboard.dashboard_name
        )

        CfnOutput(
            self, "LambdaFunctionName",
            description="Network Troubleshooting Lambda Function Name",
            value=self.troubleshooting_lambda.function_name
        )

        CfnOutput(
            self, "AutomationDocumentName",
            description="Systems Manager Automation Document Name",
            value=self.automation_document.name
        )

        CfnOutput(
            self, "AutomationRoleArn",
            description="IAM Role ARN for automation execution",
            value=self.automation_role.role_arn
        )

        CfnOutput(
            self, "LogGroupName",
            description="CloudWatch Log Group for VPC Lattice access logs",
            value=self.log_group.log_group_name
        )


def main():
    """Main application entry point"""
    app = cdk.App()
    
    # Get stack name from context or use default
    stack_name = app.node.try_get_context("stack_name") or "NetworkTroubleshootingStack"
    
    NetworkTroubleshootingStack(
        app, 
        stack_name,
        description="Network Troubleshooting VPC Lattice with Network Insights - CDK Python Implementation",
        env=cdk.Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region")
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()