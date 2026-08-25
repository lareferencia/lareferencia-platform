# API v5 Issues and Fixes

## 1. Viewer user returned `403 FORBIDDEN`

**Problem:** API v5 read endpoints require `ROLE_VIEWER` or `ROLE_ADMIN`, but the `viewer` user was configured with `ROLE_USER`.

```properties
viewer=...,ROLE_USER
```

**Fix:** Changed the `viewer` user to use `ROLE_VIEWER`.

```properties
viewer=...,ROLE_VIEWER
```

The user creation tools were also updated to support `ROLE_VIEWER`.

## 2. OpenAPI endpoint returned `NoSuchMethodError`

**Problem:** `/api/v5/openapi` failed with:

```text
NoSuchMethodError: io.swagger.v3.oas.annotations.media.Schema.types()
```

The runtime classpath had incompatible Swagger dependencies. `springdoc-openapi` used `swagger-core-jakarta 2.2.29`, but older Swagger annotation libraries were also being packaged.

**Fix:** Aligned the Swagger Jakarta dependencies to version `2.2.29` in the parent dependency management.

```text
swagger-core-jakarta 2.2.29
swagger-models-jakarta 2.2.29
swagger-annotations-jakarta 2.2.29
```

## 3. `bash build.sh ibict` reintroduced old Swagger libraries

**Problem:** The `ibict` profile adds `lareferencia-entity-lib`, which brought `springfox-swagger2` transitively. Springfox added old Swagger libraries such as `swagger-annotations 2.1.2`, causing the same `NoSuchMethodError`.

**Fix:** Excluded `springfox-swagger2` from the `lareferencia-entity-lib` dependency in the `lareferencia-lrharvester-app` profiles.

This prevents old Springfox/Swagger libraries from being packaged into `harvester.jar`.

## 4. Swagger UI loaded but failed internally

**Problem:** `/api/v5/docs` redirected to Swagger UI, but the UI failed because it also requested:

```text
/api/v5/openapi/swagger-config
```

That path was not public and returned `401 UNAUTHORIZED`.

**Fix:** Updated API v5 security rules to allow the OpenAPI and Swagger UI paths:

```text
/api/v5/openapi
/api/v5/openapi/**
/api/v5/docs
/api/v5/docs/**
/api/v5/swagger-ui/**
```

## Verification

Build with the IBICT profile:

```bash
bash build.sh ibict
```

Check that `harvester.jar` does not include old Springfox or Swagger libraries:

```bash
jar tf lareferencia-lrharvester-app/harvester.jar | grep -E 'springfox|swagger-annotations|swagger-core|swagger-models'
```

Expected result:

```text
BOOT-INF/lib/swagger-core-jakarta-2.2.29.jar
BOOT-INF/lib/swagger-models-jakarta-2.2.29.jar
BOOT-INF/lib/swagger-annotations-jakarta-2.2.29.jar
```

After restarting the application, both endpoints should work:

```text
http://localhost:8090/api/v5/openapi
http://localhost:8090/api/v5/docs
```
