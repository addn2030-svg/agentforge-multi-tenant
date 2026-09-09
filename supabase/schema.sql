-- =============================================
-- AgentForge Multi-Tenant Schema + RLS
-- =============================================

-- 1. CORE TABLES
-- =============================================

-- Organizations (Root)
CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  billing_status TEXT DEFAULT 'active' CHECK (billing_status IN ('active', 'past_due', 'suspended')),
  api_quota INTEGER DEFAULT 10000,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Branches (Tenant isolation layer)
CREATE TABLE branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  timezone TEXT DEFAULT 'UTC',
  settings JSONB DEFAULT '{}'::jsonb,
  calendar_id TEXT,
  sheet_id TEXT,
  telegram_chat_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(org_id, name)
);

-- Users / Members (Role-based access)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
  email TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('org_admin', 'branch_manager', 'operator')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tasks / Operations (Agent execution records)
CREATE TABLE tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  created_by UUID REFERENCES users(id),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'success', 'failed', 'retrying', 'escalated')),
  payload JSONB NOT NULL,
  result JSONB,
  error_log JSONB,
  retry_count INTEGER DEFAULT 0,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Audit Logs (Immutable)
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id),
  action TEXT NOT NULL,
  details JSONB NOT NULL,
  token_cost INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 2. ENABLE ROW LEVEL SECURITY
-- =============================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- =============================================
-- 3. RLS POLICIES
-- =============================================

-- Organizations: users can only see their own organization
CREATE POLICY org_isolation ON organizations
  USING (id = (SELECT org_id FROM users WHERE users.id = auth.uid()));

-- Branches: org_admin sees all, others only their branch
CREATE POLICY branch_isolation ON branches
  USING (
    org_id = (SELECT org_id FROM users WHERE users.id = auth.uid())
    AND (
      (SELECT role FROM users WHERE users.id = auth.uid()) = 'org_admin'
      OR
      id = (SELECT branch_id FROM users WHERE users.id = auth.uid())
    )
  );

-- Tasks: same isolation logic
CREATE POLICY task_isolation ON tasks
  USING (
    org_id = (SELECT org_id FROM users WHERE users.id = auth.uid())
    AND (
      (SELECT role FROM users WHERE users.id = auth.uid()) = 'org_admin'
      OR
      branch_id = (SELECT branch_id FROM users WHERE users.id = auth.uid())
    )
  );

-- Audit logs: same isolation (read-only)
CREATE POLICY audit_isolation ON audit_logs
  USING (
    org_id = (SELECT org_id FROM users WHERE users.id = auth.uid())
    AND (
      (SELECT role FROM users WHERE users.id = auth.uid()) = 'org_admin'
      OR
      branch_id = (SELECT branch_id FROM users WHERE users.id = auth.uid())
    )
  );

-- =============================================
-- 4. HELPER FUNCTION (for n8n context injection)
-- =============================================

CREATE OR REPLACE FUNCTION get_current_branch_context()
RETURNS JSONB AS \[ DECLARE
  user_record RECORD;
BEGIN
  SELECT 
    u.org_id, 
    u.branch_id, 
    u.role, 
    b.settings, 
    b.calendar_id, 
    b.sheet_id,
    b.telegram_chat_id
  INTO user_record
  FROM users u
  LEFT JOIN branches b ON u.branch_id = b.id
  WHERE u.id = auth.uid();
  
  RETURN jsonb_build_object(
    'org_id', user_record.org_id,
    'branch_id', user_record.branch_id,
    'role', user_record.role,
    'settings', user_record.settings,
    'calendar_id', user_record.calendar_id,
    'sheet_id', user_record.sheet_id,
    'telegram_chat_id', user_record.telegram_chat_id
  );
END; \] LANGUAGE plpgsql SECURITY DEFINER;
