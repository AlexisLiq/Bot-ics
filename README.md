# Bot ICS (Node.js + Playwright)

Base para automatizar:

1. Login en `iCSAuth`
2. Acceso a `ICSLight` reutilizando sesion
3. Descarga y ejecucion de JNLP
4. Flujo en ICS (`Gestion -> Gestionar`)

## Uso

```powershell
npm install
npm run pw:install
npm run login
npm run run-ICS
```

`.env` solo necesita:

- `ICS_LOGIN_URL`
- `ICS_TARGET_URL`
- `ICS_USERNAME`
- `ICS_PASSWORD`
- `ICS_DB_CONNECTION_STRING`

El resto de valores tecnicos (selectores, launcher, deteccion y timeouts) vive en `src/config`.

Para generar solo el JSON de expedientes desde SQL:

```powershell
npm run db:expedientes-json -- --fecha=2026-03-01 --demandante="MI BANCO"
```

Si no pasas parametros en `db:expedientes-json`, usa defaults:
- `fecha`: hoy (YYYY-MM-DD)
- `demandante`: `MI BANCO`

Para pasar fecha/demandante al `run-ICS`:

```powershell
npm run run-ICS -- --fecha=2026-03-01 --demandante="MI BANCO"
```

Si no pasas parametros en `run-ICS`, usa defaults:
- `fecha`: hoy (YYYY-MM-DD)
- `demandante`: `MI BANCO`

## Flujo run-ICS

1. Descarga JNLP
2. Ejecuta JNLP
3. Espera inicio estable del cliente
4. Carga expedientes/cedulas desde SQL Server
5. Itera expedientes
6. `Cedula -> Buscar -> Legal`
7. Post-busqueda:
   - si hay modal de error: cerrar y continuar
   - si no hay modal: validar/crear `Ejecutivo Singular`
8. `Archivo -> Salir` por iteracion
9. Cierra app ICS al terminar lote

## SQL y JSON en carpeta database

- Query batch adoptada: `src/database/sql/expedientes-routeB.sql`
- Repositorio SQL: `src/database/expedientes-repository.js`
- Store JSON: `src/database/expedientes-json-store.js`
- JSON generado: `src/database/json/expedientes.json`

El JSON usa por expediente:

- `demandado1Documento` (cedula)
- `actuaciones` (array)

## Variables DB

- Conexion:
  - `ICS_DB_CONNECTION_STRING`
- Query:
  - `ICS_DB_QUERY_FILE_PATH`
- Parametros:
  - opcionales por CLI: `--fecha=YYYY-MM-DD --demandante="..."`
  - defaults: `fecha=hoy`, `demandante=MI BANCO`
- Path del snapshot JSON:
  - `ICS_EXPEDIENTES_JSON_PATH`
