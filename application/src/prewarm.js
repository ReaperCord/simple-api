'use strict';

// Pre-aquece o caminho de autenticacao IAM do RDS na partida, sem bloquear a app nem derrubar o processo.
// Motivo (medido na AWS em 14/10/2026): a primeira conexao fria (credenciais da task, assinatura do token, TLS e
// autenticacao) pode passar do connectionTimeoutMillis de 2 s e dar um 503 pontual. Aqui o token fica em cache e a
// primeira conexao do pool e aberta antes da primeira requisicao.
// Falha de pre-aquecimento NAO e erro da app (ex.: o usuario do banco ainda nao foi criado pelo db-init): so um aviso.
// So name/code vao para o log (o logger reduz `err`); nunca a mensagem nem o token.
async function prewarm({ provider, db, logger }) {
  try {
    await provider.getPassword();
    await db.query('SELECT 1');
    logger.info('pre-aquecimento do token IAM concluido');
    return true;
  } catch (err) {
    logger.warn('pre-aquecimento do token IAM falhou', { err });
    return false;
  }
}

module.exports = { prewarm };
