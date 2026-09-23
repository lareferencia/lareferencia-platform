# Authentication

**Status:** current · **Last verified:** 2026-09-23

Supersedes [`AUTENTICACION_FILE_BASED.md`](AUTENTICACION_FILE_BASED.md) (kept as a historical record of
the original basic-auth → file-based migration, in Spanish). That older document contains an outdated CLI
signature, an outdated BCrypt compatibility note and does not cover the v5 roles/OIDC modes.

## Modes

The v5 security chain is configured with:

```properties
security.api-v5.auth-mode=file    # file | oidc | hybrid  (WebSecurityConfig)
```

| Mode | Behavior |
|---|---|
| `file` (default) | HTTP Basic + form login against the file-based user store |
| `oidc` | Delegates authentication to an OpenID Connect provider |
| `hybrid` | Accepts both local file users and OIDC identities |

## File-based users

- Store: `config/users.properties` (gitignored). On first run, if the file does not exist it is
  initialized from `config/users.properties.default`.
- Passwords are **BCrypt**; `$2a$`, `$2b$` and `$2y$` prefixes are all accepted by
  `FileBasedUserDetailsService` (`org.lareferencia.backend.app`).
- The service caches users and **reloads the file automatically** when an unknown user is looked up —
  adding users does not require a restart.
- `MainApp` excludes Spring Boot's `UserDetailsServiceAutoConfiguration` to keep the custom provider.

### CLI tool

```bash
python3 lareferencia-lrharvester-app/config/add-user.py <username> <password> [ROLE_ADMIN ...]
```

Arguments are **positional** (no `-u/-p` flags). Roles are passed as trailing arguments; with none, the
user gets the default role.

## Roles and endpoints

| Role | Access |
|---|---|
| `ADMIN` | Everything |
| `VIEWER` | `GET` endpoints under `/api/v5/**` |

- Mutations under `/api/v5/**` require `ADMIN`; responses use JSON 401/403 (Problem Details style),
  no browser basic-auth challenge for API routes.
- CORS for the admin web is controlled by `security.api-v5.allowed-origins`.
- The legacy AngularJS UI serves its login form at `/legacy/login.html`.

## User management API (v5, ADMIN only)

```
GET    /api/v5/users
POST   /api/v5/users                        (JSON)
PUT    /api/v5/users/{username}/roles       (JSON)
POST   /api/v5/users/{username}/password    (JSON)
DELETE /api/v5/users/{username}
```