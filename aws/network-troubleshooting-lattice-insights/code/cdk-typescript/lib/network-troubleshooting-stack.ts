import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cwActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import { Construct } from 'constructs';

/**
 * Properties for the NetworkTroubleshootingStack
 */
export interface NetworkTroubleshootingStackProps extends cdk.StackProps {
  /** Random suffix for unique resource names */
  readonly randomSuffix: string;
}

/**
 * AWS CDK Stack for Network Troubleshooting with VPC Lattice and Network Insights
 * 
 * This stack creates a comprehensive network troubleshooting platform that includes:
 * - VPC Lattice service mesh for application-level networking
 * - VPC Reachability Analyzer automation for static configuration analysis
 * - CloudWatch monitoring with dashboards and alarms
 * - Systems Manager automation documents for diagnostic workflows
 * - Lambda functions for automated response to network issues
 * - SNS notifications for proactive alerting
 * 
 * The solution enables network engineers to rapidly identify and resolve
 * service communication issues across multi-VPC environments with minimal
 * manual intervention.
 */
export class NetworkTroubleshootingStack extends cdk.Stack {
  /** VPC Lattice Service Network for testing */
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  
  /** Test EC2 instance for network analysis */
  public readonly testInstance: ec2.Instance;
  
  /** SNS topic for network alerts */
  public readonly alertsTopic: sns.Topic;
  
  /** Lambda function for automated troubleshooting */
  public readonly troubleshootingFunction: lambda.Function;
  
  /** IAM role for automation execution */
  public readonly automationRole: iam.Role;
  
