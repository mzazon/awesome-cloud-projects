#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for IoT Device Management with AWS IoT Core
 * 
 * This stack creates:
 * - IoT Thing Type and Thing for device registration
 * - Device certificate and IoT policy for secure authentication
 * - Lambda function for processing IoT sensor data
 * - IoT Rule for routing sensor data to Lambda
 * - CloudWatch Log Group for Lambda function logs
 * - Device Shadow for state management
 */
export class IoTDeviceManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 6);

    // Create IoT Thing Type for categorizing devices
    const thingType = new iot.CfnThingType(this, 'TemperatureSensorThingType', {
      thingTypeName: 'TemperatureSensor',
      thingTypeDescription: 'Temperature sensor devices for production monitoring',
      thingTypeProperties: {
        description: 'Industrial temperature sensors with WiFi connectivity',
        searchableAttributes: ['deviceType', 'manufacturer', 'location']
      },
      tags: [
        { key: 'Purpose', value: 'IoTDeviceManagement' },
        { key: 'DeviceType', value: 'TemperatureSensor' }
      ]
    });

    // Create IoT Thing (represents the physical device)
    const iotThing = new iot.CfnThing(this, 'TemperatureSensorThing', {
      thingName: `temperature-sensor-${uniqueSuffix}`,
      thingTypeName: thingType.thingTypeName,
      attributePayload: {
        attributes: {
          deviceType: 'temperature',
          manufacturer: 'SensorCorp',
          model: 'TC-2000',
          location: 'ProductionFloor-A',
          firmwareVersion: '1.0.0'
        }
      }
    });

    // Ensure Thing Type is created before Thing
    iotThing.addDependency(thingType);

    // Create device certificate for secure authentication
    const deviceCertificate = new iot.CfnCertificate(this, 'DeviceCertificate', {
      status: 'ACTIVE',
      certificateSigningRequest: undefined, // Let CDK generate the certificate
    });

    // Create IoT Policy with least privilege permissions
    const iotPolicy = new iot.CfnPolicy(this, 'DevicePolicy', {
      policyName: `device-policy-${uniqueSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: ['iot:Connect', 'iot:Publish'],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:client/\${iot:Connection.Thing.ThingName}`,
              `arn:aws:iot:${this.region}:${this.account}:topic/sensor/temperature/\${iot:Connection.Thing.ThingName}`
            ]
          },
          {
            Effect: 'Allow',
            Action: ['iot:GetThingShadow', 'iot:UpdateThingShadow'],
            Resource: `arn:aws:iot:${this.region}:${this.account}:thing/\${iot:Connection.Thing.ThingName}`
          }
        ]
      }
    });

    // Attach policy to certificate
    new iot.CfnPolicyPrincipalAttachment(this, 'PolicyCertificateAttachment', {
      policyName: iotPolicy.policyName!,
      principal: deviceCertificate.attrArn
    });

    // Attach certificate to IoT Thing
    new iot.CfnThingPrincipalAttachment(this, 'ThingCertificateAttachment', {
      thingName: iotThing.thingName!,
      principal: deviceCertificate.attrArn
    });

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'IoTDataProcessorLogGroup', {
      logGroupName: `/aws/lambda/iot-data-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'IoTLambdaRole', {
      roleName: `iot-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogStreams'
              ],
              resources: [logGroup.logGroupArn, `${logGroup.logGroupArn}:*`]
            })
          ]
        })
      }
    });

    // Create Lambda function for processing IoT sensor data
    const iotDataProcessor = new lambda.Function(this, 'IoTDataProcessor', {
      functionName: `iot-data-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process IoT sensor data from temperature devices.
    
    Args:
        event: IoT message payload containing sensor data
        context: Lambda context object
        
    Returns:
        dict: Processing result with status and processed data
    """
    try:
        logger.info(f"Received IoT data: {json.dumps(event)}")
        
        # Extract device data from the event
        device_name = event.get('device', 'unknown')
        temperature = event.get('temperature', 0)
        humidity = event.get('humidity', 0)
        timestamp = event.get('timestamp', datetime.utcnow().isoformat())
        
        # Validate temperature data
        if not isinstance(temperature, (int, float)):
            raise ValueError(f"Invalid temperature value: {temperature}")
            
        # Process temperature data and generate alerts
        alert_level = None
        if temperature > 80:
            alert_level = 'HIGH'
            logger.warning(f"High temperature alert: {temperature}°C from {device_name}")
        elif temperature < 10:
            alert_level = 'LOW'
            logger.warning(f"Low temperature alert: {temperature}°C from {device_name}")
        else:
            alert_level = 'NORMAL'
            logger.info(f"Normal temperature reading: {temperature}°C from {device_name}")
        
        # Create processed data structure
        processed_data = {
            'device_name': device_name,
            'temperature': temperature,
            'humidity': humidity,
            'timestamp': timestamp,
            'alert_level': alert_level,
            'processing_timestamp': datetime.utcnow().isoformat()
        }
        
        # Log successful processing
        logger.info(f"Successfully processed data from {device_name}: {processed_data}")
        
        # Here you could add additional processing like:
        # - Send to SNS for alerts
        # - Store in DynamoDB for historical data
        # - Forward to Kinesis for real-time analytics
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'IoT data processed successfully',
                'processed_data': processed_data
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing IoT data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to process IoT data',
                'details': str(e)
            })
        }
      `),
      role: lambdaRole,
      description: 'Process IoT sensor data from temperature devices',
      timeout: cdk.Duration.seconds(30),
      logGroup: logGroup,
      environment: {
        LOG_LEVEL: 'INFO',
        STACK_NAME: this.stackName
      }
    });

    // Create IoT Rule for automatic data routing
    const iotRule = new iot.CfnTopicRule(this, 'SensorDataRule', {
      ruleName: `sensor_data_rule_${uniqueSuffix}`,
      topicRulePayload: {
        sql: "SELECT *, topic(3) as device FROM 'sensor/temperature/+'",
        description: 'Route temperature sensor data to Lambda for processing and analysis',
        actions: [
          {
            lambda: {
              functionArn: iotDataProcessor.functionArn
            }
          }
        ],
        ruleDisabled: false,
        awsIotSqlVersion: '2016-03-23'
      }
    });

    // Grant IoT Rule permission to invoke Lambda function
    iotDataProcessor.addPermission('IoTRuleInvokePermission', {
      principal: new iam.ServicePrincipal('iot.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: `arn:aws:iot:${this.region}:${this.account}:rule/${iotRule.ruleName}`
    });

    // Output important values for device configuration and testing
    new cdk.CfnOutput(this, 'IoTThingName', {
      value: iotThing.thingName!,
      description: 'Name of the IoT Thing (device) created for temperature monitoring',
      exportName: `${this.stackName}-IoTThingName`
    });

    new cdk.CfnOutput(this, 'DeviceCertificateArn', {
      value: deviceCertificate.attrArn,
      description: 'ARN of the device certificate for secure authentication',
      exportName: `${this.stackName}-DeviceCertificateArn`
    });

    new cdk.CfnOutput(this, 'DeviceCertificateId', {
      value: deviceCertificate.attrId,
      description: 'ID of the device certificate for certificate management',
      exportName: `${this.stackName}-DeviceCertificateId`
    });

    new cdk.CfnOutput(this, 'IoTPolicyName', {
      value: iotPolicy.policyName!,
      description: 'Name of the IoT policy defining device permissions',
      exportName: `${this.stackName}-IoTPolicyName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: iotDataProcessor.functionName,
      description: 'Name of the Lambda function processing IoT sensor data',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'IoTRuleName', {
      value: iotRule.ruleName!,
      description: 'Name of the IoT rule routing sensor data to Lambda',
      exportName: `${this.stackName}-IoTRuleName`
    });

    new cdk.CfnOutput(this, 'IoTEndpoint', {
      value: `${this.account}.iot.${this.region}.amazonaws.com`,
      description: 'IoT Core endpoint for device connections',
      exportName: `${this.stackName}-IoTEndpoint`
    });

    new cdk.CfnOutput(this, 'SensorDataTopic', {
      value: `sensor/temperature/${iotThing.thingName}`,
      description: 'MQTT topic for publishing temperature sensor data',
      exportName: `${this.stackName}-SensorDataTopic`
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the IoT Device Management stack
new IoTDeviceManagementStack(app, 'IoTDeviceManagementStack', {
  description: 'IoT Device Management infrastructure using AWS IoT Core, Lambda, and CloudWatch',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'IoTDeviceManagement',
    Purpose: 'TemperatureSensorMonitoring',
    Environment: 'Development'
  }
});

// Synthesize the CloudFormation template
app.synth();