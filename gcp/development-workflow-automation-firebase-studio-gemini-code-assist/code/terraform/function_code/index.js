/**
 * AI-Powered Code Review Automation Function
 * 
 * This Cloud Function provides intelligent code review automation using
 * Gemini Code Assist for AI-powered analysis, security scanning, and
 * automated testing of development artifacts.
 */

const { Storage } = require('@google-cloud/storage');
const { PubSub } = require('@google-cloud/pubsub');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const functions = require('@google-cloud/functions-framework');
const { Logging } = require('@google-cloud/logging');

// Initialize Google Cloud clients
const storage = new Storage();
const pubsub = new PubSub();
const secretManager = new SecretManagerServiceClient();
const logging = new Logging();
const log = logging.log('code-review-automation');

// Configuration from environment variables
const CONFIG = {
  topicName: process.env.TOPIC_NAME || '${topic_name}',
  bucketName: process.env.BUCKET_NAME || '${bucket_name}',
  projectId: process.env.PROJECT_ID || '${project_id}',
  geminiModel: process.env.GEMINI_MODEL || '${gemini_model}',
  environment: process.env.ENVIRONMENT || 'dev'
};

/**
 * Main Cloud Function entry point for code review automation
 * Triggered by Cloud Storage object creation events
 */
functions.cloudEvent('codeReviewAutomation', async (cloudEvent) => {
  const startTime = Date.now();
  
  try {
    await log.info('Code review automation triggered', {
      event: cloudEvent,
      config: CONFIG,
      timestamp: new Date().toISOString()
    });

    const { bucket, name } = cloudEvent.data;
    
    // Validate event data
    if (!bucket || !name) {
      throw new Error('Invalid cloud event data: missing bucket or object name');
    }

    // Skip processing for review results and system files
    if (name.startsWith('reviews/') || name.startsWith('system/') || name.endsWith('.log')) {
      await log.info('Skipping system file', { fileName: name });
      return;
    }

    await log.info('Processing code artifact', {
      bucket: bucket,
      fileName: name,
      processingStarted: new Date().toISOString()
    });

    // Download and analyze the code artifact
    const codeContent = await downloadCodeArtifact(bucket, name);
    const reviewResults = await performIntelligentReview(codeContent, name);
    
    // Store review results in Cloud Storage
    const reviewFileName = await storeReviewResults(bucket, name, reviewResults);
    
    // Publish review completion event to Pub/Sub
    await publishReviewEvent(name, reviewFileName, reviewResults);
    
    const executionTime = Date.now() - startTime;
    await log.info('Code review completed successfully', {
      artifact: name,
      reviewFile: reviewFileName,
      status: reviewResults.approved ? 'approved' : 'needs_revision',
      executionTimeMs: executionTime,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    const executionTime = Date.now() - startTime;
    await log.error('Code review automation failed', {
      error: error.message,
      stack: error.stack,
      executionTimeMs: executionTime,
      event: cloudEvent
    });
    
    // Re-throw error to trigger function retry mechanism
    throw error;
  }
});

/**
 * Download code artifact from Cloud Storage
 */
async function downloadCodeArtifact(bucketName, fileName) {
  try {
    const file = storage.bucket(bucketName).file(fileName);
    const [exists] = await file.exists();
    
    if (!exists) {
      throw new Error(`File does not exist: gs://$${bucketName}/$${fileName}`);
    }

    const [content] = await file.download();
    const codeContent = content.toString('utf8');
    
    if (!codeContent || codeContent.trim().length === 0) {
      throw new Error('Downloaded file is empty or contains no readable content');
    }
    
    await log.info('Code artifact downloaded successfully', {
      fileName: fileName,
      contentLength: codeContent.length,
      contentPreview: codeContent.substring(0, 200) + (codeContent.length > 200 ? '...' : '')
    });
    
    return codeContent;
    
  } catch (error) {
    await log.error('Failed to download code artifact', {
      error: error.message,
      bucketName: bucketName,
      fileName: fileName
    });
    throw error;
  }
}

/**
 * Perform comprehensive AI-powered code review
 */
async function performIntelligentReview(code, fileName) {
  try {
    await log.info('Starting intelligent code review', {
      fileName: fileName,
      codeLength: code.length,
      model: CONFIG.geminiModel
    });

    // Perform multiple analysis checks
    const checks = {
      syntax: await checkSyntax(code, fileName),
      security: await checkSecurity(code, fileName),
      performance: await checkPerformance(code, fileName),
      bestPractices: await checkBestPractices(code, fileName),
      aiReview: await performAICodeReview(code, fileName)
    };

    // Calculate overall score
    const scores = Object.values(checks).map(check => check.score);
    const overallScore = scores.reduce((sum, score) => sum + score, 0) / scores.length;
    
    // Generate comprehensive suggestions
    const suggestions = generateSuggestions(checks);
    
    // Determine approval status
    const approved = overallScore >= 80 && checks.security.score >= 85;
    
    const reviewResults = {
      approved: approved,
      overallScore: Math.round(overallScore * 100) / 100,
      checks: checks,
      suggestions: suggestions,
      reviewedAt: new Date().toISOString(),
      reviewedBy: 'AI Code Review System',
      fileName: fileName,
      geminiModel: CONFIG.geminiModel,
      environment: CONFIG.environment
    };
    
    await log.info('Code review analysis completed', {
      fileName: fileName,
      approved: approved,
      overallScore: overallScore,
      checksCount: Object.keys(checks).length,
      suggestionsCount: suggestions.length
    });
    
    return reviewResults;
    
  } catch (error) {
    await log.error('Failed to perform intelligent review', {
      error: error.message,
      fileName: fileName
    });
    throw error;
  }
}

/**
 * Check code syntax and basic structure
 */
async function checkSyntax(code, fileName) {
  const issues = [];
  let score = 95;
  
  try {
    // Basic syntax validation based on file extension
    const extension = fileName.split('.').pop().toLowerCase();
    
    switch (extension) {
      case 'js':
      case 'jsx':
        // Check for basic JavaScript syntax issues
        if (code.includes('eval(')) {
          issues.push('Use of eval() detected - potential security risk');
          score -= 10;
        }
        if (code.match(/function\s+\w+\s*\([^)]*\)\s*\{[^}]*\}/g)?.length === 0 && 
            !code.includes('=>') && !code.includes('const ') && !code.includes('let ')) {
          issues.push('No functions or variable declarations detected');
          score -= 5;
        }
        break;
        
      case 'py':
        // Check for basic Python syntax
        if (code.includes('exec(')) {
          issues.push('Use of exec() detected - potential security risk');
          score -= 10;
        }
        break;
        
      case 'json':
        // Validate JSON syntax
        try {
          JSON.parse(code);
        } catch (e) {
          issues.push('Invalid JSON syntax detected');
          score -= 20;
        }
        break;
    }
    
    // Check for common syntax issues
    const brackets = (code.match(/\{/g) || []).length - (code.match(/\}/g) || []).length;
    if (brackets !== 0) {
      issues.push('Mismatched curly brackets detected');
      score -= 15;
    }
    
    const parens = (code.match(/\(/g) || []).length - (code.match(/\)/g) || []).length;
    if (parens !== 0) {
      issues.push('Mismatched parentheses detected');
      score -= 15;
    }
    
  } catch (error) {
    issues.push(`Syntax check error: $${error.message}`);
    score -= 20;
  }
  
  return {
    score: Math.max(0, score),
    issues: issues,
    status: issues.length === 0 ? 'passed' : 'warning',
    checkType: 'syntax'
  };
}

