#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import { AwsSolutionsChecks } from 'cdk-nag';

/**
 * Properties for the Canary Deployment Stack
 */
interface CanaryDeploymentStackProps extends cdk.StackProps {
  /** The initial traffic weight for the canary version (0-100) */
  readonly canaryWeight?: number;
  /** The production traffic weight (0-100) */
  readonly productionWeight?: number;
  /** Enable automatic rollback on alarm */
  readonly enableAutoRollback?: boolean;
}

/**
 * CDK Stack for implementing progressive canary deployments using VPC Lattice and Lambda
 * 
 * This stack creates:
 * - Two Lambda function versions (production and canary)
 * - VPC Lattice service network and service for weighted routing
 * - Target groups for each Lambda version
 * - CloudWatch alarms for monitoring canary health
 * - Optional automatic rollback functionality
 */
export class CanaryDeploymentStack extends cdk.Stack {
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  public readonly latticeService: vpclattice.CfnService;
  public readonly productionFunction: lambda.Function;
  public readonly canaryFunction: lambda.Function;
  public readonly rollbackTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: CanaryDeploymentStackProps = {}) {
    super(scope, id, props);

    // Default traffic weights if not specified
    const canaryWeight = props.canaryWeight ?? 10;
    const productionWeight = props.productionWeight ?? 90;
    const enableAutoRollback = props.enableAutoRollback ?? true;

    // Validate weights sum to 100
    if (canaryWeight + productionWeight !== 100) {
      throw new Error('Canary weight and production weight must sum to 100');
    }

    // Create IAM execution role for Lambda functions with least privilege
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for canary deployment Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add VPC Lattice invoke permissions
    lambdaExecutionRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['lambda:InvokeFunction'],
      resources: ['*'], // Will be restricted to specific functions after creation
    }));

    // Create production Lambda function (version 1)
    this.productionFunction = new lambda.Function(this, 'ProductionFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      role: lambdaExecutionRole,
      code: lambda.Code.fromInline(`
import json
import time

def handler(event, context):
    """Production version of the Lambda function"""
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Version': 'v1.0.0'
        },
        'body': json.dumps({
            'version': 'v1.0.0',
            'message': 'Hello from production version',
            'timestamp': int(time.time()),
            'environment': 'production',
            'request_id': context.aws_request_id
        })
    }
`),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Production version for canary deployment',
      architecture: lambda.Architecture.ARM_64, // Cost-optimized ARM architecture
      logRetention: logs.RetentionDays.ONE_WEEK, // Security best practice
      environmentEncryption: new cdk.aws_kms.Key(this, 'LambdaEnvironmentKey', {
        description: 'KMS key for Lambda environment variable encryption',
        enableKeyRotation: true,
      }),
    });

    // Create canary Lambda function (version 2) with enhanced features
    this.canaryFunction = new lambda.Function(this, 'CanaryFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      role: lambdaExecutionRole,
      code: lambda.Code.fromInline(`
import json
import time
import random
import os

def handler(event, context):
    """Canary version with enhanced features"""
    
    # Simulate enhanced processing
    features = ['feature-a', 'feature-b', 'enhanced-logging']
    response_time = random.randint(50, 200)
    
    # Add custom CloudWatch metric
    import boto3
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        cloudwatch.put_metric_data(
            Namespace='CanaryDeployment/Lambda',
            MetricData=[
                {
                    'MetricName': 'CanaryResponseTime',
                    'Value': response_time,
                    'Unit': 'Milliseconds',
                    'Dimensions': [
                        {
                            'Name': 'Version',
                            'Value': 'v2.0.0'
                        }
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Failed to send custom metric: {e}")
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Version': 'v2.0.0',
            'X-Features': ','.join(features)
        },
        'body': json.dumps({
            'version': 'v2.0.0',
            'message': 'Hello from canary version',
            'timestamp': int(time.time()),
            'environment': 'canary',
            'features': features,
            'response_time': response_time,
            'request_id': context.aws_request_id
        })
    }
`),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Canary version with enhanced features',
      architecture: lambda.Architecture.ARM_64,
      logRetention: logs.RetentionDays.ONE_WEEK,
      environmentEncryption: this.productionFunction.environmentEncryption,
    });

    // Grant CloudWatch permissions to canary function for custom metrics
    this.canaryFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['cloudwatch:PutMetricData'],
      resources: ['*'],
    }));

    // Create Lambda versions for stable deployments
    const productionVersion = new lambda.Version(this, 'ProductionVersion', {
      lambda: this.productionFunction,
      description: 'Production version 1.0.0',
    });

    const canaryVersion = new lambda.Version(this, 'CanaryVersion', {
      lambda: this.canaryFunction,
      description: 'Canary version 2.0.0 with enhanced features',
    });

    // Create VPC Lattice service network
    this.serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'CanaryServiceNetwork', {
      name: `canary-demo-network-${this.stackName.toLowerCase()}`,
      authType: 'NONE', // For demo purposes - production should use IAM
    });

    // Create target group for production Lambda version
    const productionTargetGroup = new vpclattice.CfnTargetGroup(this, 'ProductionTargetGroup', {
      name: `prod-targets-${this.stackName.toLowerCase()}`,
      type: 'LAMBDA',
      targets: [{
        id: productionVersion.functionArn,
      }],
      config: {
        healthCheck: {
          enabled: true,
          healthCheckIntervalSeconds: 30,
          healthCheckTimeoutSeconds: 5,
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
          matcher: {
            httpCode: '200',
          },
        },
      },
    });

    // Create target group for canary Lambda version
    const canaryTargetGroup = new vpclattice.CfnTargetGroup(this, 'CanaryTargetGroup', {
      name: `canary-targets-${this.stackName.toLowerCase()}`,
      type: 'LAMBDA',
      targets: [{
        id: canaryVersion.functionArn,
      }],
      config: {
        healthCheck: {
          enabled: true,
          healthCheckIntervalSeconds: 30,
          healthCheckTimeoutSeconds: 5,
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
          matcher: {
            httpCode: '200',
          },
        },
      },
    });

    // Create VPC Lattice service with weighted routing
    this.latticeService = new vpclattice.CfnService(this, 'CanaryLatticeService', {
      name: `canary-demo-service-${this.stackName.toLowerCase()}`,
      authType: 'NONE',
    });

    // Create HTTP listener with weighted routing for canary deployment
    const listener = new vpclattice.CfnListener(this, 'CanaryListener', {
      serviceIdentifier: this.latticeService.attrId,
      name: 'canary-listener',
      protocol: 'HTTP',
      port: 80,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: productionTargetGroup.attrId,
              weight: productionWeight,
            },
            {
              targetGroupIdentifier: canaryTargetGroup.attrId,
              weight: canaryWeight,
            },
          ],
        },
      },
    });

    // Associate service with service network
    new vpclattice.CfnServiceNetworkServiceAssociation(this, 'ServiceNetworkAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      serviceIdentifier: this.latticeService.attrId,
    });

    // Grant VPC Lattice permission to invoke Lambda functions
    this.productionFunction.addPermission('AllowVPCLatticeInvoke', {
      principal: new iam.ServicePrincipal('vpc-lattice.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceAccount: this.account,
    });

    this.canaryFunction.addPermission('AllowVPCLatticeInvoke', {
      principal: new iam.ServicePrincipal('vpc-lattice.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceAccount: this.account,
    });

    // Create CloudWatch alarms for canary monitoring
    const canaryErrorAlarm = new cloudwatch.Alarm(this, 'CanaryErrorAlarm', {
      alarmName: `canary-lambda-errors-${this.stackName}`,
      alarmDescription: 'Monitor errors in canary Lambda version',
      metric: this.canaryFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const canaryDurationAlarm = new cloudwatch.Alarm(this, 'CanaryDurationAlarm', {
      alarmName: `canary-lambda-duration-${this.stackName}`,
      alarmDescription: 'Monitor duration in canary Lambda version',
      metric: this.canaryFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 5000, // 5 seconds
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create custom metric for canary response time monitoring
    const canaryResponseTimeAlarm = new cloudwatch.Alarm(this, 'CanaryResponseTimeAlarm', {
      alarmName: `canary-response-time-${this.stackName}`,
      alarmDescription: 'Monitor custom response time metric in canary version',
      metric: new cloudwatch.Metric({
        namespace: 'CanaryDeployment/Lambda',
        metricName: 'CanaryResponseTime',
        dimensionsMap: {
          Version: 'v2.0.0',
        },
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 150, // 150ms average response time
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    // Create SNS topic for rollback notifications
    this.rollbackTopic = new sns.Topic(this, 'RollbackTopic', {
      topicName: `canary-rollback-${this.stackName}`,
      displayName: 'Canary Deployment Rollback Notifications',
    });

    // Create automatic rollback Lambda function if enabled
    if (enableAutoRollback) {
      const rollbackFunction = new lambda.Function(this, 'RollbackFunction', {
        runtime: lambda.Runtime.PYTHON_3_11,
        handler: 'index.handler',
        code: lambda.Code.fromInline(`
import boto3
import json
import os

def handler(event, context):
    """Automatic rollback function triggered by CloudWatch alarms"""
    
    lattice = boto3.client('vpc-lattice')
    
    try:
        # Parse SNS message
        if 'Records' in event and event['Records']:
            sns_message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = sns_message.get('AlarmName', '')
            new_state = sns_message.get('NewStateValue', '')
            
            print(f"Processing alarm: {alarm_name}, state: {new_state}")
            
            if 'canary' in alarm_name.lower() and new_state == 'ALARM':
                # Trigger rollback to 100% production traffic
                service_id = os.environ['SERVICE_ID']
                listener_id = os.environ['LISTENER_ID']
                prod_target_group_id = os.environ['PROD_TARGET_GROUP_ID']
                
                response = lattice.update_listener(
                    serviceIdentifier=service_id,
                    listenerIdentifier=listener_id,
                    defaultAction={
                        'forward': {
                            'targetGroups': [
                                {
                                    'targetGroupIdentifier': prod_target_group_id,
                                    'weight': 100
                                }
                            ]
                        }
                    }
                )
                
                print(f"Rollback completed successfully. Listener updated: {response}")
                
                # Send notification
                sns = boto3.client('sns')
                sns.publish(
                    TopicArn=os.environ['ROLLBACK_TOPIC_ARN'],
                    Subject=f"Automatic Rollback Triggered - {alarm_name}",
                    Message=f"Automatic rollback was triggered due to alarm: {alarm_name}\\n"
                           f"All traffic has been routed back to production version.\\n"
                           f"Timestamp: {context.aws_request_id}"
                )
                
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Rollback completed successfully',
                        'alarm': alarm_name,
                        'request_id': context.aws_request_id
                    })
                }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'No rollback action required',
                'request_id': context.aws_request_id
            })
        }
            
    except Exception as e:
        print(f"Rollback failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Rollback failed: {str(e)}',
                'request_id': context.aws_request_id
            })
        }
`),
        timeout: cdk.Duration.seconds(60),
        memorySize: 256,
        environment: {
          SERVICE_ID: this.latticeService.attrId,
          LISTENER_ID: listener.attrId,
          PROD_TARGET_GROUP_ID: productionTargetGroup.attrId,
          ROLLBACK_TOPIC_ARN: this.rollbackTopic.topicArn,
        },
        description: 'Automatic rollback function for canary deployments',
        architecture: lambda.Architecture.ARM_64,
        logRetention: logs.RetentionDays.ONE_WEEK,
      });

      // Grant necessary permissions to rollback function
      rollbackFunction.addToRolePolicy(new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'vpc-lattice:UpdateListener',
          'vpc-lattice:GetListener',
          'vpc-lattice:GetService',
        ],
        resources: ['*'],
      }));

      // Grant permission to publish to SNS topic
      this.rollbackTopic.grantPublish(rollbackFunction);

      // Subscribe rollback function to all canary alarms
      const rollbackSubscription = new sns.Subscription(this, 'RollbackSubscription', {
        topic: this.rollbackTopic,
        endpoint: rollbackFunction.functionArn,
        protocol: sns.SubscriptionProtocol.LAMBDA,
      });

      // Grant SNS permission to invoke rollback function
      rollbackFunction.addPermission('AllowSNSInvoke', {
        principal: new iam.ServicePrincipal('sns.amazonaws.com'),
        action: 'lambda:InvokeFunction',
        sourceArn: this.rollbackTopic.topicArn,
      });

      // Add alarms to SNS topic for automatic rollback
      canaryErrorAlarm.addAlarmAction({
        bind: () => ({ alarmActionArn: this.rollbackTopic.topicArn }),
      });
      canaryDurationAlarm.addAlarmAction({
        bind: () => ({ alarmActionArn: this.rollbackTopic.topicArn }),
      });
      canaryResponseTimeAlarm.addAlarmAction({
        bind: () => ({ alarmActionArn: this.rollbackTopic.topicArn }),
      });
    }

    // Stack outputs for easy access to important resources
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'ServiceId', {
      value: this.latticeService.attrId,
      description: 'VPC Lattice Service ID',
      exportName: `${this.stackName}-ServiceId`,
    });

    new cdk.CfnOutput(this, 'ServiceDomainName', {
      value: this.latticeService.attrDnsEntry?.domainName || 'Not available',
      description: 'VPC Lattice Service DNS Domain Name',
      exportName: `${this.stackName}-ServiceDomainName`,
    });

    new cdk.CfnOutput(this, 'ProductionFunctionArn', {
      value: this.productionFunction.functionArn,
      description: 'Production Lambda Function ARN',
      exportName: `${this.stackName}-ProductionFunctionArn`,
    });

    new cdk.CfnOutput(this, 'CanaryFunctionArn', {
      value: this.canaryFunction.functionArn,
      description: 'Canary Lambda Function ARN',
      exportName: `${this.stackName}-CanaryFunctionArn`,
    });

    new cdk.CfnOutput(this, 'TrafficWeights', {
      value: `Production: ${productionWeight}%, Canary: ${canaryWeight}%`,
      description: 'Current traffic distribution weights',
    });

    new cdk.CfnOutput(this, 'RollbackTopicArn', {
      value: this.rollbackTopic.topicArn,
      description: 'SNS Topic ARN for rollback notifications',
      exportName: `${this.stackName}-RollbackTopicArn`,
    });

    // Add tags for cost allocation and resource management
    cdk.Tags.of(this).add('Project', 'CanaryDeployment');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
    cdk.Tags.of(this).add('DeploymentPattern', 'Progressive');
  }
}

// CDK App instantiation
const app = new cdk.App();

// Apply CDK Nag for security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Create the canary deployment stack
const stack = new CanaryDeploymentStack(app, 'CanaryDeploymentStack', {
  description: 'Progressive canary deployments using VPC Lattice and Lambda (uksb-1tupboc57)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  canaryWeight: 10,      // 10% traffic to canary
  productionWeight: 90,  // 90% traffic to production
  enableAutoRollback: true,
  
  // Enable termination protection for production deployments
  terminationProtection: false, // Set to true for production
});

// Add additional stack-level tags
cdk.Tags.of(stack).add('StackName', stack.stackName);
cdk.Tags.of(stack).add('CreatedBy', 'AWS-CDK');

app.synth();