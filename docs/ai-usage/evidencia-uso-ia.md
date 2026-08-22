# Evidencia de uso de IA

Registro honesto de cómo se ha usado IA generativa en este proyecto: qué
produjo, qué decisiones tuvo que tomar, qué se verificó y qué quedó fuera.

| | |
|---|---|
| **Herramienta** | Claude Code (CLI), modelo Opus 5 |
| **Fase** | 1 — infraestructura base |
| **Fecha** | 2026-08-22 |
| **Prompt** | [01-fase1-prompt.md](01-fase1-prompt.md) |

---

## 1. Modo de trabajo

La arquitectura la fijó una persona **antes** de escribir una línea de código:
servicios, límites, rutas, política de caché y modelo de autenticación venían
dados en el prompt. El papel de la IA fue de implementación, no de diseño.

El trabajo se pidió por bloques y en un orden concreto (bootstrap → módulos →
recursos → WAF/CDN → handlers → verificación), con una descripción previa de
cada bloque antes de generarlo. Eso mantuvo cada tramo revisable en lugar de
producir un volcado único difícil de auditar.

## 2. Qué generó la IA

| Área | Ficheros | Volumen |
|---|---|---|
| Bootstrap del state remoto | `terraform/bootstrap/*` | 8 recursos |
| Módulos reutilizables | `terraform/modules/{lambda-function,static-site}/*` | 2 módulos |
| Stack de aplicación | `terraform/*.tf` | 59 recursos |
| Handlers Lambda | `src/articles/*.py`, `src/common/*.py` | 6 ficheros |
| CI/CD | `.github/workflows/deploy.yml` | 4 jobs |
| Documentación | `README.md`, `CLAUDE.md`, `docs/ai-usage/*` | — |

## 3. Decisiones tomadas durante la implementación

La arquitectura no fijaba todos los detalles. Estas son las decisiones que hubo
que resolver, con su porqué; ninguna contradice lo especificado:

**`POST /articles` comparte path con el listado cacheado.** Un
`ordered_cache_behavior` de CloudFront selecciona por patrón de ruta, no por
método, así que un behavior de `/articles` restringido a GET habría devuelto
405 a las altas. Se permiten todos los métodos en ese behavior y se limita
`cached_methods` a `GET`/`HEAD`: CloudFront no cachea POST bajo ninguna
circunstancia, así que el requisito se cumple sin romper la escritura.

**`Authorization` fuera de la clave de caché.** La origin request policy
reenvía la cabecera al origen (POST la necesita), pero la cache policy no la
incluye en la clave: `GET /articles` es público e idéntico para todos y no debe
fragmentarse por usuario.

**Forma del GSI: `publish_date` (hash) + `created_at` (range).** Con
`publish_date` en formato `YYYY-MM-DD`, el resumen diario de la Fase 2 es una
Query sobre una única partición, y `created_at` ordena dentro del día. La
alternativa (partición sintética constante) habría exigido un atributo extra en
cada item sin ventaja para este patrón de acceso.

**Rol de despliegue de CI/CD en `bootstrap/`, no en el stack raíz.** El
pipeline necesita ese rol para poder ejecutar su primer `apply`; si lo creara
el propio stack raíz, no podría arrancar. Queda desactivado por defecto
(`github_repository = ""`).

**CORS solo en API Gateway.** Los handlers no devuelven cabeceras CORS: si las
pusieran también, llegarían duplicadas al navegador y este rechazaría la
respuesta.

**Sin `AWSLambdaBasicExecutionRole`.** Esa política gestionada concede `logs:*`
sobre `*`. Como los log groups se crean explícitamente en Terraform, cada rol
lleva una política inline con `CreateLogStream`/`PutLogEvents` acotada a su
propio log group.

## 4. Verificación ejecutada (entrega inicial)

