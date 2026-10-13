# Recuperação de desastre (DR)

**Este plano é documentado e não foi implementado nem testado.** Nenhum backup, restore, cópia entre regiões ou recriação em outra conta foi executado. RPO e RTO abaixo são metas e hipóteses de desenho. O RTO em particular é uma **meta a medir** num teste real; não existe medição.

Rótulos: `[FATO: fonte]`, `[HIPÓTESE]` e `[PROPOSTA]`. A decisão de fundo está no [ADR 0011](adr/0011-dr-via-pitr.md).

## Resumo

| Cenário | RPO | RTO | Como | Estado |
|---|---|---|---|---|
| Erro lógico ou corrupção, instância viva, mesma região | Meta de até 5 min | Meta de 30 a 60 min, a medir | PITR para nova instância e troca de endpoint | Documentado |
| Perda da instância RDS, mesma região | Depende de existir backup (ver "Atenção ao destroy") | Meta de 30 a 60 min, a medir | Restore de backup automático retido ou de snapshot, mais `terraform apply` | Documentado. Sem backup retido com a configuração atual de `dev` |
| Perda da região | Minutos (replicação de backups automáticos) ou até 24 h (cópia diária de snapshot) | A medir | Recriar a stack noutra região a partir do que foi copiado | Documentado. Não suportado na conta atual sem recursos avançados |
| Recriação em outra conta | Depende da cópia compartilhada | A medir | Snapshot compartilhado com chave KMS gerenciada pelo cliente | Documentado. Chave padrão não permite |

## RPO e RTO na mesma região

### RPO: meta de até 5 minutos

- O RDS tem backups automáticos com retenção de 7 dias. [FATO: [`modules/rds/main.tf`](../infrastructure/modules/rds/main.tf) linha 32]
- A AWS envia os logs de transação do RDS ao S3 a cada cinco minutos, e o restore para um ponto no tempo aceita qualquer instante dentro da retenção. [FATO: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html, aberta em 13/10/2026]
- Disso segue a meta de RPO de até 5 minutos. O valor real num incidente é a diferença entre o momento do incidente e o campo `LatestRestorableTime` da instância. [HIPÓTESE: o intervalo real de entrega dos logs pode variar; medir `LatestRestorableTime` antes de tratar 5 minutos como garantia]

### RTO: meta de 30 a 60 minutos, a medir

A meta vem da steering ([`01-arquitetura-e-restricoes.md`](../.kiro/steering/01-arquitetura-e-restricoes.md) seção "DR"). Ela soma tempos que não foram medidos:

| Parcela | Observação |
|---|---|
| Decidir o ponto no tempo | Depende de quem opera. Não medido |
| Restore PITR para nova instância | Depende do tamanho do banco. A doc diz que, depois de disponível, os volumes continuam carregando blocos do S3 em segundo plano e o desempenho pode ficar abaixo do normal até terminar |
| Trocar o endpoint na aplicação | Ver passo a passo. Pode exigir deploy |
| `terraform apply` | Tempo de criação do RDS e do restante. Não medido |
| Verificação (`GET /connect` = 200) | Segundos |

## Atenção ao destroy

[FATO] Com a configuração atual de `dev`, destruir a stack apaga os dados e os backups:

- `skip_final_snapshot = true` e `deletion_protection = false` em [`dev.tfvars`](../infrastructure/environments/dev.tfvars) linhas 87-88: nenhum snapshot final.
- O módulo `rds` não define `delete_automated_backups`, e o padrão do provider `aws` 6.68.0 é `true`: os backups automáticos são removidos junto com a instância. [FATO: [`modules/rds/main.tf`](../infrastructure/modules/rds/main.tf) e a doc do `aws_db_instance` v6.68.0, https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.68.0/website/docs/r/db_instance.html.markdown, argumento `delete_automated_backups`]

Consequência: o PITR cobre erro lógico e corrupção **enquanto a instância existe**. Ele não cobre a destruição da instância (por `terraform destroy`, `-replace` ou exclusão manual). A escolha foi deliberada para evitar custo residual em laboratório. [FATO: comentário em [`dev.tfvars`](../infrastructure/environments/dev.tfvars) linhas 84-86]

