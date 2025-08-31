#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lightsail from 'aws-cdk-lib/aws-lightsail';
import * as crypto from 'crypto';

/**
 * Props for the SimpleWebsiteHostingLightsailStack
 */
export interface SimpleWebsiteHostingLightsailStackProps extends cdk.StackProps {
  /**
   * The name prefix for Lightsail resources
   * @default 'wordpress-site'
   */
  readonly instanceNamePrefix?: string;

  /**
   * The Lightsail bundle ID for the instance size
   * Available options: nano_3_0, micro_3_0, small_3_0, medium_3_0, large_3_0, xlarge_3_0, 2xlarge_3_0
   * @default 'nano_3_0' (smallest and most cost-effective)
   */
  readonly bundleId?: string;

  /**
   * The availability zone for the Lightsail instance
   * Must be in the format: {region}{zone} (e.g., us-east-1a, us-west-2b)
   * @default Uses the first availability zone in the stack's region
   */
  readonly availabilityZone?: string;

  /**
   * Whether to create a static IP address for the instance
   * @default true
   */
  readonly createStaticIp?: boolean;

  /**
   * Custom domain name to configure (optional)
   * If provided, a DNS zone will be created
   */
  readonly domainName?: string;

  /**
   * Tags to apply to all Lightsail resources
   * @default { Purpose: 'WebsiteHosting', Environment: 'Production' }
   */
  readonly resourceTags?: { [key: string]: string };
}

/**
 * AWS CDK Stack for Simple Website Hosting with Lightsail
 * 
 * This stack creates:
 * - A Lightsail WordPress instance with pre-configured LAMP stack
 * - A static IP address for consistent access
 * - Firewall rules for HTTP/HTTPS traffic
 * - Optional DNS zone for custom domain configuration
 * 
 * The WordPress instance includes:
 * - Latest WordPress version
 * - PHP 8.x
 * - MySQL/MariaDB database
 * - Apache web server
 * - SSL/TLS support via Let's Encrypt
 */
export class SimpleWebsiteHostingLightsailStack extends cdk.Stack {
  public readonly instance: lightsail.CfnInstance;
  public readonly staticIp?: lightsail.CfnStaticIp;
  public readonly dnsZone?: lightsail.CfnDomain;
  public readonly instanceName: string;
  public readonly staticIpName?: string;

  constructor(scope: Construct, id: string, props?: SimpleWebsiteHostingLightsailStackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource naming
    const randomSuffix = crypto.randomBytes(3).toString('hex');
    const namePrefix = props?.instanceNamePrefix || 'wordpress-site';
    
    // Configure resource names
    this.instanceName = `${namePrefix}-${randomSuffix}`;
    this.staticIpName = props?.createStaticIp !== false ? `${namePrefix}-ip-${randomSuffix}` : undefined;

    // Determine availability zone
    const availabilityZone = props?.availabilityZone || `${this.region}a`;

    // Default resource tags
    const defaultTags = {
      Purpose: 'WebsiteHosting',
      Environment: 'Production',
      ManagedBy: 'AWS-CDK',
      Recipe: 'simple-website-hosting-lightsail'
    };
    const resourceTags = { ...defaultTags, ...props?.resourceTags };

    // Convert tags to Lightsail tag format
    const lightsailTags = Object.entries(resourceTags).map(([key, value]) => ({
      key,
      value
    }));

    // Create WordPress Lightsail instance
    this.instance = new lightsail.CfnInstance(this, 'WordPressInstance', {
      instanceName: this.instanceName,
      availabilityZone: availabilityZone,
      blueprintId: 'wordpress',
      bundleId: props?.bundleId || 'nano_3_0',
      tags: lightsailTags,
      userData: this.generateUserData()
    });

    // Create static IP address if requested
    if (props?.createStaticIp !== false && this.staticIpName) {
      this.staticIp = new lightsail.CfnStaticIp(this, 'StaticIp', {
        staticIpName: this.staticIpName,
        attachedTo: this.instanceName
      });

      // Ensure static IP is created after the instance
      this.staticIp.addDependency(this.instance);
    }

    // Create DNS zone for custom domain if provided
    if (props?.domainName) {
      this.dnsZone = new lightsail.CfnDomain(this, 'DnsZone', {
        domainName: props.domainName,
        domainEntries: this.createDnsEntries(props.domainName)
      });

      // DNS zone depends on static IP if created
      if (this.staticIp) {
        this.dnsZone.addDependency(this.staticIp);
      }
    }

    // Create CloudFormation outputs
    this.createOutputs(props);
  }

  /**
   * Generates user data script for WordPress instance configuration
   */
  private generateUserData(): string {
    return [
      '#!/bin/bash',
      '# WordPress Lightsail instance configuration',
      '',
      '# Update system packages',
      'sudo apt-get update -y',
      '',
      '# Configure Apache for better performance',
      'sudo a2enmod rewrite',
      'sudo a2enmod ssl',
      '',
      '# Restart Apache to apply changes',
      'sudo systemctl restart apache2',
      '',
      '# Set proper permissions for WordPress',
      'sudo chown -R bitnami:daemon /opt/bitnami/wordpress',
      'sudo chmod -R g+w /opt/bitnami/wordpress',
      '',
      '# Configure WordPress for production',
      'sudo /opt/bitnami/wordpress/bin/installwp.sh',
      '',
      '# Enable automatic security updates',
      'echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | sudo debconf-set-selections',
      'sudo dpkg-reconfigure -f noninteractive unattended-upgrades',
      '',
      '# Log completion',
      'echo "WordPress Lightsail instance configuration completed at $(date)" >> /var/log/wordpress-setup.log'
    ].join('\n');
  }

