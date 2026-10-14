# Recuperação de desastre (DR)

**Este plano é documentado.** Foi testado **um** restore PITR na mesma região (seção "Teste realizado em 13/10/2026", abaixo). Cópia entre regiões, snapshot entre contas e recriação em outra conta **não** foram executados. RPO e RTO das demais linhas são metas e hipóteses de desenho.

Rótulos: `[FATO: fonte]`, `[HIPÓTESE]` e `[PROPOSTA]`. A decisão de fundo está no [ADR 0011](adr/0011-dr-via-pitr.md).

## Resumo

| Cenário | RPO | RTO | Como | Estado |
|---|---|---|---|---|
| Erro lógico ou corrupção, instância viva, mesma região | Meta de até 5 min (observado ~3 a 8 min, 1 execução) | Meta de 30 a 60 min; restore até banco verificado medido em 16,4 min (13/10) e restore mais troca do endpoint e da policy IAM até a app responder em 18,5 min (14/10); ambos em 1 execução, sem a decisão e sem o apply do Terraform | PITR para nova instância e troca de endpoint | Restore testado; troca de endpoint não |
| Perda da instância RDS, mesma região | Depende de existir backup (ver "Atenção ao destroy") | Meta de 30 a 60 min, a medir | Restore de backup automático retido ou de snapshot, mais `terraform apply` | Documentado. Sem backup retido com a configuração atual de `dev` |
| Perda da região | Minutos (replicação de backups automáticos) ou até 24 h (cópia diária de snapshot) | A medir | Recriar a stack noutra região a partir do que foi copiado | Documentado. Não suportado na conta atual sem recursos avançados |
| Recriação em outra conta | Depende da cópia compartilhada | A medir | Snapshot compartilhado com chave KMS gerenciada pelo cliente | Documentado. Chave padrão não permite |

## RPO e RTO na mesma região

### RPO: meta de até 5 minutos

- O módulo do RDS parametriza a retenção dos backups automáticos (alvo documentado: 7 dias). O Free plan desta conta recusa 7 (`FreeTierRestrictionError`) e o `dev` usa **1 dia**, ou seja, o PITR cobre só as últimas 24 h. [FATO: [`dev.tfvars`](../infrastructure/environments/dev.tfvars) `db_backup_retention_period = 1`; ADR 0011]. Na AWS (13/10/2026) o RDS criado gerou um snapshot automático, visível no Resource Group; nenhum restore foi feito.
- A AWS envia os logs de transação do RDS ao S3 a cada cinco minutos, e o restore para um ponto no tempo aceita qualquer instante dentro da retenção. [FATO: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html, aberta em 13/10/2026]
- Disso segue a meta de RPO de até 5 minutos. O valor real num incidente é a diferença entre o momento do incidente e o campo `LatestRestorableTime` da instância. [HIPÓTESE: o intervalo real de entrega dos logs pode variar; medir `LatestRestorableTime` antes de tratar 5 minutos como garantia]

### RTO: meta de 30 a 60 minutos (restore medido em 16,4 min)

A meta vem da steering ([`01-arquitetura-e-restricoes.md`](../.kiro/steering/01-arquitetura-e-restricoes.md) seção "DR"). Ela soma tempos que não foram medidos:

| Parcela | Observação |
|---|---|
| Decidir o ponto no tempo | Depende de quem opera. Não medido |
| Restore PITR para nova instância | Depende do tamanho do banco. A doc diz que, depois de disponível, os volumes continuam carregando blocos do S3 em segundo plano e o desempenho pode ficar abaixo do normal até terminar |
| Trocar o endpoint na aplicação | Ver passo a passo. Pode exigir deploy |
| `terraform apply` | Tempo de criação do RDS e do restante. Não medido |
| Verificação (`GET /connect` = 200) | Segundos |

## Teste realizado em 13/10/2026 (restore PITR, mesma região)

[FATO: registro com horários em `tests/load/results/2026-10-13-aws-dr-restore-log.txt`] Foi feito **um** restore PITR real do RDS `simple-api-dev-db` (`db.t4g.micro`, retenção de 1 dia) para uma instância nova na mesma VPC, subnet group e SG, não pública. O Free plan aceitou o restore.

| Passo | Medida |
|---|---|
| Marcador gravado no banco (tabela `dr_marker`) | 23:25:14 UTC |
| `LatestRestorableTime` passar do marcador | até 473 s depois (limite superior: polling a cada 20 s e o campo avança em passos) |
| Defasagem de `LatestRestorableTime` para o relógio, numa consulta | 192 s (~3,2 min) |
| Pedido do restore → instância `available` | **924 s (15,4 min)** |
| Pedido → marcador verificado na instância restaurada | **986 s (16,4 min)** |
| Verificação (task efêmera, TLS `verify-full`, mesmo segredo) | 62 s; retornou o marcador (`id` 1, `note` "pre-restore"), `pg_is_in_recovery() = false` |
| Apagar a instância restaurada (`--skip-final-snapshot --delete-automated-backups`) | 93 s |