[PROPOSTA] Para um ambiente que precise sobreviver à exclusão da instância: `delete_automated_backups = false`, `skip_final_snapshot = false` com `final_snapshot_identifier` e `deletion_protection = true`. Custo de armazenamento de snapshots e backups retidos: **a verificar** (não está na tabela de preços da steering). Essa mudança altera o comportamento do `destroy` e não foi feita.

## Passo a passo na mesma região

### Cenário A: erro lógico ou corrupção, com a instância ainda existindo

1. Definir o instante alvo em UTC, anterior ao incidente. Conferir a janela de restauração da instância (campos `LatestRestorableTime` e o menor instante restaurável). [PROPOSTA]
2. Restaurar para uma **nova** instância. O PITR nunca sobrescreve a original. Comando: `aws rds restore-db-instance-to-point-in-time` com `--source-db-instance-identifier` (a instância atual), `--target-db-instance-identifier` (nome novo), `--restore-time` (ou `--use-latest-restorable-time`), `--db-subnet-group-name` (o subnet group existente) e `--vpc-security-group-ids` (o SG `rds`). [HIPÓTESE: confirmar os nomes e a lista completa de opções com `aws rds restore-db-instance-to-point-in-time help` antes de usar]
3. Passar o subnet group e o SG explicitamente. Sem isso a instância restaurada pode usar o security group padrão da VPC e os grupos de parâmetros padrão. [FATO: doc do PITR citada acima]
4. Esperar o status `available`. O banco fica utilizável, com desempenho possivelmente reduzido, enquanto os blocos carregam. [FATO: doc do PITR citada acima]
5. Apontar a aplicação para o endpoint novo. Há dois caminhos:
   1. **Renomear as instâncias** para que o endpoint original volte a existir: renomear a antiga e depois a restaurada para o identificador original (`aws rds modify-db-instance --new-db-instance-identifier`). A aplicação não muda. O efeito no state do Terraform (o recurso aponta para o identificador) **não foi avaliado**: tratar como risco e revisar o `plan` antes do próximo apply. [HIPÓTESE]
   2. **Mudar `DB_HOST`** (e, se for o caso, `DB_SECRET_ARN`) na task definition. O service ignora `task_definition` e o `deploy.yml` só troca a imagem na revisão ativa, então uma variável nova não chega sozinha ao service. É preciso registrar uma revisão com a variável alterada e chamar `UpdateService`. [FATO: [`modules/ecs/main.tf`](../infrastructure/modules/ecs/main.tf) linhas 119-126 e [`deploy.yml`](../.github/workflows/deploy.yml) linhas 146-168]
6. Segredo da senha: o segredo gerenciado pelo RDS pertence à instância original. Se o restore cria a instância nova com segredo próprio, a aplicação precisa do ARN novo. **A verificar** na AWS: como o segredo gerenciado se comporta num restore PITR. [HIPÓTESE]
7. Validar: `GET /` e `GET /connect` devolvem 200 e o `SELECT version()` responde. Só depois remover a instância antiga. [PROPOSTA]

### Cenário B: perda da instância (ou da stack) na mesma região

1. Com a configuração atual de `dev` não há backup retido (ver "Atenção ao destroy"). Os dados se perdem. Recria-se o banco vazio.
2. Se os backups automáticos tiverem sido retidos (`delete_automated_backups = false`) ou existir snapshot final, restaurar a partir deles (PITR a partir do backup automático retido, ou restore de snapshot). [PROPOSTA]
3. Recriar o restante com `terraform apply` na stack principal. Para criar o RDS já restaurado pelo Terraform, o recurso `aws_db_instance` aceita `snapshot_identifier` e o bloco `restore_to_point_in_time` na versão 6.68.0. [FATO: doc do `aws_db_instance` v6.68.0, citada acima] O módulo [`modules/rds`](../infrastructure/modules/rds/main.tf) **não expõe** nenhum dos dois hoje, então seria uma mudança de código. [PROPOSTA]
4. Conferir a ordem: a imagem precisa existir no ECR (o ECR vem do bootstrap e sobrevive ao `destroy` da stack), e a stack é criada pelo `infra.yml` com a tag da imagem. [FATO: [`infra.yml`](../.github/workflows/infra.yml) linhas 1-3]

