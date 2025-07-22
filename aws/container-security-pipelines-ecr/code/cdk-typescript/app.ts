#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as config from 'aws-cdk-lib/aws-config';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as ssm from 'aws-cdk-lib/aws-ssm';

/**
 * Container Security Scanning Pipeline Stack
 * 
 * This CDK stack creates a comprehensive container security scanning pipeline
 * using Amazon ECR with enhanced scanning, third-party security tools integration,
 * and automated vulnerability reporting through EventBridge and Lambda.
 */
export class ContainerSecurityScanningStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 6);
    
    // Create ECR repository with enhanced scanning enabled
    const ecrRepository = new ecr.Repository(this, 'SecurityScanRepository', {
      repositoryName: `secure-app-${uniqueSuffix}`,
      imageScanOnPush: true,
      encryption: ecr.RepositoryEncryption.AES_256,
      lifecycleRules: [
        {
          description: 'Keep last 10 images',
          maxImageCount: 10,
          rulePriority: 1,
          tagStatus: ecr.TagStatus.UNTAGGED,
        },
        {
          description: 'Delete images older than 30 days',
          maxImageAge: cdk.Duration.days(30),
          rulePriority: 2,
          tagStatus: ecr.TagStatus.ANY,
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for security alerts
    const securityAlertsTopic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `security-alerts-${uniqueSuffix}`,
      displayName: 'Container Security Alerts',
      fifo: false,
    });

    // Create IAM role for CodeBuild with ECR and logging permissions
    const codeBuildRole = new iam.Role(this, 'CodeBuildSecurityScanRole', {
      roleName: `ECRSecurityScanningRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryPowerUser'),
      ],
      inlinePolicies: {
        ECRSecurityScanningPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecr:BatchCheckLayerAvailability',
                'ecr:GetDownloadUrlForLayer',
                'ecr:BatchGetImage',
                'ecr:GetAuthorizationToken',
                'ecr:InitiateLayerUpload',
                'ecr:UploadLayerPart',
                'ecr:CompleteLayerUpload',
                'ecr:PutImage',
                'ecr:DescribeRepositories',
                'ecr:DescribeImages',
                'ecr:DescribeImageScanFindings',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CodeBuild project for multi-stage security scanning
    const securityScanProject = new codebuild.Project(this, 'SecurityScanProject', {
      projectName: `security-scan-${uniqueSuffix}`,
      description: 'Multi-stage container security scanning pipeline',
      source: codebuild.Source.gitHub({
        owner: 'your-org',
        repo: 'your-repo',
        branchOrRef: 'main',
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
        privileged: true, // Required for Docker operations
        computeType: codebuild.ComputeType.MEDIUM,
        environmentVariables: {
          ECR_REPO_NAME: {
            value: ecrRepository.repositoryName,
          },
          ECR_URI: {
            value: ecrRepository.repositoryUri,
          },
          AWS_DEFAULT_REGION: {
            value: this.region,
          },
          AWS_ACCOUNT_ID: {
            value: this.account,
          },
        },
      },
      role: codeBuildRole,
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          pre_build: {
            commands: [
              'echo Logging in to Amazon ECR...',
              'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI',
              'IMAGE_TAG=${CODEBUILD_RESOLVED_SOURCE_VERSION:-latest}',
              'echo Build started on `date`',
              'echo Building the Docker image...',
            ],
          },
          build: {
            commands: [
              '# Build the container image',
              'docker build -t $ECR_REPO_NAME:$IMAGE_TAG .',
              'docker tag $ECR_REPO_NAME:$IMAGE_TAG $ECR_URI:$IMAGE_TAG',
              '',
              '# Run Snyk container security scan',
              'echo "Running Snyk container scan..."',
              'snyk container test $ECR_REPO_NAME:$IMAGE_TAG --severity-threshold=high --json > snyk-results.json || true',
              '',
              '# Run Prisma Cloud/Twistlock scan (if configured)',
              'echo "Running Prisma Cloud scan..."',
              'twistcli images scan --details $ECR_REPO_NAME:$IMAGE_TAG --output-file prisma-results.json || true',
            ],
          },
          post_build: {
            commands: [
              'echo Build completed on `date`',
              'echo Pushing the Docker image...',
              'docker push $ECR_URI:$IMAGE_TAG',
              '',
              '# Wait for enhanced scanning to complete',
              'echo "Waiting for ECR enhanced scanning..."',
              'sleep 30',
              '',
              '# Get ECR scan results',
              'aws ecr describe-image-scan-findings --repository-name $ECR_REPO_NAME --image-id imageTag=$IMAGE_TAG > ecr-scan-results.json || true',
              '',
              '# Process and combine scan results',
              'echo "Processing security scan results..."',
              'python3 process_scan_results.py',
            ],
          },
        },
        artifacts: {
          files: ['**/*'],
        },
      }),
      timeout: cdk.Duration.minutes(60),
    });

    // Create IAM role for Lambda function with Security Hub and SNS permissions
    const lambdaRole = new iam.Role(this, 'SecurityScanLambdaRole', {
      roleName: `SecurityScanLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        SecurityHubIntegrationPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'securityhub:BatchImportFindings',
                'securityhub:GetFindings',
                'sns:Publish',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for processing security scan results
    const scanProcessorFunction = new lambda.Function(this, 'SecurityScanProcessor', {
      functionName: `SecurityScanProcessor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    print("Processing security scan results...")
    
    # Parse ECR scan results from EventBridge
    detail = event.get('detail', {})
    repository_name = detail.get('repository-name', '')
    image_digest = detail.get('image-digest', '')
    finding_counts = detail.get('finding-severity-counts', {})
    
    # Create consolidated security report
    security_report = {
        'timestamp': datetime.utcnow().isoformat(),
        'repository': repository_name,
        'image_digest': image_digest,
        'scan_results': {
            'ecr_enhanced': finding_counts,
            'total_vulnerabilities': finding_counts.get('TOTAL', 0),
            'critical_vulnerabilities': finding_counts.get('CRITICAL', 0),
            'high_vulnerabilities': finding_counts.get('HIGH', 0)
        }
    }
    
    # Determine risk level and actions
    critical_count = finding_counts.get('CRITICAL', 0)
    high_count = finding_counts.get('HIGH', 0)
    
    if critical_count > 0:
        risk_level = 'CRITICAL'
        action_required = 'IMMEDIATE_BLOCK'
    elif high_count > 5:
        risk_level = 'HIGH'
        action_required = 'REVIEW_REQUIRED'
    else:
        risk_level = 'LOW'
        action_required = 'MONITOR'
    
    security_report['risk_assessment'] = {
        'risk_level': risk_level,
        'action_required': action_required,
        'compliance_status': 'FAIL' if critical_count > 0 else 'PASS'
    }
    
    # Send to Security Hub
    securityhub = boto3.client('securityhub')
    try:
        securityhub.batch_import_findings(
            Findings=[{
                'SchemaVersion': '2018-10-08',
                'Id': f"{repository_name}-{image_digest}",
                'ProductArn': f"arn:aws:securityhub:{os.environ['AWS_REGION']}:{os.environ['AWS_ACCOUNT_ID']}:product/custom/container-security-scanner",
                'GeneratorId': 'container-security-pipeline',
                'AwsAccountId': os.environ['AWS_ACCOUNT_ID'],
                'Title': f"Container Security Scan - {repository_name}",
                'Description': f"Security scan completed for {repository_name}",
                'Severity': {
                    'Label': risk_level
                },
                'Resources': [{
                    'Type': 'AwsEcrContainerImage',
                    'Id': f"{repository_name}:{image_digest}",
                    'Region': os.environ['AWS_REGION']
                }]
            }]
        )
    except Exception as e:
        print(f"Error sending to Security Hub: {e}")
    
    # Trigger notifications based on risk level
    if risk_level in ['CRITICAL', 'HIGH']:
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(security_report, indent=2),
            Subject=f"Container Security Alert - {risk_level} Risk Detected"
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps(security_report)
    }
`),
      environment: {
        SNS_TOPIC_ARN: securityAlertsTopic.topicArn,
        AWS_REGION: this.region,
        AWS_ACCOUNT_ID: this.account,
      },
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      description: 'Processes container security scan results and triggers notifications',
    });

    // Create EventBridge rule for ECR scan completion events
    const scanCompletionRule = new events.Rule(this, 'ECRScanCompletionRule', {
      ruleName: `ECRScanCompleted-${uniqueSuffix}`,
      description: 'Triggers when ECR enhanced scanning completes',
      eventPattern: {
        source: ['aws.inspector2'],
        detailType: ['Inspector2 Scan'],
        detail: {
          'scan-status': ['INITIAL_SCAN_COMPLETE'],
        },
      },
    });

    // Add Lambda function as target for EventBridge rule
    scanCompletionRule.addTarget(new targets.LambdaFunction(scanProcessorFunction));

    // Create Config rule for ECR repository compliance
    const ecrComplianceRule = new config.ManagedRule(this, 'ECRRepositoryComplianceRule', {
      identifier: config.ManagedRuleIdentifiers.ECR_PRIVATE_IMAGE_SCANNING_ENABLED,
      configRuleName: `ecr-repository-scan-enabled-${uniqueSuffix}`,
      description: 'Checks whether ECR private repositories have image scanning enabled',
      inputParameters: {},
      ruleScope: config.RuleScope.fromResources([config.ResourceType.ECR_REPOSITORY]),
    });

    // Create CloudWatch dashboard for security metrics
    const securityDashboard = new cloudwatch.Dashboard(this, 'SecurityDashboard', {
      dashboardName: `ContainerSecurityDashboard-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'ECR Repository Count',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ECR',
                metricName: 'RepositoryCount',
                statistic: 'Sum',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.LogQueryWidget({
            title: 'Critical Security Findings',
            logGroups: [scanProcessorFunction.logGroup],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /CRITICAL/',
              'sort @timestamp desc',
              'limit 20',
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Create SSM parameters for configuration
    new ssm.StringParameter(this, 'ECRRepositoryParameter', {
      parameterName: `/container-security/${uniqueSuffix}/ecr-repository-name`,
      stringValue: ecrRepository.repositoryName,
      description: 'ECR repository name for security scanning',
    });

    new ssm.StringParameter(this, 'SNSTopicParameter', {
      parameterName: `/container-security/${uniqueSuffix}/sns-topic-arn`,
      stringValue: securityAlertsTopic.topicArn,
      description: 'SNS topic ARN for security alerts',
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'ECRRepositoryName', {
      value: ecrRepository.repositoryName,
      description: 'ECR repository name for container images',
      exportName: `ECRRepositoryName-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'ECRRepositoryURI', {
      value: ecrRepository.repositoryUri,
      description: 'ECR repository URI for pushing images',
      exportName: `ECRRepositoryURI-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'CodeBuildProjectName', {
      value: securityScanProject.projectName,
      description: 'CodeBuild project name for security scanning',
      exportName: `CodeBuildProjectName-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'SecurityAlertsTopic', {
      value: securityAlertsTopic.topicArn,
      description: 'SNS topic ARN for security alerts',
      exportName: `SecurityAlertsTopic-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: scanProcessorFunction.functionName,
      description: 'Lambda function name for processing scan results',
      exportName: `LambdaFunctionName-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${securityDashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for security metrics',
      exportName: `DashboardURL-${uniqueSuffix}`,
    });

    // Grant necessary permissions
    ecrRepository.grantPullPush(codeBuildRole);
    securityAlertsTopic.grantPublish(scanProcessorFunction);
    
    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ContainerSecurityScanning');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'SecurityTeam');
    cdk.Tags.of(this).add('CostCenter', 'Security');
  }
}

// Create CDK app and instantiate the stack
const app = new cdk.App();

new ContainerSecurityScanningStack(app, 'ContainerSecurityScanningStack', {
  description: 'Container Security Scanning Pipeline with ECR and Third-Party Tools',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  stackName: 'container-security-scanning-pipeline',
  tags: {
    Project: 'ContainerSecurityScanning',
    Environment: 'Production',
    Owner: 'SecurityTeam',
    CostCenter: 'Security',
  },
});

app.synth();