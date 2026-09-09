# AgentForge Multi-Tenant

Multi-tenant AgentForge system with:

- Supabase hierarchical multi-tenant schema (Organizations → Branches → Users) + Row Level Security
- Single n8n master pipeline that routes by `branch_id`
- Self-healing layers (Critic → Circuit Breaker → Human Escalation)
- Immutable audit logging

## Quick Start

1. Run `supabase/schema.sql` in Supabase SQL Editor
2. Import `n8n/master-pipeline.json` into n8n
3. Copy `.env.example` and fill your keys

## Architecture
