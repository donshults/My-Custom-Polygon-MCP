# PRP: Enhanced Polygon MCP Server with Authentication and Monitoring

## Overview
Enhance the existing Polygon MCP server (`/workspace/src/mcp_polygon/server.py`) with Google OAuth authentication, comprehensive monitoring, and production deployment on Railway.

## Context and Research Findings

### Current State
- **Server:** Basic FastMCP implementation in `/workspace/src/mcp_polygon/server.py` (2,059 lines)
- **Auth:** Only Polygon API key, no user authentication
- **Monitoring:** None implemented
- **Deployment:** Basic Docker setup without production features

### Reference Examples Available
The repository contains production-ready patterns in `/workspace/examples/mcp-server/`:
- **OAuth Implementation:** `src/auth/github-handler.ts` - Complete OAuth flow
- **Security:** `src/database/security.ts` - SQL injection protection patterns
- **Monitoring:** `src/index_sentry.ts` - Sentry integration
- **Tool Registration:** `src/tools/register-tools.ts` - Modular patterns

## Implementation Blueprint

### Phase 1: Google OAuth Authentication

#### Pseudocode Architecture
```python
# New file: src/mcp_polygon/auth/google_oauth.py
class GoogleOAuthHandler:
    def __init__(self):
        # Initialize with Google OAuth credentials
        # Setup session middleware
        # Configure PKCE flow
    
    async def authenticate(request):
        # Check for existing session
        # Validate JWT token
        # Return user context
    
    async def login_flow():
        # Generate state and code verifier
        # Redirect to Google OAuth
        # Handle callback
        # Issue JWT token

# Modify: src/mcp_polygon/server.py
@poly_mcp.middleware()
async def auth_middleware(request, next):
    # Extract token from request
    # Validate with GoogleOAuthHandler
    # Attach user context
    # Continue or reject
```

#### Required Libraries
```toml
# Add to pyproject.toml dependencies
google-auth-oauthlib = "^1.2.0"
authlib = "^1.3.0"
python-jose[cryptography] = "^3.3.0"
python-multipart = "^0.0.9"
```

#### Environment Variables
```env
# Google OAuth Configuration
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
GOOGLE_REDIRECT_URI=https://your-domain.railway.app/callback
JWT_SECRET_KEY=your_jwt_secret
SESSION_SECRET_KEY=your_session_secret

# Existing
POLYGON_API_KEY=your_polygon_key
```

### Phase 2: Monitoring Integration

#### Monitoring Stack Components
```python
# New file: src/mcp_polygon/monitoring/sentry_config.py
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration

def init_sentry():
    sentry_sdk.init(
        dsn=os.getenv("SENTRY_DSN"),
        integrations=[FastApiIntegration()],
        traces_sample_rate=0.1,
        profiles_sample_rate=0.1,
    )

# New file: src/mcp_polygon/monitoring/metrics.py
from prometheus_client import Counter, Histogram, generate_latest
import time

request_count = Counter('mcp_requests_total', 'Total requests', ['method', 'status'])
request_duration = Histogram('mcp_request_duration_seconds', 'Request duration')

# Add to server.py
@poly_mcp.middleware()
async def metrics_middleware(request, next):
    start_time = time.time()
    try:
        response = await next(request)
        request_count.labels(method=request.method, status='success').inc()
        return response
    except Exception as e:
        request_count.labels(method=request.method, status='error').inc()
        raise
    finally:
        request_duration.observe(time.time() - start_time)
```

#### Structured Logging
```python
# New file: src/mcp_polygon/monitoring/logging_config.py
import structlog
import logging

def configure_logging():
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            structlog.processors.JSONRenderer()
        ],
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )
```

### Phase 3: Enhanced Server Structure

#### Modular Tool Registration Pattern
```python
# New file: src/mcp_polygon/tools/auth_tools.py
def register_auth_tools(server, config):
    @server.tool()
    async def get_user_info(token: str):
        """Get authenticated user information"""
        # Validate token and return user data
        pass
    
    @server.tool()
    async def refresh_token(refresh_token: str):
        """Refresh authentication token"""
        # Refresh and return new tokens
        pass

# New file: src/mcp_polygon/tools/admin_tools.py
def register_admin_tools(server, config, user_context):
    # Only register if user has admin role
    if user_context.role == "admin":
        @server.tool()
        async def manage_api_keys():
            """Manage Polygon API keys"""
            pass
```

### Phase 4: Railway Deployment

#### Production Dockerfile
```dockerfile
# Dockerfile
FROM python:3.13-slim

WORKDIR /app

# Install UV for faster package management
RUN pip install uv

# Copy dependency files
COPY pyproject.toml .
COPY uv.lock .

# Install dependencies
RUN uv sync --frozen

# Copy application code
COPY src/ src/
COPY entrypoint.py .

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:8080/health')"

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV MCP_TRANSPORT=streamable-http
ENV PORT=8080

# Expose port
EXPOSE 8080

# Run with shell to support environment variables
CMD ["/bin/sh", "-c", "uv run python entrypoint.py --port $PORT"]
```

#### Railway Configuration
```toml
# railway.toml
[build]
builder = "DOCKERFILE"
dockerfilePath = "./Dockerfile"

[deploy]
healthcheckPath = "/health"
healthcheckTimeout = 300
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 3

[[services]]
name = "polygon-mcp-server"
```

