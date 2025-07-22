import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import { Construct } from 'constructs';

export interface StaticWebsiteStackProps extends cdk.StackProps {
  domainName: string;
  hostedZoneId?: string;
  certificateArn?: string;
}

export class StaticWebsiteStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: StaticWebsiteStackProps) {
    super(scope, id, props);

    const { domainName, hostedZoneId, certificateArn } = props;
    const subdomainName = `www.${domainName}`;

    // Create S3 bucket for website content (www subdomain)
    const websiteBucket = new s3.Bucket(this, 'WebsiteBucket', {
      bucketName: subdomainName,
      publicReadAccess: true,
      websiteIndexDocument: 'index.html',
      websiteErrorDocument: 'error.html',
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ACLS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create S3 bucket for root domain redirect
    const redirectBucket = new s3.Bucket(this, 'RedirectBucket', {
      bucketName: domainName,
      websiteRedirect: {
        hostName: subdomainName,
        protocol: s3.RedirectProtocol.HTTPS,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Look up existing hosted zone or create a new one if hostedZoneId is provided
    let hostedZone: route53.IHostedZone | undefined;
    if (hostedZoneId) {
      hostedZone = route53.HostedZone.fromHostedZoneAttributes(this, 'HostedZone', {
        hostedZoneId,
        zoneName: domainName,
      });
    } else {
      // Look up existing hosted zone by domain name
      hostedZone = route53.HostedZone.fromLookup(this, 'HostedZone', {
        domainName,
      });
    }

    // Create or use existing SSL certificate
    let certificate: acm.ICertificate;
    if (certificateArn) {
      certificate = acm.Certificate.fromCertificateArn(this, 'Certificate', certificateArn);
    } else {
      certificate = new acm.Certificate(this, 'Certificate', {
        domainName,
        subjectAlternativeNames: [subdomainName],
        validation: acm.CertificateValidation.fromDns(hostedZone),
      });
    }

    // Create CloudFront distribution for the www subdomain
    const distribution = new cloudfront.Distribution(this, 'WebsiteDistribution', {
      defaultBehavior: {
        origin: new origins.S3Origin(websiteBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        compress: true,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
      domainNames: [subdomainName],
      certificate,
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 404,
          responsePagePath: '/error.html',
        },
        {
          httpStatus: 403,
          responseHttpStatus: 404,
          responsePagePath: '/error.html',
        },
      ],
    });

    // Create CloudFront distribution for root domain redirect
    const redirectDistribution = new cloudfront.Distribution(this, 'RedirectDistribution', {
      defaultBehavior: {
        origin: new origins.HttpOrigin(`${domainName}.s3-website-${this.region}.amazonaws.com`),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
      },
      domainNames: [domainName],
      certificate,
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
    });

    // Create Route 53 records
    if (hostedZone) {
      // A record for www subdomain pointing to CloudFront
      new route53.ARecord(this, 'WebsiteAliasRecord', {
        zone: hostedZone,
        recordName: subdomainName,
        target: route53.RecordTarget.fromAlias(new targets.CloudFrontTarget(distribution)),
      });

      // A record for root domain pointing to redirect CloudFront
      new route53.ARecord(this, 'RedirectAliasRecord', {
        zone: hostedZone,
        recordName: domainName,
        target: route53.RecordTarget.fromAlias(new targets.CloudFrontTarget(redirectDistribution)),
      });
    }

    // Deploy sample website content
    new s3deploy.BucketDeployment(this, 'DeployWebsite', {
      sources: [s3deploy.Source.asset('./website')],
      destinationBucket: websiteBucket,
      distribution,
      distributionPaths: ['/*'],
    });

    // Outputs
    new cdk.CfnOutput(this, 'WebsiteBucketName', {
      value: websiteBucket.bucketName,
      description: 'Name of the S3 bucket for website content',
    });

    new cdk.CfnOutput(this, 'RedirectBucketName', {
      value: redirectBucket.bucketName,
      description: 'Name of the S3 bucket for root domain redirect',
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: distribution.distributionId,
      description: 'CloudFront distribution ID for www subdomain',
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionDomainName', {
      value: distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
    });

    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: `https://${subdomainName}`,
      description: 'URL of the static website',
    });

    new cdk.CfnOutput(this, 'CertificateArn', {
      value: certificate.certificateArn,
      description: 'ARN of the SSL certificate',
    });
  }
}