/**
 * Check for security vulnerabilities
 */
async function checkSecurity(code, fileName) {
  const issues = [];
  let score = 90;
  
  try {
    // Check for potential security vulnerabilities
    const securityPatterns = [
      { pattern: /eval\s*\(/gi, message: 'Use of eval() detected - potential code injection risk', severity: 'high' },
      { pattern: /innerHTML\s*=/gi, message: 'Use of innerHTML detected - potential XSS vulnerability', severity: 'medium' },
      { pattern: /document\.write\s*\(/gi, message: 'Use of document.write() detected - potential XSS risk', severity: 'medium' },
      { pattern: /exec\s*\(/gi, message: 'Use of exec() detected - potential code injection risk', severity: 'high' },
      { pattern: /password\s*=\s*['"]\w+['"]/gi, message: 'Hardcoded password detected', severity: 'high' },
      { pattern: /api[_-]?key\s*=\s*['"]\w+['"]/gi, message: 'Hardcoded API key detected', severity: 'high' },
      { pattern: /secret\s*=\s*['"]\w+['"]/gi, message: 'Hardcoded secret detected', severity: 'high' },
      { pattern: /token\s*=\s*['"]\w+['"]/gi, message: 'Hardcoded token detected', severity: 'medium' }
    ];
    
    securityPatterns.forEach(({ pattern, message, severity }) => {
      if (pattern.test(code)) {
        issues.push({ message, severity });
        score -= severity === 'high' ? 20 : severity === 'medium' ? 10 : 5;
      }
    });
    
    // Check for proper error handling
    if (!code.includes('try') && !code.includes('catch') && code.length > 500) {
      issues.push({ message: 'No error handling detected in substantial code', severity: 'low' });
      score -= 5;
    }
    
    // Check for proper input validation
    if (code.includes('request') && !code.includes('validate') && !code.includes('sanitize')) {
      issues.push({ message: 'Input validation may be missing', severity: 'medium' });
      score -= 10;
    }
    
  } catch (error) {
    issues.push({ message: `Security check error: $${error.message}`, severity: 'low' });
    score -= 5;
  }
  
  return {
    score: Math.max(0, score),
    issues: issues.map(issue => typeof issue === 'string' ? issue : issue.message),
    status: issues.length === 0 ? 'passed' : 'warning',
    checkType: 'security',
    securityDetails: issues
  };
}

/**
 * Check for performance issues and optimization opportunities
 */
async function checkPerformance(code, fileName) {
  const issues = [];
  let score = 85;
  
  try {
    // Check for performance anti-patterns
    if (code.includes('for') && code.includes('for') && code.includes('for')) {
      issues.push('Multiple nested loops detected - may impact performance');
      score -= 10;
    }
    
    if (code.match(/console\.log/g)?.length > 5) {
      issues.push('Excessive console.log statements detected');
      score -= 5;
    }
    
    if (code.includes('setInterval') && !code.includes('clearInterval')) {
      issues.push('setInterval without clearInterval detected - potential memory leak');
      score -= 15;
    }
    
    if (code.includes('setTimeout') && code.match(/setTimeout/g)?.length > 10) {
      issues.push('Excessive setTimeout usage detected');
      score -= 10;
    }
    
    // Check for database query optimization
    if (code.includes('SELECT *') || code.includes('select *')) {
      issues.push('SELECT * detected - consider selecting specific columns');
      score -= 5;
    }
    
  } catch (error) {
    issues.push(`Performance check error: $${error.message}`);
    score -= 5;
  }
  
  return {
    score: Math.max(0, score),
    issues: issues,
    status: issues.length === 0 ? 'passed' : 'warning',
    checkType: 'performance'
  };
}

/**
 * Check adherence to coding best practices
 */
async function checkBestPractices(code, fileName) {
  const issues = [];
  let score = 88;
  
  try {
    // Check for proper variable naming
    const badVariableNames = code.match(/\b(temp|tmp|data|item|thing|stuff)\b/g);
    if (badVariableNames && badVariableNames.length > 2) {
      issues.push('Non-descriptive variable names detected');
      score -= 5;
    }
    
    // Check for proper function documentation
    const functionCount = (code.match(/function\s+\w+|const\s+\w+\s*=/g) || []).length;
    const commentCount = (code.match(/\/\*[\s\S]*?\*\/|\/\/.*$/gm) || []).length;
    
    if (functionCount > 3 && commentCount < functionCount / 2) {
      issues.push('Insufficient code documentation detected');
      score -= 10;
    }
    
    // Check for proper code organization
    if (code.length > 1000 && !code.includes('function') && !code.includes('class')) {
      issues.push('Large code block without proper function/class organization');
      score -= 10;
    }
    
    // Check for proper error messages
    if (code.includes('throw') && !code.match(/throw\s+new\s+\w*Error/g)) {
      issues.push('Non-standard error throwing detected');
      score -= 5;
    }
    
  } catch (error) {
    issues.push(`Best practices check error: $${error.message}`);
    score -= 5;
  }
  
  return {
    score: Math.max(0, score),
    issues: issues,
    status: issues.length === 0 ? 'passed' : 'warning',
    checkType: 'bestPractices'
  };
}

/**
 * Perform AI-powered code review using Gemini (simulated for this example)
 * In production, this would integrate with actual Gemini API
 */
async function performAICodeReview(code, fileName) {
  try {
    // Simulate AI analysis (in production, integrate with Vertex AI Gemini API)
    const aiInsights = {
      codeQuality: Math.floor(Math.random() * 20) + 80, // 80-100
      maintainability: Math.floor(Math.random() * 15) + 85, // 85-100
      testability: Math.floor(Math.random() * 25) + 75, // 75-100
      suggestions: [
        'Consider adding unit tests for better code coverage',
        'Function complexity could be reduced by extracting smaller functions',
        'Add input validation for better error handling'
      ]
    };
    
    const averageScore = (aiInsights.codeQuality + aiInsights.maintainability + aiInsights.testability) / 3;
    
    return {
      score: Math.round(averageScore),
      issues: aiInsights.suggestions,
      status: averageScore >= 80 ? 'passed' : 'warning',
      checkType: 'aiReview',
      aiInsights: aiInsights,
      model: CONFIG.geminiModel
    };
    
  } catch (error) {
    await log.error('AI review failed', { error: error.message });
    return {
      score: 75,
      issues: ['AI review temporarily unavailable'],
      status: 'warning',
      checkType: 'aiReview'
    };
  }
}

/**
 * Generate comprehensive suggestions based on all checks
 */
function generateSuggestions(checks) {
  const suggestions = [];
  
  Object.entries(checks).forEach(([category, result]) => {
    if (result.score < 80) {
      suggestions.push(`Improve $${category}: $${result.issues.join(', ')}`);
    }
    
    // Add specific suggestions based on check type
    if (category === 'security' && result.score < 90) {
      suggestions.push('Review security practices and consider implementing additional security measures');
    }
    
    if (category === 'performance' && result.score < 85) {
      suggestions.push('Consider optimizing performance-critical sections and reducing complexity');
    }
  });
  
  // Add general suggestions
  if (suggestions.length === 0) {
    suggestions.push('Code quality is good - consider adding comprehensive tests and documentation');
  }
  
  return suggestions;
}

/**
 * Store review results in Cloud Storage
 */
async function storeReviewResults(bucketName, originalFileName, reviewResults) {
  try {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const reviewFileName = `reviews/$${originalFileName.replace(/\.[^/.]+$/, '')}-review-$${timestamp}.json`;
    
    const reviewData = JSON.stringify(reviewResults, null, 2);
    
    await storage.bucket(bucketName)
      .file(reviewFileName)
      .save(reviewData, {
        metadata: {
          contentType: 'application/json',
          metadata: {
            originalFile: originalFileName,
            reviewedAt: reviewResults.reviewedAt,
            approved: reviewResults.approved.toString(),
            overallScore: reviewResults.overallScore.toString()
          }
        }
      });
    
    await log.info('Review results stored successfully', {
      reviewFileName: reviewFileName,
      originalFileName: originalFileName,
      approved: reviewResults.approved
    });
    
    return reviewFileName;
    
  } catch (error) {
    await log.error('Failed to store review results', {
      error: error.message,
      originalFileName: originalFileName
    });
    throw error;
  }
}

/**
 * Publish review completion event to Pub/Sub
 */
async function publishReviewEvent(originalFileName, reviewFileName, reviewResults) {
  try {
    const topic = pubsub.topic(CONFIG.topicName);
    
    const eventData = {
      type: 'review_completed',
      originalFile: originalFileName,
      reviewFile: reviewFileName,
      status: reviewResults.approved ? 'approved' : 'needs_revision',
      overallScore: reviewResults.overallScore,
      timestamp: new Date().toISOString(),
      environment: CONFIG.environment
    };
    
    const messageId = await topic.publishMessage({
      json: eventData,
      attributes: {
        eventType: 'code_review',
        status: eventData.status,
        environment: CONFIG.environment
      }
    });
    
    await log.info('Review event published successfully', {
      messageId: messageId,
      eventData: eventData
    });
    
  } catch (error) {
    await log.error('Failed to publish review event', {
      error: error.message,
      originalFileName: originalFileName
    });
    // Don't throw error here - review completion is more important than event publishing
  }
}

// Export for testing
module.exports = {
  checkSyntax,
  checkSecurity,
  checkPerformance,
  checkBestPractices,
  performIntelligentReview
};