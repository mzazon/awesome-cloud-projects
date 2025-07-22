#!/usr/bin/env python3
"""
CDK Python application for blockchain-based supply chain tracking systems.

This application deploys a comprehensive supply chain tracking solution using:
- Amazon Managed Blockchain with Hyperledger Fabric
- AWS IoT Core for sensor data collection
- Lambda functions for data processing
- EventBridge for event orchestration
- DynamoDB for metadata storage
- S3 for chaincode and data storage
- CloudWatch for monitoring and alerting
- SNS for notifications
"""

import os
from typing import Dict, Any
import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    Tags,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from aws_cdk import (
    aws_s3 as s3,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_iot as iot,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_managedblockchain as managedblockchain,
    aws_logs as logs,
)
from constructs import Construct


class SupplyChainBlockchainStack(Stack):
    """
    CDK Stack for deploying a blockchain-based supply chain tracking system.
    
    This stack creates all the necessary AWS resources for a complete supply chain
    tracking solution including blockchain network, IoT infrastructure, data processing,
    event orchestration, and monitoring capabilities.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        network_name: str = "supply-chain-network",
        member_name: str = "manufacturer-member",
        **kwargs: Any,
    ) -> None:
        """
        Initialize the Supply Chain Blockchain Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            network_name: Name of the blockchain network
            member_name: Name of the initial network member
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store parameters
        self.network_name = network_name
        self.member_name = member_name

        # Create S3 bucket for chaincode and data storage
        self.chaincode_bucket = self._create_chaincode_bucket()

        # Create DynamoDB table for supply chain metadata
        self.metadata_table = self._create_metadata_table()

        # Create IAM roles
        self.lambda_role = self._create_lambda_execution_role()

        # Create Lambda function for processing sensor data
        self.sensor_processing_function = self._create_sensor_processing_function()

        # Create IoT resources
        self.iot_thing = self._create_iot_thing()
        self.iot_policy = self._create_iot_policy()
        self.iot_rule = self._create_iot_rule()

        # Create EventBridge resources
        self.sns_topic = self._create_sns_topic()
        self.event_rule = self._create_event_rule()

        # Create CloudWatch monitoring
        self._create_cloudwatch_monitoring()

        # Create blockchain network (Note: This is simplified due to CDK limitations)
        self._create_blockchain_network()

        # Output important resource information
        self._create_outputs()

        # Apply tags to all resources
        self._apply_tags()

    def _create_chaincode_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing chaincode and supply chain data."""
        bucket = s3.Bucket(
            self,
            "SupplyChainDataBucket",
            bucket_name=f"supply-chain-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        CfnOutput(
            self,
            "ChaincodeBucketName",
            value=bucket.bucket_name,
            description="S3 bucket for chaincode and supply chain data storage",
        )

        return bucket

    def _create_metadata_table(self) -> dynamodb.Table:
        """Create DynamoDB table for supply chain metadata storage."""
        table = dynamodb.Table(
            self,
            "SupplyChainMetadata",
            table_name="SupplyChainMetadata",
            partition_key=dynamodb.Attribute(
                name="ProductId", type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp", type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=5,
            write_capacity=5,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )

        # Add GSI for location-based queries
        table.add_global_secondary_index(
            index_name="LocationIndex",
            partition_key=dynamodb.Attribute(
                name="Location", type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp", type=dynamodb.AttributeType.NUMBER
            ),
            read_capacity=5,
            write_capacity=5,
        )

        CfnOutput(
            self,
            "MetadataTableName",
            value=table.table_name,
            description="DynamoDB table for supply chain metadata",
        )

        return table

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda function execution."""
        role = iam.Role(
            self,
            "SupplyChainLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add DynamoDB permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                ],
                resources=[
                    self.metadata_table.table_arn,
                    f"{self.metadata_table.table_arn}/index/*",
                ],
            )
        )

        # Add EventBridge permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["events:PutEvents"],
                resources=[f"arn:aws:events:{self.region}:{self.account}:event-bus/*"],
            )
        )

        # Add S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject", "s3:PutObject"],
                resources=[f"{self.chaincode_bucket.bucket_arn}/*"],
            )
        )

        return role

    def _create_sensor_processing_function(self) -> lambda_.Function:
        """Create Lambda function for processing IoT sensor data."""
        function = lambda_.Function(
            self,
            "ProcessSupplyChainData",
            function_name="ProcessSupplyChainData",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "METADATA_TABLE_NAME": self.metadata_table.table_name,
                "REGION": self.region,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        CfnOutput(
            self,
            "SensorProcessingFunctionArn",
            value=function.function_arn,
            description="ARN of the sensor data processing Lambda function",
        )

        return function

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for processing sensor data."""
        return """
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const eventbridge = new AWS.EventBridge();

exports.handler = async (event) => {
    console.log('Processing sensor data:', JSON.stringify(event, null, 2));
    
    try {
        // Extract sensor data
        const sensorData = {
            productId: event.productId,
            location: event.location,
            temperature: event.temperature,
            humidity: event.humidity,
            timestamp: event.timestamp || Date.now()
        };
        
        // Store in DynamoDB
        await dynamodb.put({
            TableName: process.env.METADATA_TABLE_NAME,
            Item: {
                ProductId: sensorData.productId,
                Timestamp: sensorData.timestamp,
                Location: sensorData.location,
                SensorData: {
                    temperature: sensorData.temperature,
                    humidity: sensorData.humidity
                }
            }
        }).promise();
        
        // Send event to EventBridge
        await eventbridge.putEvents({
            Entries: [{
                Source: 'supply-chain.sensor',
                DetailType: 'Product Location Update',
                Detail: JSON.stringify(sensorData)
            }]
        }).promise();
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Sensor data processed successfully',
                productId: sensorData.productId
            })
        };
        
    } catch (error) {
        console.error('Error processing sensor data:', error);
        throw error;
    }
};
        """

    def _create_iot_thing(self) -> iot.CfnThing:
        """Create IoT Thing for supply chain tracking devices."""
        thing = iot.CfnThing(
            self,
            "SupplyChainTracker",
            thing_name=f"supply-chain-tracker-{self.account}",
            attribute_payload=iot.CfnThing.AttributePayloadProperty(
                attributes={
                    "deviceType": "supplyChainTracker",
                    "version": "1.0",
                }
            ),
        )

        CfnOutput(
            self,
            "IoTThingName",
            value=thing.thing_name,
            description="IoT Thing name for supply chain tracking devices",
        )

        return thing

    def _create_iot_policy(self) -> iot.CfnPolicy:
        """Create IoT policy for supply chain devices."""
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:Publish",
                        "iot:Subscribe",
                        "iot:Connect",
                        "iot:Receive",
                    ],
                    "Resource": "*",
                }
            ],
        }

        policy = iot.CfnPolicy(
            self,
            "SupplyChainTrackerPolicy",
            policy_name="SupplyChainTrackerPolicy",
            policy_document=policy_document,
        )

        return policy

    def _create_iot_rule(self) -> iot.CfnTopicRule:
        """Create IoT rule for processing sensor data."""
        # Grant IoT permission to invoke Lambda
        self.sensor_processing_function.add_permission(
            "IoTInvokePermission",
            principal=iam.ServicePrincipal("iot.amazonaws.com"),
            source_arn=f"arn:aws:iot:{self.region}:{self.account}:rule/SupplyChainSensorRule",
        )

        rule = iot.CfnTopicRule(
            self,
            "SupplyChainSensorRule",
            rule_name="SupplyChainSensorRule",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT * FROM 'supply-chain/sensor-data'",
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        lambda_=iot.CfnTopicRule.LambdaActionProperty(
                            function_arn=self.sensor_processing_function.function_arn
                        )
                    )
                ],
                rule_disabled=False,
            ),
        )

        CfnOutput(
            self,
            "IoTRuleName",
            value=rule.rule_name,
            description="IoT rule for processing sensor data",
        )

        return rule

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for supply chain notifications."""
        topic = sns.Topic(
            self,
            "SupplyChainNotifications",
            topic_name="supply-chain-notifications",
            display_name="Supply Chain Notifications",
        )

        CfnOutput(
            self,
            "NotificationTopicArn",
            value=topic.topic_arn,
            description="SNS topic for supply chain notifications",
        )

        return topic

    def _create_event_rule(self) -> events.Rule:
        """Create EventBridge rule for supply chain events."""
        rule = events.Rule(
            self,
            "SupplyChainTrackingRule",
            rule_name="SupplyChainTrackingRule",
            description="Rule for supply chain tracking events",
            event_pattern=events.EventPattern(
                source=["supply-chain.sensor"],
                detail_type=["Product Location Update"],
            ),
        )

        # Add SNS topic as target
        rule.add_target(events_targets.SnsTopic(self.sns_topic))

        CfnOutput(
            self,
            "EventRuleArn",
            value=rule.rule_arn,
            description="EventBridge rule for supply chain events",
        )

        return rule

    def _create_cloudwatch_monitoring(self) -> None:
        """Create CloudWatch monitoring dashboard and alarms."""
        # Create dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "SupplyChainDashboard",
            dashboard_name="SupplyChainTracking",
        )

        # Add Lambda metrics widget
        lambda_widget = cloudwatch.GraphWidget(
            title="Supply Chain Processing Metrics",
            left=[
                self.sensor_processing_function.metric_invocations(),
                self.sensor_processing_function.metric_errors(),
                self.sensor_processing_function.metric_duration(),
            ],
        )

        dashboard.add_widgets(lambda_widget)

        # Create alarm for Lambda errors
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "SupplyChainLambdaErrors",
            alarm_name="SupplyChain-Lambda-Errors",
            alarm_description="Alert on Lambda function errors",
            metric=self.sensor_processing_function.metric_errors(),
            threshold=1,
            evaluation_periods=1,
        )

        lambda_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

        # Create alarm for DynamoDB throttling
        dynamodb_throttle_alarm = cloudwatch.Alarm(
            self,
            "SupplyChainDynamoDBThrottles",
            alarm_name="SupplyChain-DynamoDB-Throttles",
            alarm_description="Alert on DynamoDB throttling",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="ThrottledRequests",
                dimensions_map={"TableName": self.metadata_table.table_name},
                statistic="Sum",
            ),
            threshold=1,
            evaluation_periods=1,
        )

        dynamodb_throttle_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _create_blockchain_network(self) -> None:
        """
        Create blockchain network configuration.
        
        Note: Due to CDK limitations with Managed Blockchain, this creates
        a basic network configuration. Full blockchain setup requires additional
        manual steps or custom resources.
        """
        # Note: Amazon Managed Blockchain is not fully supported in CDK Python yet
        # This would typically be done using CloudFormation custom resources
        # or through the AWS CLI after stack deployment
        
        CfnOutput(
            self,
            "BlockchainNetworkInfo",
            value="Blockchain network creation requires manual setup",
            description="Instructions for blockchain network setup",
        )

    def _create_outputs(self) -> None:
        """Create stack outputs for important resource information."""
        CfnOutput(
            self,
            "StackName",
            value=self.stack_name,
            description="Name of the deployed stack",
        )

        CfnOutput(
            self,
            "Region",
            value=self.region,
            description="AWS region where resources are deployed",
        )

        CfnOutput(
            self,
            "AccountId",
            value=self.account,
            description="AWS account ID",
        )

    def _apply_tags(self) -> None:
        """Apply common tags to all resources in the stack."""
        Tags.of(self).add("Project", "SupplyChainBlockchain")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "SupplyChain")


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()

    # Get configuration from context or environment variables
    network_name = app.node.try_get_context("networkName") or "supply-chain-network"
    member_name = app.node.try_get_context("memberName") or "manufacturer-member"
    
    # Determine deployment environment
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )

    # Create the supply chain blockchain stack
    SupplyChainBlockchainStack(
        app,
        "SupplyChainBlockchainStack",
        network_name=network_name,
        member_name=member_name,
        env=env,
        description="Blockchain-based supply chain tracking system",
    )

    app.synth()


if __name__ == "__main__":
    main()