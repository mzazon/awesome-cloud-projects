#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sagemaker from 'aws-cdk-lib/aws-sagemaker';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the SageMaker Model Monitor Stack
 */
export interface SageMakerModelMonitorStackProps extends cdk.StackProps {
  /** Email address for monitoring alerts */
  readonly alertEmail?: string;
  /** SageMaker instance type for monitoring jobs */
  readonly monitoringInstanceType?: string;
  /** SageMaker instance type for model endpoint */
  readonly endpointInstanceType?: string;
  /** Enable data capture on the endpoint */
  readonly enableDataCapture?: boolean;
  /** Data capture sampling percentage (0-100) */
  readonly dataCapturePercentage?: number;
}

/**
 * CDK Stack for SageMaker Model Monitor with drift detection
 * 
 * This stack creates a complete MLOps monitoring solution including:
 * - SageMaker Model and Endpoint with data capture
 * - Model Monitor baseline and monitoring schedules
 * - CloudWatch alarms and dashboards
 * - SNS notifications and Lambda response handlers
 * - S3 storage for monitoring artifacts
 */
export class SageMakerModelMonitorStack extends cdk.Stack {
  public readonly monitoringBucket: s3.Bucket;
  public readonly modelMonitorRole: iam.Role;
  public readonly lambdaFunction: lambda.Function;
  public readonly snsAlertTopic: sns.Topic;
  public readonly sagemakerModel: sagemaker.CfnModel;
  public readonly sagemakerEndpoint: sagemaker.CfnEndpoint;

