# Scoutica Agent Capability Taxonomy

## Version 1.0

This document defines the standardized capability taxonomy for all agents in the Scoutica multi-swarm network.

---

## Capability Structure

Each capability follows this structure:

```json
{
  "domain": "recruitment | content | data | education | file",
  "operation": "specific_action",
  "scope": "optional_scope",
  "modalities": ["input_types"],
  "metadata": {
    "description": "Human-readable description",
    "version": "1.0",
    "custom_key": "custom_value"
  }
}
```

---

## Domain: recruitment

Capabilities for recruitment and talent acquisition.

### recruitment.orchestrate_workflow
**Operation**: `orchestrate_workflow`  
**Description**: Coordinate complete recruitment workflow from job activation to screening  
**Scope**: `end_to_end`  
**Modalities**: `["job_activation", "multi_agent_coordination"]`  
**Agents**: Orchestrator Agent

### recruitment.manage_job
**Operation**: `manage_job`  
**Description**: Manage job lifecycle including state transitions and error recovery  
**Scope**: `job_lifecycle`  
**Modalities**: `["state_management", "error_recovery"]`  
**Agents**: Orchestrator Agent

### recruitment.coordinate_tasks
**Operation**: `coordinate_tasks`  
**Description**: Coordinate task execution with dependency resolution  
**Scope**: `task_management`  
**Modalities**: `["dependency_resolution", "task_routing"]`  
**Agents**: Orchestrator Agent

### recruitment.conversation
**Operation**: `conversation`  
**Description**: Conduct intake conversations and pre-screening interviews  
**Scope**: `candidate_interaction`  
**Modalities**: `["text", "voice", "chat"]`  
**Agents**: Conversation Agent

### recruitment.analyze_job
**Operation**: `analyze_job`  
**Description**: Analyze and synthesize job descriptions  
**Scope**: `job_analysis`  
**Modalities**: `["text", "structured_data"]`  
**Agents**: JD Agent

### recruitment.synthesize_jd
**Operation**: `synthesize_jd`  
**Description**: Generate comprehensive job descriptions from requirements  
**Scope**: `jd_generation`  
**Modalities**: `["requirements_to_jd"]`  
**Agents**: JD Agent

### recruitment.source_candidates
**Operation**: `source_candidates`  
**Description**: Discover and source candidates from multiple channels  
**Scope**: `candidate_discovery`  
**Modalities**: `["api", "web_scraping", "database"]`  
**Agents**: Sourcing Agent

### recruitment.match_candidates
**Operation**: `match_candidates`  
**Description**: Match candidates to job requirements using vector similarity  
**Scope**: `candidate_matching`  
**Modalities**: `["vector_search", "semantic_similarity"]`  
**Agents**: Matching Agent

### recruitment.screen_candidate
**Operation**: `screen_candidate`  
**Description**: Deep LLM-based candidate assessment and screening  
**Scope**: `candidate_assessment`  
**Modalities**: `["llm_analysis", "multi_dimensional_scoring"]`  
**Agents**: Screening Agent

---

## Domain: content

Capabilities for content processing and generation.

### content.search
**Operation**: `search`  
**Description**: Intelligent search across web and databases  
**Scope**: `information_retrieval`  
**Modalities**: `["web", "semantic", "multi_provider"]`  
**Agents**: Agentic Search Engine
**Providers**: `["brave", "google", "perplexity", "tavily"]`

### content.scrape
**Operation**: `scrape`  
**Description**: Extract content from web pages and documents  
**Scope**: `data_extraction`  
**Modalities**: `["html", "json", "api"]`  
**Agents**: Agentic Search Engine

### content.translate
**Operation**: `translate`  
**Description**: Translate content between languages  
**Scope**: `language_translation`  
**Modalities**: `["text", "json", "csv", "markdown", "pdf", "image"]`  
**Agents**: Translation Engine, i18n Translator
**Languages**: `["en", "es", "fr", "de", "pt", "it", "nl", "pl", "ja", "zh", "ko", "ar"]`

### content.ocr
**Operation**: `ocr`  
**Description**: Extract text from images using OCR  
**Scope**: `image_to_text`  
**Modalities**: `["image"]`  
**Agents**: Translation Engine

### content.summarize
**Operation**: `summarize`  
**Description**: Distill complex documents into actionable summaries  
**Scope**: `document_summarization`  
**Modalities**: `["text", "markdown", "pdf"]`  
**Agents**: Summarizer Agent

