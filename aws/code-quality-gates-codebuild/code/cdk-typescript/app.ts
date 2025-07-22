#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the CodeQualityGatesStack
 */
export interface CodeQualityGatesStackProps extends cdk.StackProps {
  /**
   * Email address for quality gate notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Code coverage threshold (0-100)
   * @default 80
   */
  readonly coverageThreshold?: number;
  
  /**
   * SonarQube quality gate status threshold
   * @default 'ERROR'
   */
  readonly sonarQualityGate?: string;
  
  /**
   * Maximum security vulnerability level
   * @default 'HIGH'
   */
  readonly securityThreshold?: string;
  
  /**
   * Project name prefix for resource naming
   * @default 'quality-gates-demo'
   */
  readonly projectName?: string;
}

/**
 * CDK Stack for Code Quality Gates with CodeBuild
 * 
 * This stack creates:
 * - S3 bucket for build artifacts and reports
 * - SNS topic for quality gate notifications
 * - Systems Manager parameters for quality gate configuration
 * - IAM service role for CodeBuild
 * - CodeBuild project with comprehensive quality gates
 * - CloudWatch dashboard for monitoring
 */
export class CodeQualityGatesStack extends cdk.Stack {
  
  public readonly artifactsBucket: s3.Bucket;
  public readonly notificationTopic: sns.Topic;
  public readonly codeBuildProject: codebuild.Project;
  public readonly qualityDashboard: cloudwatch.Dashboard;
  
