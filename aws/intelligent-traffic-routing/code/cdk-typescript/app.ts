#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import {
  Stack,
  StackProps,
  Duration,
  RemovalPolicy,
  CfnOutput,
  Fn,
} from 'aws-cdk-lib';
import {
  Vpc,
  SubnetType,
  SecurityGroup,
  Port,
  Protocol,
  MachineImage,
  InstanceType,
  InstanceClass,
  InstanceSize,
  UserData,
} from 'aws-cdk-lib/aws-ec2';
import {
  ApplicationLoadBalancer,
  ApplicationTargetGroup,
  TargetType,
  Protocol as ElbProtocol,
  HealthCheck,
  ApplicationProtocol,
} from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import {
  AutoScalingGroup,
  HealthCheck as AsgHealthCheck,
} from 'aws-cdk-lib/aws-autoscaling';
import {
  HostedZone,
  RecordSet,
  RecordType,
  CnameRecord,
  HealthCheck as Route53HealthCheck,
} from 'aws-cdk-lib/aws-route53';
import {
  Distribution,
  OriginGroup,
  OriginGroupProps,
  ViewerProtocolPolicy,
  PriceClass,
  HttpVersion,
  SecurityPolicyProtocol,
  OriginAccessIdentity,
  AllowedMethods,
  CachedMethods,
  CachePolicy,
  OriginRequestPolicy,
  ResponseHeadersPolicy,
  ErrorResponse,
} from 'aws-cdk-lib/aws-cloudfront';
import {
  HttpOrigin,
  S3Origin,
} from 'aws-cdk-lib/aws-cloudfront-origins';
import {
  Bucket,
  BucketAccessControl,
  BlockPublicAccess,
  BucketEncryption,
} from 'aws-cdk-lib/aws-s3';
import {
  BucketDeployment,
  Source,
} from 'aws-cdk-lib/aws-s3-deployment';
import {
  Topic,
} from 'aws-cdk-lib/aws-sns';
import {
  EmailSubscription,
} from 'aws-cdk-lib/aws-sns-subscriptions';
import {
  Alarm,
  Metric,
  Dashboard,
  GraphWidget,
  SingleValueWidget,
  ComparisonOperator,
  TreatMissingData,
} from 'aws-cdk-lib/aws-cloudwatch';
import {
  SnsAction,
} from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

/**
 * Properties for GlobalLoadBalancingStack
 */
interface GlobalLoadBalancingStackProps extends StackProps {
  /**
   * The domain name for the hosted zone
   * @default 'example.com'
   */
  readonly domainName?: string;

  /**
   * Email address for SNS notifications
   * @default undefined (no email subscription)
   */
  readonly notificationEmail?: string;

  /**
   * Minimum number of instances per region
   * @default 1
   */
  readonly minCapacity?: number;

  /**
   * Maximum number of instances per region
   * @default 3
   */
  readonly maxCapacity?: number;

  /**
   * Desired number of instances per region
   * @default 2
   */
  readonly desiredCapacity?: number;

  /**
   * Instance type for EC2 instances
   * @default t3.micro
   */
  readonly instanceType?: InstanceType;
}

/**
 * Regional infrastructure stack for global load balancing
 */
class RegionalInfrastructureStack extends Stack {
  public readonly loadBalancer: ApplicationLoadBalancer;
  public readonly targetGroup: ApplicationTargetGroup;
  public readonly healthCheck: Route53HealthCheck;

