###############################################################################
# Backend remoto
#
# Mismo bucket y tabla de locks que el stack de Fase 1 (terraform/backend.tf),
# con una key propia: son dos estados independientes, uno por fase, sobre la
# misma infraestructura de backend creada por terraform/bootstrap/.
#
# Para validar el HCL sin credenciales AWS: terraform init -backend=false
###############################################################################

terraform {
  backend "s3" {
    bucket         = "news-now-terraform-state"
    key            = "news-now/ai.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "news-now-terraform-locks"
    encrypt        = true
  }
}
