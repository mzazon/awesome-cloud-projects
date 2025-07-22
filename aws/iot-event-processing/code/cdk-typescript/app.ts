#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'path';

/**
 * CDK Stack for IoT Rules Engine Event Processing
 * 
 * This stack creates:
 * - DynamoDB table for telemetry data storage
 * - SNS topic for alerting
 * - Lambda function for custom event processing
 * - IAM roles and policies for IoT Rules Engine
 * - CloudWatch log group for monitoring
 * - Multiple IoT rules for different event types
 */
export class IoTRulesEngineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-6);

    // DynamoDB table for telemetry data storage
    const telemetryTable = new dynamodb.Table(this, 'TelemetryTable', {
      tableName: `factory-telemetry-${uniqueSuffix}`,
      partitionKey: {
        name: 'deviceId',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      tags: {
        Project: 'IoTRulesEngine',
        Environment: 'Demo'
      }
    });

    // SNS topic for alerts
    const alertsTopic = new sns.Topic(this, 'AlertsTopic', {
      topicName: `factory-alerts-${uniqueSuffix}`,
      displayName: 'Factory Alerts',
      fifo: false,
      encryption: sns.TopicEncryption.AWS_MANAGED
    });

    // Lambda function for custom event processing
    const eventProcessorFunction = new lambda.Function(this, 'EventProcessor', {
      functionName: `factory-event-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        TABLE_NAME: telemetryTable.tableName,
        TOPIC_ARN: alertsTopic.topicArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime
import os

def lambda_handler(event, context):
    """
    Process IoT events and perform custom business logic
    """
    try:
        # Parse the incoming IoT message
        device_id = event.get('deviceId', 'unknown')
        temperature = event.get('temperature', 0)
        motor_status = event.get('motorStatus', 'unknown')
        vibration = event.get('vibration', 0)
        timestamp = event.get('timestamp', int(datetime.now().timestamp()))
        
        # Custom processing logic
        severity = 'normal'
        alert_message = ''
        
        # Temperature-based severity
        if temperature > 85:
            severity = 'critical'
            alert_message = f'CRITICAL: Temperature {temperature}°C exceeds safe limits'
        elif temperature > 75:
            severity = 'warning'
            alert_message = f'WARNING: Temperature {temperature}°C above normal'
        
        # Motor status processing
        if motor_status == 'error':
            severity = 'critical'
            alert_message = f'CRITICAL: Motor error detected on {device_id}'
        elif vibration > 5.0:
            severity = 'warning'
            alert_message = f'WARNING: High vibration {vibration} detected on {device_id}'
        
        # Log the processed event
        print(f"Processing event from {device_id}: temp={temperature}°C, motor={motor_status}, vibration={vibration}, severity={severity}")
        
        # Optionally send additional notifications for critical events
        if severity == 'critical' and alert_message:
            sns_client = boto3.client('sns')
            sns_client.publish(
                TopicArn=os.environ['TOPIC_ARN'],
                Message=json.dumps({
                    'deviceId': device_id,
                    'severity': severity,
                    'message': alert_message,
                    'timestamp': timestamp
                }),
                Subject=f'Critical Alert: {device_id}'
            )
        
        # Return enriched data
        return {
            'statusCode': 200,
            'body': json.dumps({
                'deviceId': device_id,
                'temperature': temperature,
                'motorStatus': motor_status,
                'vibration': vibration,
                'severity': severity,
                'processedAt': timestamp,
                'message': alert_message or f'Event processed with severity {severity}'
            })
        }
        
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      tags: {
        Project: 'IoTRulesEngine',
        Environment: 'Demo'
      }
    });

    // Grant Lambda permissions to access DynamoDB and SNS
    telemetryTable.grantReadWriteData(eventProcessorFunction);
    alertsTopic.grantPublish(eventProcessorFunction);

    // CloudWatch log group for IoT rules
    const iotRulesLogGroup = new logs.LogGroup(this, 'IoTRulesLogGroup', {
      logGroupName: '/aws/iot/rules',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // IAM role for IoT Rules Engine
    const iotRulesRole = new iam.Role(this, 'IoTRulesRole', {
      roleName: `factory-iot-rules-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      description: 'Role for IoT Rules Engine to access AWS services',
      inlinePolicies: {
        IoTRulesPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:GetItem',
                'dynamodb:Query'
              ],
              resources: [telemetryTable.tableArn]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [alertsTopic.topicArn]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [eventProcessorFunction.functionArn]
            })
          ]
        })
      },
      tags: {
        Project: 'IoTRulesEngine',
        Environment: 'Demo'
      }
    });

    // IAM role for CloudWatch logging
    const iotLoggingRole = new iam.Role(this, 'IoTLoggingRole', {
      roleName: `factory-iot-logging-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSIoTLogsRole')
      ],
      tags: {
        Project: 'IoTRulesEngine',
        Environment: 'Demo'
      }
    });

    // Grant IoT permission to invoke Lambda function
    eventProcessorFunction.addPermission('IoTRulesInvoke', {
      principal: new iam.ServicePrincipal('iot.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: `arn:aws:iot:${this.region}:${this.account}:rule/MotorStatusRule`
    });

    // IoT Rule for temperature monitoring
    const temperatureRule = new iot.CfnTopicRule(this, 'TemperatureRule', {
      ruleName: 'TemperatureAlertRule',
      topicRulePayload: {
        sql: "SELECT deviceId, temperature, timestamp() as timestamp FROM 'factory/temperature' WHERE temperature > 70",
        description: 'Monitor temperature sensors and trigger alerts for high temperatures',
        ruleDisabled: false,
        awsIotSqlVersion: '2016-03-23',
        actions: [
          {
            dynamoDb: {
              tableName: telemetryTable.tableName,
              roleArn: iotRulesRole.roleArn,
              hashKeyField: 'deviceId',
              hashKeyValue: '${deviceId}',
              rangeKeyField: 'timestamp',
              rangeKeyValue: '${timestamp}',
              payloadField: 'data'
            }
          },
          {
            sns: {
              topicArn: alertsTopic.topicArn,
              roleArn: iotRulesRole.roleArn,
              messageFormat: 'JSON'
            }
          }
        ]
      }
    });

    // IoT Rule for motor status monitoring
    const motorStatusRule = new iot.CfnTopicRule(this, 'MotorStatusRule', {
      ruleName: 'MotorStatusRule',
      topicRulePayload: {
        sql: "SELECT deviceId, motorStatus, vibration, timestamp() as timestamp FROM 'factory/motors' WHERE motorStatus = 'error' OR vibration > 5.0",
        description: 'Monitor motor controllers for errors and excessive vibration',
        ruleDisabled: false,
        awsIotSqlVersion: '2016-03-23',
        actions: [
          {
            dynamoDb: {
              tableName: telemetryTable.tableName,
              roleArn: iotRulesRole.roleArn,
              hashKeyField: 'deviceId',
              hashKeyValue: '${deviceId}',
              rangeKeyField: 'timestamp',
              rangeKeyValue: '${timestamp}',
              payloadField: 'data'
            }
          },
          {
            lambda: {
              functionArn: eventProcessorFunction.functionArn
            }
          }
        ]
      }
    });

    // IoT Rule for security events
    const securityRule = new iot.CfnTopicRule(this, 'SecurityRule', {
      ruleName: 'SecurityEventRule',
      topicRulePayload: {
        sql: "SELECT deviceId, eventType, severity, location, timestamp() as timestamp FROM 'factory/security' WHERE eventType IN ('intrusion', 'unauthorized_access', 'door_breach')",
        description: 'Process security events and trigger immediate alerts',
        ruleDisabled: false,
        awsIotSqlVersion: '2016-03-23',
        actions: [
          {
            sns: {
              topicArn: alertsTopic.topicArn,
              roleArn: iotRulesRole.roleArn,
              messageFormat: 'JSON'
            }
          },
          {
            dynamoDb: {
              tableName: telemetryTable.tableName,
              roleArn: iotRulesRole.roleArn,
              hashKeyField: 'deviceId',
              hashKeyValue: '${deviceId}',
              rangeKeyField: 'timestamp',
              rangeKeyValue: '${timestamp}',
              payloadField: 'data'
            }
          }
        ]
      }
    });

    // IoT Rule for data archival
    const dataArchivalRule = new iot.CfnTopicRule(this, 'DataArchivalRule', {
      ruleName: 'DataArchivalRule',
      topicRulePayload: {
        sql: "SELECT * FROM 'factory/+' WHERE timestamp() % 300 = 0",
        description: 'Archive all factory data every 5 minutes for historical analysis',
        ruleDisabled: false,
        awsIotSqlVersion: '2016-03-23',
        actions: [
          {
            dynamoDb: {
              tableName: telemetryTable.tableName,
              roleArn: iotRulesRole.roleArn,
              hashKeyField: 'deviceId',
              hashKeyValue: '${deviceId}',
              rangeKeyField: 'timestamp',
              rangeKeyValue: '${timestamp}',
              payloadField: 'data'
            }
          }
        ]
      }
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'TelemetryTableName', {
      value: telemetryTable.tableName,
      description: 'DynamoDB table name for telemetry data'
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: alertsTopic.topicArn,
      description: 'SNS topic ARN for alerts'
    });

    new cdk.CfnOutput(this, 'EventProcessorFunctionName', {
      value: eventProcessorFunction.functionName,
      description: 'Lambda function name for event processing'
    });

    new cdk.CfnOutput(this, 'IoTRulesRoleArn', {
      value: iotRulesRole.roleArn,
      description: 'IAM role ARN for IoT Rules Engine'
    });

    new cdk.CfnOutput(this, 'TestCommands', {
      value: [
        'aws iot-data publish --topic "factory/temperature" --payload \'{"deviceId":"temp-sensor-01","temperature":80,"location":"production-floor"}\'',
        'aws iot-data publish --topic "factory/motors" --payload \'{"deviceId":"motor-ctrl-02","motorStatus":"error","vibration":6.5,"location":"assembly-line"}\'',
        'aws iot-data publish --topic "factory/security" --payload \'{"deviceId":"security-cam-03","eventType":"intrusion","severity":"high","location":"entrance-door"}\''
      ].join(' && '),
      description: 'Test commands to verify IoT rules functionality'
    });
  }
}

// CDK App
const app = new cdk.App();
new IoTRulesEngineStack(app, 'IoTRulesEngineStack', {
  description: 'IoT Rules Engine for Event Processing - CDK Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'IoTRulesEngine',
    Environment: 'Demo',
    CreatedBy: 'CDK'
  }
});