  constructor(scope: Construct, id: string, props: CodeQualityGatesStackProps = {}) {
    super(scope, id, props);
    
    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const projectName = props.projectName || 'quality-gates-demo';
    const resourcePrefix = `${projectName}-${randomSuffix}`;
    
    // Create S3 bucket for build artifacts and reports
    this.artifactsBucket = new s3.Bucket(this, 'ArtifactsBucket', {
      bucketName: `codebuild-quality-gates-${this.account}-${randomSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldArtifacts',
          expiration: cdk.Duration.days(30),
          noncurrentVersionExpiration: cdk.Duration.days(7),
        },
      ],
    });
    
    // Create SNS topic for quality gate notifications
    this.notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `quality-gate-notifications-${randomSuffix}`,
      displayName: 'Quality Gate Notifications',
      fifo: false,
    });
    
    // Subscribe email to notifications if provided
    if (props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }
    
    // Create Systems Manager parameters for quality gate configuration
    const coverageThreshold = props.coverageThreshold || 80;
    const sonarQualityGate = props.sonarQualityGate || 'ERROR';
    const securityThreshold = props.securityThreshold || 'HIGH';
    
    new ssm.StringParameter(this, 'CoverageThresholdParameter', {
      parameterName: '/quality-gates/coverage-threshold',
      stringValue: coverageThreshold.toString(),
      description: 'Minimum code coverage percentage',
      tier: ssm.ParameterTier.STANDARD,
    });
    
    new ssm.StringParameter(this, 'SonarQualityGateParameter', {
      parameterName: '/quality-gates/sonar-quality-gate',
      stringValue: sonarQualityGate,
      description: 'SonarQube quality gate status threshold',
      tier: ssm.ParameterTier.STANDARD,
    });
    
    new ssm.StringParameter(this, 'SecurityThresholdParameter', {
      parameterName: '/quality-gates/security-threshold',
      stringValue: securityThreshold,
      description: 'Maximum security vulnerability level',
      tier: ssm.ParameterTier.STANDARD,
    });
    
    // Create IAM service role for CodeBuild
    const codeBuildRole = new iam.Role(this, 'CodeBuildServiceRole', {
      roleName: `${resourcePrefix}-service-role`,
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      description: 'Service role for CodeBuild quality gates project',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess'),
      ],
    });
    
    // Add custom permissions for quality gates
    codeBuildRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:GetParameter',
        'ssm:GetParameters',
        'codebuild:BatchGetBuilds',
      ],
      resources: ['*'],
    }));
    
    // Grant permissions to publish to SNS topic
    this.notificationTopic.grantPublish(codeBuildRole);
    
    // Grant permissions to access S3 bucket
    this.artifactsBucket.grantReadWrite(codeBuildRole);
    
    // Create comprehensive buildspec for quality gates
    const buildspec = codebuild.BuildSpec.fromObject({
      version: '0.2',
      env: {
        'parameter-store': {
          COVERAGE_THRESHOLD: '/quality-gates/coverage-threshold',
          SONAR_QUALITY_GATE: '/quality-gates/sonar-quality-gate',
          SECURITY_THRESHOLD: '/quality-gates/security-threshold',
        },
        variables: {
          MAVEN_OPTS: '-Dmaven.repo.local=.m2/repository',
          SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        },
      },
      phases: {
        install: {
          'runtime-versions': {
            java: 'corretto21',
          },
          commands: [
            'echo "Installing dependencies and tools..."',
            'apt-get update && apt-get install -y curl unzip jq',
            'curl -sSL https://github.com/SonarSource/sonar-scanner-cli/releases/download/4.8.0.2856/sonar-scanner-cli-4.8.0.2856-linux.zip -o sonar-scanner.zip',
            'unzip sonar-scanner.zip',
            'export PATH=$PATH:$(pwd)/sonar-scanner-4.8.0.2856-linux/bin',
            'curl -sSL https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.0/dependency-check-8.4.0-release.zip -o dependency-check.zip',
            'unzip dependency-check.zip',
            'chmod +x dependency-check/bin/dependency-check.sh',
          ],
        },
        pre_build: {
          commands: [
            'echo "Validating build environment..."',
            'java -version',
            'mvn -version',
            'echo "Build started on $(date)"',
          ],
        },
        build: {
          commands: [
            'echo "=== PHASE 1: Compile and Unit Tests ==="',
            'mvn clean compile test',
            'echo "✅ Unit tests completed"',
            
            'echo "=== PHASE 2: Code Coverage Analysis ==="',
            'mvn jacoco:report',
            'COVERAGE=$(grep -o "Total[^%]*%" target/site/jacoco/index.html | grep -o "[0-9]*" | head -1)',
            'echo "Code coverage: ${COVERAGE}%"',
            'if [ "${COVERAGE:-0}" -lt "${COVERAGE_THRESHOLD}" ]; then',
            '  echo "❌ QUALITY GATE FAILED: Coverage ${COVERAGE}% below threshold ${COVERAGE_THRESHOLD}%"',
            '  aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message "Quality Gate Failed: Coverage ${COVERAGE}% below threshold ${COVERAGE_THRESHOLD}%" --subject "Quality Gate Failure"',
            '  exit 1',
            'fi',
            'echo "✅ Code coverage check passed"',
            
            'echo "=== PHASE 3: Static Code Analysis ==="',
            'if [ -n "${SONAR_TOKEN}" ]; then',
            '  mvn sonar:sonar -Dsonar.projectKey=quality-gates-demo -Dsonar.host.url=https://sonarcloud.io -Dsonar.token=${SONAR_TOKEN}',
            '  echo "✅ SonarQube analysis completed"',
            'else',
            '  echo "⚠️ SONAR_TOKEN not set, skipping SonarQube analysis"',
            'fi',
            
            'echo "=== PHASE 4: Security Scanning ==="',
            './dependency-check/bin/dependency-check.sh --project "Quality Gates Demo" --scan . --format JSON --out ./security-report.json',
            'HIGH_VULNS=$(jq ".dependencies[].vulnerabilities[]? | select(.severity == \\"HIGH\\") | length" security-report.json 2>/dev/null | wc -l)',
            'if [ "${HIGH_VULNS}" -gt 0 ]; then',
            '  echo "❌ QUALITY GATE FAILED: Found ${HIGH_VULNS} HIGH severity vulnerabilities"',
            '  aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message "Quality Gate Failed: ${HIGH_VULNS} HIGH severity vulnerabilities found" --subject "Security Gate Failure"',
            '  exit 1',
            'fi',
            'echo "✅ Security scan passed"',
            
            'echo "=== PHASE 5: Integration Tests ==="',
            'mvn verify',
            'echo "✅ Integration tests completed"',
            
            'echo "=== PHASE 6: Quality Gate Summary ==="',
            'echo "All quality gates passed successfully!"',
            'aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message "Quality Gate Success: All checks passed for build ${CODEBUILD_BUILD_ID}" --subject "Quality Gate Success"',
          ],
        },
        post_build: {
          commands: [
            'echo "=== Generating Quality Reports ==="',
            'mkdir -p quality-reports',
            'cp -r target/site/jacoco quality-reports/coverage-report',
            'cp security-report.json quality-reports/',
            'echo "Build completed on $(date)"',
          ],
        },
      },
      artifacts: {
        files: [
          'target/*.jar',
          'quality-reports/**/*',
        ],
        name: 'quality-gates-artifacts',
      },
      reports: {
        'jacoco-reports': {
          files: [
            'target/site/jacoco/jacoco.xml',
          ],
          'file-format': 'JACOCOXML',
        },
        'junit-reports': {
          files: [
            'target/surefire-reports/*.xml',
          ],
          'file-format': 'JUNITXML',
        },
      },
      cache: {
        paths: [
          '.m2/repository/**/*',
        ],
      },
    });
    
    // Create CodeBuild project with quality gates
    this.codeBuildProject = new codebuild.Project(this, 'QualityGatesProject', {
      projectName: resourcePrefix,
      description: 'Quality Gates Demo with CodeBuild',
      source: codebuild.Source.s3({
        bucket: this.artifactsBucket,
        path: 'source/source-code.zip',
      }),
      artifacts: codebuild.Artifacts.s3({
        bucket: this.artifactsBucket,
        path: 'artifacts',
        includeBuildId: true,
        packageZip: false,
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
        computeType: codebuild.ComputeType.MEDIUM,
        privileged: false,
        environmentVariables: {
          SNS_TOPIC_ARN: {
            value: this.notificationTopic.topicArn,
          },
        },
      },
      role: codeBuildRole,
      timeout: cdk.Duration.minutes(60),
      queuedTimeout: cdk.Duration.minutes(480),
      cache: codebuild.Cache.bucket(this.artifactsBucket, {
        prefix: 'cache',
      }),
      buildSpec: buildspec,
      logging: {
        cloudWatch: {
          logGroup: new logs.LogGroup(this, 'CodeBuildLogGroup', {
            logGroupName: `/aws/codebuild/${resourcePrefix}`,
            retention: logs.RetentionDays.TWO_WEEKS,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
          }),
        },
      },
    });
    
    // Create CloudWatch dashboard for quality gate monitoring
    this.qualityDashboard = new cloudwatch.Dashboard(this, 'QualityDashboard', {
      dashboardName: `Quality-Gates-${resourcePrefix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'CodeBuild Quality Gate Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/CodeBuild',
                metricName: 'Builds',
                dimensionsMap: {
                  ProjectName: this.codeBuildProject.projectName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CodeBuild',
                metricName: 'Duration',
                dimensionsMap: {
                  ProjectName: this.codeBuildProject.projectName,
                },
                statistic: 'Average',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/CodeBuild',
                metricName: 'FailedBuilds',
                dimensionsMap: {
                  ProjectName: this.codeBuildProject.projectName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CodeBuild',
                metricName: 'SucceededBuilds',
                dimensionsMap: {
                  ProjectName: this.codeBuildProject.projectName,
                },
                statistic: 'Sum',
              }),
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.LogQueryWidget({
            title: 'Quality Gate Events',
            logGroups: [
              logs.LogGroup.fromLogGroupName(this, 'ImportedLogGroup', `/aws/codebuild/${resourcePrefix}`),
            ],
            queryString: [
              'fields @timestamp, @message',
              'filter @message like /QUALITY GATE/',
              'sort @timestamp desc',
              'limit 20',
            ].join('\n'),
            width: 24,
            height: 6,
          }),
        ],
      ],
    });
    
