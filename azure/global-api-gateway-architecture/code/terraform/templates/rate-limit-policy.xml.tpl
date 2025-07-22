<policies>
  <inbound>
    <base />
    
    <!-- Extract client identifier from subscription key or use anonymous -->
    <set-variable name="clientId" value="@(context.Subscription?.Key ?? "anonymous")" />
    <set-variable name="regionName" value="@(context.Deployment.Region)" />
    <set-variable name="currentTime" value="@(DateTime.UtcNow)" />
    
    <!-- Check local cache first for rate limit status -->
    <cache-lookup-value key="@("rate-limit-" + context.Variables["clientId"])" variable-name="remainingCalls" />
    
    <choose>
      <!-- If cached rate limit exceeded, reject immediately -->
      <when condition="@(context.Variables.ContainsKey("remainingCalls") && (int)context.Variables["remainingCalls"] <= 0)">
        <return-response>
          <set-status code="429" reason="Too Many Requests" />
          <set-header name="Retry-After" exists-action="override">
            <value>60</value>
          </set-header>
          <set-header name="X-RateLimit-Limit" exists-action="override">
            <value>1000</value>
          </set-header>
          <set-header name="X-RateLimit-Remaining" exists-action="override">
            <value>0</value>
          </set-header>
          <set-header name="X-RateLimit-Reset" exists-action="override">
            <value>@(((DateTimeOffset)context.Variables["currentTime"]).ToUnixTimeSeconds() + 3600)</value>
          </set-header>
          <set-body>@{
            return new JObject(
              new JProperty("error", "Rate limit exceeded"),
              new JProperty("message", "Too many requests. Please try again later."),
              new JProperty("retryAfter", 60),
              new JProperty("region", context.Variables["regionName"])
            ).ToString();
          }</set-body>
        </return-response>
      </when>
      
      <!-- Check and update rate limit in Cosmos DB -->
      <otherwise>
        <!-- Query Cosmos DB for current rate limit status -->
        <send-request mode="new" response-variable-name="cosmosResponse" timeout="5" ignore-error="true">
          <set-url>${cosmos_endpoint}dbs/${database_name}/colls/${container_name}/docs</set-url>
          <set-method>POST</set-method>
          <set-header name="Authorization" exists-action="override">
            <value>@{
              // Use managed identity token for Cosmos DB
              var token = context.Authentication.GetAccessToken("https://cosmos.azure.com/");
              return "type=aad&ver=1.0&sig=" + token;
            }</value>
          </set-header>
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-header name="x-ms-documentdb-partitionkey" exists-action="override">
            <value>@("[\"" + context.Variables["clientId"] + "\"]")</value>
          </set-header>
          <set-header name="x-ms-documentdb-is-upsert" exists-action="override">
            <value>true</value>
          </set-header>
          
          <!-- Create or update rate limit document -->
          <set-body>@{
            var clientId = (string)context.Variables["clientId"];
            var region = (string)context.Variables["regionName"];
            var currentTime = (DateTime)context.Variables["currentTime"];
            
            // Calculate hourly window start
            var windowStart = new DateTime(currentTime.Year, currentTime.Month, currentTime.Day, currentTime.Hour, 0, 0, DateTimeKind.Utc);
            var documentId = clientId + "-" + windowStart.ToString("yyyyMMddHH");
            
            return new JObject(
              new JProperty("id", documentId),
              new JProperty("apiId", clientId),
              new JProperty("region", region),
              new JProperty("windowStart", windowStart.ToString("yyyy-MM-ddTHH:mm:ssZ")),
              new JProperty("requestCount", 1),
              new JProperty("lastRequest", currentTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")),
              new JProperty("ttl", 7200) // 2 hours TTL
            ).ToString();
          }</set-body>
        </send-request>
        
        <!-- Process Cosmos DB response and enforce limits -->
        <choose>
          <when condition="@(context.Variables.ContainsKey("cosmosResponse") && ((IResponse)context.Variables["cosmosResponse"]).StatusCode < 300)">
            <!-- Parse response to get current count -->
            <set-variable name="cosmosDoc" value="@{
              var response = (IResponse)context.Variables["cosmosResponse"];
              return JObject.Parse(response.Body.As<string>());
            }" />
            
            <set-variable name="currentCount" value="@{
              var doc = (JObject)context.Variables["cosmosDoc"];
              return (int)doc["requestCount"];
            }" />
            
            <!-- Check if rate limit exceeded -->
            <choose>
              <when condition="@((int)context.Variables["currentCount"] > 1000)">
                <!-- Cache the rate limit exceeded status -->
                <cache-store-value key="@("rate-limit-" + context.Variables["clientId"])" value="0" duration="3600" />
                
                <return-response>
                  <set-status code="429" reason="Too Many Requests" />
                  <set-header name="Retry-After" exists-action="override">
                    <value>60</value>
                  </set-header>
                  <set-header name="X-RateLimit-Limit" exists-action="override">
                    <value>1000</value>
                  </set-header>
                  <set-header name="X-RateLimit-Remaining" exists-action="override">
                    <value>0</value>
                  </set-header>
                  <set-header name="X-RateLimit-Reset" exists-action="override">
                    <value>@(((DateTimeOffset)context.Variables["currentTime"]).ToUnixTimeSeconds() + 3600)</value>
                  </set-header>
                  <set-body>@{
                    return new JObject(
                      new JProperty("error", "Rate limit exceeded"),
                      new JProperty("message", "Hourly rate limit of 1000 requests exceeded"),
                      new JProperty("retryAfter", 60),
                      new JProperty("currentCount", context.Variables["currentCount"]),
                      new JProperty("region", context.Variables["regionName"])
                    ).ToString();
                  }</set-body>
                </return-response>
              </when>
              
              <!-- Rate limit not exceeded, cache remaining calls -->
              <otherwise>
                <set-variable name="remainingCalls" value="@(1000 - (int)context.Variables["currentCount"])" />
                <cache-store-value key="@("rate-limit-" + context.Variables["clientId"])" value="@(context.Variables["remainingCalls"])" duration="300" />
                
                <!-- Add rate limit headers to response -->
                <set-header name="X-RateLimit-Limit" exists-action="override">
                  <value>1000</value>
                </set-header>
                <set-header name="X-RateLimit-Remaining" exists-action="override">
                  <value>@(context.Variables["remainingCalls"])</value>
                </set-header>
                <set-header name="X-RateLimit-Reset" exists-action="override">
                  <value>@(((DateTimeOffset)context.Variables["currentTime"]).ToUnixTimeSeconds() + 3600)</value>
                </set-header>
              </otherwise>
            </choose>
          </when>
          
          <!-- Cosmos DB error - allow request but log the issue -->
          <otherwise>
            <set-variable name="cosmosError" value="@{
              var response = context.Variables.ContainsKey("cosmosResponse") ? (IResponse)context.Variables["cosmosResponse"] : null;
              return response != null ? response.StatusCode.ToString() : "No response";
            }" />
            
            <!-- Log the error for monitoring -->
            <trace source="rate-limit-policy">@{
              return "Cosmos DB error: " + context.Variables["cosmosError"] + " for client " + context.Variables["clientId"];
            }</trace>
            
            <!-- Use local cache as fallback -->
            <cache-lookup-value key="@("fallback-rate-limit-" + context.Variables["clientId"])" variable-name="fallbackCount" />
            <set-variable name="currentFallbackCount" value="@(context.Variables.ContainsKey("fallbackCount") ? (int)context.Variables["fallbackCount"] + 1 : 1)" />
            
            <choose>
              <when condition="@((int)context.Variables["currentFallbackCount"] > 100)">
                <return-response>
                  <set-status code="429" reason="Too Many Requests" />
                  <set-header name="Retry-After" exists-action="override">
                    <value>60</value>
                  </set-header>
                  <set-body>@{
                    return new JObject(
                      new JProperty("error", "Rate limit exceeded"),
                      new JProperty("message", "Fallback rate limit exceeded due to backend error"),
                      new JProperty("region", context.Variables["regionName"])
                    ).ToString();
                  }</set-body>
                </return-response>
              </when>
              <otherwise>
                <cache-store-value key="@("fallback-rate-limit-" + context.Variables["clientId"])" value="@(context.Variables["currentFallbackCount"])" duration="3600" />
              </otherwise>
            </choose>
          </otherwise>
        </choose>
      </otherwise>
    </choose>
  </inbound>
  
  <backend>
    <base />
  </backend>
  
  <outbound>
    <base />
    
    <!-- Add region information to response headers -->
    <set-header name="X-API-Region" exists-action="override">
      <value>@(context.Variables["regionName"])</value>
    </set-header>
    
    <!-- Add request tracking header -->
    <set-header name="X-Request-Id" exists-action="override">
      <value>@(context.RequestId)</value>
    </set-header>
  </outbound>
  
  <on-error>
    <base />
    
    <!-- Log errors for monitoring -->
    <trace source="rate-limit-policy-error">@{
      return "Error in rate limiting policy: " + context.LastError.Message + " for client " + context.Variables.GetValueOrDefault("clientId", "unknown");
    }</trace>
  </on-error>
</policies>