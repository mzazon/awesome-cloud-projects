#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import { Construct } from 'constructs';

/**
 * Stack for comprehensive IoT Device Fleet Monitoring with CloudWatch and Device Defender
 * 
 * This stack implements a complete IoT fleet monitoring solution that provides:
 * - Real-time security monitoring with AWS IoT Device Defender
 * - Custom CloudWatch metrics and dashboards
 * - Automated remediation through Lambda functions
 * - SNS notifications for security events
 * - Comprehensive audit logging and compliance monitoring
 */
export class IoTDeviceFleetMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const fleetName = `iot-fleet-${randomSuffix}`;
    const securityProfileName = `fleet-security-profile-${randomSuffix}`;
    const dashboardName = `IoT-Fleet-Dashboard-${randomSuffix}`;
    const snsTopicName = `iot-fleet-alerts-${randomSuffix}`;
    const lambdaFunctionName = `iot-fleet-remediation-${randomSuffix}`;

    // Parameters for customization
    const emailEndpoint = new cdk.CfnParameter(this, 'EmailEndpoint', {
      type: 'String',
      description: 'Email address for security alerts',
      default: 'admin@example.com'
    });

    const deviceCount = new cdk.CfnParameter(this, 'DeviceCount', {
      type: 'Number',
      description: 'Number of test devices to create',
      default: 5,
      minValue: 1,
      maxValue: 20
    });

    const securityViolationThreshold = new cdk.CfnParameter(this, 'SecurityViolationThreshold', {
      type: 'Number',
      description: 'Threshold for security violation alarms',
      default: 5,
      minValue: 1,
      maxValue: 50
    });

    // ==================== IAM ROLES ====================

    // IAM Role for IoT Device Defender
    const deviceDefenderRole = new iam.Role(this, 'IoTDeviceDefenderRole', {
      roleName: `IoTDeviceDefenderRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      description: 'Role for IoT Device Defender to perform audit and monitoring tasks',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSIoTDeviceDefenderAudit')
      ]
    });

    // IAM Role for Lambda remediation function
    const lambdaRemediationRole = new iam.Role(this, 'IoTFleetRemediationRole', {
      roleName: `IoTFleetRemediationRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for Lambda function to handle IoT fleet security remediation',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Custom policy for Lambda remediation actions
    const lambdaRemediationPolicy = new iam.Policy(this, 'IoTFleetRemediationPolicy', {
      policyName: `IoTFleetRemediationPolicy-${randomSuffix}`,
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'iot:UpdateCertificate',
            'iot:DetachThingPrincipal',
            'iot:ListThingPrincipals',
            'iot:DescribeThing',
            'iot:UpdateThingAttribute',
            'iot:ListThingGroupsForThing',
            'cloudwatch:PutMetricData',
            'logs:CreateLogGroup',
            'logs:CreateLogStream',
            'logs:PutLogEvents'
          ],
          resources: ['*']
        })
      ]
    });

    lambdaRemediationRole.attachInlinePolicy(lambdaRemediationPolicy);

    // ==================== STORAGE RESOURCES ====================

    // S3 Bucket for IoT data storage and archival
    const iotDataBucket = new s3.Bucket(this, 'IoTDataBucket', {
      bucketName: `iot-fleet-data-${randomSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      lifecycleRules: [
        {
          id: 'IoTDataArchival',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ]
        }
      ]
    });

    // DynamoDB Table for device metadata and security events
    const deviceMetadataTable = new dynamodb.Table(this, 'DeviceMetadataTable', {
      tableName: `iot-device-metadata-${randomSuffix}`,
      partitionKey: { name: 'deviceId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'timestamp', type: dynamodb.AttributeType.NUMBER },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true
    });

    // Add GSI for querying by device type
    deviceMetadataTable.addGlobalSecondaryIndex({
      indexName: 'DeviceTypeIndex',
      partitionKey: { name: 'deviceType', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'timestamp', type: dynamodb.AttributeType.NUMBER }
    });

    // ==================== MESSAGING RESOURCES ====================

    // SNS Topic for security alerts
    const alertTopic = new sns.Topic(this, 'IoTFleetAlertsTopic', {
      topicName: snsTopicName,
      displayName: 'IoT Fleet Security Alerts',
      description: 'SNS topic for IoT fleet security notifications and alerts'
    });

    // Add email subscription to SNS topic
    alertTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(emailEndpoint.valueAsString)
    );

    // SQS Queue for message processing
    const messageQueue = new sqs.Queue(this, 'IoTMessageQueue', {
      queueName: `iot-fleet-messages-${randomSuffix}`,
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      deadLetterQueue: {
        queue: new sqs.Queue(this, 'IoTMessageDLQ', {
          queueName: `iot-fleet-messages-dlq-${randomSuffix}`,
          encryption: sqs.QueueEncryption.SQS_MANAGED
        }),
        maxReceiveCount: 3
      },
      visibilityTimeout: cdk.Duration.seconds(300)
    });

    // ==================== LAMBDA FUNCTIONS ====================

    // Lambda function for automated remediation
    const remediationFunction = new lambda.Function(this, 'IoTFleetRemediationFunction', {
      functionName: lambdaFunctionName,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRemediationRole,
      timeout: cdk.Duration.seconds(300),
      memorySize: 512,
      description: 'Automated remediation function for IoT fleet security violations',
      environment: {
        DEVICE_METADATA_TABLE: deviceMetadataTable.tableName,
        IOT_DATA_BUCKET: iotDataBucket.bucketName,
        MESSAGE_QUEUE_URL: messageQueue.queueUrl,
        FLEET_NAME: fleetName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
iot_client = boto3.client('iot')
cloudwatch = boto3.client('cloudwatch')
dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

# Environment variables
DEVICE_METADATA_TABLE = os.environ.get('DEVICE_METADATA_TABLE')
IOT_DATA_BUCKET = os.environ.get('IOT_DATA_BUCKET')
MESSAGE_QUEUE_URL = os.environ.get('MESSAGE_QUEUE_URL')
FLEET_NAME = os.environ.get('FLEET_NAME')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing IoT security violations and remediation
    
    Args:
        event: Lambda event containing SNS message or direct invocation
        context: Lambda context object
        
    Returns:
        Dict containing status code and response body
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Handle SNS events
        if 'Records' in event:
            for record in event['Records']:
                if record.get('EventSource') == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    process_security_violation(message)
                elif record.get('eventSource') == 'aws:sqs':
                    message = json.loads(record['body'])
                    process_device_event(message)
        
        # Handle direct invocation
        elif 'violationEventType' in event:
            process_security_violation(event)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed security violation')
        }
    
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_security_violation(message: Dict[str, Any]) -> None:
    """
    Process Device Defender security violation events
    
    Args:
        message: Security violation message from Device Defender
    """
    violation_type = message.get('violationEventType', 'unknown')
    thing_name = message.get('thingName', 'unknown')
    behavior_name = message.get('behavior', {}).get('name', 'unknown')
    violation_id = message.get('violationId', 'unknown')
    
    logger.info(f"Processing violation: {violation_type} for {thing_name}, behavior: {behavior_name}")
    
    # Store violation in DynamoDB
    store_violation_event(thing_name, violation_type, behavior_name, violation_id, message)
    
    # Send custom metric to CloudWatch
    send_security_metric(violation_type, behavior_name, thing_name)
    
    # Implement remediation logic based on violation type
    if violation_type == 'in-alarm':
        handle_security_alarm(thing_name, behavior_name, message)
    elif violation_type == 'alarm-cleared':
        handle_alarm_cleared(thing_name, behavior_name)

def store_violation_event(thing_name: str, violation_type: str, behavior_name: str, 
                         violation_id: str, message: Dict[str, Any]) -> None:
    """
    Store security violation event in DynamoDB
    
    Args:
        thing_name: Name of the IoT thing
        violation_type: Type of violation
        behavior_name: Name of the behavior that triggered the violation
        violation_id: Unique violation identifier
        message: Complete violation message
    """
    try:
        table = dynamodb.Table(DEVICE_METADATA_TABLE)
        
        item = {
            'deviceId': thing_name,
            'timestamp': int(datetime.now().timestamp()),
            'eventType': 'security_violation',
            'violationType': violation_type,
            'behaviorName': behavior_name,
            'violationId': violation_id,
            'message': json.dumps(message),
            'deviceType': 'iot_device'
        }
        
        table.put_item(Item=item)
        logger.info(f"Stored violation event for {thing_name}")
        
    except Exception as e:
        logger.error(f"Failed to store violation event: {str(e)}")

def send_security_metric(violation_type: str, behavior_name: str, thing_name: str) -> None:
    """
    Send custom security metrics to CloudWatch
    
    Args:
        violation_type: Type of violation
        behavior_name: Name of the behavior
        thing_name: Name of the IoT thing
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='AWS/IoT/FleetMonitoring',
            MetricData=[
                {
                    'MetricName': 'SecurityViolations',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'ViolationType',
                            'Value': violation_type
                        },
                        {
                            'Name': 'BehaviorName',
                            'Value': behavior_name
                        },
                        {
                            'Name': 'FleetName',
                            'Value': FLEET_NAME
                        }
                    ]
                }
            ]
        )
        logger.info(f"Sent security metric for {thing_name}")
        
    except Exception as e:
        logger.error(f"Failed to send security metric: {str(e)}")

def handle_security_alarm(thing_name: str, behavior_name: str, message: Dict[str, Any]) -> None:
    """
    Handle security alarm with appropriate remediation actions
    
    Args:
        thing_name: Name of the IoT thing
        behavior_name: Name of the behavior that triggered the alarm
        message: Complete violation message
    """
    try:
        if behavior_name == 'AuthorizationFailures':
            logger.warning(f"Authorization failures detected for {thing_name}")
            # In production, implement certificate management
            send_alert_to_queue(thing_name, 'authorization_failure', message)
            
        elif behavior_name == 'MessageByteSize':
            logger.warning(f"Unusual message size detected for {thing_name}")
            send_alert_to_queue(thing_name, 'message_size_anomaly', message)
            
        elif behavior_name in ['MessagesReceived', 'MessagesSent']:
            logger.warning(f"Unusual message volume detected for {thing_name}")
            send_alert_to_queue(thing_name, 'message_volume_anomaly', message)
            
        elif behavior_name == 'ConnectionAttempts':
            logger.warning(f"Multiple connection attempts detected for {thing_name}")
            send_alert_to_queue(thing_name, 'connection_anomaly', message)
            
    except Exception as e:
        logger.error(f"Error handling security alarm: {str(e)}")

def handle_alarm_cleared(thing_name: str, behavior_name: str) -> None:
    """
    Handle alarm cleared event
    
    Args:
        thing_name: Name of the IoT thing
        behavior_name: Name of the behavior
    """
    logger.info(f"Alarm cleared for {thing_name}, behavior: {behavior_name}")
    
    # Send metric indicating alarm cleared
    try:
        cloudwatch.put_metric_data(
            Namespace='AWS/IoT/FleetMonitoring',
            MetricData=[
                {
                    'MetricName': 'SecurityAlarmsCleared',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'BehaviorName',
                            'Value': behavior_name
                        },
                        {
                            'Name': 'FleetName',
                            'Value': FLEET_NAME
                        }
                    ]
                }
            ]
        )
        
    except Exception as e:
        logger.error(f"Failed to send alarm cleared metric: {str(e)}")

def send_alert_to_queue(thing_name: str, alert_type: str, message: Dict[str, Any]) -> None:
    """
    Send alert to SQS queue for further processing
    
    Args:
        thing_name: Name of the IoT thing
        alert_type: Type of alert
        message: Complete violation message
    """
    try:
        alert_message = {
            'thingName': thing_name,
            'alertType': alert_type,
            'timestamp': datetime.now().isoformat(),
            'originalMessage': message
        }
        
        sqs.send_message(
            QueueUrl=MESSAGE_QUEUE_URL,
            MessageBody=json.dumps(alert_message)
        )
        
        logger.info(f"Sent alert to queue for {thing_name}")
        
    except Exception as e:
        logger.error(f"Failed to send alert to queue: {str(e)}")

def process_device_event(message: Dict[str, Any]) -> None:
    """
    Process device-specific events from SQS
    
    Args:
        message: Device event message
    """
    logger.info(f"Processing device event: {json.dumps(message)}")
    
    # Implement device-specific event processing
    # This could include device health checks, firmware updates, etc.
    pass
      `)
    });

    // Grant permissions to Lambda function
    deviceMetadataTable.grantReadWriteData(remediationFunction);
    iotDataBucket.grantReadWrite(remediationFunction);
    messageQueue.grantSendMessages(remediationFunction);

    // Add Lambda as SNS subscription
    alertTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(remediationFunction)
    );

    // ==================== LOGGING ====================

    // CloudWatch Log Group for IoT events
    const iotLogGroup = new logs.LogGroup(this, 'IoTFleetMonitoringLogGroup', {
      logGroupName: '/aws/iot/fleet-monitoring',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // ==================== IOT RESOURCES ====================

    // IoT Thing Group for fleet management
    const fleetThingGroup = new iot.CfnThingGroup(this, 'FleetThingGroup', {
      thingGroupName: fleetName,
      thingGroupProperties: {
        thingGroupDescription: 'IoT device fleet for monitoring demonstration',
        attributePayload: {
          attributes: {
            'fleet_type': 'industrial_sensors',
            'managed_by': 'cdk_deployment'
          }
        }
      }
    });

    // Create test IoT devices
    const testDevices: iot.CfnThing[] = [];
    for (let i = 1; i <= deviceCount.valueAsNumber; i++) {
      const deviceName = `device-${fleetName}-${i}`;
      
      const device = new iot.CfnThing(this, `TestDevice${i}`, {
        thingName: deviceName,
        attributePayload: {
          attributes: {
            'deviceType': 'sensor',
            'location': `facility-${i}`,
            'firmware': 'v1.2.3',
            'fleetName': fleetName
          }
        }
      });

      testDevices.push(device);

      // Add device to thing group
      new iot.CfnThingGroupInfo(this, `DeviceGroupInfo${i}`, {
        thingGroupName: fleetThingGroup.thingGroupName!,
        thingName: device.thingName!
      });
    }

    // IoT Security Profile for behavioral monitoring
    const securityProfile = new iot.CfnSecurityProfile(this, 'FleetSecurityProfile', {
      securityProfileName: securityProfileName,
      securityProfileDescription: 'Comprehensive security monitoring for IoT device fleet',
      behaviors: [
        {
          name: 'AuthorizationFailures',
          metric: 'aws:num-authorization-failures',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 5 },
            durationSeconds: 300,
            consecutiveDatapointsToAlarm: 2,
            consecutiveDatapointsToClear: 2
          }
        },
        {
          name: 'MessageByteSize',
          metric: 'aws:message-byte-size',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 1024 },
            consecutiveDatapointsToAlarm: 3,
            consecutiveDatapointsToClear: 1
          }
        },
        {
          name: 'MessagesReceived',
          metric: 'aws:num-messages-received',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 100 },
            durationSeconds: 300,
            consecutiveDatapointsToAlarm: 2,
            consecutiveDatapointsToClear: 2
          }
        },
        {
          name: 'MessagesSent',
          metric: 'aws:num-messages-sent',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 100 },
            durationSeconds: 300,
            consecutiveDatapointsToAlarm: 2,
            consecutiveDatapointsToClear: 2
          }
        },
        {
          name: 'ConnectionAttempts',
          metric: 'aws:num-connection-attempts',
          criteria: {
            comparisonOperator: 'greater-than',
            value: { count: 10 },
            durationSeconds: 300,
            consecutiveDatapointsToAlarm: 2,
            consecutiveDatapointsToClear: 2
          }
        }
      ],
      alertTargets: {
        SNS: {
          alertTargetArn: alertTopic.topicArn,
          roleArn: deviceDefenderRole.roleArn
        }
      }
    });

    // Attach security profile to thing group
    new iot.CfnSecurityProfileTarget(this, 'SecurityProfileTarget', {
      securityProfileName: securityProfile.securityProfileName!,
      securityProfileTargetArn: `arn:aws:iot:${this.region}:${this.account}:thinggroup/${fleetThingGroup.thingGroupName}`
    });

    // IoT Topic Rules for advanced monitoring
    const deviceConnectionRule = new iot.CfnTopicRule(this, 'DeviceConnectionRule', {
      ruleName: `DeviceConnectionMonitoring${randomSuffix}`,
      topicRulePayload: {
        sql: 'SELECT * FROM "$aws/events/presence/connected/+" WHERE eventType = "connected" OR eventType = "disconnected"',
        description: 'Monitor device connection events',
        actions: [
          {
            cloudwatchMetric: {
              roleArn: deviceDefenderRole.roleArn,
              metricNamespace: 'AWS/IoT/FleetMonitoring',
              metricName: 'DeviceConnectionEvents',
              metricValue: '1',
              metricUnit: 'Count',
              metricTimestamp: '${timestamp()}'
            }
          },
          {
            cloudwatchLogs: {
              roleArn: deviceDefenderRole.roleArn,
              logGroupName: iotLogGroup.logGroupName
            }
          }
        ]
      }
    });

    const messageVolumeRule = new iot.CfnTopicRule(this, 'MessageVolumeRule', {
      ruleName: `MessageVolumeMonitoring${randomSuffix}`,
      topicRulePayload: {
        sql: 'SELECT clientId, timestamp, topic FROM "device/+/data"',
        description: 'Monitor message volume from devices',
        actions: [
          {
            cloudwatchMetric: {
              roleArn: deviceDefenderRole.roleArn,
              metricNamespace: 'AWS/IoT/FleetMonitoring',
              metricName: 'MessageVolume',
              metricValue: '1',
              metricUnit: 'Count',
              metricTimestamp: '${timestamp()}'
            }
          },
          {
            s3: {
              roleArn: deviceDefenderRole.roleArn,
              bucketName: iotDataBucket.bucketName,
              key: 'device-data/${topic()}/${timestamp()}.json'
            }
          }
        ]
      }
    });

    // Grant permissions for IoT rules
    iotDataBucket.grantWrite(deviceDefenderRole);
    iotLogGroup.grantWrite(deviceDefenderRole);

    // ==================== CLOUDWATCH MONITORING ====================

    // CloudWatch Alarms for fleet monitoring
    const securityViolationAlarm = new cloudwatch.Alarm(this, 'SecurityViolationAlarm', {
      alarmName: `IoT-Fleet-High-Security-Violations-${randomSuffix}`,
      alarmDescription: 'High number of security violations detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/IoT/FleetMonitoring',
        metricName: 'SecurityViolations',
        dimensionsMap: {
          FleetName: fleetName
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: securityViolationThreshold.valueAsNumber,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });

    const connectivityAlarm = new cloudwatch.Alarm(this, 'ConnectivityAlarm', {
      alarmName: `IoT-Fleet-Low-Connectivity-${randomSuffix}`,
      alarmDescription: 'Low device connectivity detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/IoT',
        metricName: 'ConnectedDevices',
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 3,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const messageProcessingAlarm = new cloudwatch.Alarm(this, 'MessageProcessingAlarm', {
      alarmName: `IoT-Fleet-Message-Processing-Errors-${randomSuffix}`,
      alarmDescription: 'High message processing error rate',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/IoT',
        metricName: 'RuleMessageProcessingErrors',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 10,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });

    // Add SNS actions to alarms
    securityViolationAlarm.addAlarmAction(new cloudwatch.SnsAction(alertTopic));
    connectivityAlarm.addAlarmAction(new cloudwatch.SnsAction(alertTopic));
    messageProcessingAlarm.addAlarmAction(new cloudwatch.SnsAction(alertTopic));

    // CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'IoTFleetDashboard', {
      dashboardName: dashboardName,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'IoT Fleet Overview',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/IoT',
                metricName: 'ConnectedDevices',
                statistic: 'Average'
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/IoT',
                metricName: 'MessagesSent',
                statistic: 'Sum'
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/IoT',
                metricName: 'MessagesReceived',
                statistic: 'Sum'
              })
            ],
            width: 12,
            height: 6
          }),
          new cloudwatch.GraphWidget({
            title: 'Security Violations',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/IoT/FleetMonitoring',
                metricName: 'SecurityViolations',
                dimensionsMap: {
                  FleetName: fleetName
                },
                statistic: 'Sum'
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/IoT/FleetMonitoring',
                metricName: 'SecurityAlarmsCleared',
                dimensionsMap: {
                  FleetName: fleetName
                },
                statistic: 'Sum'
              })
            ],
            width: 12,
            height: 6
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Message Processing',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/IoT',
                metricName: 'RuleMessageProcessingErrors',
                statistic: 'Sum'
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/IoT',
                metricName: 'RuleMessageProcessingSuccess',
                statistic: 'Sum'
              })
            ],
            width: 12,
            height: 6
          }),
          new cloudwatch.LogQueryWidget({
            title: 'Security Violation Logs',
            logGroups: [remediationFunction.logGroup],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /violation/',
              'sort @timestamp desc',
              'limit 20'
            ],
            width: 12,
            height: 6
          })
        ]
      ]
    });

    // ==================== OUTPUTS ====================

    // Stack outputs for reference
    new cdk.CfnOutput(this, 'FleetName', {
      value: fleetName,
      description: 'IoT Fleet Thing Group Name'
    });

    new cdk.CfnOutput(this, 'SecurityProfileName', {
      value: securityProfileName,
      description: 'IoT Security Profile Name'
    });

    new cdk.CfnOutput(this, 'DashboardName', {
      value: dashboardName,
      description: 'CloudWatch Dashboard Name'
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertTopic.topicArn,
      description: 'SNS Topic ARN for alerts'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: remediationFunction.functionArn,
      description: 'Lambda Function ARN for remediation'
    });

    new cdk.CfnOutput(this, 'DeviceMetadataTableName', {
      value: deviceMetadataTable.tableName,
      description: 'DynamoDB Table Name for device metadata'
    });

    new cdk.CfnOutput(this, 'IoTDataBucketName', {
      value: iotDataBucket.bucketName,
      description: 'S3 Bucket Name for IoT data storage'
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboardName}`,
      description: 'CloudWatch Dashboard URL'
    });

    new cdk.CfnOutput(this, 'IoTConsoleUrl', {
      value: `https://${this.region}.console.aws.amazon.com/iot/home?region=${this.region}#/thinggroup/${fleetName}`,
      description: 'IoT Console URL for fleet management'
    });
  }
}

// Initialize the CDK app
const app = new cdk.App();

// Create the stack
new IoTDeviceFleetMonitoringStack(app, 'IoTDeviceFleetMonitoringStack', {
  description: 'Comprehensive IoT Device Fleet Monitoring with CloudWatch and Device Defender',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'IoT-Fleet-Monitoring',
    Environment: 'Production',
    ManagedBy: 'CDK'
  }
});