  /** CloudWatch dashboard for monitoring */
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: NetworkTroubleshootingStackProps) {
    super(scope, id, props);

    // Validate required properties
    if (!props.randomSuffix || props.randomSuffix.length < 4) {
      throw new Error('randomSuffix must be at least 4 characters long');
    }

    const { randomSuffix } = props;

    // Get default VPC for testing
    const defaultVpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true,
    });

    // Create IAM role for Systems Manager automation
    this.automationRole = new iam.Role(this, 'AutomationRole', {
      roleName: `NetworkTroubleshootingRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('ssm.amazonaws.com'),
      description: 'IAM role for network troubleshooting automation',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMAutomationRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonVPCFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchReadOnlyAccess'),
      ],
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `NetworkTroubleshootingLambdaRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for network troubleshooting Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMFullAccess'),
      ],
    });

    // Create VPC Lattice service network
    this.serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `troubleshooting-network-${randomSuffix}`,
      authType: 'AWS_IAM',
    });

    // Associate VPC with service network
    const vpcAssociation = new vpclattice.CfnServiceNetworkVpcAssociation(this, 'VPCAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      vpcIdentifier: defaultVpc.vpcId,
    });

    // Create security group for test instances
    const testSecurityGroup = new ec2.SecurityGroup(this, 'TestSecurityGroup', {
      vpc: defaultVpc,
      description: 'Security group for VPC Lattice testing',
      securityGroupName: `lattice-test-sg-${randomSuffix}`,
    });

    // Add ingress rules
    testSecurityGroup.addIngressRule(
      testSecurityGroup,
      ec2.Port.tcp(80),
      'Allow HTTP traffic from within security group'
    );

    testSecurityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/8'),
      ec2.Port.tcp(22),
      'Allow SSH from private IP ranges'
    );

    // Create test EC2 instance
    this.testInstance = new ec2.Instance(this, 'TestInstance', {
      vpc: defaultVpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.latestAmazonLinux2023(),
      securityGroup: testSecurityGroup,
      instanceName: `lattice-test-${randomSuffix}`,
      associatePublicIpAddress: true,
    });

    // Create CloudWatch log group for VPC Lattice
    const logGroup = new logs.LogGroup(this, 'VPCLatticeLogGroup', {
      logGroupName: `/aws/vpclattice/servicenetwork/${this.serviceNetwork.attrId}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for alerts
    this.alertsTopic = new sns.Topic(this, 'NetworkAlertsTopic', {
      topicName: `network-alerts-${randomSuffix}`,
      displayName: 'Network Troubleshooting Alerts',
    });

    // Create Lambda function for automated troubleshooting
    this.troubleshootingFunction = new lambda.Function(this, 'TroubleshootingFunction', {
      functionName: `network-troubleshooting-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      environment: {
        AUTOMATION_ROLE_ARN: this.automationRole.roleArn,
        DEFAULT_INSTANCE_ID: this.testInstance.instanceId,
        RANDOM_SUFFIX: randomSuffix,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to automatically trigger network troubleshooting
    when CloudWatch alarms are triggered via SNS
    """
    ssm_client = boto3.client('ssm')
    
    try:
        # Parse SNS message
        if 'Records' in event:
            for record in event['Records']:
                if record['EventSource'] == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    alarm_name = message.get('AlarmName', '')
                    
                    logger.info(f"Processing alarm: {alarm_name}")
                    
                    # Get environment variables with defaults
                    automation_role = os.environ.get('AUTOMATION_ROLE_ARN', '')
                    default_instance = os.environ.get('DEFAULT_INSTANCE_ID', '')
                    suffix = os.environ.get('RANDOM_SUFFIX', '')
                    
                    if not automation_role or not default_instance or not suffix:
                        logger.error("Missing required environment variables")
                        return {
                            'statusCode': 400,
                            'body': json.dumps({'error': 'Missing environment variables'})
                        }
                    
                    # Trigger automated troubleshooting
                    response = ssm_client.start_automation_execution(
                        DocumentName=f"NetworkReachabilityAnalysis-{suffix}",
                        Parameters={
                            'SourceId': [default_instance],
                            'DestinationId': [default_instance],
                            'AutomationAssumeRole': [automation_role]
                        }
                    )
                    
                    logger.info(f"Started automation execution: {response['AutomationExecutionId']}")
                    
                    return {
                        'statusCode': 200,
                        'body': json.dumps({
                            'message': 'Network troubleshooting automation started',
                            'execution_id': response['AutomationExecutionId'],
                            'alarm_name': alarm_name
                        })
                    }
            
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'No SNS records to process'})
        }
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
    });

    // Subscribe Lambda to SNS topic
    this.alertsTopic.addSubscription(new snsSubscriptions.LambdaSubscription(this.troubleshootingFunction));

    // Create CloudWatch alarms for VPC Lattice monitoring
    const errorRateAlarm = new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `VPCLattice-HighErrorRate-${randomSuffix}`,
      alarmDescription: 'Alarm for high VPC Lattice 5XX error rate',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VpcLattice',
        metricName: 'HTTPCode_Target_5XX_Count',
        dimensionsMap: {
          ServiceNetwork: this.serviceNetwork.attrId,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    const latencyAlarm = new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      alarmName: `VPCLattice-HighLatency-${randomSuffix}`,
      alarmDescription: 'Alarm for high VPC Lattice response time',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VpcLattice',
        metricName: 'TargetResponseTime',
        dimensionsMap: {
          ServiceNetwork: this.serviceNetwork.attrId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    // Add SNS actions to alarms
    errorRateAlarm.addAlarmAction(new cwActions.SnsAction(this.alertsTopic));
    latencyAlarm.addAlarmAction(new cwActions.SnsAction(this.alertsTopic));

    // Create CloudWatch dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'NetworkDashboard', {
      dashboardName: `VPCLatticeNetworkTroubleshooting-${randomSuffix}`,
    });

    // Add performance metrics widget
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'VPC Lattice Performance Metrics',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/VpcLattice',
            metricName: 'RequestCount',
            dimensionsMap: {
              ServiceNetwork: this.serviceNetwork.attrId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/VpcLattice',
            metricName: 'TargetResponseTime',
            dimensionsMap: {
              ServiceNetwork: this.serviceNetwork.attrId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/VpcLattice',
            metricName: 'ActiveConnectionCount',
            dimensionsMap: {
              ServiceNetwork: this.serviceNetwork.attrId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
      })
    );

    // Add response codes widget
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'VPC Lattice Response Codes',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/VpcLattice',
            metricName: 'HTTPCode_Target_2XX_Count',
            dimensionsMap: {
              ServiceNetwork: this.serviceNetwork.attrId,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/VpcLattice',
            metricName: 'HTTPCode_Target_4XX_Count',
            dimensionsMap: {
              ServiceNetwork: this.serviceNetwork.attrId,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/VpcLattice',
            metricName: 'HTTPCode_Target_5XX_Count',
            dimensionsMap: {
              ServiceNetwork: this.serviceNetwork.attrId,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
      })
    );

    // Create Systems Manager automation document
    const automationDocument = new ssm.CfnDocument(this, 'AutomationDocument', {
      documentType: 'Automation',
      documentFormat: 'JSON',
      name: `NetworkReachabilityAnalysis-${randomSuffix}`,
      content: {
        schemaVersion: '0.3',
        description: 'Automated VPC Reachability Analysis for Network Troubleshooting',
        assumeRole: '{{ AutomationAssumeRole }}',
        parameters: {
          SourceId: {
            type: 'String',
            description: 'Source instance ID or ENI ID',
          },
          DestinationId: {
            type: 'String',
            description: 'Destination instance ID or ENI ID',
          },
          AutomationAssumeRole: {
            type: 'String',
            description: 'IAM role for automation execution',
          },
        },
        mainSteps: [
          {
            name: 'CreateNetworkInsightsPath',
            action: 'aws:executeAwsApi',
            description: 'Create a network insights path for reachability analysis',
            inputs: {
              Service: 'ec2',
              Api: 'CreateNetworkInsightsPath',
              Source: '{{ SourceId }}',
              Destination: '{{ DestinationId }}',
              Protocol: 'tcp',
              DestinationPort: 80,
              TagSpecifications: [
                {
                  ResourceType: 'network-insights-path',
                  Tags: [
                    {
                      Key: 'Name',
                      Value: 'AutomatedTroubleshooting',
                    },
                  ],
                },
              ],
            },
            outputs: [
              {
                Name: 'NetworkInsightsPathId',
                Selector: '$.NetworkInsightsPath.NetworkInsightsPathId',
                Type: 'String',
              },
            ],
          },
          {
            name: 'StartNetworkInsightsAnalysis',
            action: 'aws:executeAwsApi',
            description: 'Start the network insights analysis',
            inputs: {
              Service: 'ec2',
              Api: 'StartNetworkInsightsAnalysis',
              NetworkInsightsPathId: '{{ CreateNetworkInsightsPath.NetworkInsightsPathId }}',
              TagSpecifications: [
                {
                  ResourceType: 'network-insights-analysis',
                  Tags: [
                    {
                      Key: 'Name',
                      Value: 'AutomatedAnalysis',
                    },
                  ],
                },
              ],
            },
            outputs: [
              {
                Name: 'NetworkInsightsAnalysisId',
                Selector: '$.NetworkInsightsAnalysis.NetworkInsightsAnalysisId',
                Type: 'String',
              },
            ],
          },
          {
            name: 'WaitForAnalysisCompletion',
            action: 'aws:waitForAwsResourceProperty',
            description: 'Wait for the analysis to complete',
            inputs: {
              Service: 'ec2',
              Api: 'DescribeNetworkInsightsAnalyses',
              NetworkInsightsAnalysisIds: ['{{ StartNetworkInsightsAnalysis.NetworkInsightsAnalysisId }}'],
              PropertySelector: '$.NetworkInsightsAnalyses[0].Status',
              DesiredValues: ['succeeded', 'failed'],
            },
          },
        ],
      },
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'TestInstanceId', {
      value: this.testInstance.instanceId,
      description: 'Test EC2 Instance ID for network analysis',
      exportName: `${this.stackName}-TestInstanceId`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.alertsTopic.topicArn,
      description: 'SNS Topic ARN for network alerts',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.troubleshootingFunction.functionArn,
      description: 'Lambda Function ARN for automated troubleshooting',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'AutomationRoleArn', {
      value: this.automationRole.roleArn,
      description: 'IAM Role ARN for automation execution',
      exportName: `${this.stackName}-AutomationRoleArn`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
      exportName: `${this.stackName}-DashboardURL`,
    });

    new cdk.CfnOutput(this, 'AutomationDocumentName', {
      value: automationDocument.ref,
      description: 'Systems Manager Automation Document Name',
      exportName: `${this.stackName}-AutomationDocumentName`,
    });
  }
}