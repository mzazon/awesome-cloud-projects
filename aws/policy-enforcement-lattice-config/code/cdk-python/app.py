#!/usr/bin/env python3
"""
CDK Python Application for Policy Enforcement Automation with VPC Lattice and Config

This application deploys an automated policy enforcement system that monitors 
VPC Lattice resources for compliance violations using AWS Config custom rules,
Lambda functions for evaluation logic, and SNS for notifications.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any, List

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
    aws_sns_subscriptions as sns_subscriptions,
    aws_s3 as s3,
    aws_config as config,
    aws_logs as logs,
    aws_vpclattice as vpclattice,
)
from constructs import Construct


class PolicyEnforcementLatticeConfigStack(Stack):
    """
    CDK Stack for Policy Enforcement Automation with VPC Lattice and Config.
    
    This stack creates:
    - VPC Lattice service network and test service
    - AWS Config configuration recorder and custom rule
    - Lambda functions for compliance evaluation and auto-remediation
    - SNS topic for notifications
    - IAM roles and policies with least privilege access
    - S3 bucket for Config service delivery
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.notification_email = self.node.try_get_context("notification_email") or "admin@company.com"
        self.environment_suffix = self.node.try_get_context("environment_suffix") or "dev"
        
        # Create foundational resources
        self.vpc = self._create_vpc()
        self.config_bucket = self._create_config_bucket()
        self.sns_topic = self._create_sns_topic()
        
        # Create IAM roles
        self.config_role = self._create_config_service_role()
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda functions
        self.compliance_evaluator = self._create_compliance_evaluator_function()
        self.auto_remediation = self._create_auto_remediation_function()
        
        # Create AWS Config resources
        self.delivery_channel = self._create_config_delivery_channel()
        self.configuration_recorder = self._create_configuration_recorder()
        self.config_rule = self._create_config_rule()
        
        # Create VPC Lattice resources for testing
        self.service_network = self._create_test_service_network()
        self.test_service = self._create_test_service()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for VPC Lattice service network association."""
        vpc = ec2.Vpc(
            self,
            "ComplianceVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            nat_gateways=0,  # No NAT gateways needed for this demo
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24,
                )
            ],
            vpc_name=f"lattice-compliance-vpc-{self.environment_suffix}",
        )
        
        # Add VPC endpoint for VPC Lattice
        vpc.add_interface_endpoint(
            "VpcLatticeEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.VPC_LATTICE,
        )
        
        return vpc

    def _create_config_bucket(self) -> s3.Bucket:
        """Create S3 bucket for AWS Config service delivery."""
        bucket = s3.Bucket(
            self,
            "ConfigBucket",
            bucket_name=f"aws-config-bucket-{self.account}-{self.region}-{self.environment_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            versioning=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(90),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add bucket policy for AWS Config service
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketPermissionsCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:GetBucketAcl", "s3:ListBucket"],
                resources=[bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketExistenceCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:ListBucket"],
                resources=[bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketDelivery",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{bucket.bucket_arn}/AWSLogs/{self.account}/Config/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control",
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        return bucket

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for compliance notifications."""
        topic = sns.Topic(
            self,
            "ComplianceAlertsTopic",
            topic_name=f"lattice-compliance-alerts-{self.environment_suffix}",
            display_name="VPC Lattice Compliance Alerts",
        )

        # Add email subscription
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.notification_email)
        )

        return topic

    def _create_config_service_role(self) -> iam.Role:
        """Create IAM role for AWS Config service."""
        role = iam.Role(
            self,
            "ConfigServiceRole",
            role_name=f"ConfigServiceRole-{self.environment_suffix}",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/ConfigRole")
            ],
        )

        # Add inline policy for S3 delivery channel access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetBucketAcl",
                    "s3:ListBucket",
                ],
                resources=[self.config_bucket.bucket_arn],
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:PutObject"],
                resources=[f"{self.config_bucket.bucket_arn}/AWSLogs/{self.account}/Config/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control"
                    }
                }
            )
        )

        return role

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda function execution."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"LatticeComplianceRole-{self.environment_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
        )

        # Add custom policy for VPC Lattice, Config, and SNS access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "vpc-lattice:*",
                    "config:PutEvaluations",
                    "config:StartConfigRulesEvaluation",
                    "sns:Publish",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_compliance_evaluator_function(self) -> lambda_.Function:
        """Create Lambda function for compliance evaluation."""
        function = lambda_.Function(
            self,
            "ComplianceEvaluator",
            function_name=f"lattice-compliance-evaluator-{self.environment_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_compliance_evaluator_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "AWS_ACCOUNT_ID": self.account,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Grant SNS publish permissions
        self.sns_topic.grant_publish(function)

        return function

    def _create_auto_remediation_function(self) -> lambda_.Function:
        """Create Lambda function for automated remediation."""
        function = lambda_.Function(
            self,
            "AutoRemediation",
            function_name=f"lattice-auto-remediation-{self.environment_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_auto_remediation_code()),
            timeout=Duration.seconds(120),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "CONFIG_RULE_NAME": f"vpc-lattice-policy-compliance-{self.environment_suffix}",
                "AWS_ACCOUNT_ID": self.account,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Subscribe to SNS topic
        self.sns_topic.add_subscription(
            sns_subscriptions.LambdaSubscription(function)
        )

        return function

    def _create_config_delivery_channel(self) -> config.CfnDeliveryChannel:
        """Create AWS Config delivery channel."""
        delivery_channel = config.CfnDeliveryChannel(
            self,
            "ConfigDeliveryChannel",
            name="default",
            s3_bucket_name=self.config_bucket.bucket_name,
        )

        delivery_channel.node.add_dependency(self.config_bucket)
        return delivery_channel

    def _create_configuration_recorder(self) -> config.CfnConfigurationRecorder:
        """Create AWS Config configuration recorder."""
        recorder = config.CfnConfigurationRecorder(
            self,
            "ConfigurationRecorder",
            name="default",
            role_arn=self.config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=False,
                include_global_resource_types=False,
                resource_types=[
                    "AWS::VpcLattice::ServiceNetwork",
                    "AWS::VpcLattice::Service",
                ],
            ),
        )

        recorder.node.add_dependency(self.delivery_channel)
        return recorder

    def _create_config_rule(self) -> config.CfnConfigRule:
        """Create custom AWS Config rule for VPC Lattice compliance."""
        rule = config.CfnConfigRule(
            self,
            "VpcLatticeComplianceRule",
            config_rule_name=f"vpc-lattice-policy-compliance-{self.environment_suffix}",
            description="Evaluates VPC Lattice resources for compliance with security policies",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS_LAMBDA",
                source_identifier=self.compliance_evaluator.function_arn,
                source_details=[
                    config.CfnConfigRule.SourceDetailProperty(
                        event_source="aws.config",
                        message_type="ConfigurationItemChangeNotification",
                    ),
                    config.CfnConfigRule.SourceDetailProperty(
                        event_source="aws.config",
                        message_type="OversizedConfigurationItemChangeNotification",
                    ),
                ],
            ),
            input_parameters='{"requireAuthPolicy": "true", "namePrefix": "secure-", "requireAuth": "true"}',
        )

        # Grant Config permission to invoke Lambda
        self.compliance_evaluator.add_permission(
            "ConfigInvokePermission",
            principal=iam.ServicePrincipal("config.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_account=self.account,
        )

        rule.node.add_dependency(self.configuration_recorder)
        return rule

    def _create_test_service_network(self) -> vpclattice.CfnServiceNetwork:
        """Create VPC Lattice service network for testing."""
        service_network = vpclattice.CfnServiceNetwork(
            self,
            "TestServiceNetwork",
            name=f"test-network-{self.environment_suffix}",
            auth_type="AWS_IAM",
        )

        # Associate VPC with service network
        vpclattice.CfnServiceNetworkVpcAssociation(
            self,
            "ServiceNetworkVpcAssociation",
            service_network_identifier=service_network.ref,
            vpc_identifier=self.vpc.vpc_id,
        )

        return service_network

    def _create_test_service(self) -> vpclattice.CfnService:
        """Create test VPC Lattice service (intentionally non-compliant for testing)."""
        service = vpclattice.CfnService(
            self,
            "TestService",
            name=f"test-service-{self.environment_suffix}",
            auth_type="NONE",  # Non-compliant: no authentication
        )

        return service

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for VPC Lattice service network association",
        )

        CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.ref,
            description="VPC Lattice Service Network ID",
        )

        CfnOutput(
            self,
            "TestServiceId",
            value=self.test_service.ref,
            description="Test VPC Lattice Service ID (intentionally non-compliant)",
        )

        CfnOutput(
            self,
            "SnsTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for compliance notifications",
        )

        CfnOutput(
            self,
            "ConfigRuleName",
            value=self.config_rule.config_rule_name,
            description="AWS Config Rule Name for VPC Lattice compliance",
        )

        CfnOutput(
            self,
            "ComplianceEvaluatorFunctionName",
            value=self.compliance_evaluator.function_name,
            description="Lambda function name for compliance evaluation",
        )

        CfnOutput(
            self,
            "AutoRemediationFunctionName",
            value=self.auto_remediation.function_name,
            description="Lambda function name for automated remediation",
        )

    def _get_compliance_evaluator_code(self) -> str:
        """Return the compliance evaluator Lambda function code."""
        return '''
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Evaluate VPC Lattice resources for compliance."""
    
    config_client = boto3.client('config')
    lattice_client = boto3.client('vpc-lattice')
    sns_client = boto3.client('sns')
    
    # Parse Config rule invocation
    configuration_item = event['configurationItem']
    rule_parameters = json.loads(event.get('ruleParameters', '{}'))
    
    compliance_type = 'COMPLIANT'
    annotation = 'Resource is compliant with security policies'
    
    try:
        resource_type = configuration_item['resourceType']
        resource_id = configuration_item['resourceId']
        
        if resource_type == 'AWS::VpcLattice::ServiceNetwork':
            compliance_type, annotation = evaluate_service_network(
                lattice_client, resource_id, rule_parameters
            )
        elif resource_type == 'AWS::VpcLattice::Service':
            compliance_type, annotation = evaluate_service(
                lattice_client, resource_id, rule_parameters
            )
        
        # Send notification if non-compliant
        if compliance_type == 'NON_COMPLIANT':
            send_compliance_notification(sns_client, resource_id, annotation)
            
    except Exception as e:
        logger.error(f"Error evaluating compliance: {str(e)}")
        compliance_type = 'NOT_APPLICABLE'
        annotation = f"Error during evaluation: {str(e)}"
    
    # Return evaluation result to Config
    config_client.put_evaluations(
        Evaluations=[
            {
                'ComplianceResourceType': configuration_item['resourceType'],
                'ComplianceResourceId': configuration_item['resourceId'],
                'ComplianceType': compliance_type,
                'Annotation': annotation,
                'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
            }
        ],
        ResultToken=event['resultToken']
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Evaluation complete: {compliance_type}')
    }

def evaluate_service_network(client, network_id, parameters):
    """Evaluate service network compliance."""
    try:
        # Get service network details
        response = client.get_service_network(serviceNetworkIdentifier=network_id)
        network = response['serviceNetwork']
        
        # Check for auth policy requirement
        if parameters.get('requireAuthPolicy', 'true') == 'true':
            try:
                client.get_auth_policy(resourceIdentifier=network_id)
            except client.exceptions.ResourceNotFoundException:
                return 'NON_COMPLIANT', 'Service network missing required auth policy'
        
        # Check network name compliance
        if not network['name'].startswith(parameters.get('namePrefix', 'secure-')):
            return 'NON_COMPLIANT', f"Service network name must start with {parameters.get('namePrefix', 'secure-')}"
        
        return 'COMPLIANT', 'Service network meets all security requirements'
        
    except Exception as e:
        return 'NOT_APPLICABLE', f"Unable to evaluate service network: {str(e)}"

def evaluate_service(client, service_id, parameters):
    """Evaluate service compliance."""
    try:
        response = client.get_service(serviceIdentifier=service_id)
        service = response['service']
        
        # Check auth type requirement
        if parameters.get('requireAuth', 'true') == 'true':
            if service.get('authType') == 'NONE':
                return 'NON_COMPLIANT', 'Service must have authentication enabled'
        
        return 'COMPLIANT', 'Service meets security requirements'
        
    except Exception as e:
        return 'NOT_APPLICABLE', f"Unable to evaluate service: {str(e)}"

def send_compliance_notification(sns_client, resource_id, message):
    """Send SNS notification for compliance violations."""
    try:
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='VPC Lattice Compliance Violation Detected',
            Message=f"""
Compliance violation detected:

Resource ID: {resource_id}
Issue: {message}
Timestamp: {datetime.utcnow().isoformat()}

Please review and remediate this resource immediately.
            """
        )
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")
'''

    def _get_auto_remediation_code(self) -> str:
        """Return the auto-remediation Lambda function code."""
        return '''
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Automatically remediate VPC Lattice compliance violations."""
    
    lattice_client = boto3.client('vpc-lattice')
    config_client = boto3.client('config')
    
    try:
        # Parse SNS message
        message = json.loads(event['Records'][0]['Sns']['Message'])
        resource_id = extract_resource_id(message)
        
        if not resource_id:
            logger.error("Unable to extract resource ID from message")
            return
        
        # Attempt remediation based on resource type
        if 'service-network' in resource_id:
            remediate_service_network(lattice_client, resource_id)
        elif 'service' in resource_id:
            remediate_service(lattice_client, resource_id)
        
        # Trigger Config re-evaluation
        config_client.start_config_rules_evaluation(
            ConfigRuleNames=[os.environ['CONFIG_RULE_NAME']]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Remediation completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Remediation failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Remediation failed: {str(e)}')
        }

def extract_resource_id(message):
    """Extract resource ID from compliance message."""
    # Simple extraction logic - in production, use more robust parsing
    lines = message.split('\\n')
    for line in lines:
        if 'Resource ID:' in line:
            return line.split('Resource ID:')[1].strip()
    return None

def remediate_service_network(client, network_id):
    """Apply remediation to service network."""
    try:
        # Create basic auth policy if missing
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "vpc-lattice-svcs:*",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "aws:PrincipalAccount": os.environ['AWS_ACCOUNT_ID']
                        }
                    }
                }
            ]
        }
        
        client.put_auth_policy(
            resourceIdentifier=network_id,
            policy=json.dumps(auth_policy)
        )
        
        logger.info(f"Applied auth policy to service network: {network_id}")
        
    except Exception as e:
        logger.error(f"Failed to remediate service network {network_id}: {str(e)}")

def remediate_service(client, service_id):
    """Apply remediation to service."""
    try:
        # Update service to require authentication
        client.update_service(
            serviceIdentifier=service_id,
            authType='AWS_IAM'
        )
        
        logger.info(f"Updated service authentication: {service_id}")
        
    except Exception as e:
        logger.error(f"Failed to remediate service {service_id}: {str(e)}")
'''


app = cdk.App()

# Get environment configuration
env = cdk.Environment(
    account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
    region=os.environ.get("CDK_DEFAULT_REGION", "us-west-2"),
)

# Create the stack
PolicyEnforcementLatticeConfigStack(
    app,
    "PolicyEnforcementLatticeConfigStack",
    env=env,
    description="Policy Enforcement Automation with VPC Lattice and Config - CDK Python Implementation",
    tags={
        "Project": "PolicyEnforcementAutomation",
        "Environment": app.node.try_get_context("environment_suffix") or "dev",
        "ManagedBy": "CDK",
        "Recipe": "policy-enforcement-lattice-config",
    },
)

app.synth()