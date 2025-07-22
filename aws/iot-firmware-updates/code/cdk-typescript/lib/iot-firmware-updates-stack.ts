import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as signer from 'aws-cdk-lib/aws-signer';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import { Construct } from 'constructs';

export interface IoTFirmwareUpdatesStackProps extends cdk.StackProps {
  environment: string;
}

export class IoTFirmwareUpdatesStack extends cdk.Stack {
  public readonly firmwareBucket: s3.Bucket;
  public readonly firmwareUpdateFunction: lambda.Function;
  public readonly signingProfile: signer.SigningProfile;
  public readonly deviceThing: iot.CfnThing;
  public readonly deviceThingGroup: iot.CfnThingGroup;

  constructor(scope: Construct, id: string, props: IoTFirmwareUpdatesStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const suffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);

    // ============================================================================
    // S3 Bucket for Firmware Storage
    // ============================================================================
    
    this.firmwareBucket = new s3.Bucket(this, 'FirmwareBucket', {
      bucketName: `firmware-updates-${suffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'FirmwareRetention',
          enabled: true,
          expiration: cdk.Duration.days(365),
          noncurrentVersionExpiration: cdk.Duration.days(90),
        }
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Add bucket policy for secure access
    this.firmwareBucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'DenyInsecureConnections',
      effect: iam.Effect.DENY,
      principals: [new iam.AnyPrincipal()],
      actions: ['s3:*'],
      resources: [
        this.firmwareBucket.bucketArn,
        this.firmwareBucket.arnForObjects('*')
      ],
      conditions: {
        Bool: {
          'aws:SecureTransport': 'false'
        }
      }
    }));

    // ============================================================================
    // Code Signing Profile
    // ============================================================================
    
    this.signingProfile = new signer.SigningProfile(this, 'FirmwareSigningProfile', {
      signatureValidityPeriod: cdk.Duration.days(365),
      platformId: signer.Platform.AMAZON_FREE_RTOS_TI_CC3220SF,
      description: 'Code signing profile for IoT firmware updates'
    });

    // ============================================================================
    // IAM Roles
    // ============================================================================
    
    // Role for IoT Jobs to access S3 firmware
    const iotJobsRole = new iam.Role(this, 'IoTJobsRole', {
      roleName: `IoTJobsRole-${suffix}`,
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      description: 'Role for IoT Jobs to access firmware in S3',
      inlinePolicies: {
        S3FirmwareAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion'
              ],
              resources: [this.firmwareBucket.arnForObjects('*')]
            })
          ]
        })
      }
    });

    // Role for Lambda function
    const lambdaRole = new iam.Role(this, 'FirmwareUpdateLambdaRole', {
      roleName: `FirmwareUpdateLambdaRole-${suffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for firmware update management Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        FirmwareUpdatePermissions: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iot:CreateJob',
                'iot:DescribeJob',
                'iot:ListJobs',
                'iot:UpdateJob',
                'iot:CancelJob',
                'iot:DeleteJob',
                'iot:ListJobExecutionsForJob',
                'iot:ListJobExecutionsForThing',
                'iot:DescribeJobExecution'
              ],
              resources: ['*']
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetObjectVersion'
              ],
              resources: [
                this.firmwareBucket.bucketArn,
                this.firmwareBucket.arnForObjects('*')
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'signer:StartSigningJob',
                'signer:DescribeSigningJob',
                'signer:ListSigningJobs'
              ],
              resources: ['*']
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // ============================================================================
    // Lambda Function for Job Management
    // ============================================================================
    
    this.firmwareUpdateFunction = new lambda.Function(this, 'FirmwareUpdateManager', {
      functionName: `firmware-update-manager-${suffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Manages IoT firmware update jobs',
      environment: {
        FIRMWARE_BUCKET: this.firmwareBucket.bucketName,
        SIGNING_PROFILE_NAME: this.signingProfile.signingProfileName,
        IOT_JOBS_ROLE_ARN: iotJobsRole.roleArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    iot_client = boto3.client('iot')
    s3_client = boto3.client('s3')
    signer_client = boto3.client('signer')
    
    action = event.get('action')
    
    try:
        if action == 'create_job':
            return create_firmware_job(event, iot_client, s3_client)
        elif action == 'check_job_status':
            return check_job_status(event, iot_client)
        elif action == 'cancel_job':
            return cancel_job(event, iot_client)
        elif action == 'list_jobs':
            return list_jobs(event, iot_client)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid action. Supported actions: create_job, check_job_status, cancel_job, list_jobs'})
            }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_firmware_job(event, iot_client, s3_client):
    firmware_version = event['firmware_version']
    thing_group = event['thing_group']
    s3_bucket = event.get('s3_bucket', os.environ['FIRMWARE_BUCKET'])
    s3_key = event['s3_key']
    
    # Create job document
    job_document = {
        "operation": "firmware_update",
        "firmware": {
            "version": firmware_version,
            "url": f"https://{s3_bucket}.s3.amazonaws.com/{s3_key}",
            "size": get_object_size(s3_client, s3_bucket, s3_key),
            "checksum": get_object_checksum(s3_client, s3_bucket, s3_key)
        },
        "steps": [
            "download_firmware",
            "verify_signature", 
            "backup_current_firmware",
            "install_firmware",
            "verify_installation",
            "report_status"
        ]
    }
    
    # Create unique job ID
    job_id = f"firmware-update-{firmware_version}-{uuid.uuid4().hex[:8]}"
    
    # Get AWS account ID and region
    region = boto3.Session().region_name
    account_id = boto3.client('sts').get_caller_identity()['Account']
    
    # Create the job
    response = iot_client.create_job(
        jobId=job_id,
        targets=[f"arn:aws:iot:{region}:{account_id}:thinggroup/{thing_group}"],
        document=json.dumps(job_document),
        description=f"Firmware update to version {firmware_version}",
        targetSelection='SNAPSHOT',
        jobExecutionsRolloutConfig={
            'maximumPerMinute': 10,
            'exponentialRate': {
                'baseRatePerMinute': 5,
                'incrementFactor': 2.0,
                'rateIncreaseCriteria': {
                    'numberOfNotifiedThings': 10,
                    'numberOfSucceededThings': 5
                }
            }
        },
        abortConfig={
            'criteriaList': [
                {
                    'failureType': 'FAILED',
                    'action': 'CANCEL',
                    'thresholdPercentage': 20.0,
                    'minNumberOfExecutedThings': 5
                }
            ]
        },
        timeoutConfig={
            'inProgressTimeoutInMinutes': 60
        }
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'job_id': job_id,
            'job_arn': response['jobArn'],
            'message': 'Firmware update job created successfully'
        })
    }

def check_job_status(event, iot_client):
    job_id = event['job_id']
    
    response = iot_client.describe_job(jobId=job_id)
    job_executions = iot_client.list_job_executions_for_job(jobId=job_id)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'job_id': job_id,
            'status': response['job']['status'],
            'process_details': response['job']['jobProcessDetails'],
            'executions': job_executions['executionSummaries']
        })
    }

def cancel_job(event, iot_client):
    job_id = event['job_id']
    
    iot_client.cancel_job(
        jobId=job_id,
        reasonCode='USER_INITIATED',
        comment='Job cancelled by user'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'job_id': job_id,
            'message': 'Job cancelled successfully'
        })
    }

def list_jobs(event, iot_client):
    response = iot_client.list_jobs(
        status='IN_PROGRESS',
        maxResults=50
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'jobs': response['jobs']
        })
    }

def get_object_size(s3_client, bucket, key):
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response['ContentLength']
    except Exception:
        return 0

def get_object_checksum(s3_client, bucket, key):
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response.get('ETag', '').replace('"', '')
    except Exception:
        return ''
`)
    });

