#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * CDK Stack for IoT Device Shadows State Management
 * 
 * This stack creates a complete IoT Device Shadows infrastructure including:
 * - IoT Thing with certificate and policy
 * - DynamoDB table for state history
 * - Lambda function for shadow update processing
 * - IoT Rules Engine rule for event routing
 * - Proper IAM roles and permissions
 */
export class IoTDeviceShadowsStack extends cdk.Stack {
  // Public properties for outputs
  public readonly thingName: string;
  public readonly certificateArn: string;
  public readonly shadowUpdateLambda: lambda.Function;
  public readonly stateHistoryTable: dynamodb.Table;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 6);
    this.thingName = `smart-thermostat-${uniqueSuffix}`;

    // Create DynamoDB table for device state history
    this.stateHistoryTable = new dynamodb.Table(this, 'DeviceStateHistoryTable', {
      tableName: `DeviceStateHistory-${uniqueSuffix}`,
      partitionKey: {
        name: 'ThingName',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      pointInTimeRecovery: true, // Enable backup for production use
      tags: {
        Application: 'IoTShadowDemo',
        Environment: 'Demo'
      }
    });

    // Create Lambda function for shadow update processing
    this.shadowUpdateLambda = new lambda.Function(this, 'ShadowUpdateProcessor', {
      functionName: `ProcessShadowUpdate-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      environment: {
        TABLE_NAME: this.stateHistoryTable.tableName
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import time
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Process IoT Device Shadow update events
    
    This function receives shadow update events from IoT Rules Engine
    and stores the state changes in DynamoDB for historical tracking.
    """
    try:
        # Parse the shadow update event
        thing_name = event.get('thingName')
        shadow_data = event.get('state', {})
        
        if not thing_name:
            raise ValueError("Missing thingName in event")
        
        # Store state change in DynamoDB
        table = dynamodb.Table(os.environ['TABLE_NAME'])
        
        # Convert float to Decimal for DynamoDB compatibility
        def convert_floats(obj):
            if isinstance(obj, float):
                return Decimal(str(obj))
            elif isinstance(obj, dict):
                return {k: convert_floats(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [convert_floats(v) for v in obj]
            return obj
        
        # Create item for DynamoDB
        item = {
            'ThingName': thing_name,
            'Timestamp': int(time.time()),
            'ShadowState': convert_floats(shadow_data),
            'EventType': 'shadow_update',
            'EventTime': int(time.time() * 1000)  # Milliseconds for better sorting
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
        print(f"Error processing shadow update: {str(e)}")
        print(f"Event data: {json.dumps(event)}")
        
        # Re-raise the exception to trigger Lambda error handling
        raise
`)
    });

    // Grant Lambda permission to write to DynamoDB
    this.stateHistoryTable.grantWriteData(this.shadowUpdateLambda);

    // Create IoT Thing Type for better organization
    const thingType = new iot.CfnThingType(this, 'ThermostatThingType', {
      thingTypeName: `Thermostat-${uniqueSuffix}`,
      thingTypeDescription: 'Smart thermostat device type for IoT shadow management demo',
      thingTypeProperties: {
        description: 'Smart home thermostat with HVAC control capabilities',
        searchable: ['manufacturer', 'model', 'firmwareVersion']
      }
    });

    // Create IoT Thing
    const iotThing = new iot.CfnThing(this, 'SmartThermostat', {
      thingName: this.thingName,
      thingTypeName: thingType.thingTypeName,
      attributePayload: {
        attributes: {
          manufacturer: 'SmartHome',
          model: 'TH-2024',
          firmwareVersion: '1.2.3',
          deviceType: 'thermostat'
        }
      }
    });

    // Ensure Thing Type is created before Thing
    iotThing.addDependency(thingType);

    // Create IoT Certificate
    const deviceCertificate = new iot.CfnCertificate(this, 'DeviceCertificate', {
      status: 'ACTIVE',
      certificateMode: 'DEFAULT'
    });

    this.certificateArn = deviceCertificate.attrArn;

    // Create IoT Policy for device permissions
    const devicePolicy = new iot.CfnPolicy(this, 'DevicePolicy', {
      policyName: `SmartThermostatPolicy-${uniqueSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: ['iot:Connect'],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:client/\${iot:Connection.Thing.ThingName}`
            ]
          },
          {
            Effect: 'Allow',
            Action: ['iot:Subscribe', 'iot:Receive'],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:topicfilter/$aws/things/\${iot:Connection.Thing.ThingName}/shadow/*`
            ]
          },
          {
            Effect: 'Allow',
            Action: ['iot:Publish'],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:topic/$aws/things/\${iot:Connection.Thing.ThingName}/shadow/*`
            ]
          }
        ]
      }
    });

    // Attach policy to certificate
    new iot.CfnPolicyPrincipalAttachment(this, 'PolicyCertificateAttachment', {
      policyName: devicePolicy.policyName!,
      principal: deviceCertificate.attrArn
    });

    // Attach certificate to Thing
    new iot.CfnThingPrincipalAttachment(this, 'ThingCertificateAttachment', {
      thingName: iotThing.thingName!,
      principal: deviceCertificate.attrArn
    });

    // Create IoT Topic Rule for shadow updates
    const shadowUpdateRule = new iot.CfnTopicRule(this, 'ShadowUpdateRule', {
      ruleName: `ShadowUpdateRule${uniqueSuffix}`,
      topicRulePayload: {
        sql: "SELECT * FROM '$aws/things/+/shadow/update/accepted'",
        description: 'Process Device Shadow updates and store in DynamoDB',
        ruleDisabled: false,
        actions: [
          {
            lambda: {
              functionArn: this.shadowUpdateLambda.functionArn
            }
          }
        ]
      }
    });

    // Grant IoT permission to invoke Lambda
    this.shadowUpdateLambda.addPermission('AllowIoTInvoke', {
      principal: new iam.ServicePrincipal('iot.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: `arn:aws:iot:${this.region}:${this.account}:rule/${shadowUpdateRule.ruleName}`
    });

    // Create CloudWatch Log Group for IoT Rules Engine
    new logs.LogGroup(this, 'IoTRulesLogGroup', {
      logGroupName: `/aws/iot/rules/${shadowUpdateRule.ruleName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Stack Outputs
    new cdk.CfnOutput(this, 'ThingNameOutput', {
      value: this.thingName,
      description: 'Name of the created IoT Thing',
      exportName: `${this.stackName}-ThingName`
    });

    new cdk.CfnOutput(this, 'CertificateArnOutput', {
      value: this.certificateArn,
      description: 'ARN of the device certificate',
      exportName: `${this.stackName}-CertificateArn`
    });

    new cdk.CfnOutput(this, 'CertificateIdOutput', {
      value: deviceCertificate.ref,
      description: 'ID of the device certificate',
      exportName: `${this.stackName}-CertificateId`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArnOutput', {
      value: this.shadowUpdateLambda.functionArn,
      description: 'ARN of the shadow update processing Lambda function',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    new cdk.CfnOutput(this, 'DynamoDBTableNameOutput', {
      value: this.stateHistoryTable.tableName,
      description: 'Name of the DynamoDB table storing state history',
      exportName: `${this.stackName}-DynamoDBTableName`
    });

    new cdk.CfnOutput(this, 'IoTEndpointOutput', {
      value: `https://${cdk.Fn.ref('AWS::URLSuffix')}`,
      description: 'IoT Core endpoint URL (use aws iot describe-endpoint to get actual endpoint)',
      exportName: `${this.stackName}-IoTEndpoint`
    });

    new cdk.CfnOutput(this, 'ShadowTopicOutput', {
      value: `$aws/things/${this.thingName}/shadow/update`,
      description: 'MQTT topic for shadow updates',
      exportName: `${this.stackName}-ShadowTopic`
    });
  }
}

// CDK App
const app = new cdk.App();

// Create the stack with environment configuration
new IoTDeviceShadowsStack(app, 'IoTDeviceShadowsStack', {
  description: 'IoT Device Shadows State Management Infrastructure (qs-1234567890)',
  
  // Use environment variables or default to us-east-1
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },

  // Stack tags
  tags: {
    Project: 'IoTDeviceShadows',
    Purpose: 'Demo',
    ManagedBy: 'CDK'
  }
});

// Add app-level tags
cdk.Tags.of(app).add('CreatedBy', 'CDK-TypeScript');
cdk.Tags.of(app).add('Recipe', 'iot-device-shadows-state-management');