### content.improve
**Operation**: `improve`  
**Description**: Enhance writing clarity, impact, and style  
**Scope**: `writing_enhancement`  
**Modalities**: `["text", "markdown"]`  
**Agents**: Writing Assistant

### content.optimize_seo
**Operation**: `optimize_seo`  
**Description**: Optimize content for search engines  
**Scope**: `seo_optimization`  
**Modalities**: `["text", "html", "metadata"]`  
**Agents**: SEO Strategist

---

## Domain: data

Capabilities for data processing and analysis.

### data.analyze
**Operation**: `analyze`  
**Description**: Analyze structured and unstructured data  
**Scope**: `data_analysis`  
**Modalities**: `["csv", "json", "database"]`  
**Agents**: Data Analyst Agent

### data.transform
**Operation**: `transform`  
**Description**: Transform data between formats  
**Scope**: `data_transformation`  
**Modalities**: `["csv_to_json", "json_to_csv", "normalization"]`  
**Agents**: Data Transformer Agent

### data.validate
**Operation**: `validate`  
**Description**: Validate data quality and integrity  
**Scope**: `data_quality`  
**Modalities**: `["schema_validation", "integrity_checks"]`  
**Agents**: Data Validator Agent

---

## Domain: education

Capabilities for educational content and learning.

### education.create_course
**Operation**: `create_course`  
**Description**: Generate educational course content  
**Scope**: `course_creation`  
**Modalities**: `["text", "video_scripts", "assessments"]`  
**Agents**: Course Creator Agent

### education.assess_learning
**Operation**: `assess_learning`  
**Description**: Assess learner understanding and progress  
**Scope**: `learning_assessment`  
**Modalities**: `["quiz", "assignment", "project"]`  
**Agents**: Learning Assessor Agent

---

## Domain: file

Capabilities for file operations.

### file.convert
**Operation**: `convert`  
**Description**: Convert files between formats  
**Scope**: `file_conversion`  
**Modalities**: `["pdf", "docx", "markdown", "html"]`  
**Agents**: File Converter Agent

### file.extract
**Operation**: `extract`  
**Description**: Extract specific content from files  
**Scope**: `content_extraction`  
**Modalities**: `["pdf", "docx", "xlsx"]`  
**Agents**: File Extractor Agent

---

## Custom Capability Keys

Agents can include custom metadata using the `x-` prefix:

```json
{
  "domain": "recruitment",
  "operation": "match_candidates",
  "metadata": {
    "x-algorithm": "pgvector-hnsw",
    "x-performance": "10-100x",
    "x-max-candidates": 10000
  }
}
```

---

## Capability Query Format

When querying the Registry for capabilities:

```json
{
  "capability": {
    "domain": "recruitment",
    "operation": "match_candidates"
  },
  "constraints": {
    "performance": "high",
    "min_success_rate": 0.95
  }
}
```

---

## Versioning

Capabilities are versioned independently:

```json
{
  "domain": "recruitment",
  "operation": "match_candidates",
  "metadata": {
    "version": "2.0",
    "breaking_changes": "Uses pgvector instead of Python loops"
  }
}
```

---

## Best Practices

1. **Be Specific**: Use clear, descriptive operation names
2. **Document Modalities**: Always specify supported input/output types
3. **Version Everything**: Include version in metadata
4. **Use Standard Domains**: Only create custom domains when necessary
5. **Provide Examples**: Include usage examples in agent documentation

---

## Example: Complete Capability Definition

```json
{
  "name": "match_candidates",
  "description": "Match candidates to job requirements using vector similarity",
  "capability": {
    "domain": "recruitment",
    "operation": "match_candidates",
    "scope": "candidate_matching",
    "modalities": ["vector_search", "semantic_similarity"]
  },
  "metadata": {
    "version": "2.0",
    "algorithm": "pgvector-hnsw",
    "max_candidates": 10000,
    "avg_latency_ms": 300,
    "success_rate": 0.98
  },
  "input_schema": {
    "job_id": "string",
    "candidates": "array",
    "job_requirements": "object"
  },
  "output_schema": {
    "matched_candidates": "array",
    "scores": "array",
    "statistics": "object"
  }
}
```

---

## Registry Integration

Agents register capabilities on startup:

```python
capabilities = [
    {
        "name": "match_candidates",
        "description": "Match candidates using pgvector similarity",
        "capability": {
            "domain": "recruitment",
            "operation": "match_candidates"
        }
    }
]

await registry_client.register(
    agent_key="matching-agent",
    capabilities=capabilities
)
```

---

**Version**: 1.0  
**Last Updated**: 2025-11-06  
**Status**: Active

