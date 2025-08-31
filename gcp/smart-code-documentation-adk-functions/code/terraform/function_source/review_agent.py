"""
Quality Review Agent for ADK-powered documentation system.

This module implements the quality review capabilities using Google's Agent Development Kit (ADK)
to ensure generated documentation meets high standards for accuracy, completeness, and usefulness.
"""

import json
import logging
import re
from typing import Dict, Any, List, Tuple, Optional
from google.cloud import aiplatform
from google.adk import LlmAgent
from google.adk.tools import Tool

logger = logging.getLogger(__name__)

class QualityReviewAgent:
    """
    ADK-powered agent for reviewing and improving documentation quality.
    
    This agent implements quality gates that validate documentation against best practices,
    ensures accuracy and completeness, and provides improvement suggestions to maintain
    high documentation standards.
    """
    
    def __init__(self, project_id: str):
        """
        Initialize the Quality Review Agent with ADK and Vertex AI configuration.
        
        Args:
            project_id: Google Cloud project ID for Vertex AI access
        """
        self.project_id = project_id
        self.vertex_location = "${vertex_location}"
        self.model_name = "${gemini_model}"
        
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=self.vertex_location)
        
        # Initialize ADK LLM Agent with quality review expertise
        self.agent = LlmAgent(
            model_name=self.model_name,
            project_id=project_id,
            location=self.vertex_location,
            system_prompt="""You are a documentation quality expert who reviews 
            technical documentation for accuracy, completeness, clarity, and 
            usefulness. Provide constructive feedback and improvement suggestions.
            
            Your review criteria include:
            1. Accuracy - Does the documentation correctly represent the code?
            2. Completeness - Are all important components and concepts covered?
            3. Clarity - Is the documentation easy to understand and well-organized?
            4. Usefulness - Will this help developers be productive?
            5. Consistency - Does it follow documentation standards and conventions?
            6. Maintainability - Is it structured for easy updates and maintenance?
            
            Provide specific, actionable feedback that helps improve documentation quality.
            Focus on what developers actually need to be successful with the codebase."""
        )
        
        # Add specialized quality review tools
        self.agent.add_tool(self._create_completeness_checker_tool())
        self.agent.add_tool(self._create_accuracy_validator_tool())
        self.agent.add_tool(self._create_clarity_analyzer_tool())
        
        logger.info(f"Quality Review Agent initialized with model: {self.model_name}")
    
    def _create_completeness_checker_tool(self) -> Tool:
        """Create a tool for checking documentation completeness."""
        
        def check_completeness(documentation: str, code_analysis: Dict[str, Any]) -> Dict[str, Any]:
            """
            Check if documentation covers all important aspects of the code.
            
            Args:
                documentation: Generated documentation text
                code_analysis: Original code analysis data
                
            Returns:
                Completeness assessment with gaps identified
            """
            completeness_report = {
                "overall_score": 0,
                "missing_sections": [],
                "coverage_analysis": {},
                "recommendations": []
            }
            
            try:
                # Required sections for complete documentation
                required_sections = [
                    "overview", "architecture", "setup", "usage", "components",
                    "api", "examples", "troubleshooting"
                ]
                
                doc_lower = documentation.lower()
                sections_found = []
                
                for section in required_sections:
                    if section in doc_lower or f"#{section}" in doc_lower:
                        sections_found.append(section)
                    else:
                        completeness_report["missing_sections"].append(section)
                
                # Calculate coverage score
                coverage_score = (len(sections_found) / len(required_sections)) * 100
                completeness_report["coverage_analysis"]["section_coverage"] = coverage_score
                
                # Check if major components are documented
                total_files = len(code_analysis.get("file_analyses", []))
                documented_files = 0
                
                for file_analysis in code_analysis.get("file_analyses", []):
                    file_path = file_analysis.get("file_path", "")
                    if file_path.lower() in doc_lower:
                        documented_files += 1
                
                component_coverage = (documented_files / max(total_files, 1)) * 100
                completeness_report["coverage_analysis"]["component_coverage"] = component_coverage
                
                # Check API documentation coverage
                total_functions = sum(
                    len(fa.get("structure", {}).get("functions", []))
                    for fa in code_analysis.get("file_analyses", [])
                )
                
                # Count function mentions in documentation
                function_mentions = 0
                for file_analysis in code_analysis.get("file_analyses", []):
                    for func in file_analysis.get("structure", {}).get("functions", []):
                        if func.get("name", "").lower() in doc_lower:
                            function_mentions += 1
                
                api_coverage = (function_mentions / max(total_functions, 1)) * 100
                completeness_report["coverage_analysis"]["api_coverage"] = api_coverage
                
                # Calculate overall score
                overall_score = (coverage_score * 0.4 + component_coverage * 0.3 + api_coverage * 0.3)
                completeness_report["overall_score"] = round(overall_score, 1)
                
                # Generate recommendations
                if coverage_score < 80:
                    completeness_report["recommendations"].append(
                        f"Add missing sections: {', '.join(completeness_report['missing_sections'])}"
                    )
                
                if component_coverage < 70:
                    completeness_report["recommendations"].append(
                        "Increase component documentation coverage - many files are not documented"
                    )
                
                if api_coverage < 60:
                    completeness_report["recommendations"].append(
                        "Add more detailed API documentation for functions and methods"
                    )
                
            except Exception as e:
                completeness_report["error"] = str(e)
                logger.warning(f"Error checking completeness: {str(e)}")
            
            return completeness_report
        
        return Tool(
            name="completeness_checker",
            description="Check documentation completeness against code analysis",
            func=check_completeness
        )
    
    def _create_accuracy_validator_tool(self) -> Tool:
        """Create a tool for validating documentation accuracy."""
        
        def validate_accuracy(documentation: str, code_analysis: Dict[str, Any]) -> Dict[str, Any]:
            """
            Validate that documentation accurately represents the code.
            
            Args:
                documentation: Generated documentation text
                code_analysis: Original code analysis data
                
            Returns:
                Accuracy assessment with discrepancies identified
            """
            accuracy_report = {
                "accuracy_score": 0,
                "discrepancies": [],
                "verified_facts": [],
                "confidence_level": "high"
            }
            
            try:
                # Check if mentioned files actually exist in analysis
                mentioned_files = re.findall(r'(?:file|module|component):\s*([a-zA-Z0-9_./\\-]+\.(?:py|js|ts|java|cpp))', 
                                           documentation, re.IGNORECASE)
                
                actual_files = [fa.get("file_path", "") for fa in code_analysis.get("file_analyses", [])]
                
                for mentioned_file in mentioned_files:
                    if any(mentioned_file in actual_file for actual_file in actual_files):
                        accuracy_report["verified_facts"].append(f"File {mentioned_file} exists")
                    else:
                        accuracy_report["discrepancies"].append(f"Mentioned file {mentioned_file} not found in analysis")
                
                # Check if mentioned functions exist
                mentioned_functions = re.findall(r'`([a-zA-Z_][a-zA-Z0-9_]*)\([^)]*\)`', documentation)
                
                actual_functions = []
                for file_analysis in code_analysis.get("file_analyses", []):
                    for func in file_analysis.get("structure", {}).get("functions", []):
                        actual_functions.append(func.get("name", ""))
                
                for mentioned_func in mentioned_functions:
                    if mentioned_func in actual_functions:
                        accuracy_report["verified_facts"].append(f"Function {mentioned_func} exists")
                    else:
                        # Only flag as discrepancy if it's clearly meant to be a function from this codebase
                        if len(mentioned_func) > 3 and not mentioned_func.lower() in ['print', 'len', 'str', 'int']:
                            accuracy_report["discrepancies"].append(f"Mentioned function {mentioned_func} not found in analysis")
                
                # Check complexity claims
                complexity_mentions = re.findall(r'(high|low|medium|complex|simple)\s*complexity', 
                                                documentation, re.IGNORECASE)
                
                actual_complexity = code_analysis.get("overall_complexity", 0)
                total_files = len(code_analysis.get("file_analyses", []))
                avg_complexity = actual_complexity / max(total_files, 1)
                
                for mention in complexity_mentions:
                    if mention.lower() in ['high', 'complex'] and avg_complexity < 10:
                        accuracy_report["discrepancies"].append(
                            f"Documentation claims high complexity but analysis shows average complexity of {avg_complexity:.1f}"
                        )
                    elif mention.lower() in ['low', 'simple'] and avg_complexity > 20:
                        accuracy_report["discrepancies"].append(
                            f"Documentation claims low complexity but analysis shows average complexity of {avg_complexity:.1f}"
                        )
                
                # Calculate accuracy score
                total_claims = len(mentioned_files) + len(mentioned_functions) + len(complexity_mentions)
                verified_claims = len(accuracy_report["verified_facts"])
                discrepancy_count = len(accuracy_report["discrepancies"])
                
                if total_claims > 0:
                    accuracy_score = max(0, ((verified_claims - discrepancy_count) / total_claims) * 100)
                else:
                    accuracy_score = 90  # Default high score if no specific claims to verify
                
                accuracy_report["accuracy_score"] = round(accuracy_score, 1)
                
                # Set confidence level
                if discrepancy_count > 3:
                    accuracy_report["confidence_level"] = "low"
                elif discrepancy_count > 1:
                    accuracy_report["confidence_level"] = "medium"
                else:
                    accuracy_report["confidence_level"] = "high"
                
            except Exception as e:
                accuracy_report["error"] = str(e)
                logger.warning(f"Error validating accuracy: {str(e)}")
            
            return accuracy_report
        
        return Tool(
            name="accuracy_validator",
            description="Validate documentation accuracy against code analysis",
            func=validate_accuracy
        )
    
    def _create_clarity_analyzer_tool(self) -> Tool:
        """Create a tool for analyzing documentation clarity and readability."""
        
        def analyze_clarity(documentation: str) -> Dict[str, Any]:
            """
            Analyze documentation for clarity, readability, and organization.
            
            Args:
                documentation: Documentation text to analyze
                
            Returns:
                Clarity assessment with improvement suggestions
            """
            clarity_report = {
                "readability_score": 0,
                "structure_score": 0,
                "clarity_issues": [],
                "strengths": [],
                "improvement_suggestions": []
            }
            
            try:
                # Check document structure
                headers = re.findall(r'^#+\s+(.+)$', documentation, re.MULTILINE)
                
                structure_score = 0
                if len(headers) >= 3:
                    structure_score += 30  # Has multiple sections
                if any('overview' in h.lower() for h in headers):
                    structure_score += 20  # Has overview
                if any('example' in h.lower() for h in headers):
                    structure_score += 20  # Has examples
                if any('api' in h.lower() or 'reference' in h.lower() for h in headers):
                    structure_score += 20  # Has API docs
                if any('setup' in h.lower() or 'install' in h.lower() for h in headers):
                    structure_score += 10  # Has setup instructions
                
                clarity_report["structure_score"] = min(structure_score, 100)
                
                # Check for clarity issues
                sentences = re.split(r'[.!?]+', documentation)
                long_sentences = [s for s in sentences if len(s.split()) > 25]
                
                if len(long_sentences) > len(sentences) * 0.2:
                    clarity_report["clarity_issues"].append("Many sentences are too long - consider breaking them up")
                
                # Check for code examples
                code_blocks = re.findall(r'```[\s\S]*?```', documentation)
                if len(code_blocks) >= 2:
                    clarity_report["strengths"].append("Includes helpful code examples")
                elif len(code_blocks) == 0:
                    clarity_report["clarity_issues"].append("No code examples found - would help with understanding")
                
                # Check for lists and structure
                lists = re.findall(r'^\s*[-*+]\s', documentation, re.MULTILINE)
                if len(lists) >= 5:
                    clarity_report["strengths"].append("Good use of lists for organization")
                
                # Check for jargon and technical terms
                jargon_indicators = ['implementation', 'instantiation', 'polymorphism', 'encapsulation']
                jargon_count = sum(1 for term in jargon_indicators if term in documentation.lower())
                
                if jargon_count > 3:
                    clarity_report["clarity_issues"].append("Consider explaining technical terms for better accessibility")
                
                # Check paragraph length
                paragraphs = [p.strip() for p in documentation.split('\n\n') if p.strip() and not p.strip().startswith('#')]
                long_paragraphs = [p for p in paragraphs if len(p.split()) > 100]
                
                if len(long_paragraphs) > len(paragraphs) * 0.3:
                    clarity_report["clarity_issues"].append("Some paragraphs are very long - consider breaking them up")
                
                # Calculate readability score
                readability_score = 100
                readability_score -= len(clarity_report["clarity_issues"]) * 15
                readability_score += len(clarity_report["strengths"]) * 10
                readability_score = max(0, min(readability_score, 100))
                
                clarity_report["readability_score"] = readability_score
                
                # Generate improvement suggestions
                if clarity_report["structure_score"] < 60:
                    clarity_report["improvement_suggestions"].append(
                        "Add more section headers to improve document organization"
                    )
                
                if len(code_blocks) == 0:
                    clarity_report["improvement_suggestions"].append(
                        "Add practical code examples to illustrate usage"
                    )
                
                if readability_score < 70:
                    clarity_report["improvement_suggestions"].append(
                        "Simplify language and break up complex sentences for better readability"
                    )
                
            except Exception as e:
                clarity_report["error"] = str(e)
                logger.warning(f"Error analyzing clarity: {str(e)}")
            
            return clarity_report
        
        return Tool(
            name="clarity_analyzer",
            description="Analyze documentation clarity and readability",
            func=analyze_clarity
        )
    
    def review_documentation(self, documentation: str, code_analysis: Dict[str, Any]) -> Dict[str, Any]:
        """
        Perform comprehensive quality review of generated documentation.
        
        Args:
            documentation: Generated documentation text
            code_analysis: Original code analysis data
            
        Returns:
            Complete review results with quality score and improvement suggestions
        """
        logger.info("Starting comprehensive documentation quality review")
        
        # Perform automated checks using tools
        completeness_check = self.agent.tools[0].func(documentation, code_analysis)
        accuracy_check = self.agent.tools[1].func(documentation, code_analysis)
        clarity_check = self.agent.tools[2].func(documentation)
        
        # Generate comprehensive review using ADK
        review_prompt = f"""
        Perform a comprehensive quality review of this technical documentation:
        
        Documentation Length: {len(documentation)} characters
        Code Analysis Summary: {len(code_analysis.get('file_analyses', []))} files analyzed
        
        Documentation Sample (first 2000 chars):
        {documentation[:2000]}...
        
        Automated Analysis Results:
        - Completeness Score: {completeness_check.get('overall_score', 0)}/100
        - Accuracy Score: {accuracy_check.get('accuracy_score', 0)}/100
        - Readability Score: {clarity_check.get('readability_score', 0)}/100
        - Structure Score: {clarity_check.get('structure_score', 0)}/100
        
        Issues Found:
        - Missing Sections: {completeness_check.get('missing_sections', [])}
        - Accuracy Issues: {accuracy_check.get('discrepancies', [])}
        - Clarity Issues: {clarity_check.get('clarity_issues', [])}
        
        Provide a comprehensive review including:
        1. Overall quality assessment (1-10 scale)
        2. Specific strengths of the documentation
        3. Key areas that need improvement
        4. Actionable recommendations for enhancement
        5. Assessment of usefulness for developers
        6. Compliance with documentation best practices
        
        Be specific and constructive in your feedback.
        """
        
        ai_review = self.agent.generate(review_prompt)
        
        # Extract quality metrics from the review
        quality_metrics = self._extract_quality_metrics(ai_review)
        
        # Calculate composite quality score
        composite_score = self._calculate_composite_score(
            completeness_check, accuracy_check, clarity_check, quality_metrics
        )
        
        review_results = {
            "review_summary": ai_review,
            "quality_score": composite_score,
            "automated_checks": {
                "completeness": completeness_check,
                "accuracy": accuracy_check,
                "clarity": clarity_check
            },
            "strengths": self._extract_strengths(ai_review, completeness_check, accuracy_check, clarity_check),
            "improvements": self._extract_improvements(ai_review, completeness_check, accuracy_check, clarity_check),
            "recommendations": self._generate_recommendations(completeness_check, accuracy_check, clarity_check),
            "approved": composite_score >= 7,  # Approval threshold
            "confidence_level": accuracy_check.get("confidence_level", "medium"),
            "review_metadata": {
                "total_issues_found": (
                    len(completeness_check.get('missing_sections', [])) +
                    len(accuracy_check.get('discrepancies', [])) +
                    len(clarity_check.get('clarity_issues', []))
                ),
                "documentation_length": len(documentation),
                "files_analyzed": len(code_analysis.get('file_analyses', [])),
                "review_timestamp": self._get_timestamp()
            }
        }
        
        logger.info(f"Quality review completed. Score: {composite_score}/10, Approved: {review_results['approved']}")
        return review_results
    
    def suggest_improvements(self, documentation: str, review_results: Dict[str, Any]) -> str:
        """
        Generate improved documentation based on review feedback.
        
        Args:
            documentation: Original documentation text
            review_results: Results from quality review
            
        Returns:
            Improved documentation text
        """
        logger.info("Generating improved documentation based on review feedback")
        
        improvement_prompt = f"""
        Improve this documentation based on the comprehensive review feedback:
        
        Original Documentation:
        {documentation[:4000]}{"..." if len(documentation) > 4000 else ""}
        
        Quality Review Results:
        - Overall Score: {review_results.get('quality_score', 0)}/10
        - Approved: {review_results.get('approved', False)}
        
        Specific Issues to Address:
        - Missing Sections: {review_results.get('automated_checks', {}).get('completeness', {}).get('missing_sections', [])}
        - Accuracy Issues: {review_results.get('automated_checks', {}).get('accuracy', {}).get('discrepancies', [])}
        - Clarity Issues: {review_results.get('automated_checks', {}).get('clarity', {}).get('clarity_issues', [])}
        
        Key Improvements Needed:
        {chr(10).join(f"- {item}" for item in review_results.get('improvements', []))}
        
        Recommendations:
        {chr(10).join(f"- {item}" for item in review_results.get('recommendations', []))}
        
        Generate an improved version that:
        1. Addresses all identified issues and gaps
        2. Maintains the original structure and content quality
        3. Adds missing information and sections
        4. Improves clarity and readability
        5. Follows documentation best practices
        6. Ensures accuracy and completeness
        
        Preserve all existing good content while making necessary improvements.
        """
        
        improved_documentation = self.agent.generate(improvement_prompt)
        
        logger.info(f"Generated improved documentation ({len(improved_documentation)} characters)")
        return improved_documentation
    
    def _extract_quality_metrics(self, review_text: str) -> Dict[str, Any]:
        """Extract structured quality metrics from AI review text."""
        metrics = {
            "ai_score": 7,
            "strengths": [],
            "improvements": [],
            "recommendations": []
        }
        
        # Extract quality score
        score_patterns = [
            r'(?:overall|quality)(?:\s+score)?[:\s]*(\d+)(?:/10|\s*out\s*of\s*10)',
            r'(?:score|rating)[:\s]*(\d+)',
            r'(\d+)/10'
        ]
        
        for pattern in score_patterns:
            score_match = re.search(pattern, review_text.lower())
            if score_match:
                metrics["ai_score"] = int(score_match.group(1))
                break
        
        # Extract sections using improved parsing
        lines = review_text.split('\n')
        current_section = None
        
        for line in lines:
            line = line.strip()
            line_lower = line.lower()
            
            if any(keyword in line_lower for keyword in ['strength', 'positive', 'good']):
                current_section = 'strengths'
            elif any(keyword in line_lower for keyword in ['improvement', 'issue', 'problem', 'gap']):
                current_section = 'improvements'
            elif any(keyword in line_lower for keyword in ['recommend', 'suggest', 'should']):
                current_section = 'recommendations'
            elif line.startswith(('-', '•', '*')) or line_lower.startswith('- '):
                if current_section and current_section in metrics:
                    clean_line = line.lstrip('- •*').strip()
                    if clean_line:
                        metrics[current_section].append(clean_line)
        
        return metrics
    
    def _calculate_composite_score(self, completeness: Dict, accuracy: Dict, 
                                 clarity: Dict, ai_metrics: Dict) -> int:
        """Calculate a composite quality score from all assessments."""
        # Weight the different aspects
        completeness_score = completeness.get('overall_score', 0) / 10
        accuracy_score = accuracy.get('accuracy_score', 0) / 10
        readability_score = clarity.get('readability_score', 0) / 10
        structure_score = clarity.get('structure_score', 0) / 10
        ai_score = ai_metrics.get('ai_score', 7)
        
        # Weighted composite score
        composite = (
            completeness_score * 0.25 +  # 25% weight on completeness
            accuracy_score * 0.25 +      # 25% weight on accuracy
            readability_score * 0.2 +     # 20% weight on readability
            structure_score * 0.15 +      # 15% weight on structure
            ai_score * 0.15               # 15% weight on AI assessment
        )
        
        return round(composite)
    
    def _extract_strengths(self, ai_review: str, completeness: Dict, 
                          accuracy: Dict, clarity: Dict) -> List[str]:
        """Extract and combine strengths from all assessments."""
        strengths = []
        
        # From AI review
        ai_strengths = self._extract_quality_metrics(ai_review).get('strengths', [])
        strengths.extend(ai_strengths)
        
        # From automated checks
        if completeness.get('overall_score', 0) > 80:
            strengths.append("Comprehensive coverage of code components")
        
        if accuracy.get('accuracy_score', 0) > 85:
            strengths.append("High accuracy in representing code functionality")
        
        if clarity.get('readability_score', 0) > 80:
            strengths.append("Clear and readable documentation structure")
        
        strengths.extend(clarity.get('strengths', []))
        
        return list(set(strengths))  # Remove duplicates
    
    def _extract_improvements(self, ai_review: str, completeness: Dict,
                            accuracy: Dict, clarity: Dict) -> List[str]:
        """Extract and combine improvement areas from all assessments."""
        improvements = []
        
        # From AI review
        ai_improvements = self._extract_quality_metrics(ai_review).get('improvements', [])
        improvements.extend(ai_improvements)
        
        # From automated checks
        improvements.extend(completeness.get('recommendations', []))
        improvements.extend(accuracy.get('discrepancies', []))
        improvements.extend(clarity.get('clarity_issues', []))
        
        return list(set(improvements))  # Remove duplicates
    
    def _generate_recommendations(self, completeness: Dict, accuracy: Dict,
                                clarity: Dict) -> List[str]:
        """Generate actionable recommendations based on all assessments."""
        recommendations = []
        
        # Completeness recommendations
        if completeness.get('overall_score', 0) < 70:
            recommendations.append("Expand documentation to cover more components and use cases")
        
        # Accuracy recommendations
        if len(accuracy.get('discrepancies', [])) > 0:
            recommendations.append("Verify and correct factual inaccuracies in the documentation")
        
        # Clarity recommendations
        if clarity.get('readability_score', 0) < 70:
            recommendations.append("Improve readability with clearer language and better organization")
        
        if clarity.get('structure_score', 0) < 60:
            recommendations.append("Add more section headers and improve document structure")
        
        # Coverage recommendations
        coverage = completeness.get('coverage_analysis', {})
        if coverage.get('component_coverage', 0) < 60:
            recommendations.append("Document more individual components and their purposes")
        
        if coverage.get('api_coverage', 0) < 50:
            recommendations.append("Add detailed API documentation for functions and classes")
        
        return recommendations
    
    def _get_timestamp(self) -> str:
        """Get current timestamp for review metadata."""
        from datetime import datetime
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")