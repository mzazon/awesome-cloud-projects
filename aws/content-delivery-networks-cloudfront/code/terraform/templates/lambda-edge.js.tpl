const aws = require('aws-sdk');

exports.handler = async (event, context) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;
    const headers = response.headers;
    
    // Add comprehensive security headers
    headers['strict-transport-security'] = [{
        key: 'Strict-Transport-Security',
        value: 'max-age=31536000; includeSubDomains; preload'
    }];
    
    headers['x-content-type-options'] = [{
        key: 'X-Content-Type-Options',
        value: 'nosniff'
    }];
    
    headers['x-frame-options'] = [{
        key: 'X-Frame-Options',
        value: 'SAMEORIGIN'
    }];
    
    headers['x-xss-protection'] = [{
        key: 'X-XSS-Protection',
        value: '1; mode=block'
    }];
    
    headers['referrer-policy'] = [{
        key: 'Referrer-Policy',
        value: 'strict-origin-when-cross-origin'
    }];
    
    headers['content-security-policy'] = [{
        key: 'Content-Security-Policy',
        value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' https:; connect-src 'self' https:; media-src 'self'; object-src 'none'; child-src 'self'; frame-ancestors 'self'; form-action 'self'; base-uri 'self';"
    }];
    
    headers['permissions-policy'] = [{
        key: 'Permissions-Policy',
        value: 'geolocation=(), microphone=(), camera=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=()'
    }];
    
    // Add custom headers based on request path
    if (request.uri.startsWith('/api/')) {
        headers['access-control-allow-origin'] = [{
            key: 'Access-Control-Allow-Origin',
            value: '*'
        }];
        headers['access-control-allow-methods'] = [{
            key: 'Access-Control-Allow-Methods',
            value: 'GET, POST, OPTIONS, PUT, DELETE'
        }];
        headers['access-control-allow-headers'] = [{
            key: 'Access-Control-Allow-Headers',
            value: 'Content-Type, Authorization, X-Requested-With, X-API-Key'
        }];
        headers['access-control-max-age'] = [{
            key: 'Access-Control-Max-Age',
            value: '86400'
        }];
    }
    
    // Add performance headers
    headers['x-edge-location'] = [{
        key: 'X-Edge-Location',
        value: event.Records[0].cf.config.distributionId
    }];
    
    headers['x-cache-status'] = [{
        key: 'X-Cache-Status',
        value: 'PROCESSED'
    }];
    
    headers['x-environment'] = [{
        key: 'X-Environment',
        value: '${environment}'
    }];
    
    headers['x-powered-by'] = [{
        key: 'X-Powered-By',
        value: 'AWS CloudFront + Lambda@Edge'
    }];
    
    // Add timing header
    headers['x-response-time'] = [{
        key: 'X-Response-Time',
        value: Date.now().toString()
    }];
    
    // Handle CORS preflight requests
    if (request.method === 'OPTIONS') {
        response.status = '200';
        response.statusDescription = 'OK';
        response.body = '';
    }
    
    return response;
};