    // ============================================================================
    // IoT Things and Thing Groups
    // ============================================================================
    
    // Create Thing Group for firmware updates
    this.deviceThingGroup = new iot.CfnThingGroup(this, 'FirmwareUpdateThingGroup', {
      thingGroupName: `firmware-update-group-${suffix}`,
      thingGroupProperties: {
        thingGroupDescription: 'Devices eligible for firmware updates',
        attributePayload: {
          attributes: {
            Environment: props.environment,
            UpdatePolicy: 'automatic',
            CreatedBy: 'CDK'
          }
        }
      }
    });

    // Create sample IoT Thing for testing
    this.deviceThing = new iot.CfnThing(this, 'SampleIoTDevice', {
      thingName: `iot-device-${suffix}`,
      attributePayload: {
        attributes: {
          DeviceType: 'sensor',
          FirmwareVersion: '0.9.0',
          Environment: props.environment
        }
      }
    });

    // Add Thing to Thing Group
    new iot.CfnThingGroupInfo(this, 'ThingGroupMembership', {
      thingGroupName: this.deviceThingGroup.thingGroupName!,
      thingName: this.deviceThing.thingName!
    });

    // ============================================================================
    // CloudWatch Dashboard
    // ============================================================================
    
    const dashboard = new cloudwatch.Dashboard(this, 'IoTFirmwareUpdatesDashboard', {
      dashboardName: `iot-firmware-updates-${props.environment}`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'IoT Jobs Status',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'JobsCompleted',
            statistic: 'Sum'
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'JobsFailed',
            statistic: 'Sum'
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/IoT',
            metricName: 'JobsInProgress',
            statistic: 'Sum'
          })
        ],
        width: 12,
        height: 6
      }),
      new cloudwatch.LogQueryWidget({
        title: 'Firmware Update Manager Logs',
        logGroups: [this.firmwareUpdateFunction.logGroup],
        view: cloudwatch.LogQueryVisualizationType.TABLE,
        queryLines: [
          'fields @timestamp, @message',
          'sort @timestamp desc',
          'limit 100'
        ],
        width: 24,
        height: 6
      })
    );

    // ============================================================================
    // SNS Topic for Notifications
    // ============================================================================
    
    const notificationTopic = new sns.Topic(this, 'FirmwareUpdateNotifications', {
      topicName: `firmware-update-notifications-${suffix}`,
      displayName: 'IoT Firmware Update Notifications',
      description: 'Notifications for firmware update job status changes'
    });

    // ============================================================================
    // EventBridge Rules for Job Status Monitoring
    // ============================================================================
    
    const jobStatusRule = new events.Rule(this, 'JobStatusChangeRule', {
      ruleName: `iot-job-status-change-${suffix}`,
      description: 'Captures IoT Job status changes',
      eventPattern: {
        source: ['aws.iot'],
        detailType: ['IoT Job Status Change'],
        detail: {
          status: ['SUCCEEDED', 'FAILED', 'CANCELED']
        }
      }
    });

    jobStatusRule.addTarget(new targets.SnsTopic(notificationTopic));
    jobStatusRule.addTarget(new targets.LambdaFunction(this.firmwareUpdateFunction));

    // ============================================================================
    // Outputs
    // ============================================================================
    
    new cdk.CfnOutput(this, 'FirmwareBucketName', {
      value: this.firmwareBucket.bucketName,
      description: 'S3 bucket for firmware storage',
      exportName: `${this.stackName}-FirmwareBucketName`
    });

    new cdk.CfnOutput(this, 'FirmwareBucketArn', {
      value: this.firmwareBucket.bucketArn,
      description: 'S3 bucket ARN for firmware storage',
      exportName: `${this.stackName}-FirmwareBucketArn`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.firmwareUpdateFunction.functionName,
      description: 'Lambda function for firmware update management',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.firmwareUpdateFunction.functionArn,
      description: 'Lambda function ARN',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    new cdk.CfnOutput(this, 'SigningProfileName', {
      value: this.signingProfile.signingProfileName,
      description: 'Code signing profile for firmware',
      exportName: `${this.stackName}-SigningProfileName`
    });

    new cdk.CfnOutput(this, 'ThingGroupName', {
      value: this.deviceThingGroup.thingGroupName!,
      description: 'IoT Thing Group for firmware updates',
      exportName: `${this.stackName}-ThingGroupName`
    });

    new cdk.CfnOutput(this, 'SampleThingName', {
      value: this.deviceThing.thingName!,
      description: 'Sample IoT Thing for testing',
      exportName: `${this.stackName}-SampleThingName`
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for firmware update notifications',
      exportName: `${this.stackName}-NotificationTopicArn`
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
      exportName: `${this.stackName}-DashboardURL`
    });

    new cdk.CfnOutput(this, 'IoTJobsRoleArn', {
      value: iotJobsRole.roleArn,
      description: 'IAM role ARN for IoT Jobs',
      exportName: `${this.stackName}-IoTJobsRoleArn`
    });
  }
}