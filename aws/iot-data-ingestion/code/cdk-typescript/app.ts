#!/usr/bin/env node

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Duration } from 'aws-cdk-lib';

/**
 * Props for the IoT Data Ingestion Stack
 */
interface IoTDataIngestionStackProps extends cdk.StackProps {
  /** Prefix for resource names to ensure uniqueness */
  readonly resourcePrefix?: string;
  /** DynamoDB billing mode */
  readonly dynamoDbBillingMode?: dynamodb.BillingMode;
  /** Lambda function timeout */
  readonly lambdaTimeout?: Duration;
  /** CloudWatch log retention period */
  readonly logRetention?: logs.RetentionDays;
}

/**
 * AWS CDK Stack for IoT Data Ingestion Pipeline
 * 
 * This stack creates a complete IoT data ingestion pipeline including:
 * - IoT Thing with certificates and policies
 * - DynamoDB table for sensor data storage
 * - Lambda function for data processing
 * - SNS topic for alerts
 * - IoT Rules Engine for message routing
 * - CloudWatch monitoring and logging
 */
export class IoTDataIngestionStack extends cdk.Stack {
  /** DynamoDB table for storing sensor data */
  public readonly sensorDataTable: dynamodb.Table;
  
  /** Lambda function for processing IoT messages */
  public readonly iotProcessorFunction: lambda.Function;
  
  /** SNS topic for sending alerts */
  public readonly alertsTopic: sns.Topic;
  
  /** IoT Thing for device registration */
  public readonly iotThing: iot.CfnThing;
  
  /** IoT policy for device permissions */
  public readonly iotPolicy: iot.CfnPolicy;
  
  /** IoT rule for message routing */
  public readonly iotRule: iot.CfnTopicRule;

  constructor(scope: Construct, id: string, props: IoTDataIngestionStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const resourcePrefix = props.resourcePrefix || 'iot-pipeline';
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create DynamoDB table for sensor data
    this.sensorDataTable = this.createSensorDataTable(resourcePrefix, uniqueSuffix, props);

    // Create SNS topic for alerts
    this.alertsTopic = this.createAlertsTopic(resourcePrefix, uniqueSuffix);

    // Create Lambda function for data processing
    this.iotProcessorFunction = this.createIoTProcessorFunction(
      resourcePrefix,
      uniqueSuffix,
      this.sensorDataTable,
      this.alertsTopic,
      props
    );

    // Create IoT Thing for device registration
    this.iotThing = this.createIoTThing(resourcePrefix, uniqueSuffix);

    // Create IoT policy for device permissions
    this.iotPolicy = this.createIoTPolicy(resourcePrefix, uniqueSuffix);

    // Create IoT rule for message routing
    this.iotRule = this.createIoTRule(resourcePrefix, uniqueSuffix, this.iotProcessorFunction);

    // Create CloudWatch dashboard for monitoring
    this.createCloudWatchDashboard(resourcePrefix, uniqueSuffix);

    // Output important resource information
    this.createStackOutputs(resourcePrefix, uniqueSuffix);
  }

