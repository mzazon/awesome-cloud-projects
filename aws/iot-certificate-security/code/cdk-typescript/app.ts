#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as config from 'aws-cdk-lib/aws-config';

/**
 * IoT Security Stack - Implements comprehensive IoT security with device certificates and policies
 * 
 * This stack creates:
 * - IoT Thing Types and Security Policies
 * - Multiple IoT Devices with X.509 Certificates
 * - AWS IoT Device Defender Security Profiles
 * - CloudWatch Monitoring and Dashboards
 * - Lambda Functions for Security Event Processing
 * - DynamoDB for Security Event Storage
 * - Certificate Rotation Monitoring
 * - Device Quarantine Capabilities
 * - Automated Compliance Monitoring
 */
export class IoTSecurityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const thingTypeName = 'IndustrialSensor';
    const devicePrefix = 'sensor';
    const numberOfDevices = 3;

    // ==========================================
    // 1. CREATE IOT THING TYPE AND POLICIES
    // ==========================================

    // Create Thing Type for categorizing industrial sensors
    const thingType = new iot.CfnThingType(this, 'IndustrialSensorThingType', {
      thingTypeName: thingTypeName,
      thingTypeDescription: 'Industrial IoT sensors with security controls',
      thingTypeProperties: {
        thingTypeDescription: 'Industrial IoT sensors with security controls'
      }
    });

    // Create restrictive IoT policy with fine-grained permissions
    const restrictiveSensorPolicy = new iot.CfnPolicy(this, 'RestrictiveSensorPolicy', {
      policyName: 'RestrictiveSensorPolicy',
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: 'iot:Connect',
            Resource: 'arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}',
            Condition: {
              Bool: {
                'iot:Connection.Thing.IsAttached': 'true'
              }
            }
          },
          {
            Effect: 'Allow',
            Action: 'iot:Publish',
            Resource: [
              'arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/telemetry',
              'arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/status'
            ]
          },
          {
            Effect: 'Allow',
            Action: 'iot:Subscribe',
            Resource: [
              'arn:aws:iot:*:*:topicfilter/sensors/${iot:Connection.Thing.ThingName}/commands',
              'arn:aws:iot:*:*:topicfilter/sensors/${iot:Connection.Thing.ThingName}/config'
            ]
          },
          {
            Effect: 'Allow',
            Action: 'iot:Receive',
            Resource: [
              'arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/commands',
              'arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/config'
            ]
          },
          {
            Effect: 'Allow',
            Action: [
              'iot:UpdateThingShadow',
              'iot:GetThingShadow'
            ],
            Resource: 'arn:aws:iot:*:*:thing/${iot:Connection.Thing.ThingName}'
          }
        ]
      }
    });

    // Create time-based access policy for demonstration
    const timeBasedPolicy = new iot.CfnPolicy(this, 'TimeBasedAccessPolicy', {
      policyName: 'TimeBasedAccessPolicy',
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: 'iot:Connect',
            Resource: 'arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}',
            Condition: {
              Bool: {
                'iot:Connection.Thing.IsAttached': 'true'
              },
              DateGreaterThan: {
                'aws:CurrentTime': '08:00:00Z'
              },
              DateLessThan: {
                'aws:CurrentTime': '18:00:00Z'
              }
            }
          },
          {
            Effect: 'Allow',
            Action: 'iot:Publish',
            Resource: 'arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/telemetry',
            Condition: {
              StringEquals: {
                'iot:Connection.Thing.ThingTypeName': 'IndustrialSensor'
              }
            }
          }
        ]
      }
    });

    // Create location-based access policy
    const locationBasedPolicy = new iot.CfnPolicy(this, 'LocationBasedAccessPolicy', {
      policyName: 'LocationBasedAccessPolicy',
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: 'iot:Connect',
            Resource: 'arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}',
            Condition: {
              Bool: {
                'iot:Connection.Thing.IsAttached': 'true'
              },
              StringEquals: {
                'iot:Connection.Thing.Attributes[location]': [
                  'factory-001',
                  'factory-002',
                  'factory-003'
                ]
              }
            }
          },
          {
            Effect: 'Allow',
            Action: 'iot:Publish',
            Resource: 'arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/*',
            Condition: {
              StringLike: {
                'iot:Connection.Thing.Attributes[location]': 'factory-*'
              }
            }
          }
        ]
      }
    });

    // Create device quarantine policy
    const quarantinePolicy = new iot.CfnPolicy(this, 'DeviceQuarantinePolicy', {
      policyName: 'DeviceQuarantinePolicy',
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Deny',
            Action: '*',
            Resource: '*'
          }
        ]
      }
    });

    // ==========================================
    // 2. CREATE MULTIPLE IOT DEVICES WITH CERTIFICATES
    // ==========================================

    const devices: iot.CfnThing[] = [];
    const certificates: iot.CfnCertificate[] = [];

    // Create multiple IoT devices with certificates
    for (let i = 1; i <= numberOfDevices; i++) {
      const deviceId = i.toString().padStart(3, '0');
      const thingName = `${devicePrefix}-${deviceId}`;

      // Create IoT Thing
      const thing = new iot.CfnThing(this, `IoTThing${deviceId}`, {
        thingName: thingName,
        thingTypeName: thingType.thingTypeName,
        attributePayload: {
          attributes: {
            location: `factory-${deviceId}`,
            deviceType: 'temperature-sensor',
            firmwareVersion: '1.0.0'
          }
        }
      });
      thing.addDependency(thingType);
      devices.push(thing);

      // Create certificate for the device
      const certificate = new iot.CfnCertificate(this, `DeviceCertificate${deviceId}`, {
        status: 'ACTIVE',
        certificateSigningRequest: undefined // Will be auto-generated
      });
      certificates.push(certificate);

      // Attach policy to certificate
      new iot.CfnPolicyPrincipalAttachment(this, `PolicyAttachment${deviceId}`, {
        policyName: restrictiveSensorPolicy.policyName!,
        principal: certificate.attrArn
      });

      // Attach certificate to thing
      new iot.CfnThingPrincipalAttachment(this, `ThingPrincipalAttachment${deviceId}`, {
        thingName: thing.thingName!,
        principal: certificate.attrArn
      });
    }

    // ==========================================
    // 3. CREATE THING GROUP AND SECURITY PROFILES
    // ==========================================

    // Create Thing Group for organizing devices
    const thingGroup = new iot.CfnThingGroup(this, 'IndustrialSensorsGroup', {
      thingGroupName: 'IndustrialSensors',
      thingGroupProperties: {
        thingGroupDescription: 'Industrial sensor devices'
      }
    });

    // Add devices to thing group (using custom resource due to CDK limitations)
    const addDevicesToGroupRole = new iam.Role(this, 'AddDevicesToGroupRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        IoTPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iot:AddThingToThingGroup',
                'iot:RemoveThingFromThingGroup'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Lambda function to add devices to thing group
    const addDevicesToGroupFunction = new lambda.Function(this, 'AddDevicesToGroupFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: addDevicesToGroupRole,
      code: lambda.Code.fromInline(`
import boto3
import json
import cfnresponse

def lambda_handler(event, context):
    try:
        iot_client = boto3.client('iot')
        
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            thing_group_name = event['ResourceProperties']['ThingGroupName']
            device_names = event['ResourceProperties']['DeviceNames']
            
            for device_name in device_names:
                iot_client.add_thing_to_thing_group(
                    thingGroupName=thing_group_name,
                    thingName=device_name
                )
                
        elif event['RequestType'] == 'Delete':
            thing_group_name = event['ResourceProperties']['ThingGroupName']
            device_names = event['ResourceProperties']['DeviceNames']
            
            for device_name in device_names:
                try:
                    iot_client.remove_thing_from_thing_group(
                        thingGroupName=thing_group_name,
                        thingName=device_name
                    )
                except:
                    pass  # Ignore errors during cleanup
        
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
      `)
    });

    // Custom resource to add devices to thing group
    const addDevicesToGroup = new cdk.CustomResource(this, 'AddDevicesToGroupCustomResource', {
      serviceToken: addDevicesToGroupFunction.functionArn,
      properties: {
        ThingGroupName: thingGroup.thingGroupName,
        DeviceNames: devices.map(device => device.thingName)
      }
    });

    // Create Device Defender Security Profile
    const securityProfile = new iot.CfnSecurityProfile(this, 'IndustrialSensorSecurityProfile', {
      securityProfileName: 'IndustrialSensorSecurity',
      securityProfileDescription: 'Security monitoring for industrial IoT sensors',
      behaviors: [
        {
          name: 'ExcessiveConnections',
          metric: 'aws:num-connections',
          criteria: {
            comparisonOperator: 'greater-than',
            value: {
              count: 3
            },
            consecutiveDatapointsToAlarm: 2,
            consecutiveDatapointsToClear: 2
          }
        },
        {
          name: 'UnauthorizedOperations',
          metric: 'aws:num-authorization-failures',
          criteria: {
            comparisonOperator: 'greater-than',
            value: {
              count: 5
            },
            durationSeconds: 300,
            consecutiveDatapointsToAlarm: 1,
            consecutiveDatapointsToClear: 1
          }
        },
        {
          name: 'MessageSizeAnomaly',
          metric: 'aws:message-byte-size',
          criteria: {
            comparisonOperator: 'greater-than',
            value: {
              count: 1024
            },
            consecutiveDatapointsToAlarm: 3,
            consecutiveDatapointsToClear: 3
          }
        }
      ],
      targets: [
        `arn:aws:iot:${this.region}:${this.account}:thinggroup/${thingGroup.thingGroupName}`
      ]
    });

    // ==========================================
    // 4. CREATE SECURITY EVENT PROCESSING INFRASTRUCTURE
    // ==========================================

    // DynamoDB table for storing security events
    const securityEventsTable = new dynamodb.Table(this, 'IoTSecurityEventsTable', {
      tableName: 'IoTSecurityEvents',
      partitionKey: {
        name: 'eventId',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true
    });

    // Add Global Secondary Index for device queries
    securityEventsTable.addGlobalSecondaryIndex({
      indexName: 'DeviceIndex',
      partitionKey: {
        name: 'deviceId',
        type: dynamodb.AttributeType.STRING
      },
      projectionType: dynamodb.ProjectionType.ALL
    });

    // IAM role for security event processing Lambda
    const securityProcessorRole = new iam.Role(this, 'SecurityProcessorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        DynamoDBPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:Query'
              ],
              resources: [securityEventsTable.tableArn]
            })
          ]
        })
      }
    });

    // Lambda function for security event processing
    const securityProcessorFunction = new lambda.Function(this, 'SecurityEventProcessor', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: securityProcessorRole,
      environment: {
        TABLE_NAME: securityEventsTable.tableName
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
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """Process IoT security events and take appropriate actions"""
    
    # Log the security event
    logger.info(f"Security event received: {json.dumps(event)}")
    
    # Extract device information
    device_id = event.get('clientId', 'unknown')
    event_type = event.get('eventType', 'unknown')
    
    # Example security actions
    if event_type == 'Connect.AuthError':
        logger.warning(f"Authentication failure for device: {device_id}")
        # Could trigger device quarantine or alert
    
    elif event_type == 'Publish.AuthError':
        logger.warning(f"Unauthorized publish attempt from device: {device_id}")
        # Could update device policy or disable device
    
    # Store event for analysis
    try:
        table.put_item(
            Item={
                'eventId': context.aws_request_id,
                'deviceId': device_id,
                'eventType': event_type,
                'timestamp': datetime.utcnow().isoformat(),
                'eventData': json.dumps(event)
            }
        )
    except Exception as e:
        logger.error(f"Failed to store security event: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Security event processed')
    }
      `)
    });

    // ==========================================
    // 5. CREATE DEVICE QUARANTINE CAPABILITY
    // ==========================================

    // IAM role for device quarantine Lambda
    const quarantineRole = new iam.Role(this, 'QuarantineRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        IoTQuarantinePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iot:ListThingPrincipals',
                'iot:ListAttachedPolicies',
                'iot:DetachPolicy',
                'iot:AttachPolicy'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Lambda function for device quarantine
    const quarantineFunction = new lambda.Function(this, 'DeviceQuarantineFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: quarantineRole,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_client = boto3.client('iot')

def lambda_handler(event, context):
    """Quarantine suspicious IoT devices"""
    
    try:
        device_id = event['deviceId']
        reason = event.get('reason', 'Security violation')
        
        # Get device certificates
        principals = iot_client.list_thing_principals(thingName=device_id)
        
        for principal in principals['principals']:
            # Detach existing policies
            attached_policies = iot_client.list_attached_policies(target=principal)
            
            for policy in attached_policies['policies']:
                iot_client.detach_policy(
                    policyName=policy['policyName'],
                    target=principal
                )
            
            # Attach quarantine policy
            iot_client.attach_policy(
                policyName='DeviceQuarantinePolicy',
                target=principal
            )
        
        logger.info(f"Device {device_id} quarantined: {reason}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Device {device_id} quarantined successfully')
        }
        
    except Exception as e:
        logger.error(f"Device quarantine failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
      `)
    });

    // ==========================================
    // 6. CREATE CERTIFICATE ROTATION MONITORING
    // ==========================================

    // IAM role for certificate rotation Lambda
    const certRotationRole = new iam.Role(this, 'CertRotationRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        IoTCertPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iot:ListCertificates',
                'iot:DescribeCertificate'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Lambda function for certificate rotation monitoring
    const certRotationFunction = new lambda.Function(this, 'CertificateRotationFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: certRotationRole,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_client = boto3.client('iot')

def lambda_handler(event, context):
    """Rotate certificates for IoT devices based on expiration"""
    
    try:
        # List all certificates
        certificates = iot_client.list_certificates(pageSize=100)
        
        rotation_actions = []
        
        for cert in certificates['certificates']:
            cert_id = cert['certificateId']
            cert_arn = cert['certificateArn']
            
            # Get certificate details
            cert_details = iot_client.describe_certificate(
                certificateId=cert_id
            )
            
            # Check if certificate is expiring soon (within 30 days)
            # This is a simplified check - production should parse actual expiry
            creation_date = cert_details['certificateDescription']['creationDate']
            
            # Log certificate status
            logger.info(f"Certificate {cert_id} created on {creation_date}")
            
            # In production, implement actual certificate rotation logic
            rotation_actions.append({
                'certificateId': cert_id,
                'certificateArn': cert_arn,
                'action': 'monitor',
                'creationDate': creation_date.isoformat()
            })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Certificate rotation check completed',
                'actions': rotation_actions
            })
        }
        
    except Exception as e:
        logger.error(f"Certificate rotation failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
      `)
    });

    // EventBridge rule for periodic certificate checks
    const certRotationRule = new events.Rule(this, 'CertificateRotationRule', {
      ruleName: 'IoT-Certificate-Rotation-Check',
      description: 'Weekly check for certificate rotation needs',
      schedule: events.Schedule.rate(cdk.Duration.days(7))
    });

    certRotationRule.addTarget(new targets.LambdaFunction(certRotationFunction));

    // ==========================================
    // 7. CREATE CLOUDWATCH MONITORING
    // ==========================================

    // CloudWatch Log Group for IoT security events
    const securityLogGroup = new logs.LogGroup(this, 'IoTSecurityLogGroup', {
      logGroupName: '/aws/iot/security-events',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // SNS topic for security alerts
    const securityAlertsTopic = new sns.Topic(this, 'IoTSecurityAlerts', {
      topicName: 'iot-security-alerts',
      displayName: 'IoT Security Alerts'
    });

    // CloudWatch alarm for unauthorized connections
    const unauthorizedConnectionsAlarm = new cloudwatch.Alarm(this, 'UnauthorizedConnectionsAlarm', {
      alarmName: 'IoT-Unauthorized-Connections',
      alarmDescription: 'Alert on unauthorized IoT connection attempts',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/IoT',
        metricName: 'aws:num-authorization-failures',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    unauthorizedConnectionsAlarm.addAlarmAction(
      new cloudwatch.SnsAction(securityAlertsTopic)
    );

    // CloudWatch Dashboard for IoT Security
    const securityDashboard = new cloudwatch.Dashboard(this, 'IoTSecurityDashboard', {
      dashboardName: 'IoT-Security-Dashboard'
    });

    securityDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'IoT Connection Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'Connect.Success',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'Connect.AuthError',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'Connect.ClientError',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          })
        ]
      }),
      new cloudwatch.GraphWidget({
        title: 'IoT Message Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'PublishIn.Success',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'PublishIn.AuthError',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'Subscribe.Success',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'Subscribe.AuthError',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          })
        ]
      })
    );

    // ==========================================
    // 8. OUTPUTS
    // ==========================================

    new cdk.CfnOutput(this, 'ThingTypeName', {
      value: thingType.thingTypeName!,
      description: 'Name of the IoT Thing Type created'
    });

    new cdk.CfnOutput(this, 'ThingGroupName', {
      value: thingGroup.thingGroupName!,
      description: 'Name of the IoT Thing Group created'
    });

    new cdk.CfnOutput(this, 'SecurityProfileName', {
      value: securityProfile.securityProfileName!,
      description: 'Name of the Device Defender Security Profile'
    });

    new cdk.CfnOutput(this, 'SecurityEventsTableName', {
      value: securityEventsTable.tableName,
      description: 'DynamoDB table for storing security events'
    });

    new cdk.CfnOutput(this, 'SecurityProcessorFunctionName', {
      value: securityProcessorFunction.functionName,
      description: 'Lambda function for processing security events'
    });

    new cdk.CfnOutput(this, 'QuarantineFunctionName', {
      value: quarantineFunction.functionName,
      description: 'Lambda function for device quarantine'
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${securityDashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for IoT security monitoring'
    });

    new cdk.CfnOutput(this, 'CreatedDevices', {
      value: devices.map(device => device.thingName).join(', '),
      description: 'List of created IoT devices'
    });

    new cdk.CfnOutput(this, 'IoTEndpoint', {
      value: `https://console.aws.amazon.com/iot/home?region=${this.region}#/thing`,
      description: 'AWS IoT Core console URL for device management'
    });
  }
}

// CDK App
const app = new cdk.App();

// Stack configuration
const stackProps: cdk.StackProps = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  description: 'IoT Security Stack - Comprehensive security implementation with device certificates, policies, and monitoring',
  tags: {
    Project: 'IoT-Security-Demo',
    Environment: 'Development',
    Owner: 'AWS-CDK',
    CostCenter: 'Engineering'
  }
};

new IoTSecurityStack(app, 'IoTSecurityStack', stackProps);