## Recriação em outra região ou conta

### O que já é parametrizado

- A região vem de `var.region`, definida no tfvars. Não há região hardcoded nos arquivos `.tf` da raiz, do bootstrap e dos módulos, nem nos workflows (que usam `vars.AWS_REGION`). A única ocorrência de nome de região em `.tf` é um exemplo na descrição de uma variável. [FATO: busca por `us-east-`, `us-west-` e `eu-west` em `infrastructure/**/*.tf` e `*.json` e em `.github/workflows/*.yml`, em 13/10/2026]
- As AZs vêm de `data.aws_availability_zones`, filtradas para zonas sem opt-in, e `az_count` define quantas. [FATO: [`main.tf`](../infrastructure/main.tf) linhas 16-35]
- O state é separado por chave e por bucket: o nome do bucket inclui o ID da conta e a chave inclui projeto e ambiente. Uma nova conta ou região tem o próprio bootstrap e o próprio state. [FATO: [`bootstrap/main.tf`](../infrastructure/bootstrap/main.tf) linhas 12-13]
- O CA bundle do RDS que a imagem embute é o **global**, então a mesma imagem serve em outra região. [FATO: [`application/Dockerfile`](../application/Dockerfile) linhas 5-10]
- O ECR é regional. A imagem precisa ser construída e publicada no ECR da região nova pelo `deploy.yml` com `AWS_REGION` apontando para ela. Não há replicação de ECR configurada. [FATO: [`modules/ecr/main.tf`](../infrastructure/modules/ecr/main.tf) e [`deploy.yml`](../.github/workflows/deploy.yml) linhas 44-52]

### Ainda fixo para um ambiente

- O bootstrap tem uma variável `environment` única, e o `deploy.yml` tem `simple-api-dev` fixo no cluster e no service. [FATO: [`bootstrap/variables.tf`](../infrastructure/bootstrap/variables.tf) linhas 7-16 e [`deploy.yml`](../.github/workflows/deploy.yml) linhas 26-31]
- Os CIDRs de `dev`, `hml` e `prod` são fixos nos tfvars (`10.100`, `10.110`, `10.120`). Duas regiões com o mesmo ambiente podem reaproveitar o CIDR, desde que nunca sejam pareadas. [HIPÓTESE: sem peering entre as VPCs não há conflito; não há peering no código]

### O que é copiado: duas opções para os dados

| Opção | RPO | O que precisa existir | Custo |
|---|---|---|---|
| Replicação de backups automáticos para outra região | Minutos, com PITR na região destino | Replicação configurada na instância de origem. A doc cobra transferência de dados e armazenamento no destino | **A verificar**. Suporte para instância single-AZ de PostgreSQL: **a verificar** (a página da doc não foi lida inteira) |
| Cópia diária de snapshot entre regiões | Até 24 h | Rotina agendada que copia o snapshot | Armazenamento do snapshot copiado e transferência, **a verificar** |

[FATO: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReplicateBackups.html, aberta em 13/10/2026, para a replicação de backups automáticos. O RPO de "minutos" e o de "até 24 h" vêm da steering [`01-arquitetura-e-restricoes.md`](../.kiro/steering/01-arquitetura-e-restricoes.md)]

### Entre contas: snapshot e chave KMS

- Um snapshot cifrado com a chave KMS padrão **não pode ser compartilhado** com outra conta. [FATO: [`00-fonte-da-verdade.md`](../.kiro/steering/00-fonte-da-verdade.md) seção "Fatos de serviços AWS"]
- O RDS do código usa `storage_encrypted = true` sem `kms_key_id`, ou seja, a chave padrão. [FATO: [`modules/rds/main.tf`](../infrastructure/modules/rds/main.tf) linha 25]
- Para compartilhar, o banco precisa ser cifrado com uma chave gerenciada pelo cliente (CMK), cerca de US$ 1/mês, **a verificar** (o valor vem da steering e não de uma página de preços aberta). [FATO: [`04-terraform.md`](../.kiro/steering/04-terraform.md) regra 14]
- Trocar a chave de uma instância existente não é um simples `apply` sobre o recurso. [HIPÓTESE: cifragem de storage não se altera em uma instância em execução; o caminho é copiar um snapshot com a chave nova. Confirmar na doc do RDS antes de planejar]

