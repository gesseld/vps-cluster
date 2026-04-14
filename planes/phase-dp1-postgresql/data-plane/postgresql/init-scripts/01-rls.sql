-- Enable pgcrypto extension for UUID generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create tenants table
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create documents table with RLS
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    content TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create workflows table with RLS
CREATE TABLE IF NOT EXISTS workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace VARCHAR(255) NOT NULL,
    workflow_id VARCHAR(500) NOT NULL,
    run_id VARCHAR(500) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(namespace, workflow_id, run_id)
);

-- Enable Row-Level Security
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY documents_tenant_isolation ON documents
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY workflows_namespace_isolation ON workflows
    USING (namespace = current_setting('app.current_namespace'));

-- Create indexes
CREATE INDEX idx_documents_tenant_id ON documents(tenant_id);
CREATE INDEX idx_workflows_namespace ON workflows(namespace);
CREATE INDEX idx_workflows_status ON workflows(status);
