#!/usr/bin/env python3

import os
import json
import uuid
from typing import List, Dict, Any, TypedDict

# Define a TypedDict for the agent configuration to provide explicit type hints
class AgentConfig(TypedDict):
    name: str
    slug: str
    specialization: str
    tier: str
    model: str
    backup_model: str
    cooperative_level: str
    capabilities: List[str]
    integration_points: List[str]

# ==============================================
# Hardcoded Specialized Agent Categories
# ==============================================
AGENT_CATEGORIES: Dict[str, List[AgentConfig]] = {
    "frontend_ui_ux_specialists": [
        AgentConfig({
            "name": "React UI Performance Engineer",
            "slug": "react-ui-performance-engineer",
            "specialization": "Optimizes React applications for speed, responsiveness, and smooth UI rendering.",
            "tier": "primary",
            "model": "deepseek-coder-33b-instruct",
            "backup_model": "codellama-13b-instruct",
            "cooperative_level": "high",
            "capabilities": ["react_optimization", "component_architecture", "performance_profiling", "bundle_analysis"],
            "integration_points": ["ui_designer", "code_reviewer", "performance_optimizer"]
        }),
        AgentConfig({
            "name": "Accessibility UX Compliance Engineer",
            "slug": "accessibility-ux-compliance-engineer",
            "specialization": "Ensures WCAG compliance, inclusive design, and accessibility best practices across all interfaces.",
            "tier": "primary",
            "model": "qwen2.5-72b-instruct",
            "backup_model": "mistral-nemo-instruct",
            "cooperative_level": "high",
            "capabilities": ["wcag_compliance", "screen_reader_optimization", "keyboard_navigation", "inclusive_design"],
            "integration_points": ["ui_designer", "quality_assurance", "compliance_auditor"]
        }),
        AgentConfig({
            "name": "Responsive Design Architect",
            "slug": "responsive-design-architect",
            "specialization": "Designs mobile-first, multi-device layouts with progressive enhancement strategies.",
            "tier": "secondary",
            "model": "deepseek-coder-v2-236b",
            "backup_model": "codellama-34b-instruct",
            "cooperative_level": "medium",
            "capabilities": ["responsive_design", "mobile_optimization", "progressive_enhancement", "css_architecture"],
            "integration_points": ["ui_designer", "performance_optimizer", "device_compatibility_tester"]
        })
    ],
    "backend_architecture_engineers": [
        AgentConfig({
            "name": "Microservices Systems Architect",
            "slug": "microservices-systems-architect",
            "specialization": "Designs and optimizes distributed systems using service mesh and container orchestration.",
            "tier": "primary",
            "model": "deepseek-coder-33b-instruct",
            "backup_model": "wizardcoder-15b-v1.0",
            "cooperative_level": "critical",
            "capabilities": ["microservices_design", "service_mesh", "container_orchestration", "distributed_systems"],
            "integration_points": ["devops_engineer", "security_auditor", "performance_optimizer"]
        }),
        AgentConfig({
            "name": "API Gateway and Load Engineer",
            "slug": "api-gateway-and-load-engineer",
            "specialization": "Manages API gateway design, authentication, rate limiting, and load balancing.",
            "tier": "primary",
            "model": "mixtral-8x22b-instruct",
            "backup_model": "mixtral-8x7b-instruct",
            "cooperative_level": "critical",
            "capabilities": ["api_gateway_design", "rate_limiting", "load_balancing", "authentication"],
            "integration_points": ["security_auditor", "performance_optimizer", "monitoring_specialist"]
        }),
        AgentConfig({
            "name": "PostgreSQL Optimization Specialist",
            "slug": "postgresql-optimization-specialist",
            "specialization": "Specializes in PostgreSQL query optimization, indexing, and scaling for high performance.",
            "tier": "secondary",
            "model": "deepseek-v2.5",
            "backup_model": "yi-34b-chat",
            "cooperative_level": "high",
            "capabilities": ["query_optimization", "indexing_strategies", "database_scaling", "performance_tuning"],
            "integration_points": ["performance_optimizer", "data_engineer", "monitoring_specialist"]
        })
    ],
    "security_compliance_guardians": [
        AgentConfig({
            "name": "Zero Trust Security Architect",
            "slug": "zero-trust-security-architect",
            "specialization": "Implements zero-trust architectures and advanced threat modeling for enterprise-grade security.",
            "tier": "primary",
            "model": "mixtral-8x7b-instruct",
            "backup_model": "deepseek-coder-33b-instruct",
            "cooperative_level": "critical",
            "capabilities": ["zero_trust_design", "threat_modeling", "security_frameworks", "risk_assessment"],
            "integration_points": ["compliance_auditor", "penetration_tester", "incident_responder"]
        }),
        AgentConfig({
            "name": "Encryption and PKI Specialist",
            "slug": "encryption-and-pki-specialist",
            "specialization": "Implements cryptography, key management, and PKI infrastructure for secure systems.",
            "tier": "primary",
            "model": "deepseek-coder-33b-instruct",
            "backup_model": "llama-3-8b-instruct",
            "cooperative_level": "high",
            "capabilities": ["encryption_implementation", "key_management", "pki_infrastructure", "cryptographic_protocols"],
            "integration_points": ["security_architect", "compliance_auditor", "api_security_specialist"]
        }),
        AgentConfig({
            "name": "Enterprise Vulnerability Tester",
            "slug": "enterprise-vulnerability-tester",
            "specialization": "Performs penetration testing, vulnerability scanning, and exploit analysis to prevent breaches.",
            "tier": "secondary",
            "model": "deepseek-coder-v2-16b",
            "backup_model": "codellama-70b-instruct",
            "cooperative_level": "high",
            "capabilities": ["penetration_testing", "vulnerability_scanning", "security_assessment", "exploit_analysis"],
            "integration_points": ["security_architect", "incident_responder", "compliance_auditor"]
        })
    ],
    "error_handling_quality_assurance": [
        AgentConfig({
            "name": "Chaos Engineering Expert",
            "slug": "chaos-engineering-expert",
            "specialization": "Simulates system failures to improve resilience, stability, and recovery strategies.",
            "tier": "primary",
            "model": "deepseek-coder-33b-instruct",
            "backup_model": "codellama-13b-instruct",
            "cooperative_level": "high",
            "capabilities": ["chaos_engineering", "fault_injection", "resilience_testing", "reliability_analysis"],
            "integration_points": ["performance_optimizer", "monitoring_specialist", "incident_responder"]
        }),
        AgentConfig({
            "name": "Enterprise Exception Architect",
            "slug": "enterprise-exception-architect",
            "specialization": "Designs fault-tolerant exception handling hierarchies with graceful degradation methods.",
            "tier": "primary",
            "model": "deepseek-coder-v2-236b",
            "backup_model": "codellama-34b-instruct",
            "cooperative_level": "critical",
            "capabilities": ["exception_handling", "error_recovery", "graceful_degradation", "fault_tolerance"],
            "integration_points": ["chaos_engineer", "monitoring_specialist", "reliability_engineer"]
        }),
        AgentConfig({
            "name": "Automated Test Engineer",
            "slug": "automated-test-engineer",
            "specialization": "Builds and maintains CI/CD integrated test suites to ensure quality and regression-free releases.",
            "tier": "secondary",
            "model": "codellama-70b-instruct",
            "backup_model": "phi-3.5-mini-instruct",
            "cooperative_level": "high",
            "capabilities": ["test_automation", "ci_cd_integration", "quality_metrics", "test_strategy"],
            "integration_points": ["devops_engineer", "quality_assurance", "performance_tester"]
        })
    ],
    "creative_media_brand_specialists": [
        AgentConfig({
            "name": "AI Image Generation Specialist",
            "slug": "ai-image-generation-specialist",
            "specialization": "Creates brand-consistent images using AI generation tools like Stable Diffusion and DALL-E.",
            "tier": "primary",
            "model": "stable-diffusion-xl",
            "backup_model": "dall-e-3",
            "cooperative_level": "medium",
            "capabilities": ["image_generation", "style_consistency", "brand_assets", "visual_optimization"],
            "integration_points": ["brand_manager", "ui_designer", "content_creator"]
        }),
        AgentConfig({
            "name": "AI Video Content Producer",
            "slug": "ai-video-content-producer",
            "specialization": "Generates video and motion graphics content optimized for multiple platforms.",
            "tier": "primary",
            "model": "stable-video-diffusion",
            "backup_model": "runway-gen2",
            "cooperative_level": "medium",
            "capabilities": ["video_generation", "motion_graphics", "multimedia_optimization", "content_editing"],
            "integration_points": ["image_specialist", "brand_manager", "content_strategist"]
        }),
        AgentConfig({
            "name": "Brand Consistency Director",
            "slug": "brand-consistency-director",
            "specialization": "Maintains brand identity, ensuring all visual media aligns with corporate guidelines.",
            "tier": "secondary",
            "model": "llama-3.1-70b-instruct",
            "backup_model": "yi-34b-chat",
            "cooperative_level": "medium",
            "capabilities": ["brand_guidelines", "style_consistency", "visual_identity", "compliance_checking"],
            "integration_points": ["image_specialist", "video_creator", "ui_designer"]
        })
    ],
    "workflow_project_enhancement": [
        AgentConfig({
            "name": "Agile Process Strategist",
            "slug": "agile-process-strategist",
            "specialization": "Optimizes Agile processes, tracks velocity, and resolves project bottlenecks.",
            "tier": "primary",
            "model": "mixtral-8x7b-instruct",
            "backup_model": "llama-3-8b-instruct",
            "cooperative_level": "high",
            "capabilities": ["agile_optimization", "velocity_tracking", "bottleneck_analysis", "process_improvement"],
            "integration_points": ["project_manager", "resource_allocator", "delivery_coordinator"]
        }),
        AgentConfig({
            "name": "Enterprise Resource Allocator",
            "slug": "enterprise-resource-allocator",
            "specialization": "Plans capacity, optimizes resources, and balances workloads across teams.",
            "tier": "primary",
            "model": "deepseek-v2.5",
            "backup_model": "solar-10.7b-instruct",
            "cooperative_level": "critical",
            "capabilities": ["resource_planning", "capacity_optimization", "workload_balancing", "allocation_algorithms"],
            "integration_points": ["agile_optimizer", "performance_monitor", "delivery_coordinator"]
        }),
        AgentConfig({
            "name": "Delivery Pipeline Accelerator",
            "slug": "delivery-pipeline-accelerator",
            "specialization": "Speeds up deployment pipelines with automation and delivery performance tracking.",
            "tier": "secondary",
            "model": "llama-3.1-70b-instruct",
            "backup_model": "codellama-70b-instruct",
            "cooperative_level": "high",
            "capabilities": ["pipeline_optimization", "deployment_automation", "delivery_metrics", "acceleration_strategies"],
            "integration_points": ["devops_engineer", "agile_optimizer", "quality_assurance"]
        })
    ],
    "performance_code_optimization": [
        AgentConfig({
            "name": "Algorithm Optimization Specialist",
            "slug": "algorithm-optimization-specialist",
            "specialization": "Improves algorithm efficiency through complexity reduction, profiling, and optimization strategies.",
            "tier": "primary",
            "model": "deepseek-coder-v2-236b",
            "backup_model": "codellama-70b-instruct",
            "cooperative_level": "high",
            "capabilities": ["algorithm_optimization", "complexity_analysis", "performance_profiling", "optimization_strategies"],
            "integration_points": ["code_reviewer", "performance_tester", "memory_optimizer"]
        }),
        AgentConfig({
            "name": "Memory Management Engineer",
            "slug": "memory-management-engineer",
            "specialization": "Optimizes memory allocation, garbage collection, and resource usage for high-performance applications.",
            "tier": "primary",
            "model": "llama-3.1-70b-instruct",
            "backup_model": "mistral-nemo-instruct",
            "cooperative_level": "high",
            "capabilities": ["memory_optimization", "garbage_collection", "resource_management", "leak_detection"],
            "integration_points": ["algorithm_optimizer", "performance_profiler", "system_monitor"]
        }),
        AgentConfig({
            "name": "Code Profiling Specialist",
            "slug": "code-profiling-specialist",
            "specialization": "Uses profiling tools to identify bottlenecks and recommend optimization approaches.",
            "tier": "secondary",
            "model": "codellama-34b-instruct",
            "backup_model": "phi-3-medium-instruct",
            "cooperative_level": "medium",
            "capabilities": ["performance_analysis", "bottleneck_identification", "profiling_tools", "optimization_recommendations"],
            "integration_points": ["algorithm_optimizer", "memory_engineer", "performance_tester"]
        })
    ],
    "communication_integration_orchestrators": [
        AgentConfig({
            "name": "Service Mesh Orchestrator",
            "slug": "service-mesh-orchestrator",
            "specialization": "Manages Istio/Linkerd deployments, service discovery, and traffic routing for microservices.",
            "tier": "primary",
            "model": "llama-3.1-405b-instruct",
            "backup_model": "llama-3.1-70b-instruct",
            "cooperative_level": "critical",
            "capabilities": ["service_mesh_management", "traffic_routing", "service_discovery", "load_balancing"],
            "integration_points": ["microservices_architect", "api_gateway", "monitoring_specialist"]
        }),
        AgentConfig({
            "name": "Enterprise Message Queue Engineer",
            "slug": "enterprise-message-queue-engineer",
            "specialization": "Designs and optimizes message queues, event streaming, and routing strategies.",
            "tier": "primary",
            "model": "mixtral-8x22b-instruct",
            "backup_model": "mixtral-8x7b-instruct",
            "cooperative_level": "critical",
            "capabilities": ["message_queuing", "event_streaming", "routing_strategies", "queue_optimization"],
            "integration_points": ["service_mesh", "integration_specialist", "event_processor"]
        }),
        AgentConfig({
            "name": "Protocol Design Specialist",
            "slug": "protocol-design-specialist",
            "specialization": "Creates and standardizes communication protocols for interoperability across services.",
            "tier": "secondary",
            "model": "qwen2.5-72b-instruct",
            "backup_model": "yi-34b-chat",
            "cooperative_level": "medium",
            "capabilities": ["protocol_design", "message_formatting", "communication_standards", "interoperability"],
            "integration_points": ["service_mesh", "message_queue", "api_architect"]
        })
    ],
    "enterprise_compliance_standards": [
        AgentConfig({
            "name": "SOC2 Compliance Auditor",
            "slug": "soc2-compliance-auditor",
            "specialization": "Ensures SOC2 Type II compliance, implementing and verifying controls.",
            "tier": "primary",
            "model": "llama-3.1-405b-instruct",
            "backup_model": "qwen2.5-72b-instruct",
            "cooperative_level": "critical",
            "capabilities": ["soc2_compliance", "control_implementation", "audit_preparation", "risk_assessment"],
            "integration_points": ["security_architect", "documentation_specialist", "governance_manager"]
        }),
        AgentConfig({
            "name": "GDPR Privacy Engineer",
            "slug": "gdpr-privacy-engineer",
            "specialization": "Implements privacy-by-design principles, data protection policies, and consent mechanisms.",
            "tier": "primary",
            "model": "solar-10.7b-instruct",
            "backup_model": "phi-3.5-mini-instruct",
            "cooperative_level": "critical",
            "capabilities": ["gdpr_compliance", "privacy_design", "data_protection", "consent_management"],
            "integration_points": ["compliance_auditor", "security_architect", "data_governance"]
        }),
        AgentConfig({
            "name": "Enterprise Documentation Specialist",
            "slug": "enterprise-documentation-specialist",
            "specialization": "Creates detailed documentation for processes, technical systems, and compliance audits.",
            "tier": "secondary",
            "model": "llama-3.1-70b-instruct",
            "backup_model": "mistral-nemo-instruct",
            "cooperative_level": "high",
            "capabilities": ["technical_documentation", "process_documentation", "audit_trails", "knowledge_management"],
            "integration_points": ["compliance_auditor", "privacy_engineer", "security_architect"]
        })
    ]
}

