#!/usr/bin/env python3
"""
Smart City Digital Twins with SimSpace Weaver and IoT - CDK Python Application

This CDK application deploys a comprehensive smart city digital twin solution that combines
real-time IoT sensor data ingestion with large-scale spatial simulations using AWS services.

Architecture:
- IoT Core for device connectivity and message routing
- DynamoDB for scalable sensor data storage with streams
- Lambda functions for real-time data processing and analytics
- S3 for simulation assets and configuration storage
- IAM roles with least-privilege permissions

Author: AWS CDK Generator
Version: 1.0
CDK Version: 2.x
"""

import os
from typing import Dict, Any, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    aws_dynamodb as dynamodb,
    aws_iot as iot,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_s3 as s3,
    aws_lambda_event_sources as lambda_event_sources,
    aws_logs as logs,
    Duration,
    RemovalPolicy,
    CfnOutput,
    Tags
)
from constructs import Construct


class SmartCityDigitalTwinsStack(Stack):
    """
    CDK Stack for Smart City Digital Twins with SimSpace Weaver and IoT.
    
    Creates infrastructure for a comprehensive smart city digital twin solution including:
    - IoT sensor data ingestion and processing
    - Real-time analytics and simulation management
    - Scalable data storage with stream processing
    - Simulation asset management
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.project_name = self.node.try_get_context("project_name") or "smartcity-dtwin"
        self.environment = self.node.try_get_context("environment") or "dev"
        
        # Generate unique suffix for resources
        self.unique_suffix = f"{self.environment}-{self.account[-6:]}"
        self.resource_prefix = f"{self.project_name}-{self.unique_suffix}"

        # Create core infrastructure components
        self.sensor_data_table = self._create_dynamodb_table()
        self.simulation_bucket = self._create_s3_bucket()
        self.lambda_execution_role = self._create_lambda_execution_role()
        
        # Create Lambda functions
        self.data_processor_function = self._create_data_processor_function()
        self.stream_processor_function = self._create_stream_processor_function()
        self.simulation_manager_function = self._create_simulation_manager_function()
        self.analytics_processor_function = self._create_analytics_processor_function()
        
        # Configure IoT infrastructure
        self.sensor_thing_group = self._create_iot_thing_group()
        self.sensor_policy = self._create_iot_policy()
        self.sensor_topic_rule = self._create_iot_topic_rule()
        
        # Configure DynamoDB streams
        self._configure_dynamodb_streams()
        
        # Add resource tags
        self._add_resource_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """Create DynamoDB table for sensor data storage with streams enabled."""
        table = dynamodb.Table(
            self, "SensorDataTable",
            table_name=f"{self.resource_prefix}-sensor-data",
            partition_key=dynamodb.Attribute(
                name="sensor_id",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=10,
            write_capacity=10,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )
        
        # Add global secondary index for sensor type queries
        table.add_global_secondary_index(
            index_name="sensor-type-timestamp-index",
            partition_key=dynamodb.Attribute(
                name="sensor_type",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            read_capacity=5,
            write_capacity=5
        )
        
        return table

    def _create_s3_bucket(self) -> s3.Bucket:
        """Create S3 bucket for simulation assets and configuration storage."""
        bucket = s3.Bucket(
            self, "SimulationBucket",
            bucket_name=f"{self.resource_prefix}-simulation-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    noncurrent_version_expiration=Duration.days(30),
                    enabled=True
                )
            ]
        )
        
        return bucket

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda function execution with necessary permissions."""
        role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"{self.resource_prefix}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaDynamoDBExecutionRole"
                )
            ]
        )
        
        # Add custom policy for additional AWS services
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:Scan",
                    "dynamodb:Query",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem"
                ],
                resources=[
                    self.sensor_data_table.table_arn,
                    f"{self.sensor_data_table.table_arn}/index/*"
                ]
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.simulation_bucket.bucket_arn,
                    f"{self.simulation_bucket.bucket_arn}/*"
                ]
            )
        )
        
        # Add SimSpace Weaver permissions (note: service will be discontinued)
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "simspaceweaver:StartSimulation",
                    "simspaceweaver:StopSimulation",
                    "simspaceweaver:ListSimulations",
                    "simspaceweaver:DescribeSimulation"
                ],
                resources=["*"]
            )
        )
        
        return role

    def _create_data_processor_function(self) -> lambda_.Function:
        """Create Lambda function for processing IoT sensor data."""
        function = lambda_.Function(
            self, "DataProcessorFunction",
            function_name=f"{self.resource_prefix}-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            role=self.lambda_execution_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "TABLE_NAME": self.sensor_data_table.table_name,
                "BUCKET_NAME": self.simulation_bucket.bucket_name,
                "PROJECT_NAME": self.project_name
            },
            code=lambda_.Code.from_inline(self._get_data_processor_code()),
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        return function

    def _create_stream_processor_function(self) -> lambda_.Function:
        """Create Lambda function for processing DynamoDB stream events."""
        function = lambda_.Function(
            self, "StreamProcessorFunction",
            function_name=f"{self.resource_prefix}-stream-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="stream_processor.lambda_handler",
            role=self.lambda_execution_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "TABLE_NAME": self.sensor_data_table.table_name,
                "SIMULATION_BUCKET": self.simulation_bucket.bucket_name
            },
            code=lambda_.Code.from_inline(self._get_stream_processor_code()),
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        return function

    def _create_simulation_manager_function(self) -> lambda_.Function:
        """Create Lambda function for managing SimSpace Weaver simulations."""
        function = lambda_.Function(
            self, "SimulationManagerFunction",
            function_name=f"{self.resource_prefix}-simulation-manager",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="simulation_manager.lambda_handler",
            role=self.lambda_execution_role,
            timeout=Duration.seconds(300),
            memory_size=512,
            environment={
                "SIMULATION_BUCKET": self.simulation_bucket.bucket_name,
                "PROJECT_NAME": self.project_name
            },
            code=lambda_.Code.from_inline(self._get_simulation_manager_code()),
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        return function

    def _create_analytics_processor_function(self) -> lambda_.Function:
        """Create Lambda function for processing analytics and generating insights."""
        function = lambda_.Function(
            self, "AnalyticsProcessorFunction",
            function_name=f"{self.resource_prefix}-analytics",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="analytics_processor.lambda_handler",
            role=self.lambda_execution_role,
            timeout=Duration.seconds(300),
            memory_size=1024,
            environment={
                "TABLE_NAME": self.sensor_data_table.table_name,
                "BUCKET_NAME": self.simulation_bucket.bucket_name
            },
            code=lambda_.Code.from_inline(self._get_analytics_processor_code()),
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        return function

    def _create_iot_thing_group(self) -> iot.CfnThingGroup:
        """Create IoT thing group for smart city sensors."""
        thing_group = iot.CfnThingGroup(
            self, "SensorThingGroup",
            thing_group_name=f"{self.resource_prefix}-sensors",
            thing_group_properties=iot.CfnThingGroup.ThingGroupPropertiesProperty(
                thing_group_description="Smart city sensor fleet for digital twin",
                attribute_payload=iot.CfnThingGroup.AttributePayloadProperty(
                    attributes={
                        "project": self.project_name,
                        "environment": self.environment,
                        "type": "smart-city-sensors"
                    }
                )
            )
        )
        
        return thing_group

    def _create_iot_policy(self) -> iot.CfnPolicy:
        """Create IoT policy for sensor devices with least-privilege permissions."""
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["iot:Connect"],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:client/${{aws:username}}"
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Publish"],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:topic/smartcity/sensors/*"
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Subscribe"],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:topicfilter/smartcity/sensors/${{aws:username}}/*"
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Receive"],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:topic/smartcity/sensors/${{aws:username}}/*"
                }
            ]
        }
        
        policy = iot.CfnPolicy(
            self, "SensorPolicy",
            policy_name=f"{self.resource_prefix}-sensor-policy",
            policy_document=policy_document
        )
        
        return policy

    def _create_iot_topic_rule(self) -> iot.CfnTopicRule:
        """Create IoT topic rule for routing sensor data to Lambda."""
        rule_name = f"{self.resource_prefix.replace('-', '_')}_sensor_processing"
        
        topic_rule = iot.CfnTopicRule(
            self, "SensorTopicRule",
            rule_name=rule_name,
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT * FROM 'smartcity/sensors/+/data'",
                description="Route smart city sensor data to processing Lambda",
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        lambda_=iot.CfnTopicRule.LambdaActionProperty(
                            function_arn=self.data_processor_function.function_arn
                        )
                    )
                ]
            )
        )
        
        # Grant IoT permission to invoke Lambda
        self.data_processor_function.add_permission(
            "IoTInvokePermission",
            principal=iam.ServicePrincipal("iot.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"arn:aws:iot:{self.region}:{self.account}:rule/{rule_name}"
        )
        
        return topic_rule

    def _configure_dynamodb_streams(self) -> None:
        """Configure DynamoDB streams processing with Lambda."""
        # Add DynamoDB stream as event source for stream processor function
        stream_event_source = lambda_event_sources.DynamoEventSource(
            table=self.sensor_data_table,
            starting_position=lambda_.StartingPosition.LATEST,
            batch_size=10,
            max_batching_window=Duration.seconds(5),
            retry_attempts=3
        )
        
        self.stream_processor_function.add_event_source(stream_event_source)

    def _add_resource_tags(self) -> None:
        """Add consistent tags to all resources in the stack."""
        tags = {
            "Project": self.project_name,
            "Environment": self.environment,
            "Application": "SmartCityDigitalTwins",
            "ManagedBy": "CDK",
            "CostCenter": "UrbanPlanning"
        }
        
        for key, value in tags.items():
            Tags.of(self).add(key, value)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "DynamoDBTableName",
            value=self.sensor_data_table.table_name,
            description="Name of the DynamoDB table for sensor data"
        )
        
        CfnOutput(
            self, "DynamoDBTableArn",
            value=self.sensor_data_table.table_arn,
            description="ARN of the DynamoDB table for sensor data"
        )
        
        CfnOutput(
            self, "SimulationBucketName",
            value=self.simulation_bucket.bucket_name,
            description="Name of the S3 bucket for simulation assets"
        )
        
        CfnOutput(
            self, "DataProcessorFunctionArn",
            value=self.data_processor_function.function_arn,
            description="ARN of the data processor Lambda function"
        )
        
        CfnOutput(
            self, "IoTThingGroupName",
            value=self.sensor_thing_group.thing_group_name,
            description="Name of the IoT thing group for sensors"
        )
        
        CfnOutput(
            self, "IoTEndpoint",
            value=f"https://{cdk.Fn.ref('AWS::NoValue')}.iot.{self.region}.amazonaws.com",
            description="IoT endpoint for device connections"
        )
        
        CfnOutput(
            self, "ProjectResourcePrefix",
            value=self.resource_prefix,
            description="Resource prefix used for all project resources"
        )

    def _get_data_processor_code(self) -> str:
        """Return the inline code for the data processor Lambda function."""
        return '''
import json
import boto3
import uuid
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """Process IoT sensor data and store in DynamoDB"""
    try:
        # Parse IoT message
        for record in event.get('Records', []):
            # Extract sensor data from IoT message
            message = json.loads(record['body']) if 'body' in record else record
            
            sensor_data = {
                'sensor_id': message.get('sensor_id', 'unknown'),
                'timestamp': datetime.utcnow().isoformat(),
                'sensor_type': message.get('sensor_type', 'generic'),
                'location': message.get('location', {}),
                'data': message.get('data', {}),
                'metadata': {
                    'processed_at': datetime.utcnow().isoformat(),
                    'processor_id': context.function_name
                }
            }
            
            # Store in DynamoDB
            table.put_item(Item=sensor_data)
            
            logger.info(f"Processed sensor data: {sensor_data['sensor_id']}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed sensor data')
        }
        
    except Exception as e:
        logger.error(f"Error processing sensor data: {str(e)}")
        raise
'''

    def _get_stream_processor_code(self) -> str:
        """Return the inline code for the stream processor Lambda function."""
        return '''
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process DynamoDB stream events for simulation updates"""
    try:
        for record in event['Records']:
            event_name = record['eventName']
            
            if event_name in ['INSERT', 'MODIFY']:
                # Extract sensor data from stream record
                sensor_data = record['dynamodb']['NewImage']
                
                # Process for simulation input
                simulation_input = {
                    'sensor_id': sensor_data['sensor_id']['S'],
                    'timestamp': sensor_data['timestamp']['S'],
                    'sensor_type': sensor_data['sensor_type']['S'],
                    'event_type': event_name,
                    'data': sensor_data.get('data', {})
                }
                
                logger.info(f"Processed stream event: {simulation_input}")
                
                # TODO: Send to SimSpace Weaver simulation
                # This would typically trigger simulation updates
                
        return {'statusCode': 200, 'body': 'Stream processed successfully'}
        
    except Exception as e:
        logger.error(f"Error processing stream: {str(e)}")
        raise
'''

    def _get_simulation_manager_code(self) -> str:
        """Return the inline code for the simulation manager Lambda function."""
        return '''
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

simspace = boto3.client('simspaceweaver')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """Manage SimSpace Weaver simulations"""
    try:
        action = event.get('action', 'status')
        
        if action == 'start':
            return start_simulation(event, context)
        elif action == 'stop':
            return stop_simulation(event)
        elif action == 'status':
            return get_simulation_status(event)
        else:
            return {'statusCode': 400, 'body': 'Invalid action'}
            
    except Exception as e:
        logger.error(f"Error managing simulation: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def start_simulation(event, context):
    """Start a new simulation"""
    simulation_name = event.get('simulation_name', 'smart-city-simulation')
    
    try:
        # Extract AWS account ID from context
        account_id = context.invoked_function_arn.split(':')[4]
        
        response = simspace.start_simulation(
            Name=simulation_name,
            RoleArn=f'arn:aws:iam::{account_id}:role/SimSpaceWeaverRole',
            SchemaS3Location={
                'BucketName': os.environ['SIMULATION_BUCKET'],
                'ObjectKey': 'simulation_schema.yaml'
            }
        )
        
        logger.info(f"Started simulation: {simulation_name}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Simulation started',
                'simulation_name': simulation_name,
                'arn': response.get('Arn')
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to start simulation: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def stop_simulation(event):
    """Stop running simulation"""
    simulation_name = event.get('simulation_name')
    
    try:
        simspace.stop_simulation(Simulation=simulation_name)
        
        logger.info(f"Stopped simulation: {simulation_name}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Simulation stopped',
                'simulation_name': simulation_name
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to stop simulation: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def get_simulation_status(event):
    """Get current simulation status"""
    try:
        response = simspace.list_simulations()
        
        simulations = []
        for sim in response.get('Simulations', []):
            simulations.append({
                'name': sim.get('Name'),
                'status': sim.get('Status'),
                'created': sim.get('CreationTime').isoformat() if sim.get('CreationTime') else None
            })
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'simulations': simulations,
                'count': len(simulations)
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to get simulation status: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}
'''

    def _get_analytics_processor_code(self) -> str:
        """Return the inline code for the analytics processor Lambda function."""
        return '''
import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """Process analytics for smart city insights"""
    try:
        analytics_type = event.get('type', 'traffic_summary')
        time_range = event.get('time_range', '24h')
        
        if analytics_type == 'traffic_summary':
            return generate_traffic_summary(time_range)
        elif analytics_type == 'sensor_health':
            return generate_sensor_health_report()
        elif analytics_type == 'simulation_insights':
            return generate_simulation_insights()
        else:
            return {'statusCode': 400, 'body': 'Invalid analytics type'}
            
    except Exception as e:
        logger.error(f"Error processing analytics: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def generate_traffic_summary(time_range):
    """Generate traffic analytics summary"""
    try:
        # Calculate time range
        end_time = datetime.now()
        if time_range == '24h':
            start_time = end_time - timedelta(hours=24)
        elif time_range == '7d':
            start_time = end_time - timedelta(days=7)
        else:
            start_time = end_time - timedelta(hours=1)
            
        # Query traffic sensor data
        response = table.scan(
            FilterExpression='#sensor_type = :sensor_type AND #timestamp BETWEEN :start_time AND :end_time',
            ExpressionAttributeNames={
                '#sensor_type': 'sensor_type',
                '#timestamp': 'timestamp'
            },
            ExpressionAttributeValues={
                ':sensor_type': 'traffic',
                ':start_time': start_time.isoformat(),
                ':end_time': end_time.isoformat()
            }
        )
        
        # Process traffic data
        traffic_data = response['Items']
        total_vehicles = sum(item.get('data', {}).get('vehicle_count', 0) for item in traffic_data)
        average_speed = sum(item.get('data', {}).get('average_speed', 0) for item in traffic_data) / len(traffic_data) if traffic_data else 0
        
        # Generate congestion metrics
        congestion_score = calculate_congestion_score(traffic_data)
        
        summary = {
            'time_range': time_range,
            'total_vehicles': total_vehicles,
            'average_speed': float(average_speed),
            'congestion_score': congestion_score,
            'sensor_count': len(set(item['sensor_id'] for item in traffic_data)),
            'generated_at': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(summary, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate traffic summary: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def calculate_congestion_score(traffic_data):
    """Calculate traffic congestion score"""
    if not traffic_data:
        return 0
        
    # Simple congestion calculation based on speed and volume
    total_score = 0
    for item in traffic_data:
        speed = item.get('data', {}).get('average_speed', 50)
        volume = item.get('data', {}).get('vehicle_count', 0)
        
        # Higher volume and lower speed = higher congestion
        score = (volume / 10) * (60 - speed) / 60
        total_score += max(0, min(100, score))
        
    return total_score / len(traffic_data)

def generate_sensor_health_report():
    """Generate sensor health and connectivity report"""
    try:
        # Query recent sensor data
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=1)
        
        response = table.scan(
            FilterExpression='#timestamp BETWEEN :start_time AND :end_time',
            ExpressionAttributeNames={'#timestamp': 'timestamp'},
            ExpressionAttributeValues={
                ':start_time': start_time.isoformat(),
                ':end_time': end_time.isoformat()
            }
        )
        
        # Analyze sensor health
        sensors = {}
        for item in response['Items']:
            sensor_id = item['sensor_id']
            if sensor_id not in sensors:
                sensors[sensor_id] = {
                    'sensor_id': sensor_id,
                    'sensor_type': item.get('sensor_type', 'unknown'),
                    'message_count': 0,
                    'last_seen': item['timestamp'],
                    'status': 'active'
                }
            sensors[sensor_id]['message_count'] += 1
            
        # Determine sensor health status
        for sensor in sensors.values():
            if sensor['message_count'] < 5:  # Less than 5 messages per hour
                sensor['status'] = 'warning'
            if sensor['message_count'] == 0:
                sensor['status'] = 'offline'
                
        health_report = {
            'total_sensors': len(sensors),
            'active_sensors': sum(1 for s in sensors.values() if s['status'] == 'active'),
            'warning_sensors': sum(1 for s in sensors.values() if s['status'] == 'warning'),
            'offline_sensors': sum(1 for s in sensors.values() if s['status'] == 'offline'),
            'sensors': list(sensors.values()),
            'generated_at': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate sensor health report: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}

def generate_simulation_insights():
    """Generate insights from simulation results"""
    try:
        # This would typically query simulation results
        # For now, return mock insights
        insights = {
            'traffic_optimization': {
                'potential_improvement': '15%',
                'recommended_actions': [
                    'Optimize traffic light timing at Main St intersection',
                    'Implement dynamic routing for congested areas',
                    'Add traffic sensors to Highway 101 corridor'
                ]
            },
            'emergency_response': {
                'average_response_time': '4.2 minutes',
                'optimization_opportunities': [
                    'Relocate ambulance station to reduce coverage gaps',
                    'Implement priority traffic routing for emergency vehicles'
                ]
            },
            'infrastructure_utilization': {
                'capacity_utilization': '68%',
                'peak_hours': ['8:00-9:00 AM', '5:00-6:00 PM'],
                'recommendations': [
                    'Implement congestion pricing during peak hours',
                    'Promote alternative transportation options'
                ]
            },
            'generated_at': datetime.now().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(insights)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate simulation insights: {str(e)}")
        return {'statusCode': 500, 'body': str(e)}
'''


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get environment configuration
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    if not account or not region:
        raise ValueError("AWS account and region must be specified via context or environment variables")
    
    env = Environment(account=account, region=region)
    
    # Create the smart city digital twins stack
    SmartCityDigitalTwinsStack(
        app, "SmartCityDigitalTwinsStack",
        env=env,
        description="Smart City Digital Twins with SimSpace Weaver and IoT - CDK Python Stack",
        stack_name=app.node.try_get_context("stack_name") or "smart-city-digital-twins"
    )
    
    app.synth()


if __name__ == "__main__":
    main()