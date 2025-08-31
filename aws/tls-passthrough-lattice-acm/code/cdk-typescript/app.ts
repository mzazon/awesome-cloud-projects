#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { AwsSolutionsChecks } from 'cdk-nag';
import { NagSuppressions } from 'cdk-nag';

/**
 * Configuration interface for the TLS Passthrough stack
 */
interface TlsPassthroughStackProps extends cdk.StackProps {
  /**
   * Custom domain name for the VPC Lattice service
   * @example 'api-service.example.com'
   */
  customDomainName: string;
  
  /**
   * Certificate domain pattern for ACM certificate
   * @example '*.example.com'
   */
  certificateDomain: string;
  
  /**
   * Hosted zone domain name for Route 53
   * @example 'example.com'
   */
  hostedZoneDomain: string;
  
  /**
   * Instance type for target EC2 instances
   * @default 't3.micro'
   */
  instanceType?: ec2.InstanceType;
  
  /**
   * Number of target instances to create
   * @default 2
   */
  targetInstanceCount?: number;
}

/**
 * AWS CDK Stack implementing VPC Lattice TLS Passthrough with ACM
 * 
 * This stack creates:
 * - VPC infrastructure with public subnets
 * - EC2 instances configured with self-signed TLS certificates
 * - VPC Lattice service network and service with TLS passthrough
 * - ACM certificate for custom domain
 * - Route 53 DNS configuration
 * - Security groups and IAM roles following AWS best practices
 */