  constructor(scope: Construct, id: string, props: SageMakerModelMonitorStackProps = {}) {
    super(scope, id, props);

    // Default configuration values
    const alertEmail = props.alertEmail || 'admin@example.com';
    const monitoringInstanceType = props.monitoringInstanceType || 'ml.m5.xlarge';
    const endpointInstanceType = props.endpointInstanceType || 'ml.t2.medium';
    const enableDataCapture = props.enableDataCapture ?? true;
    const dataCapturePercentage = props.dataCapturePercentage ?? 100;

    // Create S3 bucket for monitoring artifacts and model data
    this.monitoringBucket = new s3.Bucket(this, 'ModelMonitorBucket', {
      bucketName: `model-monitor-${this.account}-${cdk.Names.uniqueId(this).toLowerCase()}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldMonitoringData',
          enabled: true,
          expiration: cdk.Duration.days(30),
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7)
        }
      ]
    });

    // Create IAM role for SageMaker Model Monitor
    this.modelMonitorRole = new iam.Role(this, 'ModelMonitorRole', {
      assumedBy: new iam.ServicePrincipal('sagemaker.amazonaws.com'),
      description: 'IAM role for SageMaker Model Monitor operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess')
      ],
      inlinePolicies: {
        ModelMonitorPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket'
              ],
              resources: [
                this.monitoringBucket.bucketArn,
                `${this.monitoringBucket.bucketArn}/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogStreams'
              ],
              resources: ['*']
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecr:GetAuthorizationToken',
                'ecr:BatchCheckLayerAvailability',
                'ecr:GetDownloadUrlForLayer',
                'ecr:BatchGetImage'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create SNS topic for monitoring alerts
    this.snsAlertTopic = new sns.Topic(this, 'ModelMonitorAlerts', {
      topicName: `model-monitor-alerts-${cdk.Names.uniqueId(this).toLowerCase()}`,
      displayName: 'SageMaker Model Monitor Alerts',
      description: 'SNS topic for SageMaker Model Monitor drift detection alerts'
    });

    // Add email subscription if provided
    if (alertEmail !== 'admin@example.com') {
      this.snsAlertTopic.addSubscription(
        new subscriptions.EmailSubscription(alertEmail)
      );
    }

    // Create Lambda function for automated alert handling
    this.lambdaFunction = new lambda.Function(this, 'ModelMonitorHandler', {
      functionName: `model-monitor-handler-${cdk.Names.uniqueId(this).toLowerCase()}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      description: 'Lambda function to handle Model Monitor alerts and trigger automated responses',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: this.snsAlertTopic.topicArn,
        MONITORING_BUCKET: this.monitoringBucket.bucketName
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to handle Model Monitor alerts and trigger automated responses
    """
    try:
        sns_client = boto3.client('sns')
        sagemaker_client = boto3.client('sagemaker')
        
        # Parse the CloudWatch alarm from SNS
        for record in event.get('Records', []):
            if 'Sns' in record:
                message = json.loads(record['Sns']['Message'])
                
                alarm_name = message.get('AlarmName', 'Unknown')
                alarm_description = message.get('AlarmDescription', 'No description')
                new_state = message.get('NewStateValue', 'Unknown')
                region = message.get('Region', 'Unknown')
                
                logger.info(f"Processing alarm: {alarm_name} - State: {new_state}")
                
                # Check if this is a model drift alarm
                if new_state == 'ALARM' and 'ModelMonitor' in alarm_name:
                    handle_drift_alert(sns_client, sagemaker_client, alarm_name, alarm_description, region)
                elif new_state == 'OK':
                    handle_alarm_recovery(sns_client, alarm_name, region)
                    
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Alerts processed successfully',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def handle_drift_alert(sns_client, sagemaker_client, alarm_name, description, region):
    """Handle model drift detection alerts"""
    logger.info(f"Model drift detected: {description}")
    
    # Create detailed notification message
    notification_message = f"""
🚨 SageMaker Model Monitor Alert

Alarm: {alarm_name}
Status: ALARM (Drift Detected)
Description: {description}
Region: {region}
Timestamp: {datetime.utcnow().isoformat()}

Recommended Actions:
1. Review monitoring results in S3
2. Analyze drift patterns and root causes
3. Consider model retraining if drift is significant
4. Update monitoring thresholds if needed

This is an automated alert from your ML monitoring system.
"""
    
    # Send detailed notification
    try:
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'🚨 Model Drift Alert - {alarm_name}',
            Message=notification_message
        )
        logger.info("Drift alert notification sent successfully")
    except Exception as e:
        logger.error(f"Failed to send drift notification: {str(e)}")
    
    # TODO: Add automated response actions here:
    # - Trigger model retraining pipeline
    # - Update model endpoint configuration
    # - Send alerts to external monitoring systems
    # - Create incident tickets

def handle_alarm_recovery(sns_client, alarm_name, region):
    """Handle alarm recovery notifications"""
    logger.info(f"Alarm recovered: {alarm_name}")
    
    recovery_message = f"""
✅ SageMaker Model Monitor Recovery

Alarm: {alarm_name}
Status: OK (No Drift Detected)
Region: {region}
Timestamp: {datetime.utcnow().isoformat()}

The monitoring system has returned to normal operation.
No immediate action required.
"""
    
    try:
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'✅ Model Monitor Recovery - {alarm_name}',
            Message=recovery_message
        )
        logger.info("Recovery notification sent successfully")
    except Exception as e:
        logger.error(f"Failed to send recovery notification: {str(e)}")
      `)
    });

    // Grant Lambda permissions to access SNS and SageMaker
    this.snsAlertTopic.grantPublish(this.lambdaFunction);
    this.lambdaFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'sagemaker:DescribeMonitoringSchedule',
          'sagemaker:DescribeProcessingJob',
          'sagemaker:ListMonitoringExecutions'
        ],
        resources: ['*']
      })
    );
    this.monitoringBucket.grantRead(this.lambdaFunction);

    // Subscribe Lambda to SNS topic
    this.snsAlertTopic.addSubscription(
      new subscriptions.LambdaSubscription(this.lambdaFunction)
    );

    // Create demo SageMaker model
    this.sagemakerModel = new sagemaker.CfnModel(this, 'DemoModel', {
      modelName: `demo-model-${cdk.Names.uniqueId(this).toLowerCase()}`,
      executionRoleArn: this.modelMonitorRole.roleArn,
      primaryContainer: {
        image: `763104351884.dkr.ecr.${this.region}.amazonaws.com/sklearn-inference:0.23-1-cpu-py3`,
        modelDataUrl: `s3://${this.monitoringBucket.bucketName}/model-artifacts/model.tar.gz`,
        environment: {
          SAGEMAKER_PROGRAM: 'inference.py',
          SAGEMAKER_SUBMIT_DIRECTORY: '/opt/ml/code'
        }
      }
    });

    // Create endpoint configuration with data capture enabled
    const endpointConfig = new sagemaker.CfnEndpointConfig(this, 'DemoEndpointConfig', {
      endpointConfigName: `demo-endpoint-config-${cdk.Names.uniqueId(this).toLowerCase()}`,
      productionVariants: [
        {
          variantName: 'Primary',
          modelName: this.sagemakerModel.modelName!,
          initialInstanceCount: 1,
          instanceType: endpointInstanceType,
          initialVariantWeight: 1.0
        }
      ],
      dataCaptureConfig: enableDataCapture ? {
        enableCapture: true,
        initialSamplingPercentage: dataCapturePercentage,
        destinationS3Uri: `s3://${this.monitoringBucket.bucketName}/captured-data`,
        captureOptions: [
          { captureMode: 'Input' },
          { captureMode: 'Output' }
        ]
      } : undefined
    });

    endpointConfig.addDependency(this.sagemakerModel);

    // Create SageMaker endpoint
    this.sagemakerEndpoint = new sagemaker.CfnEndpoint(this, 'DemoEndpoint', {
      endpointName: `demo-endpoint-${cdk.Names.uniqueId(this).toLowerCase()}`,
      endpointConfigName: endpointConfig.endpointConfigName!
    });

    this.sagemakerEndpoint.addDependency(endpointConfig);

    // Create data quality monitoring schedule
    const dataQualitySchedule = new sagemaker.CfnMonitoringSchedule(this, 'DataQualityMonitoringSchedule', {
      monitoringScheduleName: `data-quality-schedule-${cdk.Names.uniqueId(this).toLowerCase()}`,
      monitoringScheduleConfig: {
        scheduleConfig: {
          scheduleExpression: 'cron(0 * * * ? *)' // Hourly monitoring
        },
        monitoringJobDefinition: {
          monitoringInputs: [
            {
              endpointInput: {
                endpointName: this.sagemakerEndpoint.endpointName!,
                localPath: '/opt/ml/processing/input/endpoint',
                s3InputMode: 'File',
                s3DataDistributionType: 'FullyReplicated'
              }
            }
          ],
          monitoringOutputConfig: {
            monitoringOutputs: [
              {
                s3Output: {
                  s3Uri: `s3://${this.monitoringBucket.bucketName}/monitoring-results/data-quality`,
                  localPath: '/opt/ml/processing/output',
                  s3UploadMode: 'EndOfJob'
                }
              }
            ]
          },
          monitoringResources: {
            clusterConfig: {
              instanceType: monitoringInstanceType,
              instanceCount: 1,
              volumeSizeInGb: 20
            }
          },
          monitoringAppSpecification: {
            imageUri: `159807026194.dkr.ecr.${this.region}.amazonaws.com/sagemaker-model-monitor-analyzer:latest`
          },
          baselineConfig: {
            statisticsResource: {
              s3Uri: `s3://${this.monitoringBucket.bucketName}/monitoring-results/statistics`
            },
            constraintsResource: {
              s3Uri: `s3://${this.monitoringBucket.bucketName}/monitoring-results/constraints`
            }
          },
          roleArn: this.modelMonitorRole.roleArn
        }
      }
    });

    dataQualitySchedule.addDependency(this.sagemakerEndpoint);

    // Create model quality monitoring schedule
    const modelQualitySchedule = new sagemaker.CfnMonitoringSchedule(this, 'ModelQualityMonitoringSchedule', {
      monitoringScheduleName: `model-quality-schedule-${cdk.Names.uniqueId(this).toLowerCase()}`,
      monitoringScheduleConfig: {
        scheduleConfig: {
          scheduleExpression: 'cron(0 6 * * ? *)' // Daily monitoring
        },
        monitoringJobDefinition: {
          monitoringInputs: [
            {
              endpointInput: {
                endpointName: this.sagemakerEndpoint.endpointName!,
                localPath: '/opt/ml/processing/input/endpoint',
                s3InputMode: 'File',
                s3DataDistributionType: 'FullyReplicated'
              }
            }
          ],
          monitoringOutputConfig: {
            monitoringOutputs: [
              {
                s3Output: {
                  s3Uri: `s3://${this.monitoringBucket.bucketName}/monitoring-results/model-quality`,
                  localPath: '/opt/ml/processing/output',
                  s3UploadMode: 'EndOfJob'
                }
              }
            ]
          },
          monitoringResources: {
            clusterConfig: {
              instanceType: monitoringInstanceType,
              instanceCount: 1,
              volumeSizeInGb: 20
            }
          },
          monitoringAppSpecification: {
            imageUri: `159807026194.dkr.ecr.${this.region}.amazonaws.com/sagemaker-model-monitor-analyzer:latest`
          },
          roleArn: this.modelMonitorRole.roleArn
        }
      }
    });

    modelQualitySchedule.addDependency(this.sagemakerEndpoint);

    // Create CloudWatch alarms for monitoring
    const constraintViolationsAlarm = new cloudwatch.Alarm(this, 'ConstraintViolationsAlarm', {
      alarmName: `ModelMonitor-ConstraintViolations-${cdk.Names.uniqueId(this).toLowerCase()}`,
      alarmDescription: 'Alert when model monitor detects constraint violations indicating data drift',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SageMaker/ModelMonitor',
        metricName: 'constraint_violations',
        dimensionsMap: {
          MonitoringSchedule: dataQualitySchedule.monitoringScheduleName!
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const jobFailuresAlarm = new cloudwatch.Alarm(this, 'JobFailuresAlarm', {
      alarmName: `ModelMonitor-JobFailures-${cdk.Names.uniqueId(this).toLowerCase()}`,
      alarmDescription: 'Alert when model monitor jobs fail to execute properly',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SageMaker/ModelMonitor',
        metricName: 'monitoring_job_failures',
        dimensionsMap: {
          MonitoringSchedule: dataQualitySchedule.monitoringScheduleName!
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS actions to alarms
    constraintViolationsAlarm.addAlarmAction(
      new cloudwatchActions.SnsAction(this.snsAlertTopic)
    );
    jobFailuresAlarm.addAlarmAction(
      new cloudwatchActions.SnsAction(this.snsAlertTopic)
    );

    // Create CloudWatch Dashboard for monitoring visualization
    const dashboard = new cloudwatch.Dashboard(this, 'ModelMonitorDashboard', {
      dashboardName: `ModelMonitor-Dashboard-${cdk.Names.uniqueId(this).toLowerCase()}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Model Monitor Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/SageMaker/ModelMonitor',
                metricName: 'constraint_violations',
                dimensionsMap: {
                  MonitoringSchedule: dataQualitySchedule.monitoringScheduleName!
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/SageMaker/ModelMonitor',
                metricName: 'monitoring_job_failures',
                dimensionsMap: {
                  MonitoringSchedule: dataQualitySchedule.monitoringScheduleName!
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              })
            ],
            width: 12
          }),
          new cloudwatch.LogQueryWidget({
            title: 'Model Monitor Logs',
            logGroups: [
              logs.LogGroup.fromLogGroupName(this, 'ProcessingJobLogs', '/aws/sagemaker/ProcessingJobs')
            ],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /constraint/',
              'sort @timestamp desc',
              'limit 100'
            ],
            width: 12
          })
        ]
      ]
    });

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.monitoringBucket.bucketName,
      description: 'S3 bucket for storing monitoring artifacts and captured data'
    });

    new cdk.CfnOutput(this, 'SageMakerEndpointName', {
      value: this.sagemakerEndpoint.endpointName!,
      description: 'SageMaker endpoint name for model inference'
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsAlertTopic.topicArn,
      description: 'SNS topic ARN for monitoring alerts'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Lambda function name for automated alert handling'
    });

    new cdk.CfnOutput(this, 'DataQualityMonitoringSchedule', {
      value: dataQualitySchedule.monitoringScheduleName!,
      description: 'Data quality monitoring schedule name'
    });

    new cdk.CfnOutput(this, 'ModelQualityMonitoringSchedule', {
      value: modelQualitySchedule.monitoringScheduleName!,
      description: 'Model quality monitoring schedule name'
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboard', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for monitoring visualization'
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'SageMaker-Model-Monitor');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'MLOps-Monitoring');
    cdk.Tags.of(this).add('CostCenter', 'ML-Platform');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;
const monitoringInstanceType = app.node.tryGetContext('monitoringInstanceType') || 'ml.m5.xlarge';
const endpointInstanceType = app.node.tryGetContext('endpointInstanceType') || 'ml.t2.medium';
const enableDataCapture = app.node.tryGetContext('enableDataCapture') !== false;
const dataCapturePercentage = parseInt(app.node.tryGetContext('dataCapturePercentage') || '100');

// Create the stack
new SageMakerModelMonitorStack(app, 'SageMakerModelMonitorStack', {
  description: 'SageMaker Model Monitor with drift detection, automated alerting, and response capabilities',
  alertEmail,
  monitoringInstanceType,
  endpointInstanceType,
  enableDataCapture,
  dataCapturePercentage,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  }
});

// Synthesize the application
app.synth();