# Directory configuration
BASE_DIR = os.getcwd() # Corrected to be the current working directory
ARCHIVE_DIR = os.path.join(BASE_DIR, "agents", "archive")
ACTIVE_DIR = os.path.join(BASE_DIR, "agents", "active")
TEMPLATES_DIR = os.path.join(BASE_DIR, "agents", "templates")
RULES_DIR = os.path.join(BASE_DIR, "agents", "rules")
ENVS_DIR = os.path.join(BASE_DIR, "agents", "envs") # Added ENVS_DIR


def ensure_directories():
    """Create necessary directory structure for agent files."""
    for directory in [
        os.path.join(BASE_DIR, "agents"), # Ensure the top-level 'agents' directory exists
        ARCHIVE_DIR, 
        ACTIVE_DIR, 
        TEMPLATES_DIR, 
        RULES_DIR, 
        ENVS_DIR # Include ENVS_DIR
    ]:
        os.makedirs(directory, exist_ok=True)


def generate_env_file(agent_slug: str, category: str) -> str:
    """Generate environment configuration file for an agent."""
    return f"""# Agent Environment Configuration
AGENT_ID={uuid.uuid4()}
AGENT_NAME={agent_slug}
AGENT_CATEGORY={category}
PRIMARY_MODEL=open_source_primary_model
BACKUP_MODEL=open_source_backup_model
WORKFLOW_FILE=./agents/workflows/{category}_workflow.json

# Enterprise Mode Settings
ENTERPRISE_MODE=true
RESOURCE_MONITORING=enabled
COMMUNICATION_PROTOCOL=enterprise_json
AUTO_CLEANUP=true
INTEGRITY_CHECK=enabled
CREW_COMPATIBLE=true
SECURITY_LEVEL=enterprise_grade
AUDIT_LOGGING=comprehensive
PERFORMANCE_TRACKING=enabled
FAILOVER_ENABLED=true
LOAD_BALANCING=intelligent
COMPLIANCE_MODE=strict
"""


