"""
Documentation Generation Agent for ADK-powered documentation system.

This module implements the documentation generation capabilities using Google's Agent Development Kit (ADK)
to transform code analysis results into comprehensive, human-readable documentation.
"""

import json
import logging
import re
from typing import Dict, Any, List, Optional
from google.cloud import aiplatform
from google.adk import LlmAgent
from google.adk.tools import Tool

logger = logging.getLogger(__name__)

class DocumentationAgent:
    """
    ADK-powered agent for generating comprehensive documentation from code analysis results.
    
    This agent specializes in transforming technical code analysis into clear, comprehensive
    documentation that helps developers understand both the technical implementation and
    business purpose of code components.
    """
    
    def __init__(self, project_id: str):
        """
        Initialize the Documentation Generation Agent with ADK and Vertex AI configuration.
        
        Args:
            project_id: Google Cloud project ID for Vertex AI access
        """
        self.project_id = project_id
        self.vertex_location = "${vertex_location}"
        self.model_name = "${gemini_model}"
        
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=self.vertex_location)
        
        # Initialize ADK LLM Agent with specialized documentation prompt
        self.agent = LlmAgent(
            model_name=self.model_name,
            project_id=project_id,
            location=self.vertex_location,
            system_prompt="""You are a technical documentation expert who creates 
            clear, comprehensive documentation from code analysis. Generate 
            documentation that helps developers understand both the technical 
            implementation and business purpose of code components.
            
            Your documentation should:
            1. Be clear and accessible to developers of varying experience levels
            2. Explain both the "what" and "why" of code components
            3. Include practical usage examples where appropriate
            4. Highlight architectural decisions and design patterns
            5. Provide guidance for maintenance and extension
            6. Follow documentation best practices and conventions
            
            Focus on creating documentation that truly helps developers be 
            productive with the codebase."""
        )
        
        # Add specialized documentation generation tools
        self.agent.add_tool(self._create_markdown_formatter_tool())
        self.agent.add_tool(self._create_api_documentation_tool())
        self.agent.add_tool(self._create_example_generator_tool())
        
        logger.info(f"Documentation Agent initialized with model: {self.model_name}")
    
    def _create_markdown_formatter_tool(self) -> Tool:
        """Create a tool for formatting documentation as structured markdown."""
        
        def format_markdown_section(title: str, content: str, level: int = 2) -> str:
            """
            Format a documentation section as markdown with proper heading levels.
            
            Args:
                title: Section title
                content: Section content
                level: Heading level (1-6)
                
            Returns:
                Formatted markdown section
            """
            heading = "#" * level
            formatted_content = content.strip()
            
            # Clean up excessive whitespace
            formatted_content = re.sub(r'\n\s*\n\s*\n', '\n\n', formatted_content)
            
            return f"{heading} {title}\n\n{formatted_content}\n\n"
        
        return Tool(
            name="markdown_formatter",
            description="Format documentation content as structured markdown",
            func=format_markdown_section
        )
    
    def _create_api_documentation_tool(self) -> Tool:
        """Create a tool for generating API reference documentation."""
        
        def generate_api_reference(functions: List[Dict[str, Any]], classes: List[Dict[str, Any]]) -> str:
            """
            Generate API reference documentation for functions and classes.
            
            Args:
                functions: List of function definitions
                classes: List of class definitions
                
            Returns:
                Formatted API reference documentation
            """
            api_docs = []
            
            # Document classes
            if classes:
                api_docs.append("### Classes\n")
                for cls in classes:
                    class_doc = f"#### `{cls['name']}`\n\n"
                    
                    if cls.get('docstring'):
                        class_doc += f"{cls['docstring']}\n\n"
                    else:
                        class_doc += f"Class {cls['name']} (line {cls.get('line_start', 'unknown')})\n\n"
                    
                    # Document methods
                    if cls.get('methods'):
                        class_doc += "**Methods:**\n"
                        for method in cls['methods']:
                            class_doc += f"- `{method}()`\n"
                        class_doc += "\n"
                    
                    # Document inheritance
                    if cls.get('bases'):
                        class_doc += f"**Inherits from:** {', '.join(cls['bases'])}\n\n"
                    
                    api_docs.append(class_doc)
            
            # Document functions
            if functions:
                api_docs.append("### Functions\n")
                for func in functions:
                    func_doc = f"#### `{func['name']}({', '.join(func.get('args', []))})`\n\n"
                    
                    if func.get('docstring'):
                        func_doc += f"{func['docstring']}\n\n"
                    else:
                        func_doc += f"Function {func['name']} (line {func.get('line_start', 'unknown')})\n\n"
                    
                    # Document parameters
                    if func.get('args'):
                        func_doc += "**Parameters:**\n"
                        for arg in func['args']:
                            func_doc += f"- `{arg}`: Parameter description needed\n"
                        func_doc += "\n"
                    
                    # Document decorators
                    if func.get('decorators'):
                        func_doc += f"**Decorators:** {', '.join(func['decorators'])}\n\n"
                    
                    # Mark async functions
                    if func.get('is_async'):
                        func_doc += "**Note:** This is an async function.\n\n"
                    
                    api_docs.append(func_doc)
            
            return ''.join(api_docs)
        
        return Tool(
            name="api_documentation",
            description="Generate API reference documentation for functions and classes",
            func=generate_api_reference
        )
    
    def _create_example_generator_tool(self) -> Tool:
        """Create a tool for generating usage examples."""
        
        def generate_usage_examples(analysis_data: Dict[str, Any]) -> str:
            """
            Generate practical usage examples based on code analysis.
            
            Args:
                analysis_data: Complete analysis data for the repository
                
            Returns:
                Formatted usage examples
            """
            examples = []
            
            # Extract main classes and functions for examples
            main_components = []
            
            for file_analysis in analysis_data.get("file_analyses", []):
                structure = file_analysis.get("structure", {})
                file_path = file_analysis.get("file_path", "")
                
                # Focus on main/core files
                if any(keyword in file_path.lower() for keyword in ['main', 'app', 'core', 'service']):
                    main_components.extend(structure.get("classes", []))
                    main_components.extend(structure.get("functions", []))
            
            if main_components:
                examples.append("## Usage Examples\n")
                
                # Generate basic usage example
                examples.append("### Basic Usage\n")
                examples.append("```python\n")
                examples.append("# Example usage based on analyzed code structure\n")
                
                for i, component in enumerate(main_components[:3]):  # Limit to top 3 components
                    if 'name' in component:
                        if 'args' in component:  # It's a function
                            args = component.get('args', [])
                            example_args = ', '.join([f'"{arg}_value"' for arg in args[:2]])  # Limit args
                            examples.append(f"result = {component['name']}({example_args})\n")
                        else:  # It's a class
                            examples.append(f"instance = {component['name']}()\n")
                
                examples.append("```\n\n")
                
                # Generate configuration example if config-related code found
                config_files = [fa for fa in analysis_data.get("file_analyses", []) 
                              if 'config' in fa.get("file_path", "").lower()]
                
                if config_files:
                    examples.append("### Configuration\n")
                    examples.append("```python\n")
                    examples.append("# Configuration setup\n")
                    examples.append("config = ConfigManager('config.json')\n")
                    examples.append("settings = config.get_settings()\n")
                    examples.append("```\n\n")
            
            return ''.join(examples)
        
        return Tool(
            name="example_generator",
            description="Generate practical usage examples from code analysis",
            func=generate_usage_examples
        )
    
    def generate_documentation(self, analysis_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generate comprehensive documentation from code analysis results.
        
        Args:
            analysis_data: Complete analysis results from the CodeAnalysisAgent
            
        Returns:
            Dictionary containing organized documentation sections
        """
        logger.info("Starting documentation generation from analysis data")
        
        documentation = {
            "overview": "",
            "architecture": "",
            "components": [],
            "api_reference": [],
            "usage_examples": "",
            "setup_instructions": "",
            "development_guide": "",
            "troubleshooting": ""
        }
        
        # Generate project overview
        overview_prompt = f"""
        Based on this comprehensive code analysis, generate a project overview that includes:
        
        Analysis Summary:
        - Total files analyzed: {len(analysis_data.get('file_analyses', []))}
        - Overall complexity: {analysis_data.get('overall_complexity', 0)}
        - Business logic: {analysis_data.get('business_logic_summary', '')[:500]}...
        - Architectural insights: {analysis_data.get('architectural_insights', '')[:500]}...
        
        Create a clear, engaging overview that includes:
        1. Project purpose and main functionality
        2. Target users and use cases
        3. Key features and capabilities
        4. Technology stack and dependencies
        5. High-level architecture approach
        
        Write for developers who are new to this codebase.
        """
        
        documentation["overview"] = self.agent.generate(overview_prompt)
        logger.debug("Generated project overview")
        
        # Generate architecture documentation
        architecture_prompt = f"""
        Create detailed architecture documentation based on:
        
        Architectural Insights: {analysis_data.get('architectural_insights', '')}
        Dependency Analysis: {json.dumps(analysis_data.get('dependency_analysis', {}), indent=2)[:1000]}...
        Complexity Metrics: {json.dumps(analysis_data.get('complexity_metrics', {}), indent=2)}
        
        Include:
        1. System architecture overview and design principles
        2. Component relationships and data flow
        3. Key architectural patterns used
        4. Design decisions and trade-offs
        5. Scalability and performance considerations
        6. Security architecture elements
        
        Make it comprehensive but accessible to developers.
        """
        
        documentation["architecture"] = self.agent.generate(architecture_prompt)
        logger.debug("Generated architecture documentation")
        
        # Generate component documentation for each major file
        for file_analysis in analysis_data.get("file_analyses", []):
            file_path = file_analysis.get("file_path", "")
            ai_analysis = file_analysis.get("ai_analysis", "")
            structure = file_analysis.get("structure", {})
            
            component_prompt = f"""
            Generate detailed component documentation for this file:
            
            File: {file_path}
            AI Analysis: {ai_analysis}
            Structure: {json.dumps(structure, indent=2)[:1500]}...
            
            Create documentation that includes:
            1. Component purpose and responsibilities
            2. Key functionality and business logic
            3. Public interfaces and APIs
            4. Dependencies and relationships
            5. Configuration and usage patterns
            6. Important implementation details
            7. Potential extension points
            
            Focus on what developers need to know to work with this component.
            """
            
            component_doc = self.agent.generate(component_prompt)
            
            # Generate API reference for this component
            api_ref = ""
            if structure.get("functions") or structure.get("classes"):
                api_ref = self.agent.tools[1].func(
                    structure.get("functions", []),
                    structure.get("classes", [])
                )
            
            documentation["components"].append({
                "file_path": file_path,
                "documentation": component_doc,
                "api_reference": api_ref,
                "functions": structure.get("functions", []),
                "classes": structure.get("classes", []),
                "complexity": structure.get("complexity_score", 0),
                "lines_of_code": structure.get("lines_of_code", 0)
            })
        
        logger.info(f"Generated component documentation for {len(documentation['components'])} files")
        
        # Generate usage examples
        documentation["usage_examples"] = self.agent.tools[2].func(analysis_data)
        logger.debug("Generated usage examples")
        
        # Generate setup instructions
        setup_prompt = f"""
        Based on the code analysis, generate setup and installation instructions:
        
        Dependencies found: {analysis_data.get('dependency_analysis', {}).get('external_dependencies', [])}
        File types: {[fa.get('structure', {}).get('file_type', 'unknown') for fa in analysis_data.get('file_analyses', [])]}
        
        Create comprehensive setup instructions including:
        1. Prerequisites and system requirements
        2. Installation steps
        3. Environment setup and configuration
        4. Dependency installation
        5. Initial configuration
        6. Verification steps
        
        Make it easy for new developers to get started.
        """
        
        documentation["setup_instructions"] = self.agent.generate(setup_prompt)
        logger.debug("Generated setup instructions")
        
        # Generate development guide
        dev_guide_prompt = f"""
        Create a development guide based on the analysis:
        
        Complexity Metrics: {json.dumps(analysis_data.get('complexity_metrics', {}), indent=2)}
        Code Quality Insights: {analysis_data.get('architectural_insights', '')[:800]}...
        
        Include:
        1. Development workflow and best practices
        2. Code organization and structure guidelines
        3. Testing strategies and patterns
        4. Debugging and troubleshooting tips
        5. Contribution guidelines
        6. Code review checklist
        
        Help developers be productive and maintain code quality.
        """
        
        documentation["development_guide"] = self.agent.generate(dev_guide_prompt)
        logger.debug("Generated development guide")
        
        # Generate troubleshooting section
        troubleshooting_prompt = f"""
        Create a troubleshooting guide based on the code analysis:
        
        Common patterns found: {[fa.get('file_path', '') for fa in analysis_data.get('file_analyses', [])[:5]]}
        Complexity issues: {analysis_data.get('complexity_metrics', {}).get('technical_debt_ratio', 0)}
        
        Include:
        1. Common issues and solutions
        2. Error patterns and debugging steps
        3. Performance optimization tips
        4. Configuration problems and fixes
        5. Dependency conflicts and resolutions
        6. Monitoring and logging guidance
        
        Help developers quickly resolve common problems.
        """
        
        documentation["troubleshooting"] = self.agent.generate(troubleshooting_prompt)
        logger.debug("Generated troubleshooting guide")
        
        logger.info("Documentation generation completed successfully")
        return documentation
    
    def format_markdown_documentation(self, documentation: Dict[str, Any]) -> str:
        """
        Format the complete documentation as structured markdown.
        
        Args:
            documentation: Generated documentation sections
            
        Returns:
            Complete markdown documentation string
        """
        logger.info("Formatting documentation as markdown")
        
        markdown_content = []
        
        # Title and overview
        markdown_content.append("# Project Documentation\n\n")
        markdown_content.append("## Overview\n\n")
        markdown_content.append(f"{documentation.get('overview', '')}\n\n")
        
        # Architecture section
        markdown_content.append("## Architecture\n\n")
        markdown_content.append(f"{documentation.get('architecture', '')}\n\n")
        
        # Setup instructions
        markdown_content.append("## Getting Started\n\n")
        markdown_content.append(f"{documentation.get('setup_instructions', '')}\n\n")
        
        # Usage examples
        if documentation.get("usage_examples"):
            markdown_content.append(f"{documentation['usage_examples']}\n\n")
        
        # Components section
        markdown_content.append("## Components\n\n")
        markdown_content.append("This section provides detailed documentation for each component in the system.\n\n")
        
        for component in documentation.get("components", []):
            file_path = component.get("file_path", "Unknown")
            
            # Component header
            markdown_content.append(f"### {file_path}\n\n")
            
            # Component documentation
            comp_doc = component.get("documentation", "")
            markdown_content.append(f"{comp_doc}\n\n")
            
            # API reference if available
            if component.get("api_reference"):
                markdown_content.append("#### API Reference\n\n")
                markdown_content.append(f"{component['api_reference']}\n\n")
            
            # Component metrics
            complexity = component.get("complexity", 0)
            loc = component.get("lines_of_code", 0)
            if complexity > 0 or loc > 0:
                markdown_content.append("#### Metrics\n\n")
                markdown_content.append(f"- **Complexity Score:** {complexity}\n")
                markdown_content.append(f"- **Lines of Code:** {loc}\n")
                
                if complexity > 20:
                    markdown_content.append("- ⚠️ **High Complexity:** Consider refactoring for maintainability\n")
                elif complexity > 10:
                    markdown_content.append("- ℹ️ **Moderate Complexity:** Monitor for future refactoring opportunities\n")
                else:
                    markdown_content.append("- ✅ **Low Complexity:** Well-structured and maintainable\n")
                
                markdown_content.append("\n")
            
            markdown_content.append("---\n\n")
        
        # Development guide
        markdown_content.append("## Development Guide\n\n")
        markdown_content.append(f"{documentation.get('development_guide', '')}\n\n")
        
        # Troubleshooting
        markdown_content.append("## Troubleshooting\n\n")
        markdown_content.append(f"{documentation.get('troubleshooting', '')}\n\n")
        
        # Footer
        markdown_content.append("---\n\n")
        markdown_content.append("*This documentation was automatically generated using Google Cloud's Agent Development Kit (ADK) and Gemini AI.*\n\n")
        markdown_content.append(f"*Generation timestamp: {self._get_timestamp()}*\n")
        
        final_markdown = ''.join(markdown_content)
        
        # Clean up formatting
        final_markdown = self._clean_markdown(final_markdown)
        
        logger.info(f"Generated {len(final_markdown)} characters of markdown documentation")
        return final_markdown
    
    def _clean_markdown(self, markdown_text: str) -> str:
        """Clean up markdown formatting issues."""
        # Remove excessive blank lines
        cleaned = re.sub(r'\n\s*\n\s*\n\s*\n', '\n\n\n', markdown_text)
        
        # Ensure proper spacing around headers
        cleaned = re.sub(r'(\n#{1,6}\s+.*\n)(?!\n)', r'\1\n', cleaned)
        
        # Ensure proper spacing before headers
        cleaned = re.sub(r'(?<!\n\n)(#{1,6}\s+)', r'\n\n\1', cleaned)
        
        # Fix list formatting
        cleaned = re.sub(r'\n(\s*[-*+]\s)', r'\n\n\1', cleaned)
        
        # Clean up extra whitespace
        cleaned = re.sub(r'[ \t]+\n', '\n', cleaned)
        
        return cleaned.strip() + '\n'
    
    def _get_timestamp(self) -> str:
        """Get current timestamp for documentation metadata."""
        from datetime import datetime
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")
    
    def generate_component_summary(self, components: List[Dict[str, Any]]) -> str:
        """
        Generate a high-level summary of all components.
        
        Args:
            components: List of component documentation
            
        Returns:
            Markdown summary of components
        """
        if not components:
            return "No components found for documentation.\n"
        
        summary_prompt = f"""
        Create a high-level summary of the system components:
        
        Components analyzed: {len(components)}
        Component files: {[c.get('file_path', 'Unknown') for c in components]}
        Total complexity: {sum(c.get('complexity', 0) for c in components)}
        
        Provide:
        1. System overview and main areas of functionality
        2. Key components and their roles
        3. Component relationships and interactions
        4. Areas of highest complexity or importance
        5. Recommended reading order for new developers
        
        Create a roadmap for understanding the codebase.
        """
        
        return self.agent.generate(summary_prompt)