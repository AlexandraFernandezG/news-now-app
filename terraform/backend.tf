###############################################################################
# Backend remoto
#
# Bucket y tabla creados previamente por terraform/bootstrap/ (paso unico y
# separado). Si cambiaste `state_bucket_name` alli por colision de nombre
# global, cambia el `bucket` de abajo o inicializa con configuracion parcial:
#
#   terraform init -backend-config="bucket=<tu-bucket>"
#
# Para validar el HCL sin credenciales AWS: terraform init -backend=false
###############################################################################

terraform {
  backend "s3" {
    bucket         = "news-now-terraform-state"
    key            = "news-now/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "news-now-terraform-locks"
    encrypt        = true
  }
}
