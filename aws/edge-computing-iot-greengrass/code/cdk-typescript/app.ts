#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as greengrassv2 from 'aws-cdk-lib/aws-greengrassv2';
import { Construct } from 'constructs';

/**
 * Interface for IoT Greengrass Edge Computing Stack properties
 */
interface IoTGreengrassEdgeComputingStackProps extends cdk.StackProps {
  /**
   * Unique suffix for resource naming
   */
  readonly uniqueSuffix?: string;
  
  /**
   * Name for the Greengrass Core Thing
   */
  readonly thingName?: string;
  
  /**
   * Name for the Thing Group
   */
  readonly thingGroupName?: string;
  
  /**
   * Environment tag for resources
   */
  readonly environment?: string;
}

/**
 * AWS CDK Stack for Edge Computing with IoT Greengrass
 * 
 * This stack creates:
 * - IoT Thing and Thing Group for device management
 * - X.509 certificates for secure device authentication
 * - IAM roles with appropriate permissions for Greengrass Core
 * - Lambda function for edge processing
 * - IoT policies for device permissions
 * - Greengrass components and deployments
 */
export class IoTGreengrassEdgeComputingStack extends cdk.Stack {
  
  /**
   * The IoT Thing representing the Greengrass Core device
   */
  public readonly greengrassThing: iot.CfnThing;
  
  /**
   * The Thing Group for organizing Greengrass devices
   */
  public readonly thingGroup: iot.CfnThingGroup;
  
  /**
   * The Lambda function for edge processing
   */
  public readonly edgeProcessorFunction: lambda.Function;
  
  /**
   * The IAM role for Greengrass Core device
   */
  public readonly greengrassRole: iam.Role;
  
  /**
   * The IoT certificate for device authentication
   */
  public readonly deviceCertificate: iot.CfnCertificate;

