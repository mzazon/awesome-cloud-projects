"""
Code Analysis Agent for ADK-powered documentation system.

This module implements the code analysis capabilities using Google's Agent Development Kit (ADK)
to understand code structure, extract meaningful insights, and prepare data for documentation generation.
"""

import os
import ast
import json
import logging
from typing import Dict, List, Any, Optional
from google.cloud import aiplatform
from google.adk import LlmAgent
from google.adk.tools import Tool

logger = logging.getLogger(__name__)

class CodeAnalysisAgent:
    """
    ADK-powered agent for analyzing code repositories and extracting structural information.
    
    This agent specializes in understanding software architecture, function relationships,
    and code patterns to provide comprehensive analysis for documentation generation.
    """
    
    def __init__(self, project_id: str):
        """
        Initialize the Code Analysis Agent with ADK and Vertex AI configuration.
        
        Args:
            project_id: Google Cloud project ID for Vertex AI access
        """
        self.project_id = project_id
        self.vertex_location = "${vertex_location}"
        self.model_name = "${gemini_model}"
        
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=self.vertex_location)
        
        # Initialize ADK LLM Agent with Vertex AI Gemini
        self.agent = LlmAgent(
            model_name=self.model_name,
            project_id=project_id,
            location=self.vertex_location,
            system_prompt="""You are a code analysis expert specializing in 
            understanding software architecture, function relationships, and 
            code patterns. Analyze code repositories to extract structural 
            information, identify key components, and understand business logic.
            
            Focus on:
            1. Identifying main architectural patterns and design decisions
            2. Understanding component relationships and dependencies
            3. Extracting business logic and domain concepts
            4. Assessing code quality and complexity
            5. Identifying areas that need documentation
            
            Provide clear, actionable insights that will help generate 
            comprehensive documentation for developers."""
        )
        
        # Add specialized code parsing tools
        self.agent.add_tool(self._create_code_parser_tool())
        self.agent.add_tool(self._create_dependency_analyzer_tool())
        self.agent.add_tool(self._create_complexity_calculator_tool())
        
        logger.info(f"Code Analysis Agent initialized with model: {self.model_name}")
    
    def _create_code_parser_tool(self) -> Tool:
        """Create a tool for parsing code structure and extracting key elements."""
        
        def parse_code_structure(file_content: str, file_path: str) -> Dict[str, Any]:
            """
            Parse code to extract functions, classes, imports, and other structural elements.
            
            Args:
                file_content: The source code content to analyze
                file_path: Path to the file being analyzed
                
            Returns:
                Dictionary containing extracted structural information
            """
            structure = {
                "file_path": file_path,
                "file_type": self._detect_file_type(file_path),
                "functions": [],
                "classes": [],
                "imports": [],
                "exports": [],
                "comments": [],
                "docstrings": [],
                "complexity_score": 0,
                "lines_of_code": len(file_content.splitlines()),
                "error": None
            }
            
            try:
                if file_path.endswith('.py'):
                    structure.update(self._parse_python_file(file_content))
                elif file_path.endswith(('.js', '.ts')):
                    structure.update(self._parse_javascript_file(file_content))
                elif file_path.endswith(('.java')):
                    structure.update(self._parse_java_file(file_content))
                elif file_path.endswith(('.cpp', '.c', '.h')):
                    structure.update(self._parse_cpp_file(file_content))
                else:
                    structure.update(self._parse_generic_file(file_content))
                
                # Calculate complexity score
                structure["complexity_score"] = self._calculate_complexity_score(structure)
                
            except Exception as e:
                structure["error"] = str(e)
                logger.warning(f"Error parsing {file_path}: {str(e)}")
            
            return structure
        
        return Tool(
            name="code_parser",
            description="Parse code files to extract structural information including functions, classes, and imports",
            func=parse_code_structure
        )
    
    def _create_dependency_analyzer_tool(self) -> Tool:
        """Create a tool for analyzing dependencies between code components."""
        
        def analyze_dependencies(file_analyses: List[Dict[str, Any]]) -> Dict[str, Any]:
            """
            Analyze dependencies and relationships between code files and components.
            
            Args:
                file_analyses: List of individual file analysis results
                
            Returns:
                Dictionary containing dependency analysis
            """
            dependencies = {
                "internal_dependencies": {},
                "external_dependencies": [],
                "circular_dependencies": [],
                "dependency_graph": {},
                "critical_components": []
            }
            
            try:
                # Build dependency graph
                for analysis in file_analyses:
                    file_path = analysis.get("file_path", "")
                    imports = analysis.get("imports", [])
                    
                    dependencies["dependency_graph"][file_path] = {
                        "imports": imports,
                        "internal_imports": [],
                        "external_imports": []
                    }
                    
                    # Categorize imports
                    for imp in imports:
                        if self._is_internal_import(imp, file_analyses):
                            dependencies["dependency_graph"][file_path]["internal_imports"].append(imp)
                        else:
                            dependencies["dependency_graph"][file_path]["external_imports"].append(imp)
                            if imp not in dependencies["external_dependencies"]:
                                dependencies["external_dependencies"].append(imp)
                
                # Identify critical components (most imported)
                import_counts = {}
                for file_path, deps in dependencies["dependency_graph"].items():
                    for imp in deps["internal_imports"]:
                        import_counts[imp] = import_counts.get(imp, 0) + 1
                
                dependencies["critical_components"] = sorted(
                    import_counts.items(), 
                    key=lambda x: x[1], 
                    reverse=True
                )[:5]
                
            except Exception as e:
                dependencies["error"] = str(e)
                logger.warning(f"Error analyzing dependencies: {str(e)}")
            
            return dependencies
        
        return Tool(
            name="dependency_analyzer",
            description="Analyze dependencies and relationships between code components",
            func=analyze_dependencies
        )
    
    def _create_complexity_calculator_tool(self) -> Tool:
        """Create a tool for calculating code complexity metrics."""
        
        def calculate_complexity_metrics(analysis_results: Dict[str, Any]) -> Dict[str, Any]:
            """
            Calculate various complexity metrics for the analyzed code.
            
            Args:
                analysis_results: Complete analysis results from repository analysis
                
            Returns:
                Dictionary containing complexity metrics
            """
            metrics = {
                "cyclomatic_complexity": 0,
                "cognitive_complexity": 0,
                "maintainability_index": 0,
                "technical_debt_ratio": 0,
                "documentation_coverage": 0,
                "test_coverage_estimate": 0
            }
            
            try:
                file_analyses = analysis_results.get("file_analyses", [])
                total_functions = 0
                documented_functions = 0
                total_complexity = 0
                
                for analysis in file_analyses:
                    structure = analysis.get("structure", {})
                    functions = structure.get("functions", [])
                    
                    total_functions += len(functions)
                    total_complexity += structure.get("complexity_score", 0)
                    
                    # Count documented functions
                    for func in functions:
                        if func.get("docstring"):
                            documented_functions += 1
                
                # Calculate documentation coverage
                if total_functions > 0:
                    metrics["documentation_coverage"] = (documented_functions / total_functions) * 100
                
                # Estimate maintainability based on complexity and documentation
                complexity_factor = min(total_complexity / max(len(file_analyses), 1), 100)
                doc_factor = metrics["documentation_coverage"]
                metrics["maintainability_index"] = max(0, 100 - complexity_factor + (doc_factor * 0.3))
                
                # Estimate technical debt
                if complexity_factor > 50 or doc_factor < 30:
                    metrics["technical_debt_ratio"] = min(
                        (complexity_factor / 100) * (1 - doc_factor / 100) * 100, 
                        100
                    )
                
            except Exception as e:
                metrics["error"] = str(e)
                logger.warning(f"Error calculating complexity metrics: {str(e)}")
            
            return metrics
        
        return Tool(
            name="complexity_calculator",
            description="Calculate complexity metrics and maintainability indicators",
            func=calculate_complexity_metrics
        )
    
    def analyze_repository(self, repo_path: str) -> Dict[str, Any]:
        """
        Analyze a complete repository for documentation generation.
        
        Args:
            repo_path: Path to the extracted repository directory
            
        Returns:
            Complete analysis results including structure, dependencies, and insights
        """
        logger.info(f"Starting repository analysis for: {repo_path}")
        
        analysis_result = {
            "repository_path": repo_path,
            "repository_structure": {},
            "file_analyses": [],
            "dependency_analysis": {},
            "complexity_metrics": {},
            "overall_complexity": 0,
            "documentation_suggestions": [],
            "architectural_insights": "",
            "business_logic_summary": ""
        }
        
        total_complexity = 0
        file_count = 0
        
        # Process repository files
        for root, dirs, files in os.walk(repo_path):
            # Skip hidden directories and common build/dependency folders
            dirs[:] = [d for d in dirs if not d.startswith('.') and d not in [
                'node_modules', '__pycache__', '.git', 'build', 'dist', 'target'
            ]]
            
            for file in files:
                if self._should_analyze_file(file):
                    file_path = os.path.join(root, file)
                    relative_path = os.path.relpath(file_path, repo_path)
                    
                    try:
                        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                        
                        # Use ADK agent to analyze the file
                        analysis_prompt = f"""
                        Analyze this code file and provide comprehensive insights:
                        
                        File: {relative_path}
                        Content (first 3000 chars): {content[:3000]}{'...' if len(content) > 3000 else ''}
                        
                        Please provide detailed analysis including:
                        1. Purpose and functionality of this file
                        2. Key components and their roles in the system
                        3. Business logic and domain concepts implemented
                        4. Dependencies and relationships with other components
                        5. Code quality assessment and potential improvements
                        6. Documentation quality and gaps
                        7. Architectural patterns or design decisions evident
                        
                        Focus on information that would be valuable for generating
                        comprehensive developer documentation.
                        """
                        
                        ai_analysis = self.agent.generate(analysis_prompt)
                        
                        # Parse code structure using the parsing tool
                        structure = self.agent.tools[0].func(content, relative_path)
                        total_complexity += structure.get("complexity_score", 0)
                        file_count += 1
                        
                        analysis_result["file_analyses"].append({
                            "file_path": relative_path,
                            "ai_analysis": ai_analysis,
                            "structure": structure,
                            "file_size": len(content),
                            "lines_of_code": len(content.splitlines())
                        })
                        
                        logger.debug(f"Analyzed file: {relative_path}")
                        
                    except Exception as e:
                        logger.warning(f"Failed to analyze {relative_path}: {str(e)}")
                        continue
        
        logger.info(f"Analyzed {file_count} files with total complexity: {total_complexity}")
        
        # Perform dependency analysis
        if analysis_result["file_analyses"]:
            analysis_result["dependency_analysis"] = self.agent.tools[1].func(
                analysis_result["file_analyses"]
            )
        
        # Calculate complexity metrics
        analysis_result["complexity_metrics"] = self.agent.tools[2].func(analysis_result)
        analysis_result["overall_complexity"] = total_complexity
        
        # Generate architectural insights using ADK
        architectural_prompt = f"""
        Based on the analysis of {file_count} files in this repository, provide comprehensive
        architectural insights and recommendations:
        
        Repository structure: {len(analysis_result["file_analyses"])} files analyzed
        Total complexity: {total_complexity}
        Key components found: {[fa["file_path"] for fa in analysis_result["file_analyses"][:10]]}
        
        Please analyze:
        1. Overall architectural patterns and design decisions
        2. System structure and component organization
        3. Main business domains and functionality areas
        4. Code quality and maintainability assessment
        5. Documentation strategy recommendations
        6. Areas that need immediate attention
        7. Strengths and potential improvements
        
        Provide insights that will help create comprehensive documentation
        for new developers joining this project.
        """
        
        analysis_result["architectural_insights"] = self.agent.generate(architectural_prompt)
        
        # Generate business logic summary
        business_logic_prompt = f"""
        Summarize the key business logic and domain concepts implemented in this codebase:
        
        Based on the {file_count} analyzed files, identify:
        1. Core business functionality and use cases
        2. Domain models and key entities
        3. Business rules and logic patterns
        4. User-facing features and capabilities
        5. Integration points and external dependencies
        
        Create a summary that helps developers understand what this
        application does from a business perspective.
        """
        
        analysis_result["business_logic_summary"] = self.agent.generate(business_logic_prompt)
        
        logger.info(f"Repository analysis completed successfully")
        return analysis_result
    
    def _detect_file_type(self, file_path: str) -> str:
        """Detect the programming language/file type based on extension."""
        extension = os.path.splitext(file_path)[1].lower()
        type_mapping = {
            '.py': 'python',
            '.js': 'javascript',
            '.ts': 'typescript',
            '.jsx': 'react',
            '.tsx': 'react-typescript',
            '.java': 'java',
            '.cpp': 'cpp',
            '.c': 'c',
            '.h': 'header',
            '.go': 'go',
            '.rs': 'rust',
            '.php': 'php',
            '.rb': 'ruby',
            '.cs': 'csharp',
            '.swift': 'swift',
            '.kt': 'kotlin'
        }
        return type_mapping.get(extension, 'unknown')
    
    def _should_analyze_file(self, filename: str) -> bool:
        """Determine if a file should be analyzed based on its extension."""
        analyze_extensions = {
            '.py', '.js', '.ts', '.jsx', '.tsx', '.java', '.cpp', '.c', '.h',
            '.go', '.rs', '.php', '.rb', '.cs', '.swift', '.kt'
        }
        return any(filename.endswith(ext) for ext in analyze_extensions)
    
    def _parse_python_file(self, content: str) -> Dict[str, Any]:
        """Parse Python file using AST."""
        result = {"functions": [], "classes": [], "imports": [], "docstrings": []}
        
        try:
            tree = ast.parse(content)
            
            for node in ast.walk(tree):
                if isinstance(node, ast.FunctionDef):
                    result["functions"].append({
                        "name": node.name,
                        "line_start": node.lineno,
                        "args": [arg.arg for arg in node.args.args],
                        "docstring": ast.get_docstring(node),
                        "decorators": [d.id if hasattr(d, 'id') else str(d) for d in node.decorator_list],
                        "is_async": isinstance(node, ast.AsyncFunctionDef)
                    })
                elif isinstance(node, ast.ClassDef):
                    methods = [n.name for n in node.body if isinstance(n, ast.FunctionDef)]
                    result["classes"].append({
                        "name": node.name,
                        "line_start": node.lineno,
                        "methods": methods,
                        "docstring": ast.get_docstring(node),
                        "bases": [base.id if hasattr(base, 'id') else str(base) for base in node.bases]
                    })
                elif isinstance(node, ast.Import):
                    for alias in node.names:
                        result["imports"].append(alias.name)
                elif isinstance(node, ast.ImportFrom):
                    if node.module:
                        for alias in node.names:
                            result["imports"].append(f"{node.module}.{alias.name}")
        
        except SyntaxError as e:
            result["error"] = f"Python syntax error: {str(e)}"
        
        return result
    
    def _parse_javascript_file(self, content: str) -> Dict[str, Any]:
        """Basic JavaScript/TypeScript parsing using regex patterns."""
        import re
        
        result = {"functions": [], "classes": [], "imports": [], "exports": []}
        
        # Find function declarations
        func_pattern = r'(?:function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:function|\([^)]*\)\s*=>))'
        for match in re.finditer(func_pattern, content):
            func_name = match.group(1) or match.group(2)
            if func_name:
                result["functions"].append({
                    "name": func_name,
                    "line_start": content[:match.start()].count('\n') + 1
                })
        
        # Find class declarations
        class_pattern = r'class\s+(\w+)'
        for match in re.finditer(class_pattern, content):
            result["classes"].append({
                "name": match.group(1),
                "line_start": content[:match.start()].count('\n') + 1
            })
        
        # Find imports
        import_pattern = r'import\s+.*?\s+from\s+[\'"]([^\'"]+)[\'"]'
        for match in re.finditer(import_pattern, content):
            result["imports"].append(match.group(1))
        
        return result
    
    def _parse_java_file(self, content: str) -> Dict[str, Any]:
        """Basic Java parsing using regex patterns."""
        import re
        
        result = {"functions": [], "classes": [], "imports": []}
        
        # Find class declarations
        class_pattern = r'(?:public\s+)?class\s+(\w+)'
        for match in re.finditer(class_pattern, content):
            result["classes"].append({
                "name": match.group(1),
                "line_start": content[:match.start()].count('\n') + 1
            })
        
        # Find method declarations
        method_pattern = r'(?:public|private|protected)?\s*(?:static\s+)?(?:\w+\s+)+(\w+)\s*\([^)]*\)\s*{'
        for match in re.finditer(method_pattern, content):
            result["functions"].append({
                "name": match.group(1),
                "line_start": content[:match.start()].count('\n') + 1
            })
        
        # Find imports
        import_pattern = r'import\s+([^;]+);'
        for match in re.finditer(import_pattern, content):
            result["imports"].append(match.group(1).strip())
        
        return result
    
    def _parse_cpp_file(self, content: str) -> Dict[str, Any]:
        """Basic C/C++ parsing using regex patterns."""
        import re
        
        result = {"functions": [], "classes": [], "imports": []}
        
        # Find function declarations
        func_pattern = r'(?:(?:inline|static|virtual)\s+)*(?:\w+(?:\s*\*)*\s+)+(\w+)\s*\([^)]*\)\s*[{;]'
        for match in re.finditer(func_pattern, content):
            result["functions"].append({
                "name": match.group(1),
                "line_start": content[:match.start()].count('\n') + 1
            })
        
        # Find class declarations
        class_pattern = r'class\s+(\w+)'
        for match in re.finditer(class_pattern, content):
            result["classes"].append({
                "name": match.group(1),
                "line_start": content[:match.start()].count('\n') + 1
            })
        
        # Find includes
        include_pattern = r'#include\s+[<"]([^>"]+)[>"]'
        for match in re.finditer(include_pattern, content):
            result["imports"].append(match.group(1))
        
        return result
    
    def _parse_generic_file(self, content: str) -> Dict[str, Any]:
        """Generic parsing for unknown file types."""
        return {
            "functions": [],
            "classes": [],
            "imports": [],
            "file_type": "generic",
            "lines_of_code": len(content.splitlines())
        }
    
    def _calculate_complexity_score(self, structure: Dict[str, Any]) -> int:
        """Calculate a complexity score based on code structure."""
        score = 0
        score += len(structure.get("functions", [])) * 2
        score += len(structure.get("classes", [])) * 5
        score += len(structure.get("imports", [])) * 1
        score += structure.get("lines_of_code", 0) // 10
        return score
    
    def _is_internal_import(self, import_name: str, file_analyses: List[Dict[str, Any]]) -> bool:
        """Determine if an import is internal to the project."""
        # Simple heuristic: if it starts with '.' or matches a file in the project
        if import_name.startswith('.'):
            return True
        
        for analysis in file_analyses:
            file_path = analysis.get("file_path", "")
            if import_name in file_path or file_path.replace('/', '.').replace('.py', '') in import_name:
                return True
        
        return False