Leitura:
- A parte "restore PITR até um banco acessível e verificado" levou **~16,4 min**, dentro da meta de 30 a 60 min. O RTO total de um incidente soma ainda a decisão do ponto no tempo, a troca do endpoint na aplicação (pode exigir deploy) e o `terraform apply`, que **não foram medidos**.
- O RPO observado fica na faixa de **~3 a 8 min** neste teste (uma execução); a meta de 5 min **não é garantia**: o ponto restaurável só ultrapassou o marcador depois de até ~7,9 min.
- O restore usou o último ponto restaurável, não um instante escolhido. Não foram testados restore a partir de snapshot, outra região nem outra conta.
- Limites: uma execução, banco praticamente vazio (o tempo de restore cresce com o volume de dados) e retenção de 1 dia (o PITR cobre só as últimas 24 h).

## Teste 2 em 14/10/2026 (RTO com a troca de endpoint e a policy IAM)

[FATO: registro com horários em `tests/load/results/2026-10-14-aws-dr-rto-iam-log.txt`] Com a app em autenticação IAM (ADR 0013), repeti o restore PITR e medi também o que muda a app: apontar a policy `rds-db:connect` para o `DbiResourceId` da instância nova e trocar o `DB_HOST` por uma nova revisão da task definition.

| Parcela (14/10, horário de Brasília) | Tempo |
|---|---|
| Restore PITR, pedido às 14:59 até `available` (com IAM ligado) | **953 s (15,9 min)** |
| Policy `rds-db:connect` atualizada (`create-policy-version`) | **4 s** |
| Troca do endpoint: nova revisão, `update-service`, task nova estável | **156 s (2,6 min)** |
| **Pedido do restore até `/connect` = 200 na instância restaurada** | **1.113 s (18,5 min)** |

Leitura:
- O token IAM é assinado para o host novo, então o 200 prova que a app conectou na instância restaurada. O usuário `app_connect` veio no restore (estava nos dados).
- No modo IAM o DR tem um passo a mais que o modo senha: o `DbiResourceId` **muda** na instância restaurada, então a policy da task role precisa ser atualizada (4 s por CLI; num DR real vira `terraform apply`).
- Não foram medidos: a **decisão** do ponto no tempo, o `terraform import`/`apply` para o state passar a apontar a instância nova, e restore a partir de snapshot, outra região ou outra conta. O RTO de um incidente é essa soma, então **18,5 min é um piso**, não o RTO total.
- Reverti o service e a policy e apaguei a instância restaurada (92 s) antes do destroy.

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

- A conta foi aberta pelo cadastro **avançado** e está no **Free plan**: `accountPlanType: FREE`, `ACTIVE`, US$ 100,00 de crédito restante, expiração em 2027-04-11. [FATO: saída de `aws freetier get-account-plan-state` e print do console, ambos registrados na sessão de configuração do projeto. O dono da conta confirmou que não criou nenhum project no AWS Settings, o que descarta a experiência nova]
- As restrições da experiência nova (região única por project, sem recursos multi-região ou cross-região) **não se aplicam a esta conta**. A steering (`00-fonte-da-verdade.md` e `03-devsecops.md`) ainda as cita porque foi escrita antes dessa confirmação; o dono da conta é quem atualiza a steering. [FATO: https://docs.aws.amazon.com/accounts/latest/reference/project-regions.html descreve a região única só para projects da experiência nova]
- A replicação de backups para outra região e a cópia de snapshot entre regiões ficam só documentadas por **escopo e custo**, e não por restrição da conta. Não foi verificado se o Free plan libera esses recursos: a lista pública de serviços que encontrei vale só para a experiência nova.
- O Free plan nunca cobra, vale para serviços e recursos selecionados e fecha em 6 meses ou quando os créditos zeram. [FATO: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html, aberta em 13/10/2026] Se entrar no AWS Organizations, o Free plan vira Paid automaticamente (mesma página), por isso o Organizations não deve ser usado.
- O uso do IAM Access Analyzer (`aws accessanalyzer validate-policy`) para validar policies não foi verificado nesta conta. A steering diz que ele não existe em conta da experiência nova, o que não se aplica aqui. [HIPÓTESE: disponível, a confirmar]

## Plano de teste de DR (PROPOSTA, não executado)

Executar só com aprovação e estimativa de custo (regra 7 do [`AGENTS.md`](../AGENTS.md)):

1. Com a stack de `dev` no ar, inserir uma linha marcada no banco e anotar o horário.
2. Medir `LatestRestorableTime`.
3. Restaurar PITR para uma instância nova e cronometrar: pedido, `available`, troca de endpoint, `GET /connect` = 200.
4. Conferir que a linha marcada existe e que uma inserida depois do ponto escolhido não existe.
5. Remover a instância de teste e rodar `tools/residual-check.sh`. A instância extra `db.t4g.micro` custa cerca de US$ 0,016/h, **aproximado**. [FATO: [`02-finops-guardrails.md`](../.kiro/steering/02-finops-guardrails.md) seção "Preços de referência"]
6. Registrar o RTO medido, com a data, e só então trocar "meta" por "medido" neste documento.