  constructor(scope: Construct, id: string, props: GlobalLoadBalancingStackProps & { regionName: string }) {
    super(scope, id, props);

    const { regionName } = props;
    const minCapacity = props.minCapacity ?? 1;
    const maxCapacity = props.maxCapacity ?? 3;
    const desiredCapacity = props.desiredCapacity ?? 2;
    const instanceType = props.instanceType ?? InstanceType.of(InstanceClass.T3, InstanceSize.MICRO);

    // Create VPC with public subnets across multiple AZs
    const vpc = new Vpc(this, 'Vpc', {
      cidr: '10.0.0.0/16',
      maxAzs: 2,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'PublicSubnet',
          subnetType: SubnetType.PUBLIC,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Security group for ALB and EC2 instances
    const securityGroup = new SecurityGroup(this, 'SecurityGroup', {
      vpc,
      description: `Security group for global load balancer - ${regionName}`,
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from internet
    securityGroup.addIngressRule(
      cdk.aws_ec2.Peer.anyIpv4(),
      Port.tcp(80),
      'Allow HTTP traffic from internet'
    );

    // Allow HTTPS traffic from internet
    securityGroup.addIngressRule(
      cdk.aws_ec2.Peer.anyIpv4(),
      Port.tcp(443),
      'Allow HTTPS traffic from internet'
    );

    // Create Application Load Balancer
    this.loadBalancer = new ApplicationLoadBalancer(this, 'LoadBalancer', {
      vpc,
      internetFacing: true,
      securityGroup,
      loadBalancerName: `global-lb-${regionName.replace(/[^a-zA-Z0-9]/g, '-')}`,
    });

    // Create target group with health checks
    this.targetGroup = new ApplicationTargetGroup(this, 'TargetGroup', {
      vpc,
      port: 80,
      protocol: ApplicationProtocol.HTTP,
      targetType: TargetType.INSTANCE,
      healthCheck: {
        enabled: true,
        healthyHttpCodes: '200',
        path: '/health',
        protocol: ElbProtocol.HTTP,
        interval: Duration.seconds(30),
        timeout: Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      targetGroupName: `global-lb-tg-${regionName.replace(/[^a-zA-Z0-9]/g, '-')}`,
    });

    // Create listener
    this.loadBalancer.addListener('HttpListener', {
      port: 80,
      protocol: ApplicationProtocol.HTTP,
      defaultTargetGroups: [this.targetGroup],
    });

    // Create user data script for sample application
    const userData = UserData.forLinux();
    userData.addCommands(
      'yum update -y',
      'yum install -y httpd',
      'systemctl start httpd',
      'systemctl enable httpd',
      '',
      '# Create sample web application',
      'cat > /var/www/html/index.html << EOF',
      '<!DOCTYPE html>',
      '<html>',
      '<head>',
      '    <title>Global Load Balancer Demo</title>',
      '    <style>',
      '        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }',
      '        .region { background: #e3f2fd; padding: 20px; border-radius: 5px; margin: 20px auto; max-width: 600px; }',
      '        .healthy { color: #4caf50; font-weight: bold; }',
      '    </style>',
      '</head>',
      '<body>',
      '    <div class="region">',
      `        <h1>Hello from ${regionName}!</h1>`,
      '        <p class="healthy">Status: Healthy</p>',
      '        <p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>',
      '        <p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>',
      `        <p>Region: ${regionName}</p>`,
      '        <p>Timestamp: $(date)</p>',
      '    </div>',
      '</body>',
      '</html>',
      'EOF',
      '',
      '# Create health check endpoint',
      'cat > /var/www/html/health << EOF',
      '{',
      '    "status": "healthy",',
      `    "region": "${regionName}",`,
      '    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",',
      '    "instance_id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",',
      '    "availability_zone": "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"',
      '}',
      'EOF',
      '',
      '# Set proper permissions',
      'chmod 644 /var/www/html/index.html',
      'chmod 644 /var/www/html/health'
    );

    // Create Auto Scaling Group
    const autoScalingGroup = new AutoScalingGroup(this, 'AutoScalingGroup', {
      vpc,
      instanceType,
      machineImage: MachineImage.latestAmazonLinux2(),
      userData,
      securityGroup,
      minCapacity,
      maxCapacity,
      desiredCapacity,
      healthCheck: AsgHealthCheck.elb({
        grace: Duration.minutes(5),
      }),
      autoScalingGroupName: `global-lb-asg-${regionName.replace(/[^a-zA-Z0-9]/g, '-')}`,
    });

    // Attach ASG to target group
    autoScalingGroup.attachToApplicationTargetGroup(this.targetGroup);

    // Create Route53 health check
    this.healthCheck = new Route53HealthCheck(this, 'HealthCheck', {
      type: cdk.aws_route53.HealthCheckType.HTTP,
      resourcePath: '/health',
      fqdn: this.loadBalancer.loadBalancerDnsName,
      port: 80,
      requestInterval: Duration.seconds(30),
      failureThreshold: 3,
    });

    // Output important values
    new CfnOutput(this, 'LoadBalancerDnsName', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: `ALB DNS name for ${regionName}`,
      exportName: `GlobalLB-ALB-${regionName.replace(/[^a-zA-Z0-9]/g, '-')}`,
    });

    new CfnOutput(this, 'HealthCheckId', {
      value: this.healthCheck.healthCheckId,
      description: `Health check ID for ${regionName}`,
      exportName: `GlobalLB-HC-${regionName.replace(/[^a-zA-Z0-9]/g, '-')}`,
    });
  }
}

/**
 * Global CloudFront and Route53 stack
 */
class GlobalInfrastructureStack extends Stack {
  constructor(
    scope: Construct,
    id: string,
    props: GlobalLoadBalancingStackProps & {
      primaryStack: RegionalInfrastructureStack;
      secondaryStack: RegionalInfrastructureStack;
      tertiaryStack: RegionalInfrastructureStack;
    }
  ) {
    super(scope, id, props);

    const { primaryStack, secondaryStack, tertiaryStack } = props;
    const domainName = props.domainName ?? 'example.com';
    const notificationEmail = props.notificationEmail;

    // Create S3 bucket for fallback content
    const fallbackBucket = new Bucket(this, 'FallbackBucket', {
      bucketName: `global-lb-fallback-${this.account}-${this.region}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: BucketEncryption.S3_MANAGED,
      blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
      accessControl: BucketAccessControl.PRIVATE,
    });

    // Deploy fallback content to S3
    new BucketDeployment(this, 'DeployFallbackContent', {
      sources: [
        Source.data('index.html', `<!DOCTYPE html>
<html>
<head>
    <title>Service Temporarily Unavailable</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .message { background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px auto; max-width: 600px; }
        .status { color: #dc3545; font-size: 18px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="message">
        <h1>Service Temporarily Unavailable</h1>
        <p class="status">We're working to restore service as quickly as possible.</p>
        <p>Please try again in a few minutes. If the problem persists, contact support.</p>
        <p><small>Error Code: GLB-FALLBACK</small></p>
    </div>
</body>
</html>`),
        Source.data('health', `{
    "status": "maintenance",
    "message": "Service temporarily unavailable",
    "timestamp": "${new Date().toISOString()}"
}`),
      ],
      destinationBucket: fallbackBucket,
    });

    // Create Origin Access Identity for S3
    const originAccessIdentity = new OriginAccessIdentity(this, 'OriginAccessIdentity', {
      comment: 'OAI for global load balancer fallback content',
    });

    // Grant CloudFront access to S3 bucket
    fallbackBucket.grantRead(originAccessIdentity);

    // Create CloudFront distribution with origin groups
    const distribution = new Distribution(this, 'Distribution', {
      comment: 'Global load balancer with automatic failover',
      defaultRootObject: 'index.html',
      priceClass: PriceClass.PRICE_CLASS_100,
      httpVersion: HttpVersion.HTTP2,
      minimumProtocolVersion: SecurityPolicyProtocol.TLS_V1_2_2021,
      enableIpv6: true,
      
      // Configure default behavior
      defaultBehavior: {
        origin: new OriginGroup({
          primaryOrigin: new HttpOrigin(primaryStack.loadBalancer.loadBalancerDnsName, {
            protocolPolicy: cdk.aws_cloudfront.OriginProtocolPolicy.HTTP_ONLY,
            httpPort: 80,
            connectionAttempts: 3,
            connectionTimeout: Duration.seconds(10),
            readTimeout: Duration.seconds(30),
            keepaliveTimeout: Duration.seconds(5),
          }),
          fallbackOrigin: new OriginGroup({
            primaryOrigin: new HttpOrigin(secondaryStack.loadBalancer.loadBalancerDnsName, {
              protocolPolicy: cdk.aws_cloudfront.OriginProtocolPolicy.HTTP_ONLY,
              httpPort: 80,
              connectionAttempts: 3,
              connectionTimeout: Duration.seconds(10),
              readTimeout: Duration.seconds(30),
              keepaliveTimeout: Duration.seconds(5),
            }),
            fallbackOrigin: new OriginGroup({
              primaryOrigin: new HttpOrigin(tertiaryStack.loadBalancer.loadBalancerDnsName, {
                protocolPolicy: cdk.aws_cloudfront.OriginProtocolPolicy.HTTP_ONLY,
                httpPort: 80,
                connectionAttempts: 3,
                connectionTimeout: Duration.seconds(10),
                readTimeout: Duration.seconds(30),
                keepaliveTimeout: Duration.seconds(5),
              }),
              fallbackOrigin: new S3Origin(fallbackBucket, {
                originAccessIdentity,
              }),
              fallbackStatusCodes: [403, 404, 500, 502, 503, 504],
            }),
            fallbackStatusCodes: [403, 404, 500, 502, 503, 504],
          }),
          fallbackStatusCodes: [403, 404, 500, 502, 503, 504],
        }),
        viewerProtocolPolicy: ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: AllowedMethods.ALLOW_ALL,
        cachedMethods: CachedMethods.CACHE_GET_HEAD,
        compress: true,
        cachePolicy: CachePolicy.CACHING_OPTIMIZED,
        originRequestPolicy: OriginRequestPolicy.CORS_S3_ORIGIN,
      },

      // Configure additional behaviors
      additionalBehaviors: {
        '/health': {
          origin: new OriginGroup({
            primaryOrigin: new HttpOrigin(primaryStack.loadBalancer.loadBalancerDnsName, {
              protocolPolicy: cdk.aws_cloudfront.OriginProtocolPolicy.HTTP_ONLY,
              httpPort: 80,
            }),
            fallbackOrigin: new HttpOrigin(secondaryStack.loadBalancer.loadBalancerDnsName, {
              protocolPolicy: cdk.aws_cloudfront.OriginProtocolPolicy.HTTP_ONLY,
              httpPort: 80,
            }),
            fallbackStatusCodes: [403, 404, 500, 502, 503, 504],
          }),
          viewerProtocolPolicy: ViewerProtocolPolicy.HTTPS_ONLY,
          allowedMethods: AllowedMethods.ALLOW_GET_HEAD,
          cachedMethods: CachedMethods.CACHE_GET_HEAD,
          compress: true,
          cachePolicy: CachePolicy.CACHING_DISABLED,
        },
      },

      // Configure error responses
      errorResponses: [
        {
          httpStatus: 500,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: Duration.seconds(0),
        },
        {
          httpStatus: 502,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: Duration.seconds(0),
        },
        {
          httpStatus: 503,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: Duration.seconds(0),
        },
        {
          httpStatus: 504,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: Duration.seconds(0),
        },
      ],
    });

    // Create hosted zone
    const hostedZone = new HostedZone(this, 'HostedZone', {
      zoneName: domainName,
      comment: 'Global load balancer demo zone',
    });

    // Create weighted routing records
    new CnameRecord(this, 'WeightedPrimaryRecord', {
      zone: hostedZone,
      recordName: 'app',
      domainName: primaryStack.loadBalancer.loadBalancerDnsName,
      ttl: Duration.seconds(60),
      setIdentifier: 'us-east-1',
      weight: 100,
    });

    new CnameRecord(this, 'WeightedSecondaryRecord', {
      zone: hostedZone,
      recordName: 'app',
      domainName: secondaryStack.loadBalancer.loadBalancerDnsName,
      ttl: Duration.seconds(60),
      setIdentifier: 'eu-west-1',
      weight: 50,
    });

    new CnameRecord(this, 'WeightedTertiaryRecord', {
      zone: hostedZone,
      recordName: 'app',
      domainName: tertiaryStack.loadBalancer.loadBalancerDnsName,
      ttl: Duration.seconds(60),
      setIdentifier: 'ap-southeast-1',
      weight: 25,
    });

    // Create SNS topic for notifications
    const alertTopic = new Topic(this, 'AlertTopic', {
      topicName: 'global-lb-alerts',
      displayName: 'Global Load Balancer Alerts',
    });

    // Add email subscription if provided
    if (notificationEmail) {
      alertTopic.addSubscription(new EmailSubscription(notificationEmail));
    }

    // Create CloudWatch alarms for health checks
    const createHealthAlarm = (
      name: string,
      description: string,
      healthCheckId: string,
      region: string
    ) => {
      const alarm = new Alarm(this, `${name}HealthAlarm`, {
        alarmName: `global-lb-health-${region}`,
        alarmDescription: description,
        metric: new Metric({
          namespace: 'AWS/Route53',
          metricName: 'HealthCheckStatus',
          dimensionsMap: {
            HealthCheckId: healthCheckId,
          },
          statistic: 'Minimum',
          period: Duration.minutes(1),
        }),
        threshold: 1,
        comparisonOperator: ComparisonOperator.LESS_THAN_THRESHOLD,
        evaluationPeriods: 2,
        treatMissingData: TreatMissingData.BREACHING,
      });

      alarm.addAlarmAction(new SnsAction(alertTopic));
      alarm.addOkAction(new SnsAction(alertTopic));

      return alarm;
    };

    // Create health check alarms
    createHealthAlarm(
      'Primary',
      'Health check alarm for primary region',
      primaryStack.healthCheck.healthCheckId,
      'us-east-1'
    );

    createHealthAlarm(
      'Secondary',
      'Health check alarm for secondary region',
      secondaryStack.healthCheck.healthCheckId,
      'eu-west-1'
    );

    createHealthAlarm(
      'Tertiary',
      'Health check alarm for tertiary region',
      tertiaryStack.healthCheck.healthCheckId,
      'ap-southeast-1'
    );

    // Create CloudFront error rate alarm
    const cloudFrontErrorAlarm = new Alarm(this, 'CloudFrontErrorAlarm', {
      alarmName: 'global-lb-cloudfront-errors',
      alarmDescription: 'CloudFront error rate alarm',
      metric: new Metric({
        namespace: 'AWS/CloudFront',
        metricName: '4xxErrorRate',
        dimensionsMap: {
          DistributionId: distribution.distributionId,
        },
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 5,
      comparisonOperator: ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: TreatMissingData.NOT_BREACHING,
    });

    cloudFrontErrorAlarm.addAlarmAction(new SnsAction(alertTopic));

    // Create monitoring dashboard
    const dashboard = new Dashboard(this, 'MonitoringDashboard', {
      dashboardName: `Global-LoadBalancer-${this.stackName}`,
    });

    // Add health check status widget
    dashboard.addWidgets(
      new GraphWidget({
        title: 'Route53 Health Check Status',
        left: [
          new Metric({
            namespace: 'AWS/Route53',
            metricName: 'HealthCheckStatus',
            dimensionsMap: {
              HealthCheckId: primaryStack.healthCheck.healthCheckId,
            },
            statistic: 'Minimum',
            period: Duration.minutes(5),
            label: 'Primary Region',
          }),
          new Metric({
            namespace: 'AWS/Route53',
            metricName: 'HealthCheckStatus',
            dimensionsMap: {
              HealthCheckId: secondaryStack.healthCheck.healthCheckId,
            },
            statistic: 'Minimum',
            period: Duration.minutes(5),
            label: 'Secondary Region',
          }),
          new Metric({
            namespace: 'AWS/Route53',
            metricName: 'HealthCheckStatus',
            dimensionsMap: {
              HealthCheckId: tertiaryStack.healthCheck.healthCheckId,
            },
            statistic: 'Minimum',
            period: Duration.minutes(5),
            label: 'Tertiary Region',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Add CloudFront performance widget
    dashboard.addWidgets(
      new GraphWidget({
        title: 'CloudFront Performance',
        left: [
          new Metric({
            namespace: 'AWS/CloudFront',
            metricName: 'Requests',
            dimensionsMap: {
              DistributionId: distribution.distributionId,
            },
            statistic: 'Sum',
            period: Duration.minutes(5),
            label: 'Requests',
          }),
        ],
        right: [
          new Metric({
            namespace: 'AWS/CloudFront',
            metricName: '4xxErrorRate',
            dimensionsMap: {
              DistributionId: distribution.distributionId,
            },
            statistic: 'Average',
            period: Duration.minutes(5),
            label: '4xx Error Rate',
          }),
          new Metric({
            namespace: 'AWS/CloudFront',
            metricName: '5xxErrorRate',
            dimensionsMap: {
              DistributionId: distribution.distributionId,
            },
            statistic: 'Average',
            period: Duration.minutes(5),
            label: '5xx Error Rate',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Output important values
    new CfnOutput(this, 'CloudFrontDomainName', {
      value: distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: 'GlobalLB-CloudFront-Domain',
    });

    new CfnOutput(this, 'CloudFrontDistributionId', {
      value: distribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: 'GlobalLB-CloudFront-ID',
    });

    new CfnOutput(this, 'HostedZoneId', {
      value: hostedZone.hostedZoneId,
      description: 'Route53 hosted zone ID',
      exportName: 'GlobalLB-HostedZone-ID',
    });

    new CfnOutput(this, 'DomainName', {
      value: domainName,
      description: 'Domain name for the hosted zone',
      exportName: 'GlobalLB-Domain-Name',
    });

    new CfnOutput(this, 'FallbackBucketName', {
      value: fallbackBucket.bucketName,
      description: 'S3 fallback bucket name',
      exportName: 'GlobalLB-Fallback-Bucket',
    });

    new CfnOutput(this, 'SnsTopicArn', {
      value: alertTopic.topicArn,
      description: 'SNS topic ARN for alerts',
      exportName: 'GlobalLB-SNS-Topic',
    });
  }
}

/**
 * Main CDK application for global load balancing
 */
class GlobalLoadBalancingApp extends cdk.App {
  constructor() {
    super();

    // Configuration - modify these values as needed
    const config: GlobalLoadBalancingStackProps = {
      domainName: this.node.tryGetContext('domainName') || 'example.com',
      notificationEmail: this.node.tryGetContext('notificationEmail'),
      minCapacity: this.node.tryGetContext('minCapacity') || 1,
      maxCapacity: this.node.tryGetContext('maxCapacity') || 3,
      desiredCapacity: this.node.tryGetContext('desiredCapacity') || 2,
      instanceType: InstanceType.of(
        InstanceClass.T3,
        this.node.tryGetContext('instanceSize') || InstanceSize.MICRO
      ),
    };

    // Create regional infrastructure stacks
    const primaryStack = new RegionalInfrastructureStack(
      this,
      'GlobalLB-Primary',
      {
        ...config,
        regionName: 'us-east-1',
        env: {
          account: process.env.CDK_DEFAULT_ACCOUNT,
          region: 'us-east-1',
        },
      }
    );

    const secondaryStack = new RegionalInfrastructureStack(
      this,
      'GlobalLB-Secondary',
      {
        ...config,
        regionName: 'eu-west-1',
        env: {
          account: process.env.CDK_DEFAULT_ACCOUNT,
          region: 'eu-west-1',
        },
      }
    );

    const tertiaryStack = new RegionalInfrastructureStack(
      this,
      'GlobalLB-Tertiary',
      {
        ...config,
        regionName: 'ap-southeast-1',
        env: {
          account: process.env.CDK_DEFAULT_ACCOUNT,
          region: 'ap-southeast-1',
        },
      }
    );

    // Create global infrastructure stack (CloudFront and Route53)
    new GlobalInfrastructureStack(this, 'GlobalLB-Global', {
      ...config,
      primaryStack,
      secondaryStack,
      tertiaryStack,
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: 'us-east-1', // Global resources must be in us-east-1
      },
    });

    // Add stack dependencies
    secondaryStack.addDependency(primaryStack);
    tertiaryStack.addDependency(secondaryStack);
  }
}

// Create and run the application
new GlobalLoadBalancingApp();