mock_provider "aws" {}

# S3: 3 instancias do modulo se referenciando (inclusive a propria) planejam sem Cycle e sem
# "Invalid for_each". Rode com 'terraform test -verbose' para ver "Plan: 11 to add".
run "s3_tres_instancias_sem_ciclo" {
  command = plan

  module {
    source = "./tests/setup"
  }

  assert {
    condition     = length(output.sg_keys) == 3
    error_message = "O mapa sg_ids compartilhado deve ter as 3 chaves (vpclink, ecs, rds)."
  }
}
