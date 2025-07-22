#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as imagebuilder from 'aws-cdk-lib/aws-imagebuilder';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';

/**
 * Stack for EC2 Image Builder Pipeline
 * Creates automated AMI building pipeline with web server configuration
 */
class EC2ImageBuilderStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-6).toLowerCase();

    // Create S3 bucket for component storage and build logs
    const logsBucket = new s3.Bucket(this, 'ImageBuilderLogsBucket', {
      bucketName: `image-builder-logs-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [{
        id: 'DeleteOldLogs',
        enabled: true,
        expiration: cdk.Duration.days(30)
      }]
    });

    // Create IAM role for Image Builder instances
    const imageBuilderRole = new iam.Role(this, 'ImageBuilderInstanceRole', {
      roleName: `ImageBuilderInstanceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('EC2InstanceProfileForImageBuilder'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
      ],
      description: 'IAM role for EC2 Image Builder instances'
    });

    // Add S3 permissions for the role to access the logs bucket
    logsBucket.grantReadWrite(imageBuilderRole);

    // Create instance profile for the role
    const instanceProfile = new iam.CfnInstanceProfile(this, 'ImageBuilderInstanceProfile', {
      instanceProfileName: `ImageBuilderInstanceProfile-${uniqueSuffix}`,
      roles: [imageBuilderRole.roleName]
    });

    // Get default VPC and subnet
    const defaultVpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true
    });

    // Create security group for Image Builder instances
    const imageBuilderSecurityGroup = new ec2.SecurityGroup(this, 'ImageBuilderSecurityGroup', {
      vpc: defaultVpc,
      description: 'Security group for Image Builder instances',
      allowAllOutbound: true
    });

    // Add specific outbound rules for package downloads
    imageBuilderSecurityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS outbound for package downloads'
    );

    imageBuilderSecurityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'HTTP outbound for package downloads'
    );

    // Create SNS topic for build notifications
    const notificationsTopic = new sns.Topic(this, 'ImageBuilderNotifications', {
      topicName: `ImageBuilder-Notifications-${uniqueSuffix}`,
      displayName: 'EC2 Image Builder Notifications'
    });

    // Upload component definitions to S3
    const webServerComponentContent = `name: WebServerSetup
description: Install and configure Apache web server with security hardening
schemaVersion: 1.0

phases:
  - name: build
    steps:
      - name: UpdateSystem
        action: UpdateOS
      - name: InstallApache
        action: ExecuteBash
        inputs:
          commands:
            - yum update -y
            - yum install -y httpd
            - systemctl enable httpd
      - name: ConfigureApache
        action: ExecuteBash
        inputs:
          commands:
            - echo '<html><body><h1>Custom Web Server</h1><p>Built with EC2 Image Builder</p></body></html>' > /var/www/html/index.html
            - chown apache:apache /var/www/html/index.html
            - chmod 644 /var/www/html/index.html
      - name: SecurityHardening
        action: ExecuteBash
        inputs:
          commands:
            - sed -i 's/^#ServerTokens OS/ServerTokens Prod/' /etc/httpd/conf/httpd.conf
            - sed -i 's/^#ServerSignature On/ServerSignature Off/' /etc/httpd/conf/httpd.conf
            - systemctl start httpd
  - name: validate
    steps:
      - name: ValidateApache
        action: ExecuteBash
        inputs:
          commands:
            - systemctl is-active httpd
            - curl -f http://localhost/ || exit 1
  - name: test
    steps:
      - name: TestWebServer
        action: ExecuteBash
        inputs:
          commands:
            - systemctl status httpd
            - curl -s http://localhost/ | grep -q "Custom Web Server" || exit 1
            - netstat -tlnp | grep :80 || exit 1`;

    const testComponentContent = `name: WebServerTest
description: Comprehensive testing of web server setup
schemaVersion: 1.0

phases:
  - name: test
    steps:
      - name: ServiceTest
        action: ExecuteBash
        inputs:
          commands:
            - echo "Testing Apache service status..."
            - systemctl is-enabled httpd
            - systemctl is-active httpd
      - name: ConfigurationTest
        action: ExecuteBash
        inputs:
          commands:
            - echo "Testing Apache configuration..."
            - httpd -t
            - grep -q "ServerTokens Prod" /etc/httpd/conf/httpd.conf || exit 1
            - grep -q "ServerSignature Off" /etc/httpd/conf/httpd.conf || exit 1
      - name: SecurityTest
        action: ExecuteBash
        inputs:
          commands:
            - echo "Testing security configurations..."
            - curl -I http://localhost/ | grep -q "Apache" && exit 1 || echo "Server signature hidden"
            - ss -tlnp | grep :80 | grep -q httpd || exit 1
      - name: ContentTest
        action: ExecuteBash
        inputs:
          commands:
            - echo "Testing web content..."
            - curl -s http://localhost/ | grep -q "Custom Web Server" || exit 1
            - test -f /var/www/html/index.html || exit 1`;

    // Create S3 objects for component definitions
    new s3.CfnObject(this, 'WebServerComponentObject', {
      bucket: logsBucket.bucketName,
      key: 'components/web-server-component.yaml',
      body: webServerComponentContent,
      contentType: 'text/yaml'
    });

    new s3.CfnObject(this, 'WebServerTestObject', {
      bucket: logsBucket.bucketName,
      key: 'components/web-server-test.yaml',
      body: testComponentContent,
      contentType: 'text/yaml'
    });

    // Create the build component
    const buildComponent = new imagebuilder.CfnComponent(this, 'WebServerBuildComponent', {
      name: `web-server-component-${uniqueSuffix}`,
      platform: 'Linux',
      version: '1.0.0',
      description: 'Web server setup with security hardening',
      uri: `s3://${logsBucket.bucketName}/components/web-server-component.yaml`,
      tags: {
        Environment: 'Production',
        Purpose: 'WebServer'
      }
    });

    // Create the test component
    const testComponent = new imagebuilder.CfnComponent(this, 'WebServerTestComponent', {
      name: `web-server-test-${uniqueSuffix}`,
      platform: 'Linux',
      version: '1.0.0',
      description: 'Comprehensive web server testing',
      uri: `s3://${logsBucket.bucketName}/components/web-server-test.yaml`,
      tags: {
        Environment: 'Production',
        Purpose: 'Testing'
      }
    });

    // Create image recipe
    const imageRecipe = new imagebuilder.CfnImageRecipe(this, 'WebServerImageRecipe', {
      name: `web-server-recipe-${uniqueSuffix}`,
      version: '1.0.0',
      description: 'Web server recipe with security hardening',
      parentImage: 'arn:aws:imagebuilder:us-east-1:aws:image/amazon-linux-2-x86/x.x.x',
      components: [
        {
          componentArn: buildComponent.attrArn
        },
        {
          componentArn: testComponent.attrArn
        }
      ],
      tags: {
        Environment: 'Production',
        Purpose: 'WebServer'
      }
    });

    // Create infrastructure configuration
    const infrastructureConfiguration = new imagebuilder.CfnInfrastructureConfiguration(this, 'WebServerInfrastructureConfig', {
      name: `web-server-infra-${uniqueSuffix}`,
      description: 'Infrastructure for web server image builds',
      instanceProfileName: instanceProfile.instanceProfileName!,
      instanceTypes: ['t3.medium'],
      subnetId: defaultVpc.privateSubnets[0]?.subnetId || defaultVpc.publicSubnets[0].subnetId,
      securityGroupIds: [imageBuilderSecurityGroup.securityGroupId],
      terminateInstanceOnFailure: true,
      snsTopicArn: notificationsTopic.topicArn,
      logging: {
        s3Logs: {
          s3BucketName: logsBucket.bucketName,
          s3KeyPrefix: 'build-logs/'
        }
      },
      tags: {
        Environment: 'Production',
        Purpose: 'WebServer'
      }
    });

    // Create distribution configuration
    const distributionConfiguration = new imagebuilder.CfnDistributionConfiguration(this, 'WebServerDistributionConfig', {
      name: `web-server-dist-${uniqueSuffix}`,
      description: 'Multi-region distribution for web server AMIs',
      distributions: [
        {
          region: this.region,
          amiDistributionConfiguration: {
            name: 'WebServer-{{imagebuilder:buildDate}}-{{imagebuilder:buildVersion}}',
            description: 'Custom web server AMI built with Image Builder',
            amiTags: {
              Name: 'WebServer-AMI',
              Environment: 'Production',
              BuildDate: '{{imagebuilder:buildDate}}',
              BuildVersion: '{{imagebuilder:buildVersion}}',
              Recipe: `web-server-recipe-${uniqueSuffix}`
            }
          }
        }
      ],
      tags: {
        Environment: 'Production',
        Purpose: 'WebServer'
      }
    });

    // Create image pipeline
    const imagePipeline = new imagebuilder.CfnImagePipeline(this, 'WebServerImagePipeline', {
      name: `web-server-pipeline-${uniqueSuffix}`,
      description: 'Automated web server image building pipeline',
      imageRecipeArn: imageRecipe.attrArn,
      infrastructureConfigurationArn: infrastructureConfiguration.attrArn,
      distributionConfigurationArn: distributionConfiguration.attrArn,
      imageTestsConfiguration: {
        imageTestsEnabled: true,
        timeoutMinutes: 90
      },
      schedule: {
        scheduleExpression: 'cron(0 2 * * SUN)',
        pipelineExecutionStartCondition: 'EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE'
      },
      status: 'ENABLED',
      tags: {
        Environment: 'Production',
        Purpose: 'WebServer'
      }
    });

    // Ensure proper dependencies
    buildComponent.addDependency(logsBucket.node.defaultChild as s3.CfnBucket);
    testComponent.addDependency(logsBucket.node.defaultChild as s3.CfnBucket);
    imageRecipe.addDependency(buildComponent);
    imageRecipe.addDependency(testComponent);
    infrastructureConfiguration.addDependency(instanceProfile);
    imagePipeline.addDependency(imageRecipe);
    imagePipeline.addDependency(infrastructureConfiguration);
    imagePipeline.addDependency(distributionConfiguration);

    // Output important values
    new cdk.CfnOutput(this, 'ImagePipelineName', {
      value: imagePipeline.name!,
      description: 'Name of the created Image Builder pipeline'
    });

    new cdk.CfnOutput(this, 'ImagePipelineArn', {
      value: imagePipeline.attrArn,
      description: 'ARN of the created Image Builder pipeline'
    });

    new cdk.CfnOutput(this, 'LogsBucketName', {
      value: logsBucket.bucketName,
      description: 'S3 bucket for Image Builder logs'
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: notificationsTopic.topicArn,
      description: 'SNS topic for build notifications'
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: imageBuilderSecurityGroup.securityGroupId,
      description: 'Security group for Image Builder instances'
    });

    new cdk.CfnOutput(this, 'BuildComponentArn', {
      value: buildComponent.attrArn,
      description: 'ARN of the build component'
    });

    new cdk.CfnOutput(this, 'TestComponentArn', {
      value: testComponent.attrArn,
      description: 'ARN of the test component'
    });

    new cdk.CfnOutput(this, 'ImageRecipeArn', {
      value: imageRecipe.attrArn,
      description: 'ARN of the image recipe'
    });
  }
}

// Create CDK app and stack
const app = new cdk.App();

new EC2ImageBuilderStack(app, 'EC2ImageBuilderStack', {
  description: 'EC2 Image Builder Pipeline for automated web server AMI creation',
  tags: {
    Project: 'EC2ImageBuilder',
    Environment: 'Production',
    ManagedBy: 'CDK'
  }
});

app.synth();