  /**
   * Creates DynamoDB table for storing sensor data
   */
  private createSensorDataTable(
    resourcePrefix: string,
    uniqueSuffix: string,
    props: IoTDataIngestionStackProps
  ): dynamodb.Table {
    const table = new dynamodb.Table(this, 'SensorDataTable', {
      tableName: `${resourcePrefix}-sensor-data-${uniqueSuffix}`,
      partitionKey: {
        name: 'deviceId',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: props.dynamoDbBillingMode || dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      tableClass: dynamodb.TableClass.STANDARD
    });

    // Add tags for cost allocation and resource management
    cdk.Tags.of(table).add('Component', 'DataStorage');
    cdk.Tags.of(table).add('Purpose', 'IoTSensorData');

    return table;
  }

  /**
   * Creates SNS topic for sending alerts
   */
  private createAlertsTopic(resourcePrefix: string, uniqueSuffix: string): sns.Topic {
    const topic = new sns.Topic(this, 'AlertsTopic', {
      topicName: `${resourcePrefix}-alerts-${uniqueSuffix}`,
      displayName: 'IoT Sensor Alerts',
      fifo: false
    });

    // Add tags
    cdk.Tags.of(topic).add('Component', 'Notifications');
    cdk.Tags.of(topic).add('Purpose', 'IoTAlerts');

    return topic;
  }

  /**
   * Creates Lambda function for processing IoT messages
   */
  private createIoTProcessorFunction(
    resourcePrefix: string,
    uniqueSuffix: string,
    sensorTable: dynamodb.Table,
    alertsTopic: sns.Topic,
    props: IoTDataIngestionStackProps
  ): lambda.Function {
    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'IoTProcessorRole', {
      roleName: `${resourcePrefix}-processor-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Grant permissions to access DynamoDB table
    sensorTable.grantWriteData(lambdaRole);

    // Grant permissions to publish to SNS topic
    alertsTopic.grantPublish(lambdaRole);

    // Grant permissions to put CloudWatch metrics
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['cloudwatch:PutMetricData'],
      resources: ['*'],
      conditions: {
        StringEquals: {
          'cloudwatch:namespace': 'IoT/Sensors'
        }
      }
    }));

    // Create Lambda function
    const iotProcessorFunction = new lambda.Function(this, 'IoTProcessorFunction', {
      functionName: `${resourcePrefix}-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      timeout: props.lambdaTimeout || Duration.minutes(1),
      memorySize: 256,
      environment: {
        DYNAMODB_TABLE: sensorTable.tableName,
        SNS_TOPIC_ARN: alertsTopic.topicArn,
        TEMPERATURE_THRESHOLD: '30'
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse IoT message
        device_id = event.get('deviceId')
        timestamp = event.get('timestamp', int(datetime.now().timestamp()))
        temperature = event.get('temperature')
        humidity = event.get('humidity')
        
        logger.info(f"Processing data from device: {device_id}")
        
        # Validate required fields
        if not all([device_id, temperature is not None, humidity is not None]):
            raise ValueError("Missing required fields: deviceId, temperature, or humidity")
        
        # Store data in DynamoDB
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
        table.put_item(
            Item={
                'deviceId': device_id,
                'timestamp': timestamp,
                'temperature': float(temperature),
                'humidity': float(humidity),
                'processed_at': int(datetime.now().timestamp()),
                'location': event.get('location', 'unknown')
            }
        )
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='IoT/Sensors',
            MetricData=[
                {
                    'MetricName': 'Temperature',
                    'Dimensions': [
                        {'Name': 'DeviceId', 'Value': device_id}
                    ],
                    'Value': float(temperature),
                    'Unit': 'None'
                },
                {
                    'MetricName': 'Humidity',
                    'Dimensions': [
                        {'Name': 'DeviceId', 'Value': device_id}
                    ],
                    'Value': float(humidity),
                    'Unit': 'Percent'
                }
            ]
        )
        
        # Check for alerts (temperature > threshold)
        threshold = float(os.environ.get('TEMPERATURE_THRESHOLD', '30'))
        if float(temperature) > threshold:
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'High Temperature Alert - Device {device_id}',
                Message=f'Temperature reading of {temperature}°C exceeds threshold of {threshold}°C\\nDevice: {device_id}\\nTimestamp: {timestamp}\\nLocation: {event.get("location", "unknown")}'
            )
            logger.warning(f"High temperature alert sent for device {device_id}: {temperature}°C")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data processed successfully',
                'deviceId': device_id,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing IoT data: {str(e)}")
        # Send error metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='IoT/Sensors',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        raise
      `),
      logRetention: props.logRetention || logs.RetentionDays.ONE_WEEK
    });

    // Add tags
    cdk.Tags.of(iotProcessorFunction).add('Component', 'DataProcessing');
    cdk.Tags.of(iotProcessorFunction).add('Purpose', 'IoTMessageProcessor');

    return iotProcessorFunction;
  }

  /**
   * Creates IoT Thing for device registration
   */
  private createIoTThing(resourcePrefix: string, uniqueSuffix: string): iot.CfnThing {
    const iotThing = new iot.CfnThing(this, 'IoTThing', {
      thingName: `${resourcePrefix}-sensor-${uniqueSuffix}`,
      thingTypeName: 'SensorDevice',
      attributePayload: {
        attributes: {
          manufacturer: 'Generic',
          model: 'TempHumidSensor',
          version: '1.0'
        }
      }
    });

    // Add tags
    cdk.Tags.of(iotThing).add('Component', 'DeviceManagement');
    cdk.Tags.of(iotThing).add('Purpose', 'IoTDevice');

    return iotThing;
  }

  /**
   * Creates IoT policy for device permissions
   */
  private createIoTPolicy(resourcePrefix: string, uniqueSuffix: string): iot.CfnPolicy {
    const iotPolicy = new iot.CfnPolicy(this, 'IoTPolicy', {
      policyName: `${resourcePrefix}-sensor-policy-${uniqueSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: ['iot:Connect'],
            Resource: `arn:aws:iot:${this.region}:${this.account}:client/\${iot:Connection.Thing.ThingName}`
          },
          {
            Effect: 'Allow',
            Action: [
              'iot:Publish',
              'iot:Subscribe',
              'iot:Receive'
            ],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:topic/topic/sensor/*`,
              `arn:aws:iot:${this.region}:${this.account}:topicfilter/topic/sensor/*`
            ]
          },
          {
            Effect: 'Allow',
            Action: [
              'iot:GetThingShadow',
              'iot:UpdateThingShadow',
              'iot:DeleteThingShadow'
            ],
            Resource: `arn:aws:iot:${this.region}:${this.account}:thing/\${iot:Connection.Thing.ThingName}`
          }
        ]
      }
    });

    return iotPolicy;
  }

  /**
   * Creates IoT rule for message routing
   */
  private createIoTRule(
    resourcePrefix: string,
    uniqueSuffix: string,
    lambdaFunction: lambda.Function
  ): iot.CfnTopicRule {
    // Grant IoT permission to invoke Lambda function
    lambdaFunction.addPermission('IoTInvokePermission', {
      principal: new iam.ServicePrincipal('iot.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: `arn:aws:iot:${this.region}:${this.account}:rule/${resourcePrefix}-process-sensor-data-${uniqueSuffix}`
    });

    const iotRule = new iot.CfnTopicRule(this, 'IoTRule', {
      ruleName: `${resourcePrefix}_process_sensor_data_${uniqueSuffix}`.replace(/-/g, '_'),
      topicRulePayload: {
        sql: "SELECT * FROM 'topic/sensor/data'",
        description: 'Route sensor data to Lambda for processing and storage',
        ruleDisabled: false,
        actions: [
          {
            lambda: {
              functionArn: lambdaFunction.functionArn
            }
          }
        ],
        errorAction: {
          cloudwatchLogs: {
            logGroupName: `/aws/iot/rules/${resourcePrefix}-errors-${uniqueSuffix}`,
            roleArn: this.createIoTRuleErrorRole(resourcePrefix, uniqueSuffix).roleArn
          }
        }
      }
    });

    return iotRule;
  }

  /**
   * Creates IAM role for IoT rule error logging
   */
  private createIoTRuleErrorRole(resourcePrefix: string, uniqueSuffix: string): iam.Role {
    const role = new iam.Role(this, 'IoTRuleErrorRole', {
      roleName: `${resourcePrefix}-rule-error-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      inlinePolicies: {
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: [
                `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/iot/rules/${resourcePrefix}-errors-${uniqueSuffix}:*`
              ]
            })
          ]
        })
      }
    });

    return role;
  }

  /**
   * Creates CloudWatch dashboard for monitoring
   */
  private createCloudWatchDashboard(resourcePrefix: string, uniqueSuffix: string): void {
    new cloudwatch.Dashboard(this, 'IoTDashboard', {
      dashboardName: `${resourcePrefix}-iot-monitoring-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              this.iotProcessorFunction.metricInvocations(),
              this.iotProcessorFunction.metricErrors(),
              this.iotProcessorFunction.metricDuration()
            ]
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'DynamoDB Metrics',
            left: [
              this.sensorDataTable.metricConsumedReadCapacityUnits(),
              this.sensorDataTable.metricConsumedWriteCapacityUnits()
            ]
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'IoT Sensor Data',
            left: [
              new cloudwatch.Metric({
                namespace: 'IoT/Sensors',
                metricName: 'Temperature',
                statistic: 'Average'
              }),
              new cloudwatch.Metric({
                namespace: 'IoT/Sensors',
                metricName: 'Humidity',
                statistic: 'Average'
              })
            ]
          })
        ]
      ]
    });
  }

  /**
   * Creates stack outputs for important resource information
   */
  private createStackOutputs(resourcePrefix: string, uniqueSuffix: string): void {
    new cdk.CfnOutput(this, 'IoTEndpoint', {
      description: 'AWS IoT Core endpoint for device connections',
      value: `${this.account}.iot.${this.region}.amazonaws.com`,
      exportName: `${resourcePrefix}-iot-endpoint-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      description: 'DynamoDB table name for sensor data',
      value: this.sensorDataTable.tableName,
      exportName: `${resourcePrefix}-dynamodb-table-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      description: 'Lambda function name for IoT data processing',
      value: this.iotProcessorFunction.functionName,
      exportName: `${resourcePrefix}-lambda-function-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      description: 'SNS topic ARN for alerts',
      value: this.alertsTopic.topicArn,
      exportName: `${resourcePrefix}-sns-topic-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'IoTThingName', {
      description: 'IoT Thing name for device registration',
      value: this.iotThing.thingName!,
      exportName: `${resourcePrefix}-iot-thing-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'IoTPolicyName', {
      description: 'IoT Policy name for device permissions',
      value: this.iotPolicy.policyName!,
      exportName: `${resourcePrefix}-iot-policy-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'TestPublishCommand', {
      description: 'Sample command to publish test data',
      value: `aws iot-data publish --topic "topic/sensor/data" --payload '{"deviceId":"${this.iotThing.thingName}","timestamp":${Math.floor(Date.now() / 1000)},"temperature":25.5,"humidity":60.2,"location":"test-room"}'`
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Deploy the IoT Data Ingestion Stack
new IoTDataIngestionStack(app, 'IoTDataIngestionStack', {
  resourcePrefix: 'iot-pipeline',
  description: 'AWS CDK Stack for IoT Data Ingestion Pipeline with AWS IoT Core, Lambda, DynamoDB, and SNS',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  tags: {
    Project: 'IoTDataIngestion',
    Environment: 'Development',
    Owner: 'DevOps Team',
    CostCenter: 'IoT-Development'
  }
});

// Synthesize the app
app.synth();