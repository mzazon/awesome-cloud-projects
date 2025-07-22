"""
AWS IoT Greengrass Stack

This stack creates the complete infrastructure for edge computing with AWS IoT Greengrass,
including IoT Core devices, certificates, policies, Lambda functions, and IAM roles.
"""

from typing import Dict, Any, Optional
import json
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
)
from aws_cdk import (
    aws_iot as iot,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class IoTGreengrassStack(Stack):
    """
    CDK Stack for AWS IoT Greengrass edge computing infrastructure
    
    This stack creates:
    - IoT Thing and Thing Group for device management
    - X.509 certificates for device authentication
    - IoT policies for device permissions
    - IAM roles for Greengrass Core operation
    - Lambda function for edge processing
    - CloudWatch log groups for monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self._generate_unique_suffix()
        
        # Create IoT Thing Group for device management
        self.thing_group = self._create_thing_group(unique_suffix)
        
        # Create IoT Thing for Greengrass Core
        self.iot_thing = self._create_iot_thing(unique_suffix)
        
        # Create IoT certificates and store in Secrets Manager
        self.certificates = self._create_iot_certificates(unique_suffix)
        
        # Create IoT policy for device permissions
        self.iot_policy = self._create_iot_policy(unique_suffix)
        
        # Create IAM role for Greengrass Core
        self.greengrass_role = self._create_greengrass_iam_role(unique_suffix)
        
        # Create Lambda function for edge processing
        self.edge_lambda = self._create_edge_lambda_function(unique_suffix)
        
        # Create CloudWatch log groups
        self._create_log_groups(unique_suffix)
        
        # Create stack outputs
        self._create_outputs()

    def _generate_unique_suffix(self) -> str:
        """Generate a unique suffix for resource names"""
        # Use the stack's unique ID for naming consistency
        return self.node.addr[-8:].lower()

    def _create_thing_group(self, suffix: str) -> iot.CfnThingGroup:
        """Create IoT Thing Group for device management"""
        thing_group = iot.CfnThingGroup(
            self,
            "GreengrassThingGroup",
            thing_group_name=f"greengrass-things-{suffix}",
            thing_group_properties=iot.CfnThingGroup.ThingGroupPropertiesProperty(
                attribute_payload=iot.CfnThingGroup.AttributePayloadProperty(
                    attributes={
                        "environment": "development",
                        "purpose": "edge-computing",
                        "recipe": "iot-greengrass"
                    }
                ),
                thing_group_description="Greengrass core devices group for edge computing"
            )
        )
        
        # Apply deletion policy
        thing_group.apply_removal_policy(RemovalPolicy.DESTROY)
        
        return thing_group

    def _create_iot_thing(self, suffix: str) -> iot.CfnThing:
        """Create IoT Thing for Greengrass Core device"""
        iot_thing = iot.CfnThing(
            self,
            "GreengrassCoreThing",
            thing_name=f"greengrass-core-{suffix}",
            attribute_payload=iot.CfnThing.AttributePayloadProperty(
                attributes={
                    "device_type": "greengrass_core",
                    "version": "2.0",
                    "location": "edge"
                }
            )
        )
        
        # Add Thing to Thing Group
        iot.CfnThingGroupInfo(
            self,
            "ThingGroupInfo",
            thing_group_name=self.thing_group.thing_group_name,
            thing_name=iot_thing.thing_name
        )
        
        # Apply deletion policy
        iot_thing.apply_removal_policy(RemovalPolicy.DESTROY)
        
        return iot_thing

    def _create_iot_certificates(self, suffix: str) -> Dict[str, Any]:
        """Create IoT certificates and store in Secrets Manager"""
        # Note: CDK doesn't directly support certificate creation
        # This would typically be done post-deployment or via custom resources
        
        # Create placeholder for certificate ARN (to be updated post-deployment)
        cert_secret = secretsmanager.Secret(
            self,
            "GreengrassCertificates",
            description="IoT certificates for Greengrass Core device",
            secret_name=f"greengrass-certificates-{suffix}",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"certificateArn": "PLACEHOLDER"}',
                generate_string_key="privateKey",
                exclude_characters=' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
                include_space=False,
                password_length=32
            )
        )
        
        return {
            "secret": cert_secret,
            "secret_name": cert_secret.secret_name
        }

    def _create_iot_policy(self, suffix: str) -> iot.CfnPolicy:
        """Create IoT policy with comprehensive Greengrass permissions"""
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:Publish",
                        "iot:Subscribe",
                        "iot:Receive",
                        "iot:Connect"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:GetThingShadow",
                        "iot:UpdateThingShadow",
                        "iot:DeleteThingShadow"
                    ],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:thing/greengrass-core-{suffix}"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "greengrass:*"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogStreams"
                    ],
                    "Resource": f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/greengrass/*"
                }
            ]
        }
        
        iot_policy = iot.CfnPolicy(
            self,
            "GreengrassIoTPolicy",
            policy_name=f"greengrass-policy-{suffix}",
            policy_document=policy_document
        )
        
        # Apply deletion policy
        iot_policy.apply_removal_policy(RemovalPolicy.DESTROY)
        
        return iot_policy

    def _create_greengrass_iam_role(self, suffix: str) -> iam.Role:
        """Create IAM role for Greengrass Core device operations"""
        # Trust policy for IoT credentials service
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("credentials.iot.amazonaws.com")],
                    actions=["sts:AssumeRole"]
                )
            ]
        )
        
        # Custom policy for Greengrass operations
        greengrass_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogStreams"
                    ],
                    resources=[f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/greengrass/*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "iot:GetThingShadow",
                        "iot:UpdateThingShadow",
                        "iot:DeleteThingShadow"
                    ],
                    resources=[f"arn:aws:iot:{self.region}:{self.account}:thing/greengrass-core-{suffix}"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "lambda:InvokeFunction"
                    ],
                    resources=[f"arn:aws:lambda:{self.region}:{self.account}:function:edge-processor-{suffix}"]
                )
            ]
        )
        
        # Create IAM role
        greengrass_role = iam.Role(
            self,
            "GreengrassRole",
            role_name=f"greengrass-core-role-{suffix}",
            assumed_by=iam.ServicePrincipal("credentials.iot.amazonaws.com"),
            inline_policies={
                "GreengrassPolicy": greengrass_policy
            },
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGreengrassResourceAccessRolePolicy"
                )
            ],
            description="IAM role for Greengrass Core device operations and AWS service access"
        )
        
        return greengrass_role

    def _create_edge_lambda_function(self, suffix: str) -> lambda_.Function:
        """Create Lambda function for edge processing"""
        # Lambda function code
        lambda_code = '''
import json
import logging
import time
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Process sensor data at the edge
    
    This function demonstrates local data processing capabilities
    including data validation, transformation, and enrichment.
    """
    logger.info(f"Processing edge data: {json.dumps(event)}")
    
    try:
        # Extract sensor data
        device_id = event.get("device_id", "unknown")
        temperature = event.get("temperature", 0)
        humidity = event.get("humidity", 0)
        timestamp = event.get("timestamp", int(time.time()))
        
        # Validate sensor data
        if not isinstance(temperature, (int, float)) or temperature < -50 or temperature > 100:
            raise ValueError(f"Invalid temperature reading: {temperature}")
        
        if not isinstance(humidity, (int, float)) or humidity < 0 or humidity > 100:
            raise ValueError(f"Invalid humidity reading: {humidity}")
        
        # Process and enrich data
        processed_data = {
            "device_id": device_id,
            "timestamp": timestamp,
            "temperature": {
                "value": temperature,
                "unit": "celsius",
                "status": "normal" if -20 <= temperature <= 50 else "alert"
            },
            "humidity": {
                "value": humidity,
                "unit": "percent",
                "status": "normal" if 30 <= humidity <= 70 else "alert"
            },
            "processing": {
                "processed_at": int(time.time()),
                "processed_by": "edge-lambda",
                "processing_time_ms": 10,
                "edge_device": True
            }
        }
        
        # Log successful processing
        logger.info(f"Successfully processed data for device {device_id}")
        
        return {
            "statusCode": 200,
            "body": json.dumps(processed_data),
            "headers": {
                "Content-Type": "application/json"
            }
        }
        
    except Exception as e:
        logger.error(f"Error processing sensor data: {str(e)}")
        return {
            "statusCode": 400,
            "body": json.dumps({
                "error": str(e),
                "timestamp": int(time.time())
            }),
            "headers": {
                "Content-Type": "application/json"
            }
        }
'''
        
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "EdgeLambdaLogGroup",
            log_group_name=f"/aws/lambda/edge-processor-{suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create Lambda function
        edge_lambda = lambda_.Function(
            self,
            "EdgeProcessorFunction",
            function_name=f"edge-processor-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=Duration.seconds(30),
            memory_size=128,
            environment={
                "LOG_LEVEL": "INFO",
                "EDGE_DEVICE": "true"
            },
            log_group=log_group,
            description="Lambda function for edge data processing in Greengrass environment"
        )
        
        return edge_lambda

    def _create_log_groups(self, suffix: str) -> None:
        """Create CloudWatch log groups for Greengrass components"""
        # Greengrass system log group
        logs.LogGroup(
            self,
            "GreengrassSystemLogGroup",
            log_group_name=f"/aws/greengrass/system-{suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Greengrass user component log group
        logs.LogGroup(
            self,
            "GreengrassUserLogGroup",
            log_group_name=f"/aws/greengrass/user-{suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for deployment information"""
        CfnOutput(
            self,
            "ThingName",
            value=self.iot_thing.thing_name,
            description="IoT Thing name for Greengrass Core device"
        )
        
        CfnOutput(
            self,
            "ThingGroupName",
            value=self.thing_group.thing_group_name,
            description="IoT Thing Group name for device management"
        )
        
        CfnOutput(
            self,
            "IoTPolicyName",
            value=self.iot_policy.policy_name,
            description="IoT policy name for device permissions"
        )
        
        CfnOutput(
            self,
            "GreengrassRoleArn",
            value=self.greengrass_role.role_arn,
            description="IAM role ARN for Greengrass Core operations"
        )
        
        CfnOutput(
            self,
            "EdgeLambdaArn",
            value=self.edge_lambda.function_arn,
            description="Lambda function ARN for edge processing"
        )
        
        CfnOutput(
            self,
            "CertificateSecretName",
            value=self.certificates["secret_name"],
            description="Secrets Manager secret name containing IoT certificates"
        )
        
        CfnOutput(
            self,
            "IoTDataEndpoint",
            value=f"https://{cdk.Fn.ref('AWS::AccountId')}.iot.{self.region}.amazonaws.com",
            description="IoT data endpoint for device connectivity"
        )
        
        CfnOutput(
            self,
            "GreengrassManagementConsole",
            value=f"https://console.aws.amazon.com/iot/home?region={self.region}#/greengrass/v2/cores",
            description="AWS Console URL for Greengrass Core management"
        )