def generate_rules_file(agent_name: str, category: str, specialization: str) -> str:
    """Generate rules and compliance standards file for an agent."""
    return f"""# {agent_name} - Enterprise Rules & Compliance Standards

## Agent Identity
- **Agent ID**: {uuid.uuid4()}
- **Category**: {category}
- **Specialization**: {specialization}
- **Compliance Level**: Enterprise Grade

## Core Operational Rules
### Communication Standards
- Protocol: Structured JSON messaging only
- Message Validation: Schema-based validation required
- Error Propagation: Cascading error handling with context preservation
- Status Reporting: Real-time progress updates mandatory

### Security & Compliance
- Input Sanitization: All inputs must pass security validation
- Output Encryption: Sensitive data encrypted at rest and in transit
- Compliance Standards: SOC2, ISO27001, GDPR adherence mandatory

### Performance Requirements
- Response Time: < 2 seconds for standard operations
- Availability: 99.9% uptime requirement
- Scalability: Must handle concurrent requests gracefully
- Resource Usage: Optimized memory and CPU consumption

### Error Handling
- Graceful Degradation: Continue operation with reduced functionality
- Fault Tolerance: Automatic retry mechanisms for transient failures
- Logging: Comprehensive error logging with correlation IDs
- Escalation: Automatic escalation for critical failures

### Integration Standards
- API Compatibility: RESTful and GraphQL endpoint support
- Message Queues: Kafka, RabbitMQ integration support
- Database: Multi-database compatibility (PostgreSQL, MongoDB, Redis)
- Monitoring: Prometheus metrics and distributed tracing

## Quality Assurance
- Testing Coverage: Minimum 90% code coverage
- Load Testing: Regular performance benchmarking
- Security Scanning: Automated vulnerability assessments
- Documentation: Comprehensive API and process documentation
"""


