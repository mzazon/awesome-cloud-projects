const functions = require('@google-cloud/functions-framework');
const { VertexAI } = require('@google-cloud/vertexai');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const { Storage } = require('@google-cloud/storage');

// Initialize clients
const secretManager = new SecretManagerServiceClient();
const storage = new Storage();

// Initialize Vertex AI client
const vertexAI = new VertexAI({
  project: '${project_id}',
  location: '${region}'
});

let model;
let analysisConfig;

// Initialize the AI model and configuration
async function initializeAI() {
  if (!model || !analysisConfig) {
    try {
      // Get configuration from Secret Manager
      const [version] = await secretManager.accessSecretVersion({
        name: `projects/${project_id}/secrets/${secret_name}/versions/latest`
      });
      
      analysisConfig = JSON.parse(version.payload.data.toString());
      
      // Initialize the Vertex AI model
      model = vertexAI.getGenerativeModel({
        model: analysisConfig.model || '${model_name}',
        generationConfig: {
          temperature: analysisConfig.temperature || 0.3,
          maxOutputTokens: analysisConfig.max_tokens || 4096
        }
      });
      
      console.log('AI model initialized successfully');
    } catch (error) {
      console.error('Failed to initialize AI model:', error);
      throw error;
    }
  }
}

// Main Cloud Function entry point
functions.http('codeReviewTrigger', async (req, res) => {
  try {
    console.log('Code review automation triggered');
    console.log('Request body:', JSON.stringify(req.body, null, 2));
    
    // Initialize AI components
    await initializeAI();
    
    const eventData = req.body;
    
    // Process different event types
    if (eventData.eventType === 'push') {
      await handlePushEvent(eventData);
    } else if (eventData.eventType === 'pull_request') {
      await handlePullRequestEvent(eventData);
    } else if (eventData.eventType === 'google.cloud.source.repositories.v1.revisionCreated') {
      await handleRepositoryRevisionEvent(eventData);
    } else {
      console.log('Unsupported event type:', eventData.eventType);
    }
    
    res.status(200).json({ 
      message: 'Code review analysis completed successfully',
      timestamp: new Date().toISOString(),
      eventType: eventData.eventType
    });
    
  } catch (error) {
    console.error('Function execution error:', error);
    
    // Store error details for debugging
    await storeAnalysisResult({
      type: 'error',
      error: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });
    
    res.status(500).json({ 
      error: 'Code review analysis failed',
      details: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Handle push events from repository
async function handlePushEvent(eventData) {
  console.log('Processing push event for intelligent code review');
  
  const changedFiles = eventData.changedFiles || [];
  const analysisResults = [];
  
  for (const file of changedFiles) {
    if (shouldAnalyzeFile(file.path)) {
      console.log(`Analyzing file: $${file.path}`);
      const analysis = await analyzeCodeFile(file);
      if (analysis) {
        analysisResults.push(analysis);
      }
    }
  }
  
  // Store aggregated analysis results
  if (analysisResults.length > 0) {
    await storeAnalysisResult({
      type: 'push_analysis',
      repository: eventData.repository,
      commit: eventData.commit,
      results: analysisResults,
      timestamp: new Date().toISOString()
    });
  }
  
  console.log(`Push event analysis completed: $${analysisResults.length} files analyzed`);
}

// Handle pull request events
async function handlePullRequestEvent(eventData) {
  console.log('Processing pull request for comprehensive review');
  
  const pullRequestFiles = eventData.files || [];
  const analysisResults = [];
  
  for (const file of pullRequestFiles) {
    if (shouldAnalyzeFile(file.path)) {
      console.log(`Analyzing PR file: $${file.path}`);
      const analysis = await analyzeCodeFile(file);
      if (analysis) {
        analysisResults.push(analysis);
      }
    }
  }
  
  // Generate comprehensive pull request summary
  if (analysisResults.length > 0) {
    const summary = await generatePullRequestSummary(analysisResults, eventData);
    
    await storeAnalysisResult({
      type: 'pull_request_analysis',
      repository: eventData.repository,
      pullRequest: eventData.pullRequestId,
      results: analysisResults,
      summary: summary,
      timestamp: new Date().toISOString()
    });
  }
  
  console.log(`Pull request analysis completed: $${analysisResults.length} files analyzed`);
}

// Handle Cloud Source Repository revision events
async function handleRepositoryRevisionEvent(eventData) {
  console.log('Processing repository revision event');
  
  // Extract file changes from revision data
  const revision = eventData.revision || {};
  const modifiedFiles = revision.modifiedFiles || [];
  
  for (const filePath of modifiedFiles) {
    if (shouldAnalyzeFile(filePath)) {
      // For revision events, we need to fetch file content
      const fileContent = await fetchFileContent(eventData.repository, filePath, revision.id);
      if (fileContent) {
        const analysis = await analyzeCodeFile({
          path: filePath,
          content: fileContent
        });
        
        if (analysis) {
          await storeAnalysisResult({
            type: 'revision_analysis',
            repository: eventData.repository,
            revision: revision.id,
            file: filePath,
            analysis: analysis,
            timestamp: new Date().toISOString()
          });
        }
      }
    }
  }
}

// Determine if a file should be analyzed based on extension and configuration
function shouldAnalyzeFile(filePath) {
  if (!analysisConfig || !analysisConfig.supported_languages) {
    // Default supported extensions
    return /\.(js|ts|jsx|tsx|py|java|go|rs|cpp|c|cs|php|rb)$/.test(filePath);
  }
  
  const languageExtensions = {
    javascript: /\.(js|jsx)$/,
    typescript: /\.(ts|tsx)$/,
    python: /\.py$/,
    java: /\.java$/,
    go: /\.go$/,
    rust: /\.rs$/,
    cpp: /\.(cpp|cc|cxx|c)$/,
    csharp: /\.cs$/,
    php: /\.php$/,
    ruby: /\.rb$/
  };
  
  return analysisConfig.supported_languages.some(lang => {
    const pattern = languageExtensions[lang];
    return pattern && pattern.test(filePath);
  });
}

// Analyze individual code file using Vertex AI
async function analyzeCodeFile(fileData) {
  if (!model || !analysisConfig) {
    throw new Error('AI model not initialized');
  }
  
  const analysisPrompt = `
    As an expert code reviewer and security analyst, perform a comprehensive analysis of this code file:
    
    File: $${fileData.path}
    
    Code Content:
    $${fileData.content}
    
    Please analyze for the following aspects:
    ${analysisConfig.check_security ? '1. Security vulnerabilities and potential risks (injection attacks, unsafe operations, etc.)' : ''}
    ${analysisConfig.check_performance ? '2. Performance optimization opportunities (inefficient algorithms, memory leaks, etc.)' : ''}
    ${analysisConfig.check_best_practices ? '3. Code quality and best practices adherence (naming conventions, documentation, etc.)' : ''}
    4. Maintainability and readability issues
    5. Testing and documentation recommendations
    
    Analysis depth: $${analysisConfig.analysis_depth}
    Include suggestions: $${analysisConfig.include_suggestions}
    
    Provide your analysis in the following JSON format:
    {
      "overall_score": <1-10>,
      "security_issues": [{"line": <number>, "severity": "<high|medium|low>", "issue": "<description>", "recommendation": "<fix>"}],
      "performance_issues": [{"line": <number>, "impact": "<high|medium|low>", "issue": "<description>", "recommendation": "<fix>"}],
      "quality_issues": [{"line": <number>, "category": "<naming|structure|documentation>", "issue": "<description>", "recommendation": "<fix>"}],
      "positive_aspects": ["<good practices found>"],
      "summary": "<overall assessment>",
      "priority_actions": ["<most important fixes>"]
    }
    
    Be specific with line numbers where possible and provide actionable recommendations.
  `;
  
  try {
    console.log(`Starting AI analysis for file: $${fileData.path}`);
    
    const result = await model.generateContent(analysisPrompt);
    const responseText = result.response.text();
    
    console.log(`AI analysis completed for $${fileData.path}`);
    
    // Parse the AI response
    const analysis = parseAnalysisResult(responseText);
    
    return {
      file: fileData.path,
      analysis: analysis,
      timestamp: new Date().toISOString(),
      model_used: analysisConfig.model || '${model_name}'
    };
    
  } catch (error) {
    console.error(`Analysis failed for $${fileData.path}:`, error);
    return {
      file: fileData.path,
      error: error.message,
      timestamp: new Date().toISOString()
    };
  }
}

// Parse and structure the AI analysis result
function parseAnalysisResult(rawResult) {
  try {
    // Try to extract JSON from the response
    const jsonMatch = rawResult.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    }
    
    // Fallback to plain text analysis
    return {
      summary: "Analysis completed",
      feedback: rawResult,
      parsed: false,
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    console.error('Failed to parse analysis result:', error);
    return {
      summary: "Analysis completed with parsing errors",
      raw_feedback: rawResult,
      error: error.message,
      timestamp: new Date().toISOString()
    };
  }
}

// Generate comprehensive pull request summary
async function generatePullRequestSummary(analysisResults, pullRequestContext) {
  if (!model) {
    throw new Error('AI model not initialized');
  }
  
  const summaryPrompt = `
    Based on the following individual file analyses, generate a comprehensive code review summary for this pull request:
    
    Pull Request Context: $${JSON.stringify(pullRequestContext, null, 2)}
    
    File Analysis Results:
    $${JSON.stringify(analysisResults, null, 2)}
    
    Please provide a professional code review summary that includes:
    1. Overall assessment of code quality and security
    2. Critical issues that must be addressed before merge
    3. Recommendations for improvement
    4. Positive aspects and good practices observed
    5. Suggested next steps and testing recommendations
    
    Format the response as a structured markdown review comment that would be appropriate for posting on a pull request.
    Make the feedback constructive, educational, and encouraging while being thorough about important issues.
  `;
  
  try {
    const result = await model.generateContent(summaryPrompt);
    const summary = result.response.text();
    
    console.log('Pull request summary generated successfully');
    return summary;
    
  } catch (error) {
    console.error('Summary generation failed:', error);
    return `## Code Review Summary\n\nAnalysis completed for $${analysisResults.length} files. Please review individual file analysis results for detailed feedback.\n\n**Error generating summary:** $${error.message}`;
  }
}

// Fetch file content from Cloud Source Repository
async function fetchFileContent(repositoryName, filePath, revisionId) {
  // Note: This is a placeholder for fetching file content from Cloud Source Repositories
  // In a full implementation, you would use the Cloud Source Repositories API
  console.log(`Fetching content for $${filePath} from revision $${revisionId}`);
  
  // For now, return null to indicate content needs to be provided in the event
  return null;
}

// Store analysis results in Cloud Storage
async function storeAnalysisResult(analysisData) {
  try {
    const bucket = storage.bucket('${analysis_bucket}');
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const filename = `analysis-$${analysisData.type}-$${timestamp}.json`;
    
    const file = bucket.file(filename);
    
    await file.save(JSON.stringify(analysisData, null, 2), {
      metadata: {
        contentType: 'application/json',
        metadata: {
          analysis_type: analysisData.type,
          timestamp: analysisData.timestamp,
          repository: analysisData.repository || 'unknown'
        }
      }
    });
    
    console.log(`Analysis result stored: gs://${analysis_bucket}/$${filename}`);
    
    // Also log for Cloud Logging
    console.log('ANALYSIS_RESULT:', JSON.stringify({
      analysis_type: analysisData.type,
      file_count: analysisData.results ? analysisData.results.length : 1,
      timestamp: analysisData.timestamp,
      storage_path: `gs://${analysis_bucket}/$${filename}`
    }));
    
  } catch (error) {
    console.error('Failed to store analysis result:', error);
    throw error;
  }
}