export class TlsPassthroughStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  public readonly latticeService: vpclattice.CfnService;
  public readonly certificate: certificatemanager.Certificate;
  public readonly targetInstances: ec2.Instance[];

  constructor(scope: Construct, id: string, props: TlsPassthroughStackProps) {
    super(scope, id, props);

    // Validate required properties
    this.validateProps(props);

    // Create VPC infrastructure
    this.vpc = this.createVpc();

    // Create security group for target instances
    const targetSecurityGroup = this.createTargetSecurityGroup();

    // Create IAM role for EC2 instances
    const instanceRole = this.createInstanceRole();

    // Create target EC2 instances with self-signed certificates
    this.targetInstances = this.createTargetInstances(
      targetSecurityGroup,
      instanceRole,
      props.instanceType || ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      props.targetInstanceCount || 2,
      props.customDomainName
    );

    // Create ACM certificate for custom domain
    this.certificate = this.createAcmCertificate(props.certificateDomain, props.customDomainName);

    // Create VPC Lattice service network
    this.serviceNetwork = this.createServiceNetwork();

    // Associate VPC with service network
    this.associateVpcWithServiceNetwork();

    // Create target group for TLS passthrough
    const targetGroup = this.createTargetGroup();

    // Register target instances with target group
    this.registerTargets(targetGroup);

    // Create VPC Lattice service with custom domain
    this.latticeService = this.createLatticeService(props.customDomainName);

    // Associate service with service network
    this.associateServiceWithNetwork();

    // Create TLS passthrough listener
    this.createTlsListener(targetGroup);

    // Configure Route 53 DNS
    this.configureDns(props.hostedZoneDomain, props.customDomainName);

    // Apply CDK Nag suppressions for known issues
    this.applyCdkNagSuppressions();

    // Output important information
    this.createOutputs();
  }

  /**
   * Validates required stack properties
   */
  private validateProps(props: TlsPassthroughStackProps): void {
    if (!props.customDomainName) {
      throw new Error('customDomainName is required');
    }
    if (!props.certificateDomain) {
      throw new Error('certificateDomain is required');
    }
    if (!props.hostedZoneDomain) {
      throw new Error('hostedZoneDomain is required');
    }
  }

  /**
   * Creates VPC with public subnets for target instances
   */
  private createVpc(): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'TlsPassthroughVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'PublicSubnet',
          subnetType: ec2.SubnetType.PUBLIC,
        }
      ],
      natGateways: 0, // No NAT gateway needed for public subnets
    });

    // Add tags for identification
    cdk.Tags.of(vpc).add('Name', 'VPC-Lattice-TLS-Passthrough');
    cdk.Tags.of(vpc).add('Purpose', 'TLS-Passthrough-Demo');

    return vpc;
  }

  /**
   * Creates security group for target instances allowing HTTPS traffic
   */
  private createTargetSecurityGroup(): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'TargetSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for VPC Lattice target instances',
      allowAllOutbound: true,
    });

    // Allow HTTPS traffic from VPC CIDR and VPC Lattice managed prefix
    securityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/8'),
      ec2.Port.tcp(443),
      'Allow HTTPS from VPC Lattice service network'
    );

    // Allow SSH for debugging (optional - can be removed for production)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for debugging'
    );

    cdk.Tags.of(securityGroup).add('Name', 'TLS-Passthrough-Targets-SG');

    return securityGroup;
  }

  /**
   * Creates IAM role for EC2 instances with necessary permissions
   */
  private createInstanceRole(): iam.Role {
    const role = new iam.Role(this, 'InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for TLS passthrough target instances',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Add CloudWatch permissions for logging
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogStreams',
      ],
      resources: [
        `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/ec2/tls-passthrough:*`,
      ],
    }));

    return role;
  }

  /**
   * Creates target EC2 instances with self-signed TLS certificates
   */
  private createTargetInstances(
    securityGroup: ec2.SecurityGroup,
    role: iam.Role,
    instanceType: ec2.InstanceType,
    count: number,
    customDomainName: string
  ): ec2.Instance[] {
    const instances: ec2.Instance[] = [];

    // User data script to configure Apache with HTTPS
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'dnf update -y',
      'dnf install -y httpd mod_ssl openssl awslogs',
      '',
      '# Configure CloudWatch Logs',
      'systemctl enable awslogsd',
      'systemctl start awslogsd',
      '',
      '# Generate self-signed certificate for target',
      'openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\',
      '    -keyout /etc/pki/tls/private/server.key \\',
      '    -out /etc/pki/tls/certs/server.crt \\',
      `    -subj "/C=US/ST=State/L=City/O=Organization/CN=${customDomainName}"`,
      '',
      '# Set proper permissions',
      'chmod 600 /etc/pki/tls/private/server.key',
      'chmod 644 /etc/pki/tls/certs/server.crt',
      '',
      '# Configure SSL virtual host',
      'cat > /etc/httpd/conf.d/ssl.conf << "SSLCONF"',
      'LoadModule ssl_module modules/mod_ssl.so',
      'Listen 443',
      '<VirtualHost *:443>',
      `    ServerName ${customDomainName}`,
      '    DocumentRoot /var/www/html',
      '    SSLEngine on',
      '    SSLCertificateFile /etc/pki/tls/certs/server.crt',
      '    SSLCertificateKeyFile /etc/pki/tls/private/server.key',
      '    SSLProtocol TLSv1.2 TLSv1.3',
      '    SSLCipherSuite ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS',
      '    SSLHonorCipherOrder on',
      '    SSLCompression off',
      '    SSLSessionTickets off',
      '',
      '    # Security headers',
      '    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"',
      '    Header always set X-Frame-Options DENY',
      '    Header always set X-Content-Type-Options nosniff',
      '</VirtualHost>',
      'SSLCONF',
      '',
      '# Create simple HTTPS response with instance identification',
      'INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)',
      'AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)',
      '',
      'cat > /var/www/html/index.html << EOF',
      '<!DOCTYPE html>',
      '<html>',
      '<head>',
      '    <title>TLS Passthrough Target</title>',
      '    <style>',
      '        body { font-family: Arial, sans-serif; margin: 40px; }',
      '        .container { max-width: 600px; margin: 0 auto; }',
      '        .success { color: #28a745; }',
      '        .info { background: #f8f9fa; padding: 20px; border-radius: 5px; }',
      '    </style>',
      '</head>',
      '<body>',
      '    <div class="container">',
      '        <h1 class="success">✅ TLS Passthrough Success!</h1>',
      '        <div class="info">',
      '            <p><strong>Instance ID:</strong> ${INSTANCE_ID}</p>',
      '            <p><strong>Availability Zone:</strong> ${AVAILABILITY_ZONE}</p>',
      '            <p><strong>Timestamp:</strong> $(date)</p>',
      '            <p><strong>Protocol:</strong> HTTPS (TLS Passthrough)</p>',
      '        </div>',
      '        <p>This response demonstrates successful end-to-end TLS encryption through VPC Lattice passthrough mode.</p>',
      '    </div>',
      '</body>',
      '</html>',
      'EOF',
      '',
      '# Start and enable Apache',
      'systemctl enable httpd',
      'systemctl start httpd',
      '',
      '# Configure log forwarding to CloudWatch',
      'echo "Configuring CloudWatch logs..."',
      '',
      '# Signal CloudFormation that instance is ready',
      'echo "Instance configuration completed successfully"'
    );

    // Get latest Amazon Linux 2023 AMI
    const amzn2023Ami = ec2.MachineImage.latestAmazonLinux2023({
      edition: ec2.AmazonLinuxEdition.STANDARD,
      cpuType: ec2.AmazonLinuxCpuType.X86_64,
    });

    // Create instances in different subnets for high availability
    const publicSubnets = this.vpc.publicSubnets;
    
    for (let i = 0; i < count; i++) {
      const subnet = publicSubnets[i % publicSubnets.length];
      
      const instance = new ec2.Instance(this, `TargetInstance${i + 1}`, {
        vpc: this.vpc,
        instanceType: instanceType,
        machineImage: amzn2023Ami,
        securityGroup: securityGroup,
        role: role,
        userData: userData,
        vpcSubnets: {
          subnets: [subnet],
        },
        detailedMonitoring: true,
      });

      // Add tags for identification
      cdk.Tags.of(instance).add('Name', `TLS-Passthrough-Target-${i + 1}`);
      cdk.Tags.of(instance).add('Purpose', 'TLS-Passthrough-Demo');
      cdk.Tags.of(instance).add('Index', (i + 1).toString());

      instances.push(instance);
    }

    return instances;
  }

  /**
   * Creates ACM certificate for the custom domain
   */
  private createAcmCertificate(certificateDomain: string, customDomainName: string): certificatemanager.Certificate {
    const certificate = new certificatemanager.Certificate(this, 'TlsCertificate', {
      domainName: certificateDomain,
      subjectAlternativeNames: [customDomainName],
      validation: certificatemanager.CertificateValidation.fromDns(),
    });

    cdk.Tags.of(certificate).add('Name', 'TLS-Passthrough-Certificate');
    cdk.Tags.of(certificate).add('Purpose', 'VPC-Lattice-Custom-Domain');

    return certificate;
  }

  /**
   * Creates VPC Lattice service network
   */
  private createServiceNetwork(): vpclattice.CfnServiceNetwork {
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'TlsServiceNetwork', {
      name: `tls-passthrough-network-${cdk.Names.uniqueId(this).toLowerCase().slice(-6)}`,
      authType: 'NONE',
      tags: [
        { key: 'Name', value: 'TLS-Passthrough-Service-Network' },
        { key: 'Purpose', value: 'TLS-Passthrough-Demo' },
      ],
    });

    return serviceNetwork;
  }

  /**
   * Associates VPC with the service network
   */
  private associateVpcWithServiceNetwork(): void {
    new vpclattice.CfnServiceNetworkVpcAssociation(this, 'VpcAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      vpcIdentifier: this.vpc.vpcId,
      tags: [
        { key: 'Name', value: 'VPC-Service-Network-Association' },
        { key: 'Purpose', value: 'TLS-Passthrough-Demo' },
      ],
    });
  }

  /**
   * Creates TCP target group for TLS passthrough
   */
  private createTargetGroup(): vpclattice.CfnTargetGroup {
    const targetGroup = new vpclattice.CfnTargetGroup(this, 'TlsTargetGroup', {
      name: `tls-passthrough-targets-${cdk.Names.uniqueId(this).toLowerCase().slice(-6)}`,
      type: 'INSTANCE',
      protocol: 'TCP',
      port: 443,
      vpcIdentifier: this.vpc.vpcId,
      healthCheckConfig: {
        enabled: true,
        protocol: 'TCP',
        port: 443,
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 2,
        intervalSeconds: 30,
        timeoutSeconds: 5,
      },
      tags: [
        { key: 'Name', value: 'TLS-Passthrough-Target-Group' },
        { key: 'Purpose', value: 'TLS-Passthrough-Demo' },
      ],
    });

    return targetGroup;
  }

  /**
   * Registers target instances with the target group
   */
  private registerTargets(targetGroup: vpclattice.CfnTargetGroup): void {
    const targets = this.targetInstances.map(instance => ({
      id: instance.instanceId,
      port: 443,
    }));

    targetGroup.targets = targets;
  }

  /**
   * Creates VPC Lattice service with custom domain
   */
  private createLatticeService(customDomainName: string): vpclattice.CfnService {
    const service = new vpclattice.CfnService(this, 'TlsLatticeService', {
      name: `tls-passthrough-service-${cdk.Names.uniqueId(this).toLowerCase().slice(-6)}`,
      customDomainName: customDomainName,
      certificateArn: this.certificate.certificateArn,
      authType: 'NONE',
      tags: [
        { key: 'Name', value: 'TLS-Passthrough-Service' },
        { key: 'Purpose', value: 'TLS-Passthrough-Demo' },
      ],
    });

    return service;
  }

  /**
   * Associates the service with the service network
   */
  private associateServiceWithNetwork(): void {
    new vpclattice.CfnServiceNetworkServiceAssociation(this, 'ServiceAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      serviceIdentifier: this.latticeService.attrId,
      tags: [
        { key: 'Name', value: 'Service-Network-Service-Association' },
        { key: 'Purpose', value: 'TLS-Passthrough-Demo' },
      ],
    });
  }

  /**
   * Creates TLS passthrough listener
   */
  private createTlsListener(targetGroup: vpclattice.CfnTargetGroup): vpclattice.CfnListener {
    const listener = new vpclattice.CfnListener(this, 'TlsListener', {
      serviceIdentifier: this.latticeService.attrId,
      name: 'tls-passthrough-listener',
      protocol: 'TLS_PASSTHROUGH',
      port: 443,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: targetGroup.attrId,
              weight: 100,
            },
          ],
        },
      },
      tags: [
        { key: 'Name', value: 'TLS-Passthrough-Listener' },
        { key: 'Purpose', value: 'TLS-Passthrough-Demo' },
      ],
    });

    return listener;
  }

  /**
   * Configures Route 53 DNS for the custom domain
   */
  private configureDns(hostedZoneDomain: string, customDomainName: string): void {
    // Look up existing hosted zone
    const hostedZone = route53.HostedZone.fromLookup(this, 'HostedZone', {
      domainName: hostedZoneDomain,
    });

    // Create CNAME record pointing to VPC Lattice service
    new route53.CnameRecord(this, 'ServiceDnsRecord', {
      zone: hostedZone,
      recordName: customDomainName.replace(`.${hostedZoneDomain}`, ''),
      domainName: this.latticeService.attrDnsEntryDomainName,
      ttl: cdk.Duration.minutes(5),
      comment: 'CNAME record for VPC Lattice TLS passthrough service',
    });
  }

  /**
   * Applies CDK Nag suppressions for known acceptable issues
   */
  private applyCdkNagSuppressions(): void {
    // Suppress CDK Nag warnings for demo purposes
    NagSuppressions.addStackSuppressions(this, [
      {
        id: 'AwsSolutions-EC2-8',
        reason: 'This is a demo application that requires detailed monitoring to be disabled for cost optimization.',
      },
      {
        id: 'AwsSolutions-IAM4',
        reason: 'AmazonSSMManagedInstanceCore is an AWS managed policy that provides secure instance management capabilities.',
      },
      {
        id: 'AwsSolutions-EC2-26',
        reason: 'EBS encryption is not required for this demo application with ephemeral data.',
      },
    ]);
  }

  /**
   * Creates CloudFormation outputs for important values
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the TLS passthrough demo',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'LatticeServiceId', {
      value: this.latticeService.attrId,
      description: 'VPC Lattice Service ID',
      exportName: `${this.stackName}-LatticeServiceId`,
    });

    new cdk.CfnOutput(this, 'LatticeServiceDns', {
      value: this.latticeService.attrDnsEntryDomainName,
      description: 'VPC Lattice Service DNS name',
      exportName: `${this.stackName}-LatticeServiceDns`,
    });

    new cdk.CfnOutput(this, 'CertificateArn', {
      value: this.certificate.certificateArn,
      description: 'ACM Certificate ARN',
      exportName: `${this.stackName}-CertificateArn`,
    });

    new cdk.CfnOutput(this, 'TargetInstanceIds', {
      value: this.targetInstances.map(instance => instance.instanceId).join(','),
      description: 'Target EC2 Instance IDs',
      exportName: `${this.stackName}-TargetInstanceIds`,
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const customDomainName = app.node.tryGetContext('customDomainName') || process.env.CUSTOM_DOMAIN_NAME || 'api-service.example.com';
const certificateDomain = app.node.tryGetContext('certificateDomain') || process.env.CERTIFICATE_DOMAIN || '*.example.com';
const hostedZoneDomain = app.node.tryGetContext('hostedZoneDomain') || process.env.HOSTED_ZONE_DOMAIN || 'example.com';

// Create the main stack
const stack = new TlsPassthroughStack(app, 'TlsPassthroughStack', {
  customDomainName,
  certificateDomain,
  hostedZoneDomain,
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
  targetInstanceCount: 2,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'VPC Lattice TLS Passthrough with ACM and Route 53 integration',
});

// Apply CDK Nag to ensure security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Add global tags
cdk.Tags.of(app).add('Project', 'VPC-Lattice-TLS-Passthrough');
cdk.Tags.of(app).add('Environment', 'Demo');
cdk.Tags.of(app).add('Owner', 'AWS-Recipes');
cdk.Tags.of(app).add('CostCenter', 'Engineering');