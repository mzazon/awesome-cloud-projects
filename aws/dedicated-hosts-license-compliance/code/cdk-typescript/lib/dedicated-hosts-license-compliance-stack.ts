import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as config from 'aws-cdk-lib/aws-config';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

export interface DedicatedHostsLicenseComplianceStackProps extends cdk.StackProps {
  /**
   * Email address for compliance notifications
   */
  readonly notificationEmail?: string;

  /**
   * Instance family for Windows/SQL Server workloads
   */
  readonly windowsInstanceFamily?: string;

  /**
   * Instance family for Oracle Database workloads
   */
  readonly oracleInstanceFamily?: string;

  /**
   * Number of Windows Server licenses available
   */
  readonly windowsLicenseCount?: number;

  /**
   * Number of Oracle licenses available (core-based)
   */
  readonly oracleLicenseCount?: number;
}

export class DedicatedHostsLicenseComplianceStack extends cdk.Stack {
  public readonly windowsDedicatedHost: ec2.CfnHost;
  public readonly oracleDedicatedHost: ec2.CfnHost;
  public readonly complianceSnsTopic: sns.Topic;
  public readonly complianceReportsBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: DedicatedHostsLicenseComplianceStackProps) {
    super(scope, id, props);

    // Extract properties with defaults
    const notificationEmail = props?.notificationEmail || this.node.tryGetContext('notificationEmail');
    const windowsInstanceFamily = props?.windowsInstanceFamily || 'm5';
    const oracleInstanceFamily = props?.oracleInstanceFamily || 'r5';
    const windowsLicenseCount = props?.windowsLicenseCount || 10;
    const oracleLicenseCount = props?.oracleLicenseCount || 16;

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const resourcePrefix = `license-compliance-${uniqueSuffix}`;

    // Create SNS topic for compliance notifications
    this.complianceSnsTopic = new sns.Topic(this, 'ComplianceAlertsTopic', {
      topicName: `${resourcePrefix}-compliance-alerts`,
      displayName: 'License Compliance Alerts',
    });

    // Add email subscription if provided
    if (notificationEmail) {
      this.complianceSnsTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(notificationEmail)
      );
    }

    // Create S3 bucket for compliance reports
    this.complianceReportsBucket = new s3.Bucket(this, 'ComplianceReportsBucket', {
      bucketName: `${resourcePrefix}-reports-${this.account}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [{
        id: 'DeleteOldReports',
        expiration: cdk.Duration.days(365),
        abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
      }],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create Config delivery channel bucket
    const configBucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `${resourcePrefix}-config-${this.account}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [{
        id: 'DeleteOldConfigSnapshots',
        expiration: cdk.Duration.days(90),
      }],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for AWS Config
    const configRole = new iam.Role(this, 'ConfigServiceRole', {
      roleName: `${resourcePrefix}-config-role`,
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
    });

    // Grant Config service permissions to write to S3 bucket
    configBucket.grantReadWrite(configRole);

    // Create AWS Config Configuration Recorder
    const configRecorder = new config.CfnConfigurationRecorder(this, 'ConfigRecorder', {
      name: `${resourcePrefix}-recorder`,
      roleArn: configRole.roleArn,
      recordingGroup: {
        allSupported: false,
        includeGlobalResourceTypes: false,
        resourceTypes: ['AWS::EC2::Host', 'AWS::EC2::Instance'],
      },
    });

    // Create AWS Config Delivery Channel
    const configDeliveryChannel = new config.CfnDeliveryChannel(this, 'ConfigDeliveryChannel', {
      name: `${resourcePrefix}-delivery-channel`,
      s3BucketName: configBucket.bucketName,
      configSnapshotDeliveryProperties: {
        deliveryFrequency: 'TwentyFour_Hours',
      },
    });

    // Ensure delivery channel depends on recorder
    configDeliveryChannel.addDependency(configRecorder);

    // Allocate Windows/SQL Server Dedicated Host
    this.windowsDedicatedHost = new ec2.CfnHost(this, 'WindowsDedicatedHost', {
      instanceFamily: windowsInstanceFamily,
      availabilityZone: `${this.region}a`,
      autoPlacement: 'off',
      hostRecovery: 'on',
    });

    // Tag Windows Dedicated Host
    cdk.Tags.of(this.windowsDedicatedHost).add('LicenseCompliance', 'BYOL-Production');
    cdk.Tags.of(this.windowsDedicatedHost).add('LicenseType', 'WindowsServer');
    cdk.Tags.of(this.windowsDedicatedHost).add('Purpose', 'SQLServer');

    // Allocate Oracle Database Dedicated Host
    this.oracleDedicatedHost = new ec2.CfnHost(this, 'OracleDedicatedHost', {
      instanceFamily: oracleInstanceFamily,
      availabilityZone: `${this.region}b`,
      autoPlacement: 'off',
      hostRecovery: 'on',
    });

    // Tag Oracle Dedicated Host
    cdk.Tags.of(this.oracleDedicatedHost).add('LicenseCompliance', 'BYOL-Production');
    cdk.Tags.of(this.oracleDedicatedHost).add('LicenseType', 'Oracle');
    cdk.Tags.of(this.oracleDedicatedHost).add('Purpose', 'Database');

    // Create IAM role for License Manager
    const licenseManagerRole = new iam.Role(this, 'LicenseManagerRole', {
      assumedBy: new iam.ServicePrincipal('license-manager.amazonaws.com'),
    });

    // Grant License Manager permissions to write reports to S3
    this.complianceReportsBucket.grantReadWrite(licenseManagerRole);

    // Create License Manager bucket policy
    this.complianceReportsBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'LicenseManagerReportAccess',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('license-manager.amazonaws.com')],
        actions: [
          's3:GetBucketLocation',
          's3:ListBucket',
          's3:PutObject',
          's3:GetObject',
        ],
        resources: [
          this.complianceReportsBucket.bucketArn,
          `${this.complianceReportsBucket.bucketArn}/*`,
        ],
      })
    );

    // Create Config rule for Dedicated Host compliance
    const hostComplianceRule = new config.CfnConfigRule(this, 'HostComplianceRule', {
      configRuleName: `${resourcePrefix}-host-compliance`,
      description: 'Checks if EC2 instances are running on properly configured Dedicated Hosts',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'EC2_DEDICATED_HOST_COMPLIANCE',
      },
      scope: {
        complianceResourceTypes: ['AWS::EC2::Instance'],
      },
    });

    // Ensure Config rule depends on recorder
    hostComplianceRule.addDependency(configRecorder);

    // Create IAM role for compliance Lambda function
    const lambdaRole = new iam.Role(this, 'ComplianceLambdaRole', {
      roleName: `${resourcePrefix}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Grant Lambda permissions to access License Manager and SNS
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'license-manager:ListLicenseConfigurations',
          'license-manager:ListUsageForLicenseConfiguration',
          'ec2:DescribeHosts',
          'ec2:DescribeInstances',
          'sns:Publish',
        ],
        resources: ['*'],
      })
    );

    // Create Lambda function for compliance reporting
    const complianceReportFunction = new lambda.Function(this, 'ComplianceReportFunction', {
      functionName: `${resourcePrefix}-compliance-report`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(1),
      role: lambdaRole,
      environment: {
        SNS_TOPIC_ARN: this.complianceSnsTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    license_manager = boto3.client('license-manager')
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    try:
        # Get license configurations
        license_configs = license_manager.list_license_configurations()
        
        compliance_report = {
            'report_date': datetime.now().isoformat(),
            'license_utilization': [],
            'dedicated_hosts': []
        }
        
        # Process license configurations
        for config in license_configs['LicenseConfigurations']:
            try:
                usage = license_manager.list_usage_for_license_configuration(
                    LicenseConfigurationArn=config['LicenseConfigurationArn']
                )
                
                utilization_percentage = 0
                if config['LicenseCount'] > 0:
                    utilization_percentage = (len(usage['LicenseConfigurationUsageList']) / config['LicenseCount']) * 100
                
                compliance_report['license_utilization'].append({
                    'license_name': config['Name'],
                    'license_count': config['LicenseCount'],
                    'consumed_licenses': len(usage['LicenseConfigurationUsageList']),
                    'utilization_percentage': utilization_percentage
                })
            except Exception as e:
                print(f"Error processing license config {config['Name']}: {str(e)}")
        
        # Get Dedicated Host information
        try:
            hosts = ec2.describe_hosts()
            for host in hosts['Hosts']:
                compliance_report['dedicated_hosts'].append({
                    'host_id': host['HostId'],
                    'state': host['State'],
                    'instance_family': host.get('InstanceFamily', 'Unknown'),
                    'availability_zone': host['AvailabilityZone'],
                    'auto_placement': host['AutoPlacement'],
                    'host_recovery': host['HostRecovery']
                })
        except Exception as e:
            print(f"Error getting host information: {str(e)}")
        
        # Send compliance report via SNS
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(compliance_report, indent=2),
            Subject='Weekly License Compliance Report'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Compliance report generated successfully')
        }
        
    except Exception as e:
        print(f"Error in compliance report function: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error generating compliance report: {str(e)}')
        }
`),
    });

    // Create EventBridge rule for weekly compliance reporting
    const weeklyReportRule = new events.Rule(this, 'WeeklyComplianceReport', {
      ruleName: `${resourcePrefix}-weekly-report`,
      description: 'Trigger weekly compliance report generation',
      schedule: events.Schedule.cron({
        weekDay: 'MON',
        hour: '9',
        minute: '0',
      }),
    });

    // Add Lambda function as target for the rule
    weeklyReportRule.addTarget(new targets.LambdaFunction(complianceReportFunction));

    // Create Launch Template for Windows/SQL Server instances
    const windowsLaunchTemplate = new ec2.CfnLaunchTemplate(this, 'WindowsSQLLaunchTemplate', {
      launchTemplateName: `${resourcePrefix}-windows-sql`,
      launchTemplateData: {
        imageId: this.node.tryGetContext('windowsAmiId') || 'ami-0c02fb55956c7d316', // Windows Server 2022
        instanceType: 'm5.large',
        iamInstanceProfile: {
          name: this.node.tryGetContext('instanceProfile') || 'EC2-SSM-Role',
        },
        tagSpecifications: [{
          resourceType: 'instance',
          tags: [
            { key: 'Name', value: `${resourcePrefix}-windows-sql` },
            { key: 'LicenseType', value: 'WindowsServer' },
            { key: 'Application', value: 'SQLServer' },
            { key: 'BYOLCompliance', value: 'true' },
          ],
        }],
        placement: {
          tenancy: 'host',
        },
      },
    });

    // Create Launch Template for Oracle Database instances
    const oracleLaunchTemplate = new ec2.CfnLaunchTemplate(this, 'OracleDBLaunchTemplate', {
      launchTemplateName: `${resourcePrefix}-oracle-db`,
      launchTemplateData: {
        imageId: this.node.tryGetContext('oracleAmiId') || 'ami-0abcdef1234567890', // Oracle Linux
        instanceType: 'r5.xlarge',
        iamInstanceProfile: {
          name: this.node.tryGetContext('instanceProfile') || 'EC2-SSM-Role',
        },
        tagSpecifications: [{
          resourceType: 'instance',
          tags: [
            { key: 'Name', value: `${resourcePrefix}-oracle-db` },
            { key: 'LicenseType', value: 'Oracle' },
            { key: 'Application', value: 'Database' },
            { key: 'BYOLCompliance', value: 'true' },
          ],
        }],
        placement: {
          tenancy: 'host',
        },
      },
    });

    // Create CloudWatch Dashboard for compliance monitoring
    const complianceDashboard = new cloudwatch.Dashboard(this, 'ComplianceDashboard', {
      dashboardName: `${resourcePrefix}-compliance-dashboard`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Dedicated Host Utilization',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/EC2',
                metricName: 'CPUUtilization',
                dimensionsMap: {
                  InstanceId: 'i-placeholder', // Would be replaced with actual instance IDs
                },
                statistic: 'Average',
              }),
            ],
          }),
          new cloudwatch.SingleValueWidget({
            title: 'Active Dedicated Hosts',
            width: 12,
            height: 6,
            metrics: [
              new cloudwatch.Metric({
                namespace: 'AWS/EC2',
                metricName: 'HostUtilization',
                statistic: 'Average',
              }),
            ],
          }),
        ],
      ],
    });

    // Store important values in SSM Parameter Store
    new ssm.StringParameter(this, 'WindowsHostIdParameter', {
      parameterName: `/${resourcePrefix}/windows-host-id`,
      stringValue: this.windowsDedicatedHost.ref,
      description: 'Windows/SQL Server Dedicated Host ID',
    });

    new ssm.StringParameter(this, 'OracleHostIdParameter', {
      parameterName: `/${resourcePrefix}/oracle-host-id`,
      stringValue: this.oracleDedicatedHost.ref,
      description: 'Oracle Database Dedicated Host ID',
    });

    new ssm.StringParameter(this, 'ResourcePrefixParameter', {
      parameterName: `/${resourcePrefix}/resource-prefix`,
      stringValue: resourcePrefix,
      description: 'Resource naming prefix for this deployment',
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'WindowsDedicatedHostId', {
      value: this.windowsDedicatedHost.ref,
      description: 'ID of the Windows/SQL Server Dedicated Host',
      exportName: `${this.stackName}-WindowsHostId`,
    });

    new cdk.CfnOutput(this, 'OracleDedicatedHostId', {
      value: this.oracleDedicatedHost.ref,
      description: 'ID of the Oracle Database Dedicated Host',
      exportName: `${this.stackName}-OracleHostId`,
    });

    new cdk.CfnOutput(this, 'ComplianceSnsTopicArn', {
      value: this.complianceSnsTopic.topicArn,
      description: 'ARN of the compliance alerts SNS topic',
      exportName: `${this.stackName}-ComplianceTopicArn`,
    });

    new cdk.CfnOutput(this, 'ComplianceReportsBucketName', {
      value: this.complianceReportsBucket.bucketName,
      description: 'Name of the S3 bucket for compliance reports',
      exportName: `${this.stackName}-ReportsBucketName`,
    });

    new cdk.CfnOutput(this, 'ResourcePrefix', {
      value: resourcePrefix,
      description: 'Resource naming prefix for this deployment',
      exportName: `${this.stackName}-ResourcePrefix`,
    });

    new cdk.CfnOutput(this, 'WindowsLaunchTemplateId', {
      value: windowsLaunchTemplate.ref,
      description: 'ID of the Windows/SQL Server launch template',
      exportName: `${this.stackName}-WindowsLaunchTemplate`,
    });

    new cdk.CfnOutput(this, 'OracleLaunchTemplateId', {
      value: oracleLaunchTemplate.ref,
      description: 'ID of the Oracle Database launch template',
      exportName: `${this.stackName}-OracleLaunchTemplate`,
    });

    new cdk.CfnOutput(this, 'ComplianceDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${resourcePrefix}-compliance-dashboard`,
      description: 'URL to access the compliance monitoring dashboard',
    });
  }
}