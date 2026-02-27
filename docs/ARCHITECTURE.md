# Architecture — IT-Stack JITSI

## Overview

Jitsi provides self-hosted video conferencing, replacing Zoom/Teams meetings with OIDC authentication via Keycloak.

## Role in IT-Stack

- **Category:** collaboration
- **Phase:** 2
- **Server:** lab-app1 (10.0.50.13)
- **Ports:** 443 (HTTPS), 10000/udp (Media)

## Dependencies

| Dependency | Type | Required For |
|-----------|------|--------------|
| FreeIPA | Identity | User directory |
| Keycloak | SSO | Authentication |
| PostgreSQL | Database | Data persistence |
| Redis | Cache | Sessions/queues |
| Traefik | Proxy | HTTPS routing |

## Data Flow

```
User → Traefik (HTTPS) → jitsi → PostgreSQL (data)
                       ↗ Keycloak (auth)
                       ↗ Redis (sessions)
```

## Security

- All traffic over TLS via Traefik
- Authentication delegated to Keycloak OIDC
- Database credentials via Ansible Vault
- Logs shipped to Graylog