  constructor(scope: Construct, id: string, props: IoTGreengrassEdgeComputingStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource naming if not provided
    const uniqueSuffix = props.uniqueSuffix || Math.random().toString(36).substring(2, 8);
    const thingName = props.thingName || `greengrass-core-${uniqueSuffix}`;
    const thingGroupName = props.thingGroupName || `greengrass-things-${uniqueSuffix}`;
    const environment = props.environment || 'development';

    // Tags to apply to all taggable resources
    const commonTags = {
      Project: 'IoT-Greengrass-Edge-Computing',
      Environment: environment,
      Recipe: 'edge-computing-aws-iot-greengrass',
      ManagedBy: 'AWS-CDK'
    };

    // Create Thing Group for device management
    this.thingGroup = new iot.CfnThingGroup(this, 'GreengrassThingGroup', {
      thingGroupName: thingGroupName,
      thingGroupProperties: {
        thingGroupDescription: 'Greengrass core devices group for edge computing',
        attributePayload: {
          attributes: {
            environment: environment,
            purpose: 'edge-computing',
            managedBy: 'cdk'
          }
        }
      },
      tags: Object.entries(commonTags).map(([key, value]) => ({ key, value }))
    });

    // Create IoT Thing for Greengrass Core
    this.greengrassThing = new iot.CfnThing(this, 'GreengrassCoreThing', {
      thingName: thingName,
      attributePayload: {
        attributes: {
          deviceType: 'greengrass-core',
          environment: environment,
          version: '2.0'
        }
      }
    });

    // Add Thing to Thing Group
    new iot.CfnThingGroupInfo(this, 'ThingGroupInfo', {
      thingGroupName: this.thingGroup.thingGroupName!,
      thingName: this.greengrassThing.thingName!
    });

    // Create X.509 certificate for device authentication
    this.deviceCertificate = new iot.CfnCertificate(this, 'DeviceCertificate', {
      status: 'ACTIVE',
      certificateMode: 'DEFAULT'
    });

    // Create IAM role for Greengrass Core device
    this.greengrassRole = new iam.Role(this, 'GreengrassCoreRole', {
      roleName: `greengrass-core-role-${uniqueSuffix}`,
      description: 'IAM role for AWS IoT Greengrass Core device operations',
      assumedBy: new iam.ServicePrincipal('credentials.iot.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGreengrassResourceAccessRolePolicy')
      ],
      inlinePolicies: {
        'GreengrassAdditionalPermissions': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogStreams'
              ],
              resources: [
                `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/greengrass/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iot:GetThingShadow',
                'iot:UpdateThingShadow',
                'iot:DeleteThingShadow'
              ],
              resources: [
                `arn:aws:iot:${this.region}:${this.account}:thing/${thingName}`
              ]
            })
          ]
        })
      },
      tags: commonTags
    });

    // Create IoT Policy for Greengrass Core permissions
    const greengrassPolicy = new iot.CfnPolicy(this, 'GreengrassPolicy', {
      policyName: `greengrass-policy-${uniqueSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              'iot:Publish',
              'iot:Subscribe',
              'iot:Receive',
              'iot:Connect'
            ],
            Resource: '*'
          },
          {
            Effect: 'Allow',
            Action: [
              'greengrass:*'
            ],
            Resource: '*'
          },
          {
            Effect: 'Allow',
            Action: [
              'iot:GetThingShadow',
              'iot:UpdateThingShadow',
              'iot:DeleteThingShadow'
            ],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:thing/${thingName}`
            ]
          }
        ]
      }
    });

    // Attach policy to certificate
    new iot.CfnPolicyPrincipalAttachment(this, 'PolicyCertificateAttachment', {
      policyName: greengrassPolicy.policyName!,
      principal: this.deviceCertificate.attrArn
    });

    // Create CloudWatch Log Group for Greengrass
    new logs.LogGroup(this, 'GreengrassLogGroup', {
      logGroupName: `/aws/greengrass/core-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create Lambda function for edge processing
    this.edgeProcessorFunction = new lambda.Function(this, 'EdgeProcessorFunction', {
      functionName: `edge-processor-${uniqueSuffix}`,
      description: 'Lambda function for processing sensor data at the edge',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import logging
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process sensor data at the edge
    """
    logger.info(f"Processing edge data: {event}")
    
    # Simulate sensor data processing
    processed_data = {
        "timestamp": int(time.time()),
        "device_id": event.get("device_id", "unknown"),
        "temperature": event.get("temperature", 0),
        "status": "processed_at_edge",
        "processing_time": 0.1
    }
    
    logger.info(f"Processed data: {processed_data}")
    
    return {
        "statusCode": 200,
        "body": json.dumps(processed_data)
    }
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      environment: {
        'THING_NAME': thingName,
        'THING_GROUP_NAME': thingGroupName,
        'AWS_REGION': this.region
      },
      role: this.greengrassRole,
      tags: commonTags
    });

    // Create Greengrass Component Definition for Lambda function
    const lambdaComponent = new greengrassv2.CfnComponentVersion(this, 'EdgeProcessorComponent', {
      lambdaFunction: {
        lambdaArn: this.edgeProcessorFunction.functionArn,
        componentName: 'com.example.EdgeProcessor',
        componentVersion: '1.0.0',
        componentLambdaParameters: {
          eventSources: [
            {
              topic: `$aws/things/${thingName}/shadow/update/accepted`,
              type: 'IOT_CORE'
            }
          ],
          maxIdleTimeInSeconds: 60,
          maxInstancesCount: 1,
          maxQueueSize: 1000,
          pinned: true,
          statusTimeoutInSeconds: 60,
          timeoutInSeconds: 30,
          environmentVariables: {
            'THING_NAME': thingName,
            'LOG_LEVEL': 'INFO'
          },
          execArgs: [],
          inputPayloadEncodingType: 'json',
          linuxProcessParams: {
            isolationMode: 'GreengrassContainer',
            containerParams: {
              memorySizeInKb: 131072,
              mountRoSysfs: false,
              volumes: []
            }
          }
        }
      },
      tags: commonTags
    });

    // Output important values for verification and management
    new cdk.CfnOutput(this, 'ThingName', {
      description: 'Name of the IoT Thing for Greengrass Core',
      value: this.greengrassThing.thingName!,
      exportName: `${this.stackName}-ThingName`
    });

    new cdk.CfnOutput(this, 'ThingGroupName', {
      description: 'Name of the Thing Group',
      value: this.thingGroup.thingGroupName!,
      exportName: `${this.stackName}-ThingGroupName`
    });

    new cdk.CfnOutput(this, 'CertificateArn', {
      description: 'ARN of the device certificate',
      value: this.deviceCertificate.attrArn,
      exportName: `${this.stackName}-CertificateArn`
    });

    new cdk.CfnOutput(this, 'CertificateId', {
      description: 'ID of the device certificate',
      value: this.deviceCertificate.attrId,
      exportName: `${this.stackName}-CertificateId`
    });

    new cdk.CfnOutput(this, 'GreengrassRoleArn', {
      description: 'ARN of the Greengrass Core IAM role',
      value: this.greengrassRole.roleArn,
      exportName: `${this.stackName}-GreengrassRoleArn`
    });

    new cdk.CfnOutput(this, 'EdgeProcessorFunctionArn', {
      description: 'ARN of the edge processor Lambda function',
      value: this.edgeProcessorFunction.functionArn,
      exportName: `${this.stackName}-EdgeProcessorFunctionArn`
    });

    new cdk.CfnOutput(this, 'EdgeProcessorFunctionName', {
      description: 'Name of the edge processor Lambda function',
      value: this.edgeProcessorFunction.functionName,
      exportName: `${this.stackName}-EdgeProcessorFunctionName`
    });

    new cdk.CfnOutput(this, 'IoTEndpoint', {
      description: 'IoT Core endpoint for device connection',
      value: `https://${cdk.Fn.ref('AWS::URLSuffix')}`,
      exportName: `${this.stackName}-IoTEndpoint`
    });

    new cdk.CfnOutput(this, 'DeploymentInstructions', {
      description: 'Next steps for Greengrass deployment',
      value: `1. Download certificates using certificate ID: ${this.deviceCertificate.attrId} 2. Install Greengrass Core software on edge device 3. Configure with Thing name: ${this.greengrassThing.thingName} 4. Deploy components using Thing Group: ${this.thingGroup.thingGroupName}`
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from context or use defaults
const stackName = app.node.tryGetContext('stackName') || 'IoTGreengrassEdgeComputingStack';
const environment = app.node.tryGetContext('environment') || 'development';
const uniqueSuffix = app.node.tryGetContext('uniqueSuffix');

// Create the stack
new IoTGreengrassEdgeComputingStack(app, stackName, {
  description: 'AWS CDK Stack for Edge Computing with IoT Greengrass - Recipe: edge-computing-aws-iot-greengrass',
  uniqueSuffix: uniqueSuffix,
  environment: environment,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  tags: {
    Project: 'IoT-Greengrass-Edge-Computing',
    Recipe: 'edge-computing-aws-iot-greengrass',
    ManagedBy: 'AWS-CDK',
    Environment: environment
  }
});

// Synthesize the app
app.synth();