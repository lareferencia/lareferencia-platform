# Sistema de Autenticación Basado en Archivos

## Descripción General

Se implementó un nuevo sistema de autenticación para reemplazar el sistema básico de autenticación HTTP (basic-auth). El nuevo sistema es más flexible y seguro, permitiendo:

- **Autenticación dual**: Soporta tanto Form Login (formulario web) como HTTP Basic Auth
- **Usuarios en archivo**: Los usuarios se almacenan en un archivo de texto con contraseñas encriptadas con BCrypt
- **Recarga automática**: Si un usuario no se encuentra en caché, el sistema recarga automáticamente el archivo de usuarios
- **Protección por roles**: Todos los endpoints requieren el rol `ADMIN`

## Archivos Creados

### 1. `FileBasedUserDetailsService.java`
**Ubicación**: `lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/app/FileBasedUserDetailsService.java`

Servicio de Spring Security que implementa `UserDetailsService`. Características:
- Carga usuarios desde `config/users.properties`
- Mantiene caché en memoria para rendimiento
- Recarga automática del archivo cuando un usuario no se encuentra
- Devuelve una **copia** del usuario en cache para evitar que Spring Security corrompa las credenciales almacenadas

```java
// Punto clave: devolver copia, no referencia del cache
return User.withUserDetails(cachedUser).build();
```

### 2. `users.properties`
**Ubicación**: `lareferencia-lrharvester-app/config/users.properties`

Archivo de usuarios con formato:
```properties
# Formato: usuario=hash_bcrypt,ROL1,ROL2
admin=$2a$10$4y1zPBq1Sab.k62WLj7QNudiifOuJq/Da27oIT1S7SgPwdvheGw5W,ROLE_ADMIN
```

**Usuario por defecto**: `admin` / `admin`

> ⚠️ **IMPORTANTE**: Los hashes BCrypt deben usar el prefijo `$2a$` (no `$2b$`) para compatibilidad con Java.

### 3. `add-user.py`
**Ubicación**: `lareferencia-lrharvester-app/config/add-user.py`

Script Python para agregar usuarios al archivo. Soporta modo interactivo y línea de comandos.

**Uso interactivo**:
```bash
python add-user.py
```

**Uso por línea de comandos**:
```bash
python add-user.py -u usuario -p contraseña -r ROLE_ADMIN
```

**Requisitos**:
```bash
pip install bcrypt
```

### 4. `login.html`
**Ubicación**: `lareferencia-lrharvester-app/src/main/resources/templates/login.html`

Página de login con formulario HTML usando Thymeleaf.

## Archivos Modificados

### 1. `WebSecurityConfig.java`
**Ubicación**: `lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/app/WebSecurityConfig.java`

Configuración de Spring Security modificada para:
- Usar `DaoAuthenticationProvider` con `FileBasedUserDetailsService`
- Configurar autenticación dual (Form + Basic)
- Requerir rol `ADMIN` para todos los endpoints excepto login y recursos estáticos
- Configurar logout con redirección a login

### 2. `MainApp.java`
**Ubicación**: `lareferencia-lrharvester-app/src/main/java/org/lareferencia/backend/app/MainApp.java`

Se agregó exclusión de `UserDetailsServiceAutoConfiguration` para evitar que Spring Boot cree un usuario por defecto en memoria:

```java
@EnableAutoConfiguration(exclude = {
    UserDetailsServiceAutoConfiguration.class,
    ElasticsearchDataAutoConfiguration.class
})
```

### 3. `04-security.properties`
**Ubicación**: `lareferencia-lrharvester-app/config/04-security.properties`

Se agregó la propiedad para configurar la ubicación del archivo de usuarios:
```properties
security.users.file=config/users.properties
```

## Configuración

### Propiedades de Configuración

| Propiedad | Descripción | Valor por defecto |
|-----------|-------------|-------------------|
| `security.users.file` | Ruta al archivo de usuarios | `config/users.properties` |

### Formato del Archivo de Usuarios

```properties
# Comentarios empiezan con #
# Formato: username=bcrypt_hash,ROLE1,ROLE2,...
admin=$2a$10$hash...,ROLE_ADMIN
user=$2a$10$hash...,ROLE_USER,ROLE_VIEWER
```

## Notas Técnicas Importantes

### Compatibilidad BCrypt

Java `BCryptPasswordEncoder` solo soporta hashes con prefijo `$2a$`. El prefijo `$2b$` (usado por implementaciones más modernas) **no es compatible**.

El script `add-user.py` genera hashes compatibles usando:
```python
bcrypt.gensalt(rounds=10, prefix=b'2a')
```

### Problema de Borrado de Contraseñas

Spring Security borra la contraseña del objeto `UserDetails` después de una autenticación exitosa por seguridad. Esto corrompía el caché de usuarios.

**Solución**: Devolver una copia del usuario en lugar de la referencia del caché:
```java
// INCORRECTO - Spring borra la contraseña del objeto en caché
return cachedUser;

// CORRECTO - Devolver copia
return User.withUserDetails(cachedUser).build();
```

### Recarga Automática de Usuarios

El servicio implementa recarga automática del archivo de usuarios:
1. Si el usuario existe en caché → retorna copia del caché
2. Si no existe → recarga el archivo desde disco
3. Si sigue sin existir → lanza `UsernameNotFoundException`

Esto permite agregar usuarios sin reiniciar la aplicación.

## Endpoints Protegidos

| Endpoint | Acceso |
|----------|--------|
| `/login` | Público |
| `/css/**`, `/js/**`, `/images/**` | Público (recursos estáticos) |
| Todos los demás | Requiere `ROLE_ADMIN` |

## Flujo de Autenticación

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐
│   Cliente   │────▶│  Form Login  │────▶│ FileBasedUserDetails│
│             │     │  o Basic Auth│     │      Service        │
└─────────────┘     └──────────────┘     └──────────┬──────────┘
                                                     │
                                                     ▼
                                          ┌─────────────────────┐
                                          │  users.properties   │
                                          │  (config/)          │
                                          └─────────────────────┘
```

## Agregar Nuevos Usuarios

### Método 1: Script Python (Recomendado)
```bash
cd lareferencia-lrharvester-app/config
python add-user.py -u nuevo_admin -p mi_password -r ROLE_ADMIN
```

### Método 2: Manual
1. Generar hash BCrypt con prefijo `$2a$`
2. Agregar línea al archivo `users.properties`:
   ```
   nuevo_usuario=$2a$10$hash...,ROLE_ADMIN
   ```
3. El usuario estará disponible inmediatamente (recarga automática)

## Logout

Acceder a `/logout` cierra la sesión y redirige a `/login?logout`.

---

*Documento creado: Diciembre 2025*
