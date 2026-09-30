INSERT INTO subscription_plans (id, name, slug, max_products, created_at, updated_at)
SELECT 1, 'Local Dev', 'local-dev', 1000, NOW(), NOW()
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM subscription_plans WHERE id = 1);

INSERT INTO tenants (id, uuid, name, subdomain, subscription_plan_id, created_at, updated_at)
SELECT 1, UUID(), 'Local Tenant', 'local', 1, NOW(), NOW()
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM tenants WHERE id = 1);

INSERT INTO stores (id, tenant_id, phone, verification_status, status, created_at, updated_at)
SELECT 18, 1, '9800000018', 'verified', 'active', NOW(), NOW()
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM stores WHERE id = 18);

INSERT INTO store_profiles (store_id, tenant_id, name, slug, created_at, updated_at)
SELECT 18, 1, 'Eg Looks', 'eg-looks', NOW(), NOW()
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM store_profiles WHERE store_id = 18);
