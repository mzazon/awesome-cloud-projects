#!/usr/bin/env python3
"""
AWS CDK application for IoT Device Shadows State Management

This CDK application creates the infrastructure for managing IoT device shadows,
including IoT Core resources, Lambda functions for processing shadow updates,
and DynamoDB for storing state history.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_iot as iot,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class IoTDeviceShadowsStack(Stack):
    """
    CDK Stack for IoT Device Shadows State Management
    
    This stack creates:
    - IoT Thing and Certificate for device authentication
    - IoT Policy for shadow access permissions
    - DynamoDB table for state history
    - Lambda function for processing shadow updates
    - IoT Rule for routing shadow updates to Lambda
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        thing_name: str = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Use provided thing name or generate default
        self.thing_name = thing_name or f"smart-thermostat-{cdk.Aws.ACCOUNT_ID[:8]}"
        
        # Create DynamoDB table for device state history
        self.state_table = self._create_state_table()
        
        # Create Lambda function for processing shadow updates
        self.shadow_processor = self._create_shadow_processor()
        
        # Create IoT resources
        self.iot_thing = self._create_iot_thing()
        self.iot_certificate = self._create_iot_certificate()
        self.iot_policy = self._create_iot_policy()
        
        # Attach policy to certificate
        self._attach_policy_to_certificate()
        
        # Create IoT rule for shadow updates
        self.iot_rule = self._create_iot_rule()
        
        # Grant IoT permission to invoke Lambda
        self._grant_iot_lambda_permission()
        
        # Create outputs
        self._create_outputs()

    def _create_state_table(self) -> dynamodb.Table:
        """Create DynamoDB table for storing device state history"""
        table = dynamodb.Table(
            self,
            "DeviceStateHistoryTable",
            table_name=f"DeviceStateHistory-{cdk.Aws.ACCOUNT_ID[:8]}",
            partition_key=dynamodb.Attribute(
                name="ThingName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add tags
        cdk.Tags.of(table).add("Application", "IoTShadowDemo")
        cdk.Tags.of(table).add("Environment", "Development")
        
        return table

    def _create_shadow_processor(self) -> lambda_.Function:
        """Create Lambda function for processing shadow updates"""
        
        # Create Lambda function code
        lambda_code = '''import json
import boto3
import time
import os
from decimal import Decimal
from typing import Dict, Any, Union

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process IoT Device Shadow updates and store state history in DynamoDB
    
    Args:
        event: IoT shadow update event containing thing name and state
        context: Lambda context object
        
    Returns:
        Response indicating success or failure
    """
    try:
        print(f"Received shadow update event: {json.dumps(event)}")
        
        # Parse the shadow update event
        thing_name = event.get('thingName')
        shadow_data = event.get('state', {})
        
        if not thing_name:
            raise ValueError("Missing thingName in event")
        
        # Store state change in DynamoDB
        table = dynamodb.Table(os.environ['TABLE_NAME'])
        
        # Convert float to Decimal for DynamoDB compatibility
        def convert_floats(obj: Union[Dict, list, float, Any]) -> Union[Dict, list, Decimal, Any]:
            if isinstance(obj, float):
                return Decimal(str(obj))
            elif isinstance(obj, dict):
                return {k: convert_floats(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [convert_floats(v) for v in obj]
            return obj
        
        # Create DynamoDB item
        item = {
            'ThingName': thing_name,
            'Timestamp': int(time.time()),
            'ShadowState': convert_floats(shadow_data),
            'EventType': 'shadow_update',
            'ProcessedAt': int(time.time() * 1000)  # milliseconds
        }
        
        # Store in DynamoDB
        table.put_item(Item=item)
        
        print(f"Successfully processed shadow update for {thing_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully processed shadow update',
                'thingName': thing_name,
                'timestamp': item['Timestamp']
            })
        }
        
    except Exception as e:
        error_msg = f"Error processing shadow update: {str(e)}"
        print(error_msg)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'event': event
            })
        }
'''
        
        # Create Lambda function
        function = lambda_.Function(
            self,
            "ShadowProcessorFunction",
            function_name=f"ProcessShadowUpdate-{cdk.Aws.ACCOUNT_ID[:8]}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=Duration.seconds(30),
            memory_size=128,
            environment={
                "TABLE_NAME": self.state_table.table_name,
                "AWS_REGION": cdk.Aws.REGION
            },
            description="Process IoT Device Shadow updates and store state history",
            retry_attempts=2,
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Grant permissions to write to DynamoDB
        self.state_table.grant_write_data(function)
        
        return function

    def _create_iot_thing(self) -> iot.CfnThing:
        """Create IoT Thing representing the physical device"""
        thing = iot.CfnThing(
            self,
            "SmartThermostatThing",
            thing_name=self.thing_name,
            attribute_payload=iot.CfnThing.AttributePayloadProperty(
                attributes={
                    "manufacturer": "SmartHome",
                    "model": "TH-2024",
                    "deviceType": "thermostat",
                    "firmware": "1.2.3"
                }
            ),
        )
        
        return thing

    def _create_iot_certificate(self) -> iot.CfnCertificate:
        """Create IoT certificate for device authentication"""
        certificate = iot.CfnCertificate(
            self,
            "DeviceCertificate",
            status="ACTIVE",
            certificate_signing_request=None,  # Will be auto-generated
        )
        
        return certificate

    def _create_iot_policy(self) -> iot.CfnPolicy:
        """Create IoT policy for device shadow access"""
        
        # Define policy document for device shadow access
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["iot:Connect"],
                    "Resource": f"arn:aws:iot:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:client/${{iot:Connection.Thing.ThingName}}"
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Subscribe", "iot:Receive"],
                    "Resource": [
                        f"arn:aws:iot:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:topicfilter/$aws/things/${{iot:Connection.Thing.ThingName}}/shadow/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Publish"],
                    "Resource": [
                        f"arn:aws:iot:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:topic/$aws/things/${{iot:Connection.Thing.ThingName}}/shadow/*"
                    ]
                }
            ]
        }
        
        policy = iot.CfnPolicy(
            self,
            "SmartThermostatPolicy",
            policy_name=f"SmartThermostatPolicy-{cdk.Aws.ACCOUNT_ID[:8]}",
            policy_document=policy_document,
        )
        
        return policy

    def _attach_policy_to_certificate(self) -> None:
        """Attach IoT policy to certificate and certificate to thing"""
        
        # Attach policy to certificate
        iot.CfnPolicyPrincipalAttachment(
            self,
            "PolicyCertificateAttachment",
            policy_name=self.iot_policy.policy_name,
            principal=self.iot_certificate.attr_arn,
        )
        
        # Attach certificate to thing
        iot.CfnThingPrincipalAttachment(
            self,
            "ThingCertificateAttachment",
            thing_name=self.iot_thing.thing_name,
            principal=self.iot_certificate.attr_arn,
        )

    def _create_iot_rule(self) -> iot.CfnTopicRule:
        """Create IoT rule to process shadow updates"""
        
        # Define rule payload
        rule_payload = iot.CfnTopicRule.TopicRulePayloadProperty(
            sql="SELECT * FROM '$aws/things/+/shadow/update/accepted'",
            description="Process Device Shadow updates and trigger Lambda processing",
            actions=[
                iot.CfnTopicRule.ActionProperty(
                    lambda_=iot.CfnTopicRule.LambdaActionProperty(
                        function_arn=self.shadow_processor.function_arn
                    )
                )
            ],
            rule_disabled=False,
            aws_iot_sql_version="2016-03-23"
        )
        
        rule = iot.CfnTopicRule(
            self,
            "ShadowUpdateRule",
            rule_name=f"ShadowUpdateRule{cdk.Aws.ACCOUNT_ID[:8]}",
            topic_rule_payload=rule_payload,
        )
        
        return rule

    def _grant_iot_lambda_permission(self) -> None:
        """Grant IoT service permission to invoke Lambda function"""
        
        self.shadow_processor.add_permission(
            "AllowIoTInvoke",
            principal=iam.ServicePrincipal("iot.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"arn:aws:iot:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:rule/{self.iot_rule.rule_name}",
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information"""
        
        CfnOutput(
            self,
            "ThingName",
            value=self.iot_thing.thing_name,
            description="Name of the IoT Thing representing the smart thermostat",
        )
        
        CfnOutput(
            self,
            "CertificateArn",
            value=self.iot_certificate.attr_arn,
            description="ARN of the IoT certificate for device authentication",
        )
        
        CfnOutput(
            self,
            "CertificateId",
            value=self.iot_certificate.attr_id,
            description="ID of the IoT certificate",
        )
        
        CfnOutput(
            self,
            "PolicyName",
            value=self.iot_policy.policy_name,
            description="Name of the IoT policy for shadow access",
        )
        
        CfnOutput(
            self,
            "StateTableName",
            value=self.state_table.table_name,
            description="Name of the DynamoDB table storing device state history",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.shadow_processor.function_name,
            description="Name of the Lambda function processing shadow updates",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.shadow_processor.function_arn,
            description="ARN of the Lambda function processing shadow updates",
        )
        
        CfnOutput(
            self,
            "IoTRuleName",
            value=self.iot_rule.rule_name,
            description="Name of the IoT rule routing shadow updates to Lambda",
        )
        
        CfnOutput(
            self,
            "IoTEndpoint",
            value=f"https://{cdk.Aws.ACCOUNT_ID}.iot.{cdk.Aws.REGION}.amazonaws.com",
            description="IoT Core endpoint for device connections",
        )


class IoTDeviceShadowsApp(cdk.App):
    """CDK Application for IoT Device Shadows State Management"""
    
    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        
        # Get configuration from context or environment
        thing_name = self.node.try_get_context("thing_name")
        
        # Create the main stack
        IoTDeviceShadowsStack(
            self,
            "IoTDeviceShadowsStack",
            thing_name=thing_name,
            description="Infrastructure for IoT Device Shadows State Management with Lambda processing and DynamoDB storage",
            env=cdk.Environment(
                account=os.getenv('CDK_DEFAULT_ACCOUNT'),
                region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
            ),
        )


# Create and run the application
app = IoTDeviceShadowsApp()
app.synth()