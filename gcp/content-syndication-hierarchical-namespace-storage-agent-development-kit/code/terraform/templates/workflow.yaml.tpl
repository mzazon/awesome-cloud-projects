# Cloud Workflow Definition for Content Syndication Platform
# This workflow orchestrates the complete content syndication pipeline
# integrating storage events, AI processing, and distribution routing

main:
  params: [input]
  steps:
    # Initialize workflow with environment variables and input validation
    - init:
        assign:
          - bucket: $${sys.get_env("STORAGE_BUCKET")}
          - projectId: $${sys.get_env("PROJECT_ID")}
          - functionUrl: $${sys.get_env("FUNCTION_URL")}
          - vertexAiLocation: $${sys.get_env("VERTEX_AI_LOCATION")}
          - environment: $${sys.get_env("ENVIRONMENT")}
          - inputObject: $${input.object}
          - inputBucket: $${input.bucket}
          - workflowStartTime: $${sys.now()}

    # Validate input parameters
    - validateInput:
        switch:
          - condition: $${inputBucket == bucket}
            next: checkIncomingFolder
        next: invalidBucketError

    # Check if object is in the incoming folder for processing
    - checkIncomingFolder:
        switch:
          - condition: $${text.match_regex(inputObject, "^incoming/")}
            next: processContent
        next: skipProcessing

    # Call the content processing function
    - processContent:
        try:
          call: http.post
          args:
            url: $${functionUrl}
            headers:
              Content-Type: "application/json"
            body:
              bucket: $${inputBucket}
              object: $${inputObject}
            timeout: 300
          result: processingResult
        except:
          as: processingError
          next: handleProcessingError

    # Extract processing results
    - extractResults:
        assign:
          - contentAnalysis: $${processingResult.body.result.analysis}
          - routingDecision: $${processingResult.body.result.routing}
          - qualityAssessment: $${processingResult.body.result.quality}
          - finalStatus: $${processingResult.body.result.status}
          - newPath: $${processingResult.body.result.new_path}

    # Log processing completion
    - logProcessingSuccess:
        call: sys.log
        args:
          text: $${"Content processing completed for " + inputObject + " with status: " + finalStatus}
          severity: "INFO"

    # Branch based on quality assessment results
    - handleQualityResults:
        switch:
          - condition: $${qualityAssessment.approved_for_distribution}
            next: initiateDistribution
          - condition: $${qualityAssessment.passes_quality_check == false}
            next: flagForReview
        next: requiresProcessing

    # Initiate content distribution to approved channels
    - initiateDistribution:
        try:
          parallel:
            shared: [routingDecision]
            for:
              value: platform
              in: $${routingDecision.target_platforms}
              steps:
                - distributeToPlatform:
                    call: http.post
                    args:
                      url: $${"https://content-distribution-api.example.com/distribute"}
                      headers:
                        Content-Type: "application/json"
                      body:
                        platform: $${platform}
                        content_path: $${newPath}
                        bucket: $${bucket}
                        priority: $${routingDecision.priority}
                      timeout: 60
                    result: distributionResult
        except:
          as: distributionError
          next: handleDistributionError
        next: logDistributionSuccess

    # Flag content for human review
    - flagForReview:
        call: http.post
        args:
          url: $${"https://review-api.example.com/flag"}
          headers:
            Content-Type: "application/json"
          body:
            content_path: $${newPath}
            quality_score: $${qualityAssessment.quality_score}
            recommendations: $${qualityAssessment.recommendations}
            reason: "Quality threshold not met"
        result: reviewFlagResult
        next: logReviewFlag

    # Content requires additional processing
    - requiresProcessing:
        call: http.post
        args:
          url: $${"https://processing-api.example.com/enhance"}
          headers:
            Content-Type: "application/json"
          body:
            content_path: $${newPath}
            category: $${contentAnalysis.category}
            processing_required: $${routingDecision.processing_required}
            size_optimizations_needed: $${routingDecision.size_optimizations_needed}
        result: enhancementResult
        next: logProcessingQueued

    # Log successful distribution
    - logDistributionSuccess:
        call: sys.log
        args:
          text: $${"Content successfully distributed to " + string(len(routingDecision.target_platforms)) + " platforms"}
          severity: "INFO"
        next: calculateMetrics

    # Log review flag
    - logReviewFlag:
        call: sys.log
        args:
          text: $${"Content flagged for review: " + inputObject + " (Score: " + string(qualityAssessment.quality_score) + ")"}
          severity: "WARNING"
        next: calculateMetrics

    # Log processing queue
    - logProcessingQueued:
        call: sys.log
        args:
          text: $${"Content queued for additional processing: " + inputObject}
          severity: "INFO"
        next: calculateMetrics

    # Calculate and log workflow metrics
    - calculateMetrics:
        assign:
          - workflowEndTime: $${sys.now()}
          - processingDuration: $${workflowEndTime - workflowStartTime}
          - metricsData:
              workflow_duration_ms: $${processingDuration}
              content_category: $${contentAnalysis.category}
              content_size_mb: $${contentAnalysis.size_mb}
              quality_score: $${qualityAssessment.quality_score}
              platforms_targeted: $${len(routingDecision.target_platforms)}
              final_status: $${finalStatus}
              environment: $${environment}

    # Send metrics to monitoring
    - sendMetrics:
        try:
          call: http.post
          args:
            url: $${"https://monitoring.googleapis.com/v3/projects/" + projectId + "/timeSeries"}
            headers:
              Content-Type: "application/json"
            body:
              timeSeries:
                - metric:
                    type: "custom.googleapis.com/content_syndication/processing_duration"
                  resource:
                    type: "global"
                  points:
                    - value:
                        doubleValue: $${processingDuration}
                      interval:
                        endTime: $${sys.now()}
        except:
          as: metricsError
          next: logMetricsError

    # Return final workflow result
    - returnResult:
        return:
          success: true
          original_object: $${inputObject}
          new_path: $${newPath}
          status: $${finalStatus}
          metrics: $${metricsData}
          processing_result: $${processingResult.body}

    # Skip processing for objects outside incoming folder
    - skipProcessing:
        call: sys.log
        args:
          text: $${"Skipping processing for object outside incoming folder: " + inputObject}
          severity: "INFO"
        next: returnSkipped

    # Return skipped result
    - returnSkipped:
        return:
          success: true
          original_object: $${inputObject}
          status: "skipped"
          reason: "Object not in incoming folder"

    # Error handling for invalid bucket
    - invalidBucketError:
        call: sys.log
        args:
          text: $${"Invalid bucket in workflow input: " + inputBucket + " (expected: " + bucket + ")"}
          severity: "ERROR"
        next: returnError

    # Error handling for processing failures
    - handleProcessingError:
        call: sys.log
        args:
          text: $${"Content processing failed: " + string(processingError)}
          severity: "ERROR"
        next: returnProcessingError

    # Error handling for distribution failures
    - handleDistributionError:
        call: sys.log
        args:
          text: $${"Content distribution failed: " + string(distributionError)}
          severity: "ERROR"
        next: returnDistributionError

    # Error handling for metrics failures
    - logMetricsError:
        call: sys.log
        args:
          text: $${"Failed to send metrics: " + string(metricsError)}
          severity: "WARNING"
        next: returnResult

    # Return error result
    - returnError:
        return:
          success: false
          error: "Invalid bucket name"
          original_object: $${inputObject}
          expected_bucket: $${bucket}
          provided_bucket: $${inputBucket}

    # Return processing error result  
    - returnProcessingError:
        return:
          success: false
          error: "Content processing failed"
          original_object: $${inputObject}
          error_details: $${processingError}

    # Return distribution error result
    - returnDistributionError:
        return:
          success: false
          error: "Content distribution failed"
          original_object: $${inputObject}
          new_path: $${newPath}
          error_details: $${distributionError}
          partial_success: true