#### Docker Compose for Local Development
```yaml
# docker-compose.yml
version: '3.8'

services:
  mcp-server:
    build: .
    ports:
      - "8080:8080"
    environment:
      - POLYGON_API_KEY=${POLYGON_API_KEY}
      - GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
      - GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
      - SENTRY_DSN=${SENTRY_DSN}
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
      - MCP_TRANSPORT=streamable-http
    volumes:
      - ./src:/app/src:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 3s
      retries: 3

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

## Implementation Tasks

### Task 1: Setup Authentication Foundation
1. Create `src/mcp_polygon/auth/` directory structure
2. Implement `google_oauth.py` with OAuth flow
3. Add JWT token generation and validation
4. Create session management middleware
5. Add authentication middleware to server.py

### Task 2: Implement Monitoring
1. Create `src/mcp_polygon/monitoring/` directory
2. Setup Sentry integration
3. Add Prometheus metrics collection
4. Configure structured logging
5. Create `/metrics` and `/health` endpoints

### Task 3: Enhance Server Architecture
1. Refactor tools into modular registration pattern
2. Add role-based access control
3. Implement rate limiting middleware
4. Add request validation and sanitization

### Task 4: Configure Railway Deployment
1. Update Dockerfile for production
2. Create railway.toml configuration
3. Setup environment variables in Railway
4. Configure custom domain
5. Setup monitoring dashboards

### Task 5: Testing and Validation
1. Write unit tests for auth flow
2. Test monitoring integrations
3. Load test the server
4. Verify Railway deployment
5. Test failover and recovery

## File Structure After Implementation
```
/workspace/
├── src/mcp_polygon/
│   ├── __init__.py
│   ├── server.py (modified)
│   ├── auth/
│   │   ├── __init__.py
│   │   ├── google_oauth.py
│   │   ├── jwt_handler.py
│   │   └── middleware.py
│   ├── monitoring/
│   │   ├── __init__.py
│   │   ├── sentry_config.py
│   │   ├── metrics.py
│   │   └── logging_config.py
│   ├── tools/
│   │   ├── __init__.py
│   │   ├── auth_tools.py
│   │   ├── admin_tools.py
│   │   └── polygon_tools.py (refactored from server.py)
│   └── config/
│       ├── __init__.py
│       └── settings.py
├── tests/
│   ├── test_auth.py
│   ├── test_monitoring.py
│   └── test_tools.py
├── Dockerfile (updated)
├── docker-compose.yml (new)
├── railway.toml (new)
├── prometheus.yml (new)
└── pyproject.toml (updated)
```

## Validation Gates

### Authentication Validation
```bash
# Test OAuth flow
curl -X GET http://localhost:8080/auth/login
# Should redirect to Google OAuth

# Test token validation
curl -H "Authorization: Bearer <token>" http://localhost:8080/api/user
# Should return user info or 401

# Test protected endpoints
curl -H "Authorization: Bearer <token>" http://localhost:8080/tools/list
# Should return tool list or 401
```

### Monitoring Validation
```bash
# Check health endpoint
curl http://localhost:8080/health
# Should return {"status": "healthy"}

# Check metrics endpoint
curl http://localhost:8080/metrics
# Should return Prometheus metrics

# Test Sentry error capture
curl -X POST http://localhost:8080/test-error
# Should appear in Sentry dashboard
```

### Deployment Validation
```bash
# Build Docker image
docker build -t polygon-mcp:latest .

# Run locally with docker-compose
docker-compose up

# Deploy to Railway
railway up

# Test production endpoint
curl https://your-app.railway.app/health
```

### Code Quality Gates
```bash
# Lint and format
uv run ruff format src/ tests/
uv run ruff check --fix src/ tests/

# Type checking
uv run mypy src/

# Run all tests
uv run pytest tests/ -v --cov=src --cov-report=html

# Security scan
uv run bandit -r src/
```

## External Documentation References

### Google OAuth Setup
- Google Cloud Console: https://console.cloud.google.com/
- OAuth 2.0 Guide: https://developers.google.com/identity/protocols/oauth2
- Python Library: https://google-auth-oauthlib.readthedocs.io/en/latest/

### Monitoring Resources
- Sentry Python: https://docs.sentry.io/platforms/python/
- Prometheus Python Client: https://github.com/prometheus/client_python
- Grafana Dashboard Examples: https://grafana.com/grafana/dashboards/

### Railway Deployment
- Railway Docs: https://docs.railway.com/
- Environment Variables: https://docs.railway.com/guides/variables
- Docker Deployment: https://docs.railway.com/deploy/deployments

### FastMCP Documentation
- FastMCP 2.0: https://gofastmcp.com/getting-started/welcome
- OAuth with FastMCP: https://github.com/peterlarnholt/fastmcp-oauth

## Common Pitfalls to Avoid

1. **OAuth State Management**: Always use PKCE flow for security
2. **Token Storage**: Never store tokens in cookies without encryption
3. **Rate Limiting**: Implement per-user and per-IP limits
4. **Error Exposure**: Sanitize error messages before sending to clients
5. **Secret Management**: Use Railway's secret management, never hardcode
6. **CORS Configuration**: Properly configure for your frontend domain
7. **Session Timeout**: Implement proper session expiry and refresh
8. **Monitoring Overhead**: Balance between observability and performance

## Success Criteria

- [ ] Users can authenticate via Google OAuth
- [ ] All API endpoints are protected with JWT validation
- [ ] Sentry captures and reports errors with context
- [ ] Prometheus metrics are collected and viewable in Grafana
- [ ] Server deploys successfully on Railway
- [ ] Health checks pass in production
- [ ] Load testing shows <100ms p95 latency
- [ ] All tests pass with >80% coverage

## Confidence Score: 8/10

This PRP provides comprehensive context for implementing authentication, monitoring, and deployment. The score reflects:
- **Strengths**: Clear architecture, extensive examples, validation gates
- **Considerations**: Integration complexity between components, Railway-specific configurations may need adjustment
- **Mitigation**: Phased implementation approach, extensive testing gates

The implementation should succeed in one pass with iterative refinement for optimization.