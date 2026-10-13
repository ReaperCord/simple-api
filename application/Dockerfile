# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# Frontend fixado por digest (indice OCI de docker/dockerfile:1, obtido em 2026-10-12 via
# `docker buildx imagetools inspect docker/dockerfile:1`). Exige >= 1.6 (ADD --checksum) e >= 1.2 (COPY --chmod).

# Stage 1: bundle de CAs da RDS (necessario para DB_SSLMODE=verify-full).
# SHA-256 medido em 2026-10-12 (TOFU): a AWS nao publica checksum do bundle.
# Se a AWS atualizar o arquivo, este build falha de proposito: conferir a mudanca e atualizar o hash em PR.
FROM scratch AS rds-ca
ADD --checksum=sha256:fe45bbebf92ad3e27a583bbb2ddd1553c521ed4d49af5514dc0a40372ea5395c \
    https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /rds-global-bundle.pem

# Stage 2: dependencias de producao
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Stage 3: imagem final (sem HEALTHCHECK: o health check e o da task definition, via wget do busybox)
FROM node:24.21.0-alpine3.24@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src
# O diretorio e criado antes com 0755: o COPY --chmod aplica o modo tambem ao diretorio de destino que ele
# cria (resultaria em dr--r--r--, sem bit de execucao, e o usuario node nao conseguiria ler o bundle).
RUN mkdir -m 0755 /certs
COPY --from=rds-ca --chmod=0444 /rds-global-bundle.pem /certs/rds-global-bundle.pem
ENV DB_SSL_CA_FILE=/certs/rds-global-bundle.pem
# npm/npx nao sao usados em runtime (CMD chama node direto) e o npm embutido na base carrega CVEs HIGH
# (brace-expansion, ip-address, tar, undici) que reprovam o trivy image. Remover reduz a superficie de ataque.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
# Justificativa do ignore: o usuario "node" ja existe na imagem base (uid 1000) e a spec exige USER node.
# hadolint ignore=DL3066
USER node
EXPOSE 3000
CMD ["node","src/index.js"]