### Passo a passo de recriação (PROPOSTA)

1. Nova conta ou região: copiar `bootstrap/terraform.tfvars.example` para `secrets.tfvars`, ajustar região, `github_owner` e e-mails do budget, e aplicar o bootstrap (com aprovação, custo estimado e perfil de escrita). Mantém-se o budget de US$ 45 antes de qualquer stack.
2. Criar os GitHub environments e as variáveis do repositório para a nova conta (`AWS_REGION`, ARNs das roles, `TF_STATE_BUCKET`, `TF_STATE_KEY`).
3. Publicar a primeira imagem no ECR novo com `deploy.yml` e `only_build=true`.
4. Restaurar o banco: a partir de PITR na região destino (se houver replicação de backups) ou de um snapshot copiado ou compartilhado. Isso exige o módulo `rds` aceitar `snapshot_identifier` ou `restore_to_point_in_time`, o que não existe hoje.
5. `infra.yml` com a tag da imagem, apontando para o state novo.
6. Verificar `GET /connect` pelo endpoint do API Gateway da nova região. O endpoint **muda** (API Gateway é regional); qualquer cliente precisa do novo endereço. [HIPÓTESE: não há domínio próprio nem Route 53 no código, então não existe failover de DNS]
7. Medir o tempo total e registrar como RTO real.

## Limitações da conta

- A conta foi aberta pelo cadastro novo ("Sign up for AWS (new)") nos dois planos até a ativação de "Activate advanced AWS features". Nessa condição não há recursos multi-região ou cross-região, e faltam GuardDuty, IAM Access Analyzer, Organizations, IAM Identity Center, Security Hub e Trusted Advisor, entre outros. Fonte registrada na steering: https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html. [FATO: [`00-fonte-da-verdade.md`](../.kiro/steering/00-fonte-da-verdade.md) seção "Conta AWS e orçamento"; a página não foi reaberta neste turno]
- Por isso a replicação de backups para outra região e a cópia de snapshot entre regiões ficam só documentadas. Ativar os recursos avançados é decisão do dono da conta e não foi feita.
- O Free plan nunca cobra, vale para serviços e recursos selecionados e fecha em 6 meses ou quando os créditos zeram. [FATO: [`00-fonte-da-verdade.md`](../.kiro/steering/00-fonte-da-verdade.md) seção "Conta AWS e orçamento"] A steering lista o plano da conta como desconhecido; o handoff do projeto de 13/10/2026 registra Free plan, o que não foi reverificado aqui.
- Sem IAM Access Analyzer, a validação de policies com `aws accessanalyzer validate-policy` não é possível. [FATO: [`03-devsecops.md`](../.kiro/steering/03-devsecops.md) seção "IAM"]

## Plano de teste de DR (PROPOSTA, não executado)

Executar só com aprovação e estimativa de custo (regra 7 do [`AGENTS.md`](../AGENTS.md)):

1. Com a stack de `dev` no ar, inserir uma linha marcada no banco e anotar o horário.
2. Medir `LatestRestorableTime`.
3. Restaurar PITR para uma instância nova e cronometrar: pedido, `available`, troca de endpoint, `GET /connect` = 200.
4. Conferir que a linha marcada existe e que uma inserida depois do ponto escolhido não existe.
5. Remover a instância de teste e rodar `tools/residual-check.sh`. A instância extra `db.t4g.micro` custa cerca de US$ 0,016/h, **aproximado**. [FATO: [`02-finops-guardrails.md`](../.kiro/steering/02-finops-guardrails.md) seção "Preços de referência"]
6. Registrar o RTO medido, com a data, e só então trocar "meta" por "medido" neste documento.
