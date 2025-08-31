-- BigQuery view for content rankings with performance categorization
-- This view ranks content by performance score and assigns quality categories
SELECT 
    content_id,
    title,
    content_type,
    content_score,
    page_views,
    engagement_rate,
    conversion_rate,
    social_shares,
    publish_date,
    CASE 
        WHEN content_score >= 9.0 THEN 'Excellent'
        WHEN content_score >= 7.5 THEN 'Good'
        WHEN content_score >= 6.0 THEN 'Average'
        ELSE 'Needs Improvement'
    END as performance_category,
    RANK() OVER (ORDER BY content_score DESC) as performance_rank,
    RANK() OVER (PARTITION BY content_type ORDER BY content_score DESC) as type_rank
FROM `${project_id}.${dataset_name}.${table_name}`
ORDER BY content_score DESC