En el momento de esta entrega no se hizo `apply`: nada se había creado en AWS
todavía. El despliegue real contra una cuenta AWS se hizo después, en una
sesión de continuación — ver [sección 7](#7-continuación-despliegue-contra-una-cuenta-aws-real).

```
terraform fmt -check -recursive terraform/     → OK
terraform init  (bootstrap)                    → OK
terraform validate (bootstrap)                 → Success
terraform plan  (bootstrap)                    → 8 to add, 0 to change, 0 to destroy
terraform init -backend=false (raíz)           → OK
terraform validate (raíz)                      → Success (2 avisos de deprecación)
terraform plan  (raíz)                         → 59 to add, 0 to change, 0 to destroy
python -m compileall src ai-summarizer         → OK
```

Comprobaciones puntuales sobre la salida del plan, más allá de que compile:

- 3 rutas con `authorization_type = "JWT"` y 1 con `"NONE"` → coincide con
  GET público y POST/PUT/DELETE protegidos.
- 5 log groups con `retention_in_days = 14` (4 Lambdas + logs de acceso del API).
- `web_acl_id` presente en una sola distribución: la de la app pública.

**Avisos conocidos:** el provider AWS 6.x marca `hash_key` como obsoleto en
favor de `key_schema`. Se mantiene `hash_key` deliberadamente porque
`key_schema` no existe en el provider 5.x y el rango declarado
(`>= 5.40.0, < 7.0.0`) admite ambas mayores. Es una deprecación, no un error.

## 5. Qué NO hizo la IA

- **No diseñó la arquitectura.** Venía decidida y se implementó tal cual.
- **No implementó la capa de IA.** `ai-summarizer/` contiene stubs que lanzan
  `NotImplementedError` y tests marcados como `skip`. Ver
  [02-fase2-prompt.md](02-fase2-prompt.md).
- **No desplegó nada.** Solo `validate` y `plan`, ambos de solo lectura.
- **No escribió los frontends React.** Fuera del alcance de la Fase 1; el
  workflow de despliegue se los salta mientras `apps/*/package.json` no exista.

## 6. Revisión humana pendiente antes de producción

Puntos que la IA dejó abiertos a propósito y que requieren una decisión humana:

1. `cors_allow_origins` está en `["*"]`. Restringir a los dos dominios
   CloudFront reales una vez desplegados.
2. Los nombres `news-now-public-app`, `news-now-admin-app` y
   `news-now-terraform-state` son globales en S3. Si están ocupados, hay que
   cambiarlos (y ajustar `backend.tf` en el caso del state).
3. `github_repository` en bootstrap está vacío: sin rellenar no existe rol de
   CI/CD y el workflow no puede autenticarse.
4. `terraform plan` no valida permisos IAM en tiempo de ejecución. La política
   mínima de cada Lambda debería contrastarse contra CloudTrail tras el primer
   despliegue real.

## 7. Continuación: despliegue contra una cuenta AWS real

Misma sesión, mismo día, una vez decidido probar contra una cuenta real.
Reparto de responsabilidad, explícito desde el primer mensaje del usuario:

- **Bootstrap** (`terraform/bootstrap/`): lo aplicó Claude Code, con
  confirmación expresa del usuario antes de ejecutar nada (comprobación
  previa de que el nombre de bucket y el de la tabla estaban libres, y
  confirmación de región). 8 recursos creados en `eu-west-1`.
- **Stack de aplicación** (`terraform/`): el usuario pidió explícitamente
  ejecutar él mismo los `terraform apply` — *"si, pero yo ejecuto el terraform
  apply"*. Desde ese momento, el trabajo de Claude en esta carpeta se limitó a
  `init`/`validate`/`plan` (solo lectura) para preparar y verificar cada
  cambio antes de que el usuario lo aplicara en su propia terminal.

### Troubleshooting durante el primer `apply` del usuario

El primer `terraform apply` del stack de aplicación, ejecutado por el
usuario, terminó con errores parciales: solo 2 de las 4 Lambdas quedaron
creadas. El usuario pegó el error completo de su terminal.

**Diagnóstico correcto, tras ver el error real.** Antes de tener el texto del
error, la primera hipótesis fue *throttling* de la API de IAM al crear 4
roles en paralelo — una suposición razonable pero **incorrecta**, y así quedó
dicho en cuanto el usuario compartió el error real. El error real era otro:
`ValidationError` de IAM y de CloudWatch Logs porque el tag `Route =
"PUT /articles/{id}"` (y su equivalente en `delete_article`) contenía llaves
`{ }`, un carácter que el regex de AWS para valores de tag no admite. Por eso
fallaban justo esas dos Lambdas: son las únicas dos rutas con parámetro en el
path. Fix: cambiar el valor del tag a `PUT /articles/:id` /
`DELETE /articles/:id` (los dos puntos sí están permitidos); el `route_key`
real de API Gateway, que sí necesita la sintaxis `{id}`, no se tocó porque no
es un tag y no le aplica esa restricción.

**Empaquetado de las Lambdas, a petición del usuario.** El usuario detectó
—inspeccionando el código desplegado— que el zip de cada Lambda contenía los
4 handlers del CRUD en lugar de solo el suyo (p. ej. la función
`create-article` incluía también `delete_article.py`, `get_articles.py` y
`update_article.py`). Correcto: el módulo `lambda-function` comprimía
`src/` entero con `archive_file source_dir` para poder compartir `common/`
entre las 4 funciones, y eso arrastraba también el código de las otras tres
operaciones. Se comprobó primero que ningún handler importa código de otro
handler (solo de `common/`), y se cambió el empaquetado de `source_dir` a
`source_files` (mapa fichero a fichero), de forma que cada zip incluye
únicamente `common/db.py` + `common/responses.py` + su propio handler.
Verificado con `unzip -l` sobre los 4 zips generados.

En ambos casos: Claude diagnosticó, corrigió el código y verificó con
`terraform validate` / `terraform plan` (lectura); el usuario aplicó el fix
ejecutando `terraform apply` en su propia terminal.

## 8. Unit tests de los handlers (con mocks)

A petición del usuario, tests para las 4 Lambdas del CRUD (`tests/`), con la
tabla DynamoDB sustituida por un `MagicMock` (fixture `mock_table` en
`tests/conftest.py`, que parchea `common.db.get_table`) — sin `moto`, sin
tocar AWS. Se creó un entorno virtual local (`.venv/`, en `.gitignore`) e
instalaron `pytest` y `boto3` como dependencias de test para poder ejecutar y
verificar la suite de verdad en esta sesión, no solo generarla.

**Resultado, verificado ejecutando `pytest --cov`:** 57 tests, **100% de
cobertura de líneas** en los 4 handlers. El primer barrido de tests dejó un
92% de cobertura; las ramas que faltaban (errores de `ClientError` con
códigos distintos al esperado, cuerpos en base64 corruptos, JSON que no es un
objeto, algunas validaciones de longitud en `update_article`) se identificaron
con `--cov-report=term-missing` y se completaron con tests adicionales hasta
cubrirlas todas.

**Novedad:** el proyecto no tenía hasta ahora un mecanismo de test para
`src/articles/`; se cubrió con `pytest.ini` (`testpaths = tests`) y
`requirements-test.txt`, y se añadió el paso `pytest -v` al job `validate` de
`.github/workflows/deploy.yml`, antes del `terraform validate`. `boto3` y
`pytest` son dependencias de desarrollo únicamente: el empaquetado de cada
Lambda (`source_files` en `terraform/main.tf`) sigue listando ficheros de
`src/` explícitamente, así que nunca viajan en un zip de despliegue.
