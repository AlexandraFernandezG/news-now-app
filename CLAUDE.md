# CLAUDE.md

Guía para trabajar en este repositorio. La visión general está en el
[README](README.md); aquí solo lo que no es evidente leyendo el código.

## Qué es esto

MVP de NewsNow, un periódico digital serverless en AWS. **Fase 1** (entregada):
infraestructura Terraform + API de artículos. **Fase 2** (pendiente): capa de IA
para resúmenes — no implementarla salvo petición explícita.

## Reglas del proyecto

**La arquitectura está decidida.** Servicios, límites, rutas, política de caché
y modelo de autenticación vienen dados. Implementar, no rediseñar. Si algo
parece mejorable, decirlo en una frase y seguir con lo especificado.

**No aplicar Terraform.** `validate` y `plan` son seguros; `apply` y `destroy`
requieren pedirlo antes, siempre.

**`ai-summarizer/` es territorio de la Fase 2.** Sus ficheros lanzan
`NotImplementedError` a propósito y sus tests están marcados como `skip`.

## Comandos

```bash
# Validar sin credenciales ni backend remoto
cd terraform && terraform init -backend=false && terraform validate

# Formato (el CI lo comprueba con -check)
terraform fmt -recursive terraform/

# Sintaxis de los handlers (no hay dependencias que instalar: boto3 lo aporta
# el runtime de Lambda)
python -m compileall -q src
```

Para un `plan` de la raíz antes de que exista el bucket de state, crear un
`backend_override.tf` temporal con `terraform { backend "local" {} }` (los
`*_override.tf` están en `.gitignore`) y borrarlo al terminar.

## Cómo está montado

**Empaquetado de las Lambdas.** Las cuatro comparten el mismo zip: `archive_file`
comprime **todo `src/`**, por eso los handlers se declaran como
`articles.<módulo>.lambda_handler` y pueden hacer `from common.db import …`.
Un handler nuevo va en `src/articles/` y se instancia con el módulo
`lambda-function`; no hay que tocar el empaquetado.

**Módulo `lambda-function`.** Crea función + rol + log group juntos. Los
permisos concretos llegan por `policy_statements` (lista de objetos
`{sid, effect, actions, resources}`) y se definen en
[terraform/iam.tf](terraform/iam.tf), no dentro del módulo.

**WAF vive en us-east-1.** `scope = CLOUDFRONT` lo exige. Usa el provider con
alias `aws.us_east_1` declarado en [terraform/main.tf](terraform/main.tf).

**El rol de CI/CD está en `bootstrap/`, no en la raíz.** El pipeline lo necesita
para poder ejecutar su primer `apply`; el stack raíz no puede crearse a sí mismo
las credenciales con las que se despliega.

## Convenciones

- **Los comentarios explican el porqué, no el qué.** Los ficheros existentes
  llevan una cabecera con la intención del bloque y comentarios puntuales donde
  una decisión no es obvia. Mantener ese nivel: ni más denso ni más escueto.
- **Todo en castellano**: comentarios, descripciones de variables, mensajes de
  error de la API y documentación. Sin tildes en los ficheros `.tf` y `.py`
  (se ha evitado deliberadamente el no-ASCII en código); el Markdown sí las usa.
- **Los handlers no devuelven cabeceras CORS.** Las pone API Gateway
  (`cors_configuration`); duplicarlas rompe la petición en el navegador.
- **Nada de `dynamodb:*` ni políticas gestionadas amplias.** Cada Lambda lleva
  exactamente las acciones que ejecuta.
- **Todo recurso nuevo debe salir en `terraform plan` sin avisos nuevos.** Los
  dos avisos actuales (`hash_key` obsoleto en el provider 6.x) son conocidos y
  están justificados en el README.

## Ficheros que conviene mirar antes de tocar nada

| Fichero | Por qué |
|---|---|
| [terraform/api_cache_cloudfront.tf](terraform/api_cache_cloudfront.tf) | La interacción entre `path_pattern` y `cached_methods` es sutil: un cambio descuidado rompe `POST /articles` |
| [terraform/dynamodb.tf](terraform/dynamodb.tf) | Cambiar claves o streams recrea la tabla; tiene `prevent_destroy` |
| [src/common/responses.py](src/common/responses.py) | Formato de respuesta y serialización de `Decimal`, compartidos por los cuatro handlers |