def generate_agent_json(
    agent_name: str, 
    slug: str, 
    category: str, 
    specialization: str, 
    tier: str, 
    model: str, # Added model parameter
    backup_model: str, # Added backup_model parameter
    coop_level: str, 
    capabilities: List[str], 
    integrations: List[str]
) -> Dict[str, Any]:
    """Generate complete agent configuration JSON."""
    return {
        "agent_id": str(uuid.uuid4()),
        "agent_name": slug,
        "display_name": agent_name,
        "category": category,
        "specialization": specialization,
        "tier": tier,
        "default_model": model, # Use passed model
        "backup_model": backup_model, # Use passed backup_model
        "global_system_prompt": "You are an enterprise-grade AI agent, adhering to all communication protocols and compliance standards.",
        "agent_scope": specialization,
        "specific_workflow": f"Detailed workflow for {slug} tasks with enterprise-grade error handling and monitoring.",
        "communication_rules": "Structured JSON protocols for all inter-agent communication with validation and error handling.",
        "environment_file": f"./agents/env/{slug}.env",
        "rules_file": f"./agents/rules/{slug}-rules.md",
        "interchangeable": True,
        "cooperative_level": coop_level,
        "enterprise_compliance": {
            "accuracy_standard": "99.9%",
            "communication_protocol": "structured_json",
            "error_handling": "comprehensive_with_fallback",
            "output_validation": "rigorous_multi_point_check",
            "security_level": "enterprise_grade",
            "audit_logging": "comprehensive",
            "performance_monitoring": "real_time"
        },
        "specialized_capabilities": capabilities,
        "integration_points": integrations,
        "metadata": {
            "created_at": str(uuid.uuid4()),
            "version": "1.0.0",
            "status": "active",
            "last_updated": "auto_generated"
        }
    }