    // Output important resource information
    new cdk.CfnOutput(this, 'ArtifactsBucketName', {
      value: this.artifactsBucket.bucketName,
      description: 'S3 bucket for build artifacts and reports',
      exportName: `${this.stackName}-ArtifactsBucket`,
    });
    
    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS topic ARN for quality gate notifications',
      exportName: `${this.stackName}-NotificationTopic`,
    });
    
    new cdk.CfnOutput(this, 'CodeBuildProjectName', {
      value: this.codeBuildProject.projectName,
      description: 'CodeBuild project name for quality gates',
      exportName: `${this.stackName}-CodeBuildProject`,
    });
    
    new cdk.CfnOutput(this, 'QualityDashboardName', {
      value: this.qualityDashboard.dashboardName,
      description: 'CloudWatch dashboard name for quality gate monitoring',
      exportName: `${this.stackName}-QualityDashboard`,
    });
    
    new cdk.CfnOutput(this, 'StartBuildCommand', {
      value: `aws codebuild start-build --project-name ${this.codeBuildProject.projectName}`,
      description: 'AWS CLI command to start a build',
    });
    
    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'CodeQualityGates');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack with configurable properties
new CodeQualityGatesStack(app, 'CodeQualityGatesStack', {
  description: 'CDK Stack for Code Quality Gates with CodeBuild',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Uncomment and modify these properties as needed
  // notificationEmail: 'your-email@example.com',
  // coverageThreshold: 80,
  // sonarQualityGate: 'ERROR',
  // securityThreshold: 'HIGH',
  // projectName: 'quality-gates-demo',
});

// Synthesize the app
app.synth();