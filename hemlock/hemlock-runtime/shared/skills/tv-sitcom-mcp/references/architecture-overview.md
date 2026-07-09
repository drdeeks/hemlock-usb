# TV Sitcom MCP — Architecture Overview

## System Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL COMPANY                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  MCP Client │  │  MCP Client │  │  MCP Client │             │
│  │ (Dashboard) │  │  (Alerting) │  │ (Analytics) │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          ▼                                        │
│              ┌─────────────────────────┐                         │
│              │      MCP Transport      │                         │
│              │  (HTTP / WebSocket)     │                         │
│              └───────────┬─────────────┘                         │
└──────────────────────────┼──────────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────────┐
│                    TV MCP SERVER                                 │
│                          ▼                                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    MCP Handler                          │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐          │    │
│  │  │  Rooms    │  │   Feed    │  │  Status   │          │    │
│  │  │  API      │  │   API     │  │  API      │          │    │
│  │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘          │    │
│  │        │              │              │                  │    │
│  │        └──────────────┼──────────────┘                  │    │
│  │                       ▼                                  │    │
│  │              ┌─────────────────┐                        │    │
│  │              │   Data Store    │                        │    │
│  │              │  (SQLite/JSON)  │                        │    │
│  │              └─────────────────┘                        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 Federation Gateway                      │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐          │    │
│  │  │  Agent    │  │   Room    │  │  Project  │          │    │
│  │  │ Registry  │  │ Manager   │  │ Manager   │          │    │
│  │  └───────────┘  └───────────┘  └───────────┘          │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────────┐
│                    HERMES AGENTS                                 │
│                          ▼                                        │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐   │
│  │  Agent 1  │  │  Agent 2  │  │  Agent 3  │  │  Agent N  │   │
│  │ (Writer)  │  │ (Director)│  │ (Producer)│  │ (Host)    │   │
│  └───────────┘  └───────────┘  └───────────┘  └───────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

## Component Descriptions

### 1. MCP Client Layer

External companies connect via standard MCP clients:

- **Dashboard Client**: Real-time monitoring of agent activity
- **Alerting Client**: Notifications for specific events
- **Analytics Client**: Data collection for analysis

### 2. MCP Transport Layer

Handles communication between clients and server:

- **HTTP**: RESTful API for request/response
- **WebSocket**: Real-time bidirectional communication
- **Authentication**: Bearer token validation

### 3. TV MCP Server

Core server handling all MCP requests:

- **Rooms API**: Manages TV rooms and their status
- **Feed API**: Provides real-time agent activity feed
- **Status API**: Reports system health and metrics
- **Data Store**: Persists room and feed data

### 4. Federation Gateway

Connects to the Hermes agent ecosystem:

- **Agent Registry**: Tracks all registered agents
- **Room Manager**: Creates and manages TV rooms
- **Project Manager**: Coordinates multi-agent projects

### 5. Hermes Agents

The actual agents generating content:

- **Writers**: Create scripts and content
- **Directors**: Manage production flow
- **Producers**: Coordinate resources
- **Hosts**: Present and moderate

## Data Flow

1. **Client Request**: External company sends MCP request
2. **Transport**: Request routed through HTTP/WebSocket
3. **Authentication**: Token validated
4. **API Handler**: Request processed by appropriate API
5. **Data Store**: Data retrieved or stored
6. **Response**: Result returned to client
7. **Feed Update**: Real-time updates pushed to connected clients

## Scalability

### Horizontal Scaling

- Multiple MCP server instances behind load balancer
- Shared data store for consistency
- Stateless request handling

### Vertical Scaling

- Increase worker processes
- Optimize database queries
- Cache frequently accessed data

## Security

### Authentication

- Bearer token validation
- Token rotation support
- Rate limiting per token

### Authorization

- Role-based access control
- Endpoint-level permissions
- Audit logging

### Data Protection

- Encryption in transit (TLS)
- Encryption at rest (optional)
- Secure token storage