def main():
    """Main function to generate all agent configurations."""
    print("Starting enterprise AI agent generation...")
    ensure_directories()
    
    starter_written = False
    total_agents: int = 0
    
    for category, agents in AGENT_CATEGORIES.items():
        print(f"Processing category: {category}")
        
        for agent in agents:
            slug: str = agent["slug"]
            print(f"  Generating agent: {slug}")
            
            # Generate agent JSON configuration
            json_data: Dict[str, Any] = generate_agent_json(
                agent["name"], 
                slug, 
                category, 
                agent["specialization"],
                agent["tier"], 
                agent["model"], # Pass model
                agent["backup_model"], # Pass backup_model
                agent["cooperative_level"],
                agent["capabilities"], 
                agent["integration_points"]
            )

            # Generate environment and rules files
            env_content = generate_env_file(slug, category)
            rules_content = generate_rules_file(agent["name"], category, agent["specialization"])

            # Determine placement (first agent goes to active, rest to archive)
            if not starter_written:
                json_path = os.path.join(ACTIVE_DIR, f"{slug}.json")
                starter_written = True
                print(f"    Placed in ACTIVE directory: {slug}")
            else:
                json_path = os.path.join(ARCHIVE_DIR, f"{slug}.json")
                print(f"    Placed in ARCHIVE directory: {slug}")

            # Write all files
            with open(json_path, "w") as f:
                json.dump(json_data, f, indent=2)

            with open(os.path.join(RULES_DIR, f"{slug}-rules.md"), "w") as f:
                f.write(rules_content)

            with open(os.path.join(ENVS_DIR, f"{slug}.env"), "w") as f:
                f.write(env_content)

            total_agents += 1

    # Create blank template agent
    print("Creating blank template agent...")
    blank_template_json: Dict[str, Any] = generate_agent_json(
        "Blank Template Agent", 
        "blank-template-agent", 
        "template",
        "Generic template for creating new agents", 
        "tertiary", 
        "ollama-model-small", # Default model for template
        "ollama-model-tiny",  # Backup model for template
        "low", 
        [], # capabilities
        []  # integration_points
    )
    
    with open(os.path.join(TEMPLATES_DIR, "blank-template-agent.json"), "w") as f:
        json.dump(blank_template_json, f, indent=2)

    print(f"\nAgent generation complete!")
    print(f"Total agents generated: {total_agents}")
    print(f"Directory structure created at: {BASE_DIR}")
    print(f"Active agents: 1")
    print(f"Archived agents: {total_agents - 1}")
    print(f"Template agents: 1")


if __name__ == "__main__":
    main()
