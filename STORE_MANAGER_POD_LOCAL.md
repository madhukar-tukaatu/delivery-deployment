# Local Store Manager (doorstep POD payment-session)

Express staff online POD creates sessions via Store Manager (`tukaatu-api`), not HamroPay.

## Local Docker path (preferred)

1. Store Manager source must exist at `../../Tukaatu-main/tukaatu-api` (sibling of `delivery/`).
2. `docker compose -f docker-compose.local.yml up -d store-manager` (builds `Dockerfile.store-manager.local`).
3. First-time DB setup:
   - MySQL DB `tukaatu_sm` (created automatically if you run the seed steps below)
   - Inside container: `php artisan key:generate --force && php artisan migrate --force`
   - Seed STORE-00018: `docker exec -i delivery-local-mysql mysql -uroot -proot_password tukaatu_sm < store-manager-seed-local.sql`
4. Express env (`delivery-deployment/.env.local`):
   - `STORE_MANAGER_PAYMENT_BASE_URL=http://store-manager:8000`
   - Shared secret must match SM `TUKAATU_EXPRESS_PAYMENT_INTEGRATION_SECRET`
5. Recreate backend after env changes: `docker compose -f docker-compose.local.yml up -d backend-app`

### Why not localhost?

`localhost` / `127.0.0.1` inside `delivery-local-backend-app` is the container itself.
Use the compose service name `store-manager` on the `delivery-local` network.
`host.docker.internal:8000` only works if SM is published on the Windows/Mac host port 8000.

## Production

Set:
```
STORE_MANAGER_PAYMENT_BASE_URL=https://tukaatu.com
STORE_MANAGER_PAYMENT_INTEGRATION_ID=tukaatu-express
STORE_MANAGER_PAYMENT_INTEGRATION_SECRET=<same as marketplace TUKAATU_EXPRESS_PAYMENT_INTEGRATION_SECRET>
```
Deploy the POD integration routes on marketplace (`/api/v1/integrations/tukaatu-express/pod-payment-sessions`) before pointing prod Express at them.

## Retest

Staff FE: delivery out_for_delivery + POD online -> payment-session should return QR.
Or: `POST /api/v1/staff/deliveries/{id}/payment-session` with `{}` + staff auth.
