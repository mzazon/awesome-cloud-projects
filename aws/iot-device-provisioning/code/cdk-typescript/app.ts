#!/usr/bin/env node

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatch_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import { RemovalPolicy, Duration } from 'aws-cdk-lib';

/**
 * Props for the IoT Device Provisioning Stack
 */
export interface IoTDeviceProvisioningStackProps extends cdk.StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'dev'
   */
  readonly environmentPrefix?: string;
  
  /**
   * List of valid device types for provisioning
   * @default ['temperature-sensor', 'humidity-sensor', 'pressure-sensor', 'gateway']
   */
  readonly validDeviceTypes?: string[];
  
  /**
   * Enable monitoring and alerting
   * @default true
   */
  readonly enableMonitoring?: boolean;
  
  /**
   * Email address for alerts
   * @default undefined
   */
  readonly alertEmail?: string;
}

/**
 * AWS CDK Stack for IoT Device Provisioning and Certificate Management
 * 
 * This stack implements a comprehensive IoT device provisioning system with:
 * - Automated certificate generation and management
 * - Device validation through pre-provisioning hooks
 * - Hierarchical device organization with Thing Groups
 * - Granular security policies for different device types
 * - Comprehensive monitoring and alerting
 * - Device shadow initialization for immediate management
 */
export class IoTDeviceProvisioningStack extends cdk.Stack {
  // Core infrastructure resources
  public readonly deviceRegistryTable: dynamodb.Table;
  public readonly preProvisioningHookFunction: lambda.Function;
  public readonly shadowInitializerFunction: lambda.Function;
  public readonly provisioningTemplate: iot.CfnProvisioningTemplate;
  public readonly claimCertificate: iot.CfnCertificate;
  
  // Monitoring resources
  public readonly provisioningLogGroup: logs.LogGroup;
  public readonly alertingTopic?: sns.Topic;
  
  constructor(scope: Construct, id: string, props: IoTDeviceProvisioningStackProps = {}) {
    super(scope, id, props);
    
    // Configuration
    const environmentPrefix = props.environmentPrefix || 'dev';
    const validDeviceTypes = props.validDeviceTypes || ['temperature-sensor', 'humidity-sensor', 'pressure-sensor', 'gateway'];
    const enableMonitoring = props.enableMonitoring !== false;
    
    // Generate unique suffix for resources
    const uniqueSuffix = this.node.addr.substring(0, 8);
    
    // Create DynamoDB table for device registry
    this.deviceRegistryTable = this.createDeviceRegistryTable(environmentPrefix, uniqueSuffix);
    
    // Create IAM roles for Lambda functions
    const lambdaExecutionRole = this.createLambdaExecutionRole(environmentPrefix, uniqueSuffix);
    
    // Create pre-provisioning hook Lambda function
    this.preProvisioningHookFunction = this.createPreProvisioningHookFunction(
      environmentPrefix,
      uniqueSuffix,
      lambdaExecutionRole,
      validDeviceTypes
    );
    
    // Create shadow initializer Lambda function
    this.shadowInitializerFunction = this.createShadowInitializerFunction(
      environmentPrefix,
      uniqueSuffix,
      lambdaExecutionRole
    );
    
    // Create Thing Groups for device organization
    this.createThingGroups(environmentPrefix, uniqueSuffix, validDeviceTypes);
    
    // Create IoT policies for different device types
    this.createIoTPolicies(validDeviceTypes);
    
    // Create IAM role for IoT provisioning
    const iotProvisioningRole = this.createIoTProvisioningRole(environmentPrefix, uniqueSuffix);
    
    // Create provisioning template
    this.provisioningTemplate = this.createProvisioningTemplate(
      environmentPrefix,
      uniqueSuffix,
      iotProvisioningRole,
      this.preProvisioningHookFunction
    );
    
    // Create claim certificate for device manufacturing
    this.claimCertificate = this.createClaimCertificate(environmentPrefix, uniqueSuffix);
    
    // Set up monitoring and alerting if enabled
    if (enableMonitoring) {
      this.setupMonitoring(environmentPrefix, uniqueSuffix, props.alertEmail);
    }
    
    // Create stack outputs
    this.createOutputs(environmentPrefix, uniqueSuffix);
  }
  
