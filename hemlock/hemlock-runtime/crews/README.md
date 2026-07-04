# Autonomous Crew Skill

## Overview

The Autonomous Crew Skill enables fully autonomous multi-agent collaboration for complex projects. A lead agent creates a blueprint, specialized agents work in coordinated loops, and the system continues until success criteria are met.

## Key Features

### 🤖 **Autonomous Operation**
- No human input required during execution
- Agents solve problems autonomously
- Web search when stuck
- Continuous until success criteria met

### 👥 **Specialized Agents**
- **Lead Agent**: Blueprint creation, coordination
- **UI Specialist**: User interface, experience
- **Integration Architect**: System interconnectedness
- **Blockchain & Security**: Security, encryption
- **Debugger**: Issue identification, fixes
- **Documentation Specialist**: Comprehensive docs
- **Optimization Expert**: Performance, efficiency
- **Organizational Architect**: Structure, workflow
- **Validation Expert**: Testing, quality assurance

### 🔄 **Workflow Phases**
1. **Planning**: Blueprint creation, success criteria
2. **Confirmation**: Blueprint solidifying, protocols
3. **Acting**: Autonomous execution loop
4. **Validation**: End-to-end testing, review

### 🛡️ **Safety Features**
- Sandboxed execution
- Checkpoint system
- Rollback capability
- Git integration
- Detailed logging

## Quick Start

### 1. Initialize Crew
```bash
/crew init my-project ui,debugger,documentation
```

### 2. Check Status
```bash
/crew status my-project
```

### 3. Run Workflow
```bash
/crew run my-project
```

### 4. Monitor Progress
```bash
/crew logs my-project
/crew agents my-project
```

## Telegram Commands

### Setup Commands
```
/crew init <project> [agents]    - Initialize new crew
/crew help                       - Show all commands
```

### Status Commands
```
/crew status [project]           - Show crew status
/crew agents [project]           - List active agents
/crew blueprint [project]        - Show project blueprint
/crew logs [project] [agent]     - Show agent logs
```

### Action Commands
```
/crew run [project]              - Start autonomous workflow
/crew checkpoint [project]       - Create checkpoint
/crew rollback [project] <id>    - Rollback to checkpoint
```

## Agent Types

### 1. Lead Agent
- Creates project blueprint
- Coordinates all agents
- Monitors progress
- Validates results
- Creates checkpoints

### 2. UI Specialist
- User interface design
- User experience optimization
- Component implementation
- UI testing

### 3. Integration Architect
- System architecture design
- Data flow optimization
- API integration
- Performance monitoring

### 4. Blockchain & Security
- Security implementation
- Encryption management
- Blockchain integration
- Vulnerability assessment

### 5. Debugger
- Issue identification
- Root cause analysis
- Fix implementation
- Regression testing

### 6. Documentation Specialist
- Documentation creation
- API documentation
- User guides
- Code documentation

### 7. Optimization Expert
- Performance analysis
- Bottleneck identification
- Code optimization
- Resource management

### 8. Organizational Architect
- Project structure design
- Workflow optimization
- Resource allocation
- Process improvement

### 9. Validation Expert
- Test plan creation
- Test implementation
- Quality assurance
- Acceptance testing

## Workflow Engine

### Phase 1: Planning
- Lead agent creates comprehensive blueprint
- Define success criteria
- Identify required agent types
- Create workflow plan

### Phase 2: Confirmation
- Review and validate blueprint
- Finalize agent assignments
- Establish communication protocols
- Set up checkpoints

### Phase 3: Acting (Autonomous Loop)
- 1-2 agents work at a time
- Mandatory agent communication
- Continuous progress until success
- Autonomous problem-solving

### Phase 4: Validation
- End-to-end testing
- Documentation review
- Blueprint vs actual comparison
- Changelog validation

## Communication Protocols

### Agent Communication
1. **Shared Changelog**: All changes documented
2. **Agent-to-Agent Messages**: Direct communication
3. **Blueprint Updates**: Shared project understanding
4. **Checkpoint Sync**: State synchronization

### Communication Rules
- **Mandatory**: Agents must communicate
- **Regular**: Daily sync between working agents
- **Immediate**: Blockage alerts immediately
- **Comprehensive**: Share solutions with all

## Git Integration

### Commit Rules
- **Commit After Every Change**: Automatic commits
- **Detailed Commit Messages**: Agent, action, description
- **Branch Management**: Feature branches per agent
- **Merge Protocols**: Coordinated merges

