'use strict';

// Drenagem antes do encerramento (EKS): o preStop manda SIGUSR2 e espera; dai em diante cada resposta sai com
// `Connection: close`, e o cliente (VPC Link do API Gateway, atras do NLB) abre conexoes novas, que o NLB ja manda
// para o pod novo. Sem isso, a conexao keep-alive presa ao alvo `draining` era fechada pelo SIGTERM no meio de uma
// requisicao (medido em 15/10/2026: 0,30% de falhas no rolling restart, todas no SIGTERM).
// Nao fecha conexoes ociosas aqui: fechar uma conexao ociosa do lado do servidor e a propria corrida que se quer
// evitar. As ociosas vencem pelo keepAliveTimeout do Node (5 s) dentro da janela do preStop.
function createDrain() {
  let active = false;
  return {
    // true so na primeira chamada (para logar uma vez).
    start() {
      const first = !active;
      active = true;
      return first;
    },
    isActive: () => active,
    middleware(req, res, next) {
      if (active) res.set('Connection', 'close');
      next();
    },
  };
}

module.exports = { createDrain };
