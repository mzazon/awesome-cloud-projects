#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import { DynamoEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';
import path = require('path');

/**
 * Props for the Smart City Digital Twin Stack
 */
export interface SmartCityDigitalTwinStackProps extends cdk.StackProps {
  /**
   * Project name prefix for resource naming
   * @default 'smartcity'
   */
  readonly projectName?: string;
  
  /**
   * Environment (dev, staging, prod) for resource tagging
   * @default 'dev'
   */
  readonly environment?: string;
}

/**
 * Smart City Digital Twin Stack using SimSpace Weaver and IoT Core
 * 
 * This stack deploys infrastructure for a comprehensive smart city digital twin
 * that combines real-time IoT sensor data with spatial simulations.
 */
export class SmartCityDigitalTwinStack extends cdk.Stack {
  
  // Core infrastructure properties
  public readonly sensorDataTable: dynamodb.Table;
  public readonly simulationBucket: s3.Bucket;
  public readonly dataProcessorFunction: lambda.Function;
  public readonly streamProcessorFunction: lambda.Function;
  public readonly simulationManagerFunction: lambda.Function;
  public readonly analyticsFunction: lambda.Function;
  
  constructor(scope: Construct, id: string, props?: SmartCityDigitalTwinStackProps) {
    super(scope, id, props);
    
    const projectName = props?.projectName ?? 'smartcity';
    const environment = props?.environment ?? 'dev';
    
    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const resourcePrefix = `${projectName}-${uniqueSuffix}`;
    
    // Apply common tags to all resources in the stack
    cdk.Tags.of(this).add('Project', 'SmartCityDigitalTwin');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    
    // =========================================================================
    // DynamoDB Table for Sensor Data Storage
    // =========================================================================
    
    this.sensorDataTable = new dynamodb.Table(this, 'SensorDataTable', {
      tableName: `${resourcePrefix}-sensor-data`,
      partitionKey: {
        name: 'sensor_id',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 10,
      writeCapacity: 10,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
    });
    
    // =========================================================================
    // S3 Bucket for Simulation Assets
    // =========================================================================
    
    this.simulationBucket = new s3.Bucket(this, 'SimulationBucket', {
      bucketName: `${resourcePrefix}-simulation-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'delete-incomplete-multipart-uploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
          enabled: true,
        },
        {
          id: 'delete-old-versions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
          enabled: true,
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true, // For demo purposes only
    });
    
    // =========================================================================
    // IAM Roles and Policies
    // =========================================================================
    
    // Lambda execution role with comprehensive permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${resourcePrefix}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSLambdaDynamoDBExecutionRole'),
      ],
      inlinePolicies: {
        'SmartCityPermissions': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:UpdateItem',
                'dynamodb:DescribeTable',
              ],
              resources: [this.sensorDataTable.tableArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                this.simulationBucket.bucketArn,
                `${this.simulationBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iot:Publish',
                'iot:Connect',
                'iot:Receive',
              ],
              resources: [
                `arn:aws:iot:${this.region}:${this.account}:topic/smartcity/*`,
                `arn:aws:iot:${this.region}:${this.account}:client/*`,
              ],
            }),
            // SimSpace Weaver permissions (commented out as service is being discontinued)
            // new iam.PolicyStatement({
            //   effect: iam.Effect.ALLOW,
            //   actions: [
            //     'simspaceweaver:StartSimulation',
            //     'simspaceweaver:StopSimulation',
            //     'simspaceweaver:ListSimulations',
            //     'simspaceweaver:DescribeSimulation',
            //   ],
            //   resources: ['*'], // SimSpace Weaver doesn't support resource-level permissions
            // }),
          ],
        }),
      },
    });
    
    // =========================================================================
    // Lambda Functions
    // =========================================================================
    
    // Data Processor Function - Processes IoT sensor data
    this.dataProcessorFunction = new lambda.Function(this, 'DataProcessorFunction', {
      functionName: `${resourcePrefix}-processor`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """Process IoT sensor data and store in DynamoDB"""
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Handle different event sources (IoT Core, API Gateway, etc.)
        records = event.get('Records', [])
        if not records:
            # Direct invocation or single message
            records = [event] if 'sensor_id' in event else []
        
        processed_count = 0
        for record in records:
            # Extract sensor data from message
            if 'body' in record:
                # SQS message format
                message = json.loads(record['body'])
            elif 'Sns' in record:
                # SNS message format
                message = json.loads(record['Sns']['Message'])
            else:
                # Direct message format
                message = record
            
            # Validate required fields
            if 'sensor_id' not in message:
                logger.warning(f"Missing sensor_id in message: {message}")
                continue
                
            # Prepare sensor data for storage
            sensor_data = {
                'sensor_id': message.get('sensor_id', 'unknown'),
                'timestamp': message.get('timestamp', datetime.utcnow().isoformat()),
                'sensor_type': message.get('sensor_type', 'generic'),
                'location': message.get('location', {}),
                'data': message.get('data', {}),
                'metadata': {
                    'processed_at': datetime.utcnow().isoformat(),
                    'processor_id': context.function_name,
                    'request_id': context.aws_request_id
                }
            }
            
            # Store in DynamoDB
            try:
                table.put_item(Item=sensor_data)
                processed_count += 1
                logger.info(f"Stored sensor data: {sensor_data['sensor_id']} at {sensor_data['timestamp']}")
            except Exception as e:
                logger.error(f"Failed to store sensor data: {str(e)}")
                raise
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {processed_count} sensor records',
                'processed_count': processed_count
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing sensor data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to process sensor data',
                'details': str(e)
            })
        }
      `),
      environment: {
        'TABLE_NAME': this.sensorDataTable.tableName,
        'SIMULATION_BUCKET': this.simulationBucket.bucketName,
      },
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });
    
    // Stream Processor Function - Processes DynamoDB stream events
    this.streamProcessorFunction = new lambda.Function(this, 'StreamProcessorFunction', {
      functionName: `${resourcePrefix}-stream-processor`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'stream_processor.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process DynamoDB stream events for real-time simulation updates"""
    try:
        logger.info(f"Processing {len(event['Records'])} stream records")
        
        processed_events = []
        
        for record in event['Records']:
            event_name = record['eventName']
            
            if event_name in ['INSERT', 'MODIFY']:
                # Extract sensor data from stream record
                dynamodb_record = record['dynamodb']
                
                if 'NewImage' in dynamodb_record:
                    # Convert DynamoDB format to standard format
                    sensor_data = {
                        'sensor_id': dynamodb_record['NewImage'].get('sensor_id', {}).get('S', 'unknown'),
                        'timestamp': dynamodb_record['NewImage'].get('timestamp', {}).get('S', ''),
                        'sensor_type': dynamodb_record['NewImage'].get('sensor_type', {}).get('S', 'generic'),
                        'event_type': event_name,
                        'stream_event_id': record.get('eventID'),
                        'approximate_creation_time': record.get('dynamodb', {}).get('ApproximateCreationDateTime')
                    }
                    
                    # Extract nested data if present
                    if 'data' in dynamodb_record['NewImage']:
                        sensor_data['data'] = parse_dynamodb_attribute(dynamodb_record['NewImage']['data'])
                    
                    if 'location' in dynamodb_record['NewImage']:
                        sensor_data['location'] = parse_dynamodb_attribute(dynamodb_record['NewImage']['location'])
                    
                    processed_events.append(sensor_data)
                    logger.info(f"Processed stream event for sensor: {sensor_data['sensor_id']}")
                    
                    # TODO: In production, this would trigger simulation updates
                    # For now, we log the event for monitoring
                    logger.info(f"Simulation update trigger: {json.dumps(sensor_data, default=str)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {len(processed_events)} stream events',
                'processed_events': len(processed_events)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing stream events: {str(e)}")
        raise

def parse_dynamodb_attribute(attribute):
    """Parse DynamoDB attribute value to Python object"""
    if 'S' in attribute:
        return attribute['S']
    elif 'N' in attribute:
        return float(attribute['N'])
    elif 'BOOL' in attribute:
        return attribute['BOOL']
    elif 'M' in attribute:
        # Map type - recursively parse nested attributes
        result = {}
        for key, value in attribute['M'].items():
            result[key] = parse_dynamodb_attribute(value)
        return result
    elif 'L' in attribute:
        # List type - recursively parse list items
        return [parse_dynamodb_attribute(item) for item in attribute['L']]
    else:
        return str(attribute)
      `),
      environment: {
        'TABLE_NAME': this.sensorDataTable.tableName,
        'SIMULATION_BUCKET': this.simulationBucket.bucketName,
      },
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });
    
    // Add DynamoDB stream as event source for stream processor
    this.streamProcessorFunction.addEventSource(new DynamoEventSource(this.sensorDataTable, {
      startingPosition: lambda.StartingPosition.LATEST,
      batchSize: 10,
      retryAttempts: 3,
    }));
    
    // Simulation Manager Function - Manages simulation lifecycle
    this.simulationManagerFunction = new lambda.Function(this, 'SimulationManagerFunction', {
      functionName: `${resourcePrefix}-simulation-manager`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'simulation_manager.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

def lambda_handler(event, context):
    """Manage simulation lifecycle and coordination"""
    try:
        action = event.get('action', 'status')
        logger.info(f"Simulation manager action: {action}")
        
        if action == 'prepare_simulation':
            return prepare_simulation_assets(event, context)
        elif action == 'status':
            return get_simulation_status(event)
        elif action == 'cleanup':
            return cleanup_simulation_resources(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Invalid action: {action}'})
            }
            
    except Exception as e:
        logger.error(f"Error in simulation manager: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def prepare_simulation_assets(event, context):
    """Prepare simulation assets and configuration"""
    try:
        simulation_name = event.get('simulation_name', 'smart-city-simulation')
        bucket_name = os.environ['SIMULATION_BUCKET']
        
        # Create simulation configuration
        simulation_config = {
            'name': simulation_name,
            'version': '1.0',
            'created_at': datetime.utcnow().isoformat(),
            'spatial_domains': {
                'city_grid': {
                    'dimensions': {'x': 1000, 'y': 1000, 'z': 100},
                    'partitioning_strategy': 'grid_4x4'
                }
            },
            'applications': [
                {
                    'name': 'traffic_simulation',
                    'type': 'spatial',
                    'instances': 4,
                    'resources': {'cpu': '1 vCPU', 'memory': '2 GB'}
                },
                {
                    'name': 'utility_monitoring', 
                    'type': 'spatial',
                    'instances': 2,
                    'resources': {'cpu': '0.5 vCPU', 'memory': '1 GB'}
                },
                {
                    'name': 'emergency_response',
                    'type': 'spatial', 
                    'instances': 1,
                    'resources': {'cpu': '0.5 vCPU', 'memory': '1 GB'}
                }
            ]
        }
        
        # Upload configuration to S3
        config_key = f'simulations/{simulation_name}/config.json'
        s3.put_object(
            Bucket=bucket_name,
            Key=config_key,
            Body=json.dumps(simulation_config, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Simulation configuration uploaded: s3://{bucket_name}/{config_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Simulation assets prepared successfully',
                'simulation_name': simulation_name,
                'config_location': f's3://{bucket_name}/{config_key}',
                'note': 'SimSpace Weaver integration commented out due to service discontinuation'
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to prepare simulation assets: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def get_simulation_status(event):
    """Get current simulation status and metrics"""
    try:
        # In a production environment with active simulation service,
        # this would query the simulation platform for real status
        
        status_info = {
            'simulations': [
                {
                    'name': 'smart-city-simulation',
                    'status': 'configured',
                    'note': 'SimSpace Weaver service discontinued - configuration ready for alternative platform',
                    'created': datetime.utcnow().isoformat(),
                    'components': ['traffic_simulation', 'utility_monitoring', 'emergency_response']
                }
            ],
            'total_simulations': 1,
            'active_sensors': 0,  # Would be populated from actual sensor data
            'last_updated': datetime.utcnow().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(status_info, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to get simulation status: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def cleanup_simulation_resources(event):
    """Clean up simulation resources"""
    try:
        bucket_name = os.environ['SIMULATION_BUCKET']
        simulation_name = event.get('simulation_name', 'smart-city-simulation')
        
        # List and delete simulation objects
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix=f'simulations/{simulation_name}/'
        )
        
        deleted_objects = 0
        if 'Contents' in response:
            for obj in response['Contents']:
                s3.delete_object(Bucket=bucket_name, Key=obj['Key'])
                deleted_objects += 1
                logger.info(f"Deleted simulation object: {obj['Key']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Simulation resources cleaned up',
                'deleted_objects': deleted_objects,
                'simulation_name': simulation_name
            })
        }
        
    except Exception as e:
        logger.error(f"Failed to cleanup simulation resources: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
      `),
      environment: {
        'TABLE_NAME': this.sensorDataTable.tableName,
        'SIMULATION_BUCKET': this.simulationBucket.bucketName,
      },
      role: lambdaExecutionRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });
    
    // Analytics Function - Processes data for insights and visualization
    this.analyticsFunction = new lambda.Function(this, 'AnalyticsFunction', {
      functionName: `${resourcePrefix}-analytics`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'analytics_processor.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime, timedelta
from decimal import Decimal
import os
from boto3.dynamodb.conditions import Key, Attr

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """Process analytics for smart city insights"""
    try:
        analytics_type = event.get('type', 'traffic_summary')
        time_range = event.get('time_range', '24h')
        
        logger.info(f"Processing analytics: {analytics_type} for {time_range}")
        
        if analytics_type == 'traffic_summary':
            return generate_traffic_summary(time_range)
        elif analytics_type == 'sensor_health':
            return generate_sensor_health_report()
        elif analytics_type == 'simulation_insights':
            return generate_simulation_insights()
        elif analytics_type == 'city_metrics':
            return generate_city_metrics(time_range)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Invalid analytics type: {analytics_type}'})
            }
            
    except Exception as e:
        logger.error(f"Error processing analytics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def generate_traffic_summary(time_range):
    """Generate comprehensive traffic analytics"""
    try:
        # Calculate time boundaries
        end_time = datetime.utcnow()
        if time_range == '24h':
            start_time = end_time - timedelta(hours=24)
        elif time_range == '7d':
            start_time = end_time - timedelta(days=7)
        elif time_range == '1h':
            start_time = end_time - timedelta(hours=1)
        else:
            start_time = end_time - timedelta(hours=24)
        
        # Query traffic sensor data
        try:
            response = table.scan(
                FilterExpression=Attr('sensor_type').eq('traffic') & 
                               Attr('timestamp').between(
                                   start_time.isoformat(), 
                                   end_time.isoformat()
                               ),
                ProjectionExpression='sensor_id, sensor_type, #data, #loc, #ts',
                ExpressionAttributeNames={
                    '#data': 'data',
                    '#loc': 'location', 
                    '#ts': 'timestamp'
                }
            )
            
            traffic_data = response['Items']
            
        except Exception as e:
            logger.warning(f"No traffic data found or query failed: {str(e)}")
            traffic_data = []
        
        # Process traffic metrics
        if traffic_data:
            total_vehicles = sum(
                item.get('data', {}).get('vehicle_count', 0) 
                for item in traffic_data
            )
            
            speeds = [
                item.get('data', {}).get('average_speed', 0) 
                for item in traffic_data 
                if item.get('data', {}).get('average_speed', 0) > 0
            ]
            average_speed = sum(speeds) / len(speeds) if speeds else 0
            
            congestion_score = calculate_congestion_score(traffic_data)
            
            # Geographic distribution
            locations = {}
            for item in traffic_data:
                location = item.get('location', {})
                if location:
                    area = location.get('area', 'unknown')
                    locations[area] = locations.get(area, 0) + 1
            
        else:
            # Default values when no data is available
            total_vehicles = 0
            average_speed = 0
            congestion_score = 0
            locations = {}
        
        summary = {
            'time_range': time_range,
            'start_time': start_time.isoformat(),
            'end_time': end_time.isoformat(),
            'metrics': {
                'total_vehicles': total_vehicles,
                'average_speed': round(float(average_speed), 2),
                'congestion_score': round(congestion_score, 2),
                'unique_sensors': len(set(item['sensor_id'] for item in traffic_data)),
                'data_points': len(traffic_data)
            },
            'geographic_distribution': locations,
            'recommendations': generate_traffic_recommendations(congestion_score, average_speed),
            'generated_at': datetime.utcnow().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(summary, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate traffic summary: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def calculate_congestion_score(traffic_data):
    """Calculate traffic congestion score (0-100)"""
    if not traffic_data:
        return 0
    
    total_score = 0
    valid_readings = 0
    
    for item in traffic_data:
        data = item.get('data', {})
        speed = data.get('average_speed', 50)  # Default speed
        volume = data.get('vehicle_count', 0)
        
        if speed > 0:  # Only process valid speed readings
            # Higher volume and lower speed = higher congestion
            # Score ranges from 0 (free flow) to 100 (heavy congestion)
            volume_factor = min(volume / 20, 1.0)  # Normalize volume (20+ vehicles = max)
            speed_factor = max(0, (60 - speed) / 60)  # Slower = higher score
            
            score = (volume_factor * 0.6 + speed_factor * 0.4) * 100
            total_score += score
            valid_readings += 1
    
    return total_score / valid_readings if valid_readings > 0 else 0

def generate_traffic_recommendations(congestion_score, average_speed):
    """Generate traffic management recommendations"""
    recommendations = []
    
    if congestion_score > 70:
        recommendations.extend([
            "Implement dynamic traffic light timing optimization",
            "Consider congestion pricing during peak hours",
            "Deploy additional traffic management personnel"
        ])
    elif congestion_score > 40:
        recommendations.extend([
            "Monitor traffic patterns for optimization opportunities",
            "Consider alternative route suggestions via mobile apps"
        ])
    else:
        recommendations.append("Traffic flow is optimal - maintain current management strategies")
    
    if average_speed < 25:
        recommendations.append("Investigate speed bottlenecks and infrastructure improvements")
    elif average_speed > 65:
        recommendations.append("Review speed limits and safety measures")
    
    return recommendations

def generate_sensor_health_report():
    """Generate sensor connectivity and health report"""
    try:
        # Query recent sensor data (last hour)
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        try:
            response = table.scan(
                FilterExpression=Attr('timestamp').between(
                    start_time.isoformat(),
                    end_time.isoformat()
                ),
                ProjectionExpression='sensor_id, sensor_type, #ts',
                ExpressionAttributeNames={'#ts': 'timestamp'}
            )
            
            recent_data = response['Items']
            
        except Exception as e:
            logger.warning(f"Query failed for sensor health: {str(e)}")
            recent_data = []
        
        # Analyze sensor activity
        sensors = {}
        for item in recent_data:
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
            # Keep the latest timestamp
            if item['timestamp'] > sensors[sensor_id]['last_seen']:
                sensors[sensor_id]['last_seen'] = item['timestamp']
        
        # Determine sensor health status
        for sensor in sensors.values():
            if sensor['message_count'] < 3:  # Less than 3 messages per hour
                sensor['status'] = 'warning'
            if sensor['message_count'] == 0:
                sensor['status'] = 'offline'
        
        # Calculate summary statistics
        total_sensors = len(sensors)
        active_sensors = sum(1 for s in sensors.values() if s['status'] == 'active')
        warning_sensors = sum(1 for s in sensors.values() if s['status'] == 'warning')
        offline_sensors = sum(1 for s in sensors.values() if s['status'] == 'offline')
        
        health_report = {
            'summary': {
                'total_sensors': total_sensors,
                'active_sensors': active_sensors,
                'warning_sensors': warning_sensors,
                'offline_sensors': offline_sensors,
                'health_percentage': round((active_sensors / total_sensors * 100), 2) if total_sensors > 0 else 0
            },
            'sensor_details': list(sensors.values()),
            'recommendations': generate_sensor_recommendations(warning_sensors, offline_sensors),
            'time_window': f"{start_time.isoformat()} to {end_time.isoformat()}",
            'generated_at': datetime.utcnow().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate sensor health report: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def generate_sensor_recommendations(warning_count, offline_count):
    """Generate sensor maintenance recommendations"""
    recommendations = []
    
    if offline_count > 0:
        recommendations.append(f"Investigate {offline_count} offline sensors immediately")
        recommendations.append("Check network connectivity and power supply for offline sensors")
    
    if warning_count > 0:
        recommendations.append(f"Monitor {warning_count} sensors with low activity")
        recommendations.append("Schedule maintenance for sensors with irregular reporting")
    
    if offline_count == 0 and warning_count == 0:
        recommendations.append("All sensors operating normally - continue regular monitoring")
    
    return recommendations

def generate_city_metrics(time_range):
    """Generate overall city performance metrics"""
    try:
        # This would typically aggregate data across all sensor types
        # For demo purposes, we'll create representative metrics
        
        metrics = {
            'infrastructure': {
                'traffic_efficiency': 72.5,
                'utility_performance': 89.2,
                'emergency_response_readiness': 94.1
            },
            'sustainability': {
                'estimated_carbon_footprint': '1,247 tons CO2/day',
                'energy_efficiency_score': 78.3,
                'waste_management_efficiency': 85.7
            },
            'citizen_services': {
                'public_transport_punctuality': 91.2,
                'service_request_response_time': '2.4 hours average',
                'citizen_satisfaction_estimate': 76.8
            },
            'simulation_insights': {
                'optimization_potential': '15-23% improvement possible',
                'priority_areas': [
                    'Traffic light synchronization',
                    'Emergency vehicle routing',
                    'Peak hour capacity management'
                ],
                'predicted_outcomes': {
                    'traffic_improvement': '15% reduction in congestion',
                    'response_time_improvement': '12% faster emergency response',
                    'cost_savings': '$2.3M annually in operational efficiency'
                }
            },
            'time_range': time_range,
            'generated_at': datetime.utcnow().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(metrics, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate city metrics: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def generate_simulation_insights():
    """Generate insights and recommendations from simulation data"""
    try:
        # In production, this would analyze actual simulation results
        # For demo, we provide representative insights
        
        insights = {
            'traffic_optimization': {
                'current_efficiency': '68%',
                'potential_improvement': '15%',
                'recommended_actions': [
                    'Optimize traffic light timing at Main St and Oak Ave intersection',
                    'Implement dynamic routing for Highway 101 corridor during peak hours',
                    'Add smart traffic sensors at three identified bottleneck locations',
                    'Introduce adaptive traffic management system for downtown area'
                ],
                'estimated_impact': {
                    'travel_time_reduction': '8-12 minutes average',
                    'fuel_savings': '$1.2M annually across city',
                    'emission_reduction': '145 tons CO2 annually'
                }
            },
            'emergency_response': {
                'current_response_time': '4.2 minutes average',
                'target_response_time': '3.5 minutes',
                'optimization_opportunities': [
                    'Relocate Station 7 to reduce coverage gap in Northwest district',
                    'Implement priority traffic signal preemption on emergency routes',
                    'Deploy predictive positioning based on historical incident patterns',
                    'Optimize ambulance-to-hospital routing using real-time traffic data'
                ],
                'estimated_improvement': '18% faster response times'
            },
            'infrastructure_utilization': {
                'current_capacity': '68%',
                'peak_utilization_hours': ['7:30-9:00 AM', '4:30-6:30 PM'],
                'underutilized_resources': [
                    'Public transit during off-peak hours',
                    'Parking structures in financial district evenings',
                    'Alternative route capacity during rush hours'
                ],
                'recommendations': [
                    'Implement dynamic congestion pricing during peak hours',
                    'Promote flexible work arrangements to distribute traffic',
                    'Enhance public transit frequency and routes',
                    'Deploy real-time parking availability system'
                ]
            },
            'digital_twin_performance': {
                'model_accuracy': '94.2%',
                'prediction_confidence': '89.7%',
                'data_freshness': '< 30 seconds average',
                'areas_for_improvement': [
                    'Increase sensor density in residential areas',
                    'Enhance weather data integration for predictive accuracy',
                    'Expand pedestrian and cyclist tracking capabilities'
                ]
            },
            'cost_benefit_analysis': {
                'total_implementation_cost': '$4.2M',
                'annual_operational_savings': '$2.8M',
                'roi_timeline': '18 months',
                'intangible_benefits': [
                    'Improved citizen satisfaction',
                    'Enhanced emergency preparedness',
                    'Better urban planning decision-making',
                    'Reduced environmental impact'
                ]
            },
            'generated_at': datetime.utcnow().isoformat(),
            'note': 'Insights based on simulation models - SimSpace Weaver service discontinued'
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(insights, default=str)
        }
        
    except Exception as e:
        logger.error(f"Failed to generate simulation insights: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

# Utility function to handle Decimal serialization
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)
      `),
      environment: {
        'TABLE_NAME': this.sensorDataTable.tableName,
        'SIMULATION_BUCKET': this.simulationBucket.bucketName,
      },
      role: lambdaExecutionRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 1024,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });
    
    // =========================================================================
    // IoT Core Resources
    // =========================================================================
    
    // IoT Thing Group for sensor management
    const iotThingGroup = new iot.CfnThingGroup(this, 'IoTSensorThingGroup', {
      thingGroupName: `${resourcePrefix}-sensors`,
      thingGroupProperties: {
        thingGroupDescription: 'Smart city sensor fleet for digital twin integration',
        attributePayload: {
          attributes: {
            'project': 'SmartCityDigitalTwin',
            'environment': environment,
            'managed_by': 'CDK'
          }
        }
      }
    });
    
    // IoT Policy for sensor devices
    const iotPolicy = new iot.CfnPolicy(this, 'IoTSensorPolicy', {
      policyName: `${resourcePrefix}-sensor-policy`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: ['iot:Connect'],
            Resource: `arn:aws:iot:${this.region}:${this.account}:client/\${aws:username}`,
          },
          {
            Effect: 'Allow',
            Action: ['iot:Publish'],
            Resource: `arn:aws:iot:${this.region}:${this.account}:topic/smartcity/sensors/*`,
          },
          {
            Effect: 'Allow',
            Action: ['iot:Subscribe', 'iot:Receive'],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:topicfilter/smartcity/sensors/\${aws:username}/*`,
              `arn:aws:iot:${this.region}:${this.account}:topic/smartcity/sensors/\${aws:username}/*`,
            ],
          },
        ],
      },
    });
    
    // IoT Rule for routing sensor data to Lambda
    const iotTopicRule = new iot.CfnTopicRule(this, 'IoTSensorDataRule', {
      ruleName: `${resourcePrefix.replace(/-/g, '_')}_sensor_processing`,
      topicRulePayload: {
        sql: "SELECT * FROM 'smartcity/sensors/+/data'",
        description: 'Route smart city sensor data to processing Lambda function',
        actions: [
          {
            lambda: {
              functionArn: this.dataProcessorFunction.functionArn,
            },
          },
        ],
        errorAction: {
          cloudwatchLogs: {
            logGroupName: '/aws/iot/rules/errors',
            roleArn: lambdaExecutionRole.roleArn,
          },
        },
        ruleDisabled: false,
      },
    });
    
    // Grant IoT permission to invoke the data processor Lambda
    this.dataProcessorFunction.addPermission('IoTInvokePermission', {
      principal: new iam.ServicePrincipal('iot.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: iotTopicRule.attrArn,
    });
    
    // Sample IoT Thing for testing
    const sampleIoTThing = new iot.CfnThing(this, 'SampleTrafficSensor', {
      thingName: `${resourcePrefix}-traffic-sensor-001`,
      attributePayload: {
        attributes: {
          'sensor_type': 'traffic',
          'location': 'Main St & Oak Ave',
          'installation_date': new Date().toISOString().split('T')[0],
        }
      }
    });
    
    // =========================================================================
    // CloudWatch Dashboard for Monitoring
    // =========================================================================
    
    const dashboard = new logs.LogGroup(this, 'SmartCityDashboard', {
      logGroupName: `/aws/smartcity/${resourcePrefix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    
    // =========================================================================
    // Stack Outputs
    // =========================================================================
    
    new cdk.CfnOutput(this, 'SensorDataTableName', {
      value: this.sensorDataTable.tableName,
      description: 'DynamoDB table for storing sensor data',
      exportName: `${this.stackName}-SensorDataTable`,
    });
    
    new cdk.CfnOutput(this, 'SimulationBucketName', {
      value: this.simulationBucket.bucketName,
      description: 'S3 bucket for simulation assets and configurations',
      exportName: `${this.stackName}-SimulationBucket`,
    });
    
    new cdk.CfnOutput(this, 'DataProcessorFunctionName', {
      value: this.dataProcessorFunction.functionName,
      description: 'Lambda function for processing IoT sensor data',
      exportName: `${this.stackName}-DataProcessorFunction`,
    });
    
    new cdk.CfnOutput(this, 'AnalyticsFunctionName', {
      value: this.analyticsFunction.functionName,
      description: 'Lambda function for analytics and insights generation',
      exportName: `${this.stackName}-AnalyticsFunction`,
    });
    
    new cdk.CfnOutput(this, 'IoTThingGroupName', {
      value: iotThingGroup.thingGroupName!,
      description: 'IoT Thing Group for managing smart city sensors',
      exportName: `${this.stackName}-IoTThingGroup`,
    });
    
    new cdk.CfnOutput(this, 'IoTEndpoint', {
      value: `https://${cdk.Fn.ref('AWS::AccountId')}.iot.${this.region}.amazonaws.com`,
      description: 'IoT Core endpoint for device connectivity',
      exportName: `${this.stackName}-IoTEndpoint`,
    });
    
    new cdk.CfnOutput(this, 'ProjectResourcePrefix', {
      value: resourcePrefix,
      description: 'Resource naming prefix used across the stack',
      exportName: `${this.stackName}-ResourcePrefix`,
    });
  }
}

// =========================================================================
// CDK App Definition
// =========================================================================

const app = new cdk.App();

// Get deployment context
const environment = app.node.tryGetContext('environment') || 'dev';
const projectName = app.node.tryGetContext('projectName') || 'smartcity';

// Deploy the Smart City Digital Twin Stack
const smartCityStack = new SmartCityDigitalTwinStack(app, 'SmartCityDigitalTwinStack', {
  stackName: `smart-city-digital-twin-${environment}`,
  description: 'Smart City Digital Twin infrastructure with IoT integration and simulation capabilities',
  projectName: projectName,
  environment: environment,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SmartCityDigitalTwin',
    Environment: environment,
    ManagedBy: 'CDK',
    CostCenter: 'UrbanPlanning',
  }
});

// Add additional stack-level tags
cdk.Tags.of(smartCityStack).add('Application', 'SmartCityDigitalTwin');
cdk.Tags.of(smartCityStack).add('Owner', 'UrbanPlanningTeam');
cdk.Tags.of(smartCityStack).add('Version', '1.0');