### Commit Format
```
[agent-id] Action: Description

Agent: agent-id
Timestamp: ISO timestamp
Files Modified:
- file1.py
- file2.py
```

## Checkpoint System

### When to Checkpoint
- Before risky operations
- Every 5 iterations
- Major milestones
- Before rollback

### Checkpoint Contents
- Complete project state
- Metadata (phase, agents, timestamp)
- Git state (commit history)
- Agent logs (current progress)

## Agent Logging

### agent.json Format
```json
{
  "agent_id": "ui-specialist-1",
  "agent_type": "ui",
  "workflow": ["task1", "task2", "task3"],
  "actions": [
    {
      "timestamp": "2026-04-10T18:00:00",
      "action": "Created component",
      "tool_used": "file_write",
      "result": "success",
      "details": "Created Button component"
    }
  ],
  "summary": {
    "total_actions": 15,
    "successful": 14,
    "failed": 1,
    "obstacles": ["API rate limit"],
    "solutions": ["Implemented retry logic"]
  }
}
```

## Best Practices

### Planning
1. **Clear Objectives**: Define clear goals
2. **Measurable Criteria**: Use measurable success criteria
3. **Realistic Timeline**: Set realistic deadlines
4. **Resource Allocation**: Properly allocate resources

### Execution
1. **Focused Work**: Concentrate on assigned tasks
2. **Regular Updates**: Provide regular updates
3. **Collaboration**: Work well with others
4. **Adaptability**: Adapt to changes

### Communication
1. **Clear Communication**: Be clear and concise
2. **Regular Updates**: Update frequently
3. **Active Listening**: Listen to others
4. **Constructive Feedback**: Provide helpful feedback

### Problem-Solving
1. **Systematic Approach**: Use systematic methods
2. **Creative Thinking**: Think creatively
3. **Persistence**: Don't give up easily
4. **Learning**: Learn from mistakes

## Rules & Enforcement

### Core Rules
1. **Autonomous Operation**: No human input required
2. **Mandatory Communication**: Agents must communicate
3. **Checkpoint Discipline**: Regular checkpoints
4. **Git Discipline**: Commit after every change

### Enforcement
1. **Lead Agent**: Enforces rules
2. **Peer Review**: Agents review each other
3. **Automated Checks**: Automated validation
4. **Documentation**: Rules documented

## Example Workflow

### 1. Project Initialization
```bash
# Initialize crew with specific agents
/crew init e-commerce-platform ui,integration,blockchain,debugger,documentation,validation
```

### 2. Blueprint Review
```bash
# View the created blueprint
/crew blueprint e-commerce-platform
```

### 3. Start Autonomous Workflow
```bash
# Begin autonomous execution
/crew run e-commerce-platform
```

### 4. Monitor Progress
```bash
# Check status
/crew status e-commerce-platform

# View agent logs
/crew logs e-commerce-platform

# List agents
/crew agents e-commerce-platform
```

### 5. Create Checkpoint
```bash
# Create manual checkpoint
/crew checkpoint e-commerce-platform
```

### 6. Rollback if Needed
```bash
# Rollback to checkpoint
/crew rollback e-commerce-platform abc123
```

## Success Criteria

### Project Success
1. **All Tests Pass**: 100% test success
2. **Documentation Complete**: All docs written
3. **Code Quality**: Meets quality standards
4. **Performance**: Meets performance goals

### Agent Success
1. **Tasks Completed**: All assigned tasks done
2. **Communication**: Regular communication
3. **Problem-Solving**: Autonomous resolution
4. **Documentation**: Proper documentation

### Crew Success
1. **Collaboration**: Effective teamwork
2. **Efficiency**: Optimized workflow
3. **Quality**: High-quality output
4. **Timeliness**: Completed on time

## Troubleshooting

### Common Issues
1. **Agent Stuck**: Check logs, enable web search
2. **Communication Failure**: Verify protocols
3. **Checkpoint Issues**: Check disk space
4. **Git Problems**: Verify git configuration

### Solutions
1. **Review Logs**: Check agent.json logs
2. **Verify Communication**: Test protocols
3. **Check Disk Space**: Ensure sufficient space
4. **Verify Git**: Check git configuration

## Support

For issues or questions:
1. Check agent.json logs
2. Review changelog
3. Examine checkpoints
4. Consult blueprint

## License

Part of Hermes Agent System