  /**
   * Creates the DynamoDB table for device registry
   */
  private createDeviceRegistryTable(environmentPrefix: string, uniqueSuffix: string): dynamodb.Table {
    const table = new dynamodb.Table(this, 'DeviceRegistryTable', {
      tableName: `${environmentPrefix}-device-registry-${uniqueSuffix}`,
      partitionKey: {
        name: 'serialNumber',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED
    });
    
    // Add Global Secondary Index for device type queries
    table.addGlobalSecondaryIndex({
      indexName: 'DeviceTypeIndex',
      partitionKey: {
        name: 'deviceType',
        type: dynamodb.AttributeType.STRING
      },
      projectionType: dynamodb.ProjectionType.ALL
    });
    
    // Add tags
    cdk.Tags.of(table).add('Project', 'IoTProvisioning');
    cdk.Tags.of(table).add('Environment', environmentPrefix);
    
    return table;
  }
  
  /**
   * Creates the IAM execution role for Lambda functions
   */
  private createLambdaExecutionRole(environmentPrefix: string, uniqueSuffix: string): iam.Role {
    const role = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${environmentPrefix}-iot-provisioning-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });
    
    // Add permissions for DynamoDB access
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:GetItem',
        'dynamodb:PutItem',
        'dynamodb:UpdateItem',
        'dynamodb:Query'
      ],
      resources: [
        this.deviceRegistryTable.tableArn,
        `${this.deviceRegistryTable.tableArn}/*`
      ]
    }));
    
    // Add permissions for IoT operations
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'iot:DescribeThing',
        'iot:ListThingTypes',
        'iot:UpdateThingShadow',
        'iot:GetThingShadow'
      ],
      resources: ['*']
    }));
    
    return role;
  }
  
  /**
   * Creates the pre-provisioning hook Lambda function
   */
  private createPreProvisioningHookFunction(
    environmentPrefix: string,
    uniqueSuffix: string,
    executionRole: iam.Role,
    validDeviceTypes: string[]
  ): lambda.Function {
    const functionCode = `
import json
import boto3
import logging
from datetime import datetime, timezone
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
iot = boto3.client('iot')

def lambda_handler(event, context):
    """
    Pre-provisioning hook to validate and authorize device provisioning
    """
    try:
        # Extract device information from provisioning request
        certificate_pem = event.get('certificatePem', '')
        template_arn = event.get('templateArn', '')
        parameters = event.get('parameters', {})
        
        serial_number = parameters.get('SerialNumber', '')
        device_type = parameters.get('DeviceType', '')
        firmware_version = parameters.get('FirmwareVersion', '')
        manufacturer = parameters.get('Manufacturer', '')
        
        logger.info(f"Processing provisioning request for device: {serial_number}")
        
        # Validate required parameters
        if not all([serial_number, device_type, manufacturer]):
            return create_response(False, "Missing required device parameters")
        
        # Validate device type
        valid_device_types = os.environ.get('VALID_DEVICE_TYPES', '').split(',')
        if device_type not in valid_device_types:
            return create_response(False, f"Invalid device type: {device_type}")
        
        # Check if device is already registered
        table = dynamodb.Table(os.environ['DEVICE_REGISTRY_TABLE'])
        
        try:
            response = table.get_item(Key={'serialNumber': serial_number})
            if 'Item' in response:
                existing_status = response['Item'].get('status', '')
                if existing_status == 'provisioned':
                    return create_response(False, "Device already provisioned")
                elif existing_status == 'revoked':
                    return create_response(False, "Device has been revoked")
        except Exception as e:
            logger.error(f"Error checking device registry: {str(e)}")
        
        # Validate firmware version (basic check)
        if firmware_version and not firmware_version.startswith('v'):
            return create_response(False, "Invalid firmware version format")
        
        # Store device information in registry
        try:
            device_item = {
                'serialNumber': serial_number,
                'deviceType': device_type,
                'manufacturer': manufacturer,
                'firmwareVersion': firmware_version,
                'status': 'provisioning',
                'provisioningTimestamp': datetime.now(timezone.utc).isoformat(),
                'templateArn': template_arn
            }
            
            table.put_item(Item=device_item)
            logger.info(f"Device {serial_number} registered in device registry")
            
        except Exception as e:
            logger.error(f"Error storing device in registry: {str(e)}")
            return create_response(False, "Failed to register device")
        
        # Determine thing group based on device type
        thing_group = f"{device_type}-devices"
        
        # Create response with device-specific parameters
        response_parameters = {
            'ThingName': f"{device_type}-{serial_number}",
            'ThingGroupName': thing_group,
            'DeviceLocation': parameters.get('Location', 'unknown'),
            'ProvisioningTime': datetime.now(timezone.utc).isoformat()
        }
        
        return create_response(True, "Device validation successful", response_parameters)
        
    except Exception as e:
        logger.error(f"Unexpected error in provisioning hook: {str(e)}")
        return create_response(False, "Internal provisioning error")

def create_response(allow_provisioning, message, parameters=None):
    """Create standardized response for provisioning hook"""
    response = {
        'allowProvisioning': allow_provisioning,
        'message': message
    }
    
    if parameters:
        response['parameters'] = parameters
    
    logger.info(f"Provisioning response: {response}")
    return response
    `;
    
    const func = new lambda.Function(this, 'PreProvisioningHookFunction', {
      functionName: `${environmentPrefix}-device-provisioning-hook-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(functionCode),
      role: executionRole,
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        DEVICE_REGISTRY_TABLE: this.deviceRegistryTable.tableName,
        VALID_DEVICE_TYPES: validDeviceTypes.join(',')
      }
    });
    
    // Add tags
    cdk.Tags.of(func).add('Project', 'IoTProvisioning');
    cdk.Tags.of(func).add('Environment', environmentPrefix);
    
    return func;
  }
  
  /**
   * Creates the shadow initializer Lambda function
   */
  private createShadowInitializerFunction(
    environmentPrefix: string,
    uniqueSuffix: string,
    executionRole: iam.Role
  ): lambda.Function {
    const functionCode = `
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_data = boto3.client('iot-data')

def lambda_handler(event, context):
    """Initialize device shadow after successful provisioning"""
    try:
        # Extract thing name from the event
        thing_name = event.get('thingName', '')
        device_type = event.get('deviceType', '')
        
        if not thing_name:
            logger.error("Thing name not provided in event")
            return {'statusCode': 400, 'body': 'Thing name required'}
        
        # Create initial shadow document based on device type
        if device_type == 'temperature-sensor':
            initial_shadow = {
                "state": {
                    "desired": {
                        "samplingRate": 30,
                        "temperatureUnit": "celsius",
                        "alertThreshold": 80,
                        "enabled": True
                    }
                }
            }
        elif device_type == 'gateway':
            initial_shadow = {
                "state": {
                    "desired": {
                        "connectionTimeout": 30,
                        "bufferSize": 100,
                        "compressionEnabled": True,
                        "logLevel": "INFO"
                    }
                }
            }
        else:
            initial_shadow = {
                "state": {
                    "desired": {
                        "enabled": True,
                        "reportingInterval": 60
                    }
                }
            }
        
        # Update device shadow
        iot_data.update_thing_shadow(
            thingName=thing_name,
            payload=json.dumps(initial_shadow)
        )
        
        logger.info(f"Initialized shadow for device: {thing_name}")
        return {
            'statusCode': 200,
            'body': json.dumps(f'Shadow initialized for {thing_name}')
        }
        
    except Exception as e:
        logger.error(f"Error initializing shadow: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
    `;
    
    const func = new lambda.Function(this, 'ShadowInitializerFunction', {
      functionName: `${environmentPrefix}-device-shadow-initializer-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(functionCode),
      role: executionRole,
      timeout: Duration.seconds(30),
      memorySize: 256
    });
    
    // Add IoT data permissions
    func.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['iot:UpdateThingShadow'],
      resources: ['*']
    }));
    
    // Add tags
    cdk.Tags.of(func).add('Project', 'IoTProvisioning');
    cdk.Tags.of(func).add('Environment', environmentPrefix);
    
    return func;
  }
  
  /**
   * Creates Thing Groups for device organization
   */
  private createThingGroups(environmentPrefix: string, uniqueSuffix: string, validDeviceTypes: string[]): void {
    // Create parent thing group
    const parentGroupName = `${environmentPrefix}-provisioned-devices-${uniqueSuffix}`;
    const parentGroup = new iot.CfnThingGroup(this, 'ParentThingGroup', {
      thingGroupName: parentGroupName,
      thingGroupProperties: {
        thingGroupDescription: 'Parent group for all provisioned devices'
      }
    });
    
    // Create device-type specific thing groups
    validDeviceTypes.forEach((deviceType, index) => {
      new iot.CfnThingGroup(this, `${deviceType}ThingGroup`, {
        thingGroupName: `${deviceType}-devices`,
        thingGroupProperties: {
          thingGroupDescription: `${deviceType} devices`,
          parentGroupName: parentGroupName
        }
      });
    });
  }
  
  /**
   * Creates IoT policies for different device types
   */
  private createIoTPolicies(validDeviceTypes: string[]): void {
    const region = this.region;
    const account = this.account;
    
    // Create policy for temperature sensors
    if (validDeviceTypes.includes('temperature-sensor')) {
      new iot.CfnPolicy(this, 'TemperatureSensorPolicy', {
        policyName: 'TemperatureSensorPolicy',
        policyDocument: {
          Version: '2012-10-17',
          Statement: [
            {
              Effect: 'Allow',
              Action: ['iot:Connect'],
              Resource: `arn:aws:iot:${region}:${account}:client/temperature-sensor-*`
            },
            {
              Effect: 'Allow',
              Action: ['iot:Publish'],
              Resource: `arn:aws:iot:${region}:${account}:topic/sensors/temperature/*`
            },
            {
              Effect: 'Allow',
              Action: ['iot:Subscribe', 'iot:Receive'],
              Resource: [
                `arn:aws:iot:${region}:${account}:topicfilter/config/temperature-sensor/*`,
                `arn:aws:iot:${region}:${account}:topic/config/temperature-sensor/*`
              ]
            },
            {
              Effect: 'Allow',
              Action: ['iot:GetThingShadow', 'iot:UpdateThingShadow'],
              Resource: `arn:aws:iot:${region}:${account}:thing/temperature-sensor-*`
            }
          ]
        }
      });
    }
    
    // Create policy for gateway devices
    if (validDeviceTypes.includes('gateway')) {
      new iot.CfnPolicy(this, 'GatewayDevicePolicy', {
        policyName: 'GatewayDevicePolicy',
        policyDocument: {
          Version: '2012-10-17',
          Statement: [
            {
              Effect: 'Allow',
              Action: ['iot:Connect'],
              Resource: `arn:aws:iot:${region}:${account}:client/gateway-*`
            },
            {
              Effect: 'Allow',
              Action: ['iot:Publish'],
              Resource: [
                `arn:aws:iot:${region}:${account}:topic/gateway/*`,
                `arn:aws:iot:${region}:${account}:topic/sensors/*`
              ]
            },
            {
              Effect: 'Allow',
              Action: ['iot:Subscribe', 'iot:Receive'],
              Resource: [
                `arn:aws:iot:${region}:${account}:topicfilter/config/gateway/*`,
                `arn:aws:iot:${region}:${account}:topic/config/gateway/*`,
                `arn:aws:iot:${region}:${account}:topicfilter/commands/*`,
                `arn:aws:iot:${region}:${account}:topic/commands/*`
              ]
            },
            {
              Effect: 'Allow',
              Action: ['iot:GetThingShadow', 'iot:UpdateThingShadow'],
              Resource: `arn:aws:iot:${region}:${account}:thing/gateway-*`
            }
          ]
        }
      });
    }
  }
  
  /**
   * Creates the IAM role for IoT provisioning
   */
  private createIoTProvisioningRole(environmentPrefix: string, uniqueSuffix: string): iam.Role {
    const role = new iam.Role(this, 'IoTProvisioningRole', {
      roleName: `${environmentPrefix}-iot-provisioning-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com')
    });
    
    // Add permissions for provisioning operations
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'iot:CreateThing',
        'iot:DescribeThing',
        'iot:CreateKeysAndCertificate',
        'iot:AttachThingPrincipal',
        'iot:AttachPolicy',
        'iot:AddThingToThingGroup',
        'iot:UpdateThingShadow'
      ],
      resources: ['*']
    }));
    
    // Add permission to invoke Lambda function
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['lambda:InvokeFunction'],
      resources: [this.preProvisioningHookFunction.functionArn]
    }));
    
    return role;
  }
  
  /**
   * Creates the provisioning template
   */
  private createProvisioningTemplate(
    environmentPrefix: string,
    uniqueSuffix: string,
    provisioningRole: iam.Role,
    hookFunction: lambda.Function
  ): iot.CfnProvisioningTemplate {
    const templateName = `${environmentPrefix}-device-provisioning-template-${uniqueSuffix}`;
    
    const templateBody = {
      Parameters: {
        SerialNumber: { Type: 'String' },
        DeviceType: { Type: 'String' },
        FirmwareVersion: { Type: 'String' },
        Manufacturer: { Type: 'String' },
        Location: { Type: 'String' },
        'AWS::IoT::Certificate::Id': { Type: 'String' },
        'AWS::IoT::Certificate::Arn': { Type: 'String' }
      },
      Resources: {
        thing: {
          Type: 'AWS::IoT::Thing',
          Properties: {
            ThingName: { Ref: 'ThingName' },
            AttributePayload: {
              serialNumber: { Ref: 'SerialNumber' },
              deviceType: { Ref: 'DeviceType' },
              firmwareVersion: { Ref: 'FirmwareVersion' },
              manufacturer: { Ref: 'Manufacturer' },
              location: { Ref: 'DeviceLocation' },
              provisioningTime: { Ref: 'ProvisioningTime' }
            },
            ThingTypeName: 'IoTDevice'
          }
        },
        certificate: {
          Type: 'AWS::IoT::Certificate',
          Properties: {
            CertificateId: { Ref: 'AWS::IoT::Certificate::Id' },
            Status: 'Active'
          }
        },
        policy: {
          Type: 'AWS::IoT::Policy',
          Properties: {
            PolicyName: { 'Fn::Sub': '${DeviceType}Policy' }
          }
        },
        thingGroup: {
          Type: 'AWS::IoT::ThingGroup',
          Properties: {
            ThingGroupName: { Ref: 'ThingGroupName' }
          }
        }
      }
    };
    
    const template = new iot.CfnProvisioningTemplate(this, 'ProvisioningTemplate', {
      templateName,
      description: 'Template for automated device provisioning with validation',
      templateBody: JSON.stringify(templateBody),
      enabled: true,
      provisioningRoleArn: provisioningRole.roleArn,
      preProvisioningHook: {
        targetArn: hookFunction.functionArn,
        payloadVersion: '2020-04-01'
      }
    });
    
    // Add tags
    cdk.Tags.of(template).add('Project', 'IoTProvisioning');
    cdk.Tags.of(template).add('Environment', environmentPrefix);
    
    return template;
  }
  
  /**
   * Creates the claim certificate for device manufacturing
   */
  private createClaimCertificate(environmentPrefix: string, uniqueSuffix: string): iot.CfnCertificate {
    // Create claim certificate policy
    const claimPolicy = new iot.CfnPolicy(this, 'ClaimCertificatePolicy', {
      policyName: 'ClaimCertificatePolicy',
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: ['iot:Connect'],
            Resource: '*'
          },
          {
            Effect: 'Allow',
            Action: ['iot:Publish'],
            Resource: `arn:aws:iot:${this.region}:${this.account}:topic/$aws/provisioning-templates/${environmentPrefix}-device-provisioning-template-${uniqueSuffix}/provision/*`
          },
          {
            Effect: 'Allow',
            Action: ['iot:Subscribe', 'iot:Receive'],
            Resource: `arn:aws:iot:${this.region}:${this.account}:topicfilter/$aws/provisioning-templates/${environmentPrefix}-device-provisioning-template-${uniqueSuffix}/provision/*`
          }
        ]
      }
    });
    
    // Create claim certificate
    const claimCert = new iot.CfnCertificate(this, 'ClaimCertificate', {
      status: 'ACTIVE'
    });
    
    // Attach policy to claim certificate
    new iot.CfnPolicyPrincipalAttachment(this, 'ClaimCertificatePolicyAttachment', {
      policyName: claimPolicy.policyName!,
      principal: claimCert.attrArn
    });
    
    return claimCert;
  }
  
  /**
   * Sets up monitoring and alerting
   */
  private setupMonitoring(environmentPrefix: string, uniqueSuffix: string, alertEmail?: string): void {
    // Create CloudWatch log group for provisioning monitoring
    this.provisioningLogGroup = new logs.LogGroup(this, 'ProvisioningLogGroup', {
      logGroupName: '/aws/iot/provisioning',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY
    });
    
    // Create SNS topic for alerts if email is provided
    if (alertEmail) {
      this.alertingTopic = new sns.Topic(this, 'ProvisioningAlertsTopic', {
        topicName: `${environmentPrefix}-provisioning-alerts-${uniqueSuffix}`,
        displayName: 'IoT Provisioning Alerts'
      });
      
      // Add email subscription
      this.alertingTopic.addSubscription(
        new sns.EmailSubscription(alertEmail)
      );
    }
    
    // Create CloudWatch alarm for failed provisioning attempts
    const failureAlarm = new cloudwatch.Alarm(this, 'ProvisioningFailuresAlarm', {
      alarmName: `${environmentPrefix}-IoTProvisioningFailures-${uniqueSuffix}`,
      alarmDescription: 'Monitor failed device provisioning attempts',
      metric: this.preProvisioningHookFunction.metricErrors({
        period: Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });
    
    // Add SNS action to alarm if topic exists
    if (this.alertingTopic) {
      failureAlarm.addAlarmAction(
        new cloudwatch_actions.SnsAction(this.alertingTopic)
      );
    }
    
    // Create IoT rule to log provisioning events
    const auditRule = new iot.CfnTopicRule(this, 'ProvisioningAuditRule', {
      ruleName: 'ProvisioningAuditRule',
      topicRulePayload: {
        sql: 'SELECT * FROM "$aws/events/provisioning/template/+/+"',
        description: 'Log all provisioning events for audit',
        actions: [
          {
            cloudwatchLogs: {
              logGroupName: this.provisioningLogGroup.logGroupName,
              roleArn: this.createCloudWatchLogsRole().roleArn
            }
          }
        ]
      }
    });
  }
  
  /**
   * Creates IAM role for CloudWatch Logs
   */
  private createCloudWatchLogsRole(): iam.Role {
    const role = new iam.Role(this, 'CloudWatchLogsRole', {
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com')
    });
    
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents'
      ],
      resources: [this.provisioningLogGroup.logGroupArn]
    }));
    
    return role;
  }
  
  /**
   * Creates stack outputs
   */
  private createOutputs(environmentPrefix: string, uniqueSuffix: string): void {
    new cdk.CfnOutput(this, 'DeviceRegistryTableName', {
      value: this.deviceRegistryTable.tableName,
      description: 'Name of the device registry DynamoDB table',
      exportName: `${environmentPrefix}-device-registry-table-${uniqueSuffix}`
    });
    
    new cdk.CfnOutput(this, 'PreProvisioningHookFunctionArn', {
      value: this.preProvisioningHookFunction.functionArn,
      description: 'ARN of the pre-provisioning hook Lambda function',
      exportName: `${environmentPrefix}-pre-provisioning-hook-${uniqueSuffix}`
    });
    
    new cdk.CfnOutput(this, 'ProvisioningTemplateName', {
      value: this.provisioningTemplate.templateName!,
      description: 'Name of the IoT provisioning template',
      exportName: `${environmentPrefix}-provisioning-template-${uniqueSuffix}`
    });
    
    new cdk.CfnOutput(this, 'ClaimCertificateArn', {
      value: this.claimCertificate.attrArn,
      description: 'ARN of the claim certificate for device manufacturing',
      exportName: `${environmentPrefix}-claim-certificate-${uniqueSuffix}`
    });
    
    new cdk.CfnOutput(this, 'ClaimCertificateId', {
      value: this.claimCertificate.ref,
      description: 'ID of the claim certificate for device manufacturing',
      exportName: `${environmentPrefix}-claim-certificate-id-${uniqueSuffix}`
    });
    
    if (this.alertingTopic) {
      new cdk.CfnOutput(this, 'AlertingTopicArn', {
        value: this.alertingTopic.topicArn,
        description: 'ARN of the SNS topic for provisioning alerts',
        exportName: `${environmentPrefix}-alerting-topic-${uniqueSuffix}`
      });
    }
  }
}

/**
 * Main CDK App
 */
class IoTDeviceProvisioningApp extends cdk.App {
  constructor() {
    super();
    
    // Get configuration from context or environment
    const environmentPrefix = this.node.tryGetContext('environmentPrefix') || process.env.ENVIRONMENT_PREFIX || 'dev';
    const alertEmail = this.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;
    const enableMonitoring = this.node.tryGetContext('enableMonitoring') !== 'false';
    
    // Create the stack
    new IoTDeviceProvisioningStack(this, 'IoTDeviceProvisioningStack', {
      environmentPrefix,
      alertEmail,
      enableMonitoring,
      description: 'AWS IoT Device Provisioning and Certificate Management Stack',
      tags: {
        Project: 'IoTProvisioning',
        Environment: environmentPrefix,
        ManagedBy: 'CDK'
      }
    });
  }
}

// Initialize the CDK app
new IoTDeviceProvisioningApp();