  /**
   * Creates DNS entries for the custom domain
   */
  private createDnsEntries(domainName: string): lightsail.CfnDomain.DomainEntryProperty[] {
    const entries: lightsail.CfnDomain.DomainEntryProperty[] = [];

    if (this.staticIp) {
      // A record for root domain
      entries.push({
        name: '@',
        type: 'A',
        target: cdk.Fn.getAtt(this.staticIp.logicalId, 'IpAddress').toString()
      });

      // CNAME record for www subdomain
      entries.push({
        name: 'www',
        type: 'CNAME',
        target: domainName
      });
    }

    return entries;
  }

  /**
   * Creates CloudFormation outputs for the stack
   */
  private createOutputs(props?: SimpleWebsiteHostingLightsailStackProps): void {
    // Instance name output
    new cdk.CfnOutput(this, 'InstanceName', {
      value: this.instance.instanceName!,
      description: 'The name of the WordPress Lightsail instance',
      exportName: `${this.stackName}-InstanceName`
    });

    // Instance availability zone output
    new cdk.CfnOutput(this, 'AvailabilityZone', {
      value: this.instance.availabilityZone!,
      description: 'The availability zone of the WordPress instance',
      exportName: `${this.stackName}-AvailabilityZone`
    });

    // Static IP address output
    if (this.staticIp) {
      new cdk.CfnOutput(this, 'StaticIpAddress', {
        value: cdk.Fn.getAtt(this.staticIp.logicalId, 'IpAddress').toString(),
        description: 'The static IP address of the WordPress site',
        exportName: `${this.stackName}-StaticIpAddress`
      });

      new cdk.CfnOutput(this, 'WebsiteUrl', {
        value: `http://${cdk.Fn.getAtt(this.staticIp.logicalId, 'IpAddress')}`,
        description: 'The URL to access your WordPress website',
        exportName: `${this.stackName}-WebsiteUrl`
      });

      new cdk.CfnOutput(this, 'AdminUrl', {
        value: `http://${cdk.Fn.getAtt(this.staticIp.logicalId, 'IpAddress')}/wp-admin`,
        description: 'The URL to access WordPress admin panel',
        exportName: `${this.stackName}-AdminUrl`
      });
    }

    // DNS zone output
    if (this.dnsZone && props?.domainName) {
      new cdk.CfnOutput(this, 'DomainName', {
        value: props.domainName,
        description: 'The custom domain name configured for the website',
        exportName: `${this.stackName}-DomainName`
      });

      new cdk.CfnOutput(this, 'CustomWebsiteUrl', {
        value: `https://${props.domainName}`,
        description: 'The custom domain URL for your WordPress website',
        exportName: `${this.stackName}-CustomWebsiteUrl`
      });
    }

    // Instance bundle information
    new cdk.CfnOutput(this, 'InstanceBundle', {
      value: props?.bundleId || 'nano_3_0',
      description: 'The Lightsail bundle ID used for the instance',
      exportName: `${this.stackName}-InstanceBundle`
    });

    // WordPress admin credentials information
    new cdk.CfnOutput(this, 'AdminCredentials', {
      value: 'Connect via SSH and run: sudo cat /home/bitnami/bitnami_application_password',
      description: 'Command to retrieve WordPress admin password',
      exportName: `${this.stackName}-AdminCredentials`
    });

    // SSH connection information
    if (this.staticIp) {
      new cdk.CfnOutput(this, 'SshConnection', {
        value: `ssh -i ~/.ssh/your-key-pair.pem bitnami@${cdk.Fn.getAtt(this.staticIp.logicalId, 'IpAddress')}`,
        description: 'SSH command to connect to the WordPress instance',
        exportName: `${this.stackName}-SshConnection`
      });
    }
  }
}

/**
 * AWS CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Stack configuration with sensible defaults
const stackProps: SimpleWebsiteHostingLightsailStackProps = {
  env,
  description: 'Simple Website Hosting with AWS Lightsail WordPress (uksb-1tupboc58)',
  
  // Configure instance settings
  instanceNamePrefix: app.node.tryGetContext('instanceNamePrefix') || 'wordpress-site',
  bundleId: app.node.tryGetContext('bundleId') || 'nano_3_0',
  availabilityZone: app.node.tryGetContext('availabilityZone'),
  
  // Network configuration
  createStaticIp: app.node.tryGetContext('createStaticIp') !== false,
  domainName: app.node.tryGetContext('domainName'),
  
  // Resource tagging
  resourceTags: {
    Project: 'SimpleWebsiteHosting',
    CreatedBy: 'AWS-CDK',
    Recipe: 'simple-website-hosting-lightsail',
    ...(app.node.tryGetContext('resourceTags') || {})
  }
};

// Create the stack
const stack = new SimpleWebsiteHostingLightsailStack(app, 'SimpleWebsiteHostingLightsailStack', stackProps);

// Add stack-level tags
cdk.Tags.of(stack).add('Project', 'SimpleWebsiteHosting');
cdk.Tags.of(stack).add('Recipe', 'simple-website-hosting-lightsail');
cdk.Tags.of(stack).add('ManagedBy', 'AWS-CDK');

// Synthesize the CDK app
app.synth();