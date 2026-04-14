-- Insert sample tenants
INSERT INTO tenants (id, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'tenant-a'),
    ('22222222-2222-2222-2222-222222222222', 'tenant-b'),
    ('33333333-3333-3333-3333-333333333333', 'tenant-c')
ON CONFLICT (id) DO NOTHING;

-- Insert sample documents for tenant-a
INSERT INTO documents (tenant_id, title, content) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Document A1', 'Content for tenant A document 1'),
    ('11111111-1111-1111-1111-111111111111', 'Document A2', 'Content for tenant A document 2')
ON CONFLICT (id) DO NOTHING;

-- Insert sample documents for tenant-b
INSERT INTO documents (tenant_id, title, content) VALUES
    ('22222222-2222-2222-2222-222222222222', 'Document B1', 'Content for tenant B document 1'),
    ('22222222-2222-2222-2222-222222222222', 'Document B2', 'Content for tenant B document 2')
ON CONFLICT (id) DO NOTHING;

-- Insert sample workflows
INSERT INTO workflows (namespace, workflow_id, run_id, status) VALUES
    ('namespace-1', 'workflow-1', 'run-1', 'RUNNING'),
    ('namespace-1', 'workflow-2', 'run-2', 'COMPLETED'),
    ('namespace-2', 'workflow-3', 'run-3', 'FAILED')
ON CONFLICT (namespace, workflow_id, run_id) DO NOTHING;
