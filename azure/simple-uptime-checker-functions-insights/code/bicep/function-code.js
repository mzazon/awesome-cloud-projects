const https = require('https');
const http = require('http');
const { URL } = require('url');

module.exports = async function (context, timer) {
    context.log('Uptime checker function started');
    
    // Get websites to monitor from environment variable
    const websitesEnv = process.env.WEBSITES_TO_MONITOR || 'https://www.microsoft.com,https://azure.microsoft.com,https://github.com';
    const websites = websitesEnv.split(',').map(url => url.trim());
    
    const results = [];
    
    for (const website of websites) {
        try {
            const result = await checkWebsite(website, context);
            results.push(result);
            
            // Log success to Application Insights
            context.log(`✅ ${website}: ${result.status} (${result.responseTime}ms)`);
            
            // Send custom telemetry to Application Insights
            if (context.bindings && context.bindings.appInsights) {
                context.bindings.appInsights.trackDependency({
                    dependencyTypeName: 'HTTP',
                    name: website,
                    data: website,
                    duration: result.responseTime,
                    success: result.status === 'UP',
                    resultCode: result.statusCode
                });
            }
            
        } catch (error) {
            const failureResult = {
                url: website,
                status: 'ERROR',
                responseTime: 0,
                statusCode: 0,
                error: error.message,
                timestamp: new Date().toISOString()
            };
            
            results.push(failureResult);
            context.log(`❌ ${website}: ${error.message}`);
            
            // Send failure telemetry to Application Insights
            if (context.bindings && context.bindings.appInsights) {
                context.bindings.appInsights.trackException({
                    exception: error,
                    properties: {
                        website: website,
                        operation: 'uptime-check'
                    }
                });
            }
        }
    }
    
    // Calculate summary statistics
    const summary = {
        totalChecks: results.length,
        successfulChecks: results.filter(r => r.status === 'UP').length,
        failedChecks: results.filter(r => r.status !== 'UP').length,
        averageResponseTime: calculateAverageResponseTime(results),
        timestamp: new Date().toISOString()
    };
    
    // Log summary to Application Insights
    context.log('Uptime check summary:', JSON.stringify(summary));
    
    // Send custom metric to Application Insights
    if (context.bindings && context.bindings.appInsights) {
        context.bindings.appInsights.trackMetric({
            name: 'UptimeCheck.SuccessRate',
            value: summary.totalChecks > 0 ? (summary.successfulChecks / summary.totalChecks) * 100 : 0
        });
        
        context.bindings.appInsights.trackMetric({
            name: 'UptimeCheck.AverageResponseTime',
            value: summary.averageResponseTime
        });
        
        context.bindings.appInsights.trackEvent({
            name: 'UptimeCheckCompleted',
            properties: summary
        });
    }
    
    context.log('Uptime checker function completed');
};

async function checkWebsite(url, context) {
    return new Promise((resolve, reject) => {
        const startTime = Date.now();
        const urlObj = new URL(url);
        const client = urlObj.protocol === 'https:' ? https : http;
        
        const options = {
            timeout: 10000,
            headers: {
                'User-Agent': 'Azure-Functions-Uptime-Checker/1.0'
            }
        };
        
        const request = client.get(url, options, (response) => {
            const responseTime = Date.now() - startTime;
            const status = response.statusCode >= 200 && response.statusCode < 300 ? 'UP' : 'DOWN';
            
            // Consume response body to free up memory
            response.on('data', () => {});
            response.on('end', () => {
                resolve({
                    url: url,
                    status: status,
                    responseTime: responseTime,
                    statusCode: response.statusCode,
                    timestamp: new Date().toISOString(),
                    headers: {
                        'content-type': response.headers['content-type'],
                        'content-length': response.headers['content-length'],
                        'server': response.headers['server']
                    }
                });
            });
        });
        
        request.on('timeout', () => {
            request.destroy();
            reject(new Error('Request timeout (10 seconds)'));
        });
        
        request.on('error', (error) => {
            const responseTime = Date.now() - startTime;
            context.log(`HTTP error for ${url}: ${error.message}`);
            reject(new Error(`HTTP request failed: ${error.message}`));
        });
        
        // Set timeout
        request.setTimeout(10000);
    });
}

function calculateAverageResponseTime(results) {
    const validResults = results.filter(r => r.responseTime > 0);
    if (validResults.length === 0) return 0;
    
    const totalTime = validResults.reduce((sum, r) => sum + r.responseTime, 0);
    return Math.round(totalTime / validResults.length);
}