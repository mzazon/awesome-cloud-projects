#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Properties for the EdgeApplicationStack
 */
export interface EdgeApplicationStackProps extends cdk.StackProps {
  /**
   * The Wavelength Zone to deploy edge resources to
   * @example "us-west-2-wl1-las-wlz-1"
   */
  readonly wavelengthZone: string;

  /**
   * Domain name for the application (optional)
   * If provided, Route 53 hosted zone and DNS records will be created
   */
  readonly domainName?: string;

  /**
   * Project name prefix for resource naming
   * @default "edge-app"
   */
  readonly projectName?: string;

  /**
   * EC2 instance type for Wavelength deployment
   * @default "t3.medium"
   */
  readonly instanceType?: string;

  /**
   * Enable detailed monitoring for EC2 instances
   * @default false
   */
  readonly enableDetailedMonitoring?: boolean;
}

/**
 * CDK Stack for Low-Latency Edge Applications with Wavelength
 * 
 * This stack creates:
 * - VPC extended to Wavelength Zone with carrier gateway
 * - EC2 instance in Wavelength Zone running edge application
 * - Application Load Balancer for high availability
 * - S3 bucket for static assets
 * - CloudFront distribution with multiple origins
 * - Route 53 DNS configuration (optional)
 */
export class EdgeApplicationStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly wavelengthSubnet: ec2.Subnet;
  public readonly edgeInstance: ec2.Instance;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly staticAssetsBucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;
  public readonly hostedZone?: route53.HostedZone;

  constructor(scope: Construct, id: string, props: EdgeApplicationStackProps) {
    super(scope, id, props);

    const projectName = props.projectName || 'edge-app';
    const instanceType = props.instanceType || 't3.medium';
    const enableDetailedMonitoring = props.enableDetailedMonitoring || false;

    // Create VPC for edge application
    this.vpc = new ec2.Vpc(this, 'EdgeApplicationVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      vpcName: `${projectName}-vpc`,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'regional-public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'regional-private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
    });

    // Create Wavelength subnet manually since CDK doesn't have native support
    this.wavelengthSubnet = new ec2.Subnet(this, 'WavelengthSubnet', {
      vpc: this.vpc,
      cidr: '10.0.100.0/24',
      availabilityZone: props.wavelengthZone,
      subnetName: `${projectName}-wavelength-subnet`,
    });

    // Create carrier gateway for Wavelength connectivity
    const carrierGateway = new ec2.CfnCarrierGateway(this, 'CarrierGateway', {
      vpcId: this.vpc.vpcId,
      tags: [
        {
          key: 'Name',
          value: `${projectName}-carrier-gateway`,
        },
      ],
    });

    // Create route table for Wavelength subnet
    const wavelengthRouteTable = new ec2.CfnRouteTable(this, 'WavelengthRouteTable', {
      vpcId: this.vpc.vpcId,
      tags: [
        {
          key: 'Name',
          value: `${projectName}-wavelength-rt`,
        },
      ],
    });

    // Add route to carrier gateway
    new ec2.CfnRoute(this, 'CarrierGatewayRoute', {
      routeTableId: wavelengthRouteTable.ref,
      destinationCidrBlock: '0.0.0.0/0',
      carrierGatewayId: carrierGateway.ref,
    });

    // Associate route table with Wavelength subnet
    new ec2.CfnSubnetRouteTableAssociation(this, 'WavelengthSubnetRouteTableAssociation', {
      subnetId: this.wavelengthSubnet.subnetId,
      routeTableId: wavelengthRouteTable.ref,
    });

    // Security group for Wavelength edge servers
    const wavelengthSecurityGroup = new ec2.SecurityGroup(this, 'WavelengthSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Wavelength edge applications',
      securityGroupName: `${projectName}-wavelength-sg`,
    });

    // Allow HTTP/HTTPS traffic from mobile clients
    wavelengthSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from mobile clients'
    );

    wavelengthSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from mobile clients'
    );

    // Allow custom application port
    wavelengthSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(8080),
      'Allow application traffic on port 8080'
    );

    // Security group for regional backend services
    const regionalSecurityGroup = new ec2.SecurityGroup(this, 'RegionalSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for regional backend services',
      securityGroupName: `${projectName}-regional-sg`,
    });

    // Allow traffic from Wavelength security group
    regionalSecurityGroup.addIngressRule(
      wavelengthSecurityGroup,
      ec2.Port.tcp(80),
      'Allow traffic from Wavelength subnet'
    );

    // User data script for edge application setup
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      'yum update -y',
      'yum install -y docker',
      'systemctl start docker',
      'systemctl enable docker',
      'usermod -a -G docker ec2-user',
      '',
      '# Run edge application container',
      'docker run -d --name edge-app -p 8080:8080 --restart unless-stopped nginx:alpine',
      '',
      '# Configure nginx for edge application',
      'sleep 10',
      'docker exec edge-app sh -c \'echo "',
      'server {',
      '    listen 8080;',
      '    location / {',
      '        return 200 \\"Edge Server Response Time: \\$(date +%s%3N)ms\\";',
      '        add_header Content-Type text/plain;',
      '    }',
      '    location /health {',
      '        return 200 \\"healthy\\";',
      '        add_header Content-Type text/plain;',
      '    }',
      '}" > /etc/nginx/conf.d/default.conf\'',
      '',
      'docker restart edge-app'
    );

    // Launch EC2 instance in Wavelength Zone
    this.edgeInstance = new ec2.Instance(this, 'WavelengthEdgeInstance', {
      vpc: this.vpc,
      vpcSubnets: {
        subnets: [this.wavelengthSubnet],
      },
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      securityGroup: wavelengthSecurityGroup,
      userData: userData,
      instanceName: `${projectName}-wavelength-server`,
      detailedMonitoring: enableDetailedMonitoring,
    });

    // Create Application Load Balancer in Wavelength Zone
    this.loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'WavelengthALB', {
      vpc: this.vpc,
      vpcSubnets: {
        subnets: [this.wavelengthSubnet],
      },
      internetFacing: false, // Internal ALB for carrier gateway traffic
      securityGroup: wavelengthSecurityGroup,
      loadBalancerName: `${projectName}-wavelength-alb`,
    });

    // Create target group for edge instances
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'EdgeTargetGroup', {
      vpc: this.vpc,
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetGroupName: `${projectName}-edge-targets`,
      healthCheck: {
        enabled: true,
        healthyHttpCodes: '200',
        path: '/health',
        interval: cdk.Duration.seconds(30),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      targets: [
        new elbv2.InstanceTarget(this.edgeInstance, 8080),
      ],
    });

    // Create listener for load balancer
    const listener = this.loadBalancer.addListener('HttpListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultAction: elbv2.ListenerAction.forward([targetGroup]),
    });

    // Create S3 bucket for static assets
    this.staticAssetsBucket = new s3.Bucket(this, 'StaticAssetsBucket', {
      bucketName: `${projectName}-static-assets-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create sample static content deployment
    new s3.BucketDeployment(this, 'StaticContentDeployment', {
      sources: [
        s3.Source.data(
          'index.html',
          `<!DOCTYPE html>
<html>
<head>
    <title>Edge Application</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .latency-test { background: #f0f0f0; padding: 20px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Low-Latency Edge Application</h1>
    <div class="latency-test">
        <h2>Latency Test</h2>
        <p>Edge Server: <span id="edge-response">Testing...</span></p>
        <p>Load time: <span id="load-time"></span>ms</p>
    </div>
    <script>
        const startTime = performance.now();
        window.onload = function() {
            document.getElementById('load-time').textContent = 
                Math.round(performance.now() - startTime);
            
            // Test edge server latency
            fetch('/api/health')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('edge-response').textContent = data;
                })
                .catch(error => {
                    document.getElementById('edge-response').textContent = 'Error: ' + error.message;
                });
        };
    </script>
</body>
</html>`
        ),
      ],
      destinationBucket: this.staticAssetsBucket,
    });

    // Create Origin Access Control for CloudFront
    const originAccessControl = new cloudfront.S3OriginAccessControl(this, 'S3OriginAccessControl', {
      description: `OAC for ${projectName} S3 static assets`,
    });

    // Create CloudFront distribution with multiple origins
    this.distribution = new cloudfront.Distribution(this, 'EdgeApplicationDistribution', {
      comment: 'Edge application with Wavelength and S3 origins',
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_ALL,
      
      // Default behavior for static content (S3)
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.staticAssetsBucket, {
          originAccessControl: originAccessControl,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        compress: true,
      },
      
      // Additional behavior for API calls (Wavelength ALB)
      additionalBehaviors: {
        '/api/*': {
          origin: new origins.LoadBalancerV2Origin(this.loadBalancer, {
            protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
            httpPort: 80,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
          compress: false,
        },
      },
    });

    // Grant CloudFront access to S3 bucket
    this.staticAssetsBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudFrontServicePrincipal',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
        actions: ['s3:GetObject'],
        resources: [this.staticAssetsBucket.arnForObjects('*')],
        conditions: {
          StringEquals: {
            'AWS:SourceArn': `arn:aws:cloudfront::${this.account}:distribution/${this.distribution.distributionId}`,
          },
        },
      })
    );

    // Create Route 53 resources if domain name is provided
    if (props.domainName) {
      this.hostedZone = new route53.HostedZone(this, 'HostedZone', {
        zoneName: props.domainName,
        comment: `Edge application DNS zone for ${projectName}`,
      });

      // Create CNAME record for the application
      new route53.CnameRecord(this, 'AppCnameRecord', {
        zone: this.hostedZone,
        recordName: 'app',
        domainName: this.distribution.distributionDomainName,
        ttl: cdk.Duration.minutes(5),
        comment: 'CNAME record for edge application',
      });
    }

    // Stack outputs
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the edge application',
      exportName: `${projectName}-vpc-id`,
    });

    new cdk.CfnOutput(this, 'WavelengthSubnetId', {
      value: this.wavelengthSubnet.subnetId,
      description: 'Wavelength subnet ID',
      exportName: `${projectName}-wavelength-subnet-id`,
    });

    new cdk.CfnOutput(this, 'EdgeInstanceId', {
      value: this.edgeInstance.instanceId,
      description: 'EC2 instance ID in Wavelength Zone',
      exportName: `${projectName}-edge-instance-id`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: 'Application Load Balancer DNS name',
      exportName: `${projectName}-alb-dns`,
    });

    new cdk.CfnOutput(this, 'StaticAssetsBucketName', {
      value: this.staticAssetsBucket.bucketName,
      description: 'S3 bucket name for static assets',
      exportName: `${projectName}-static-assets-bucket`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: `${projectName}-cloudfront-distribution-id`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: `${projectName}-cloudfront-domain`,
    });

    if (this.hostedZone) {
      new cdk.CfnOutput(this, 'HostedZoneId', {
        value: this.hostedZone.hostedZoneId,
        description: 'Route 53 hosted zone ID',
        exportName: `${projectName}-hosted-zone-id`,
      });

      new cdk.CfnOutput(this, 'ApplicationUrl', {
        value: `https://app.${props.domainName}`,
        description: 'Application URL with custom domain',
        exportName: `${projectName}-app-url`,
      });
    }

    new cdk.CfnOutput(this, 'CarrierGatewayId', {
      value: carrierGateway.ref,
      description: 'Carrier Gateway ID for Wavelength connectivity',
      exportName: `${projectName}-carrier-gateway-id`,
    });
  }
}

// CDK App
const app = new cdk.App();

// Get context values or use defaults
const wavelengthZone = app.node.tryGetContext('wavelengthZone') || 'us-west-2-wl1-las-wlz-1';
const domainName = app.node.tryGetContext('domainName');
const projectName = app.node.tryGetContext('projectName') || 'edge-app';
const instanceType = app.node.tryGetContext('instanceType') || 't3.medium';
const enableDetailedMonitoring = app.node.tryGetContext('enableDetailedMonitoring') === 'true';

// Create the main stack
new EdgeApplicationStack(app, 'EdgeApplicationStack', {
  wavelengthZone,
  domainName,
  projectName,
  instanceType,
  enableDetailedMonitoring,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Low-latency edge application with AWS Wavelength and CloudFront',
  tags: {
    Project: projectName,
    Component: 'edge-computing',
    Environment: 'production',
  },
});

app.synth();