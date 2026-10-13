'use strict';

const crypto = require('node:crypto');
const express = require('express');

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;

// request_id = x-request-id recebido (se valido) ou UUID gerado; ecoa o header.
function requestContext(logger) {
  return (req, res, next) => {
    const incoming = req.get('x-request-id');
    const requestId =
      incoming && REQUEST_ID_PATTERN.test(incoming) ? incoming : crypto.randomUUID();
    req.requestId = requestId;
    res.set('x-request-id', requestId);

    const start = process.hrtime.bigint();
    res.on('finish', () => {
      logger.info('request', {
        method: req.method,
        path: req.path,
        status: res.statusCode,
        duration_ms: Number(process.hrtime.bigint() - start) / 1e6,
        request_id: requestId,
      });
    });
    next();
  };
}

// Handler final: resposta generica, sem stack nem mensagem interna.
function errorHandler(logger) {
  // eslint-disable-next-line no-unused-vars
  return (err, req, res, next) => {
    const status = err && err.status >= 400 && err.status < 500 ? err.status : 500;
    const messages = {
      400: 'Requisicao invalida',
      413: 'Corpo da requisicao muito grande',
      500: 'Erro interno',
    };
    logger.error('falha na requisicao', { request_id: req.requestId, status, err });
    res.status(status).json({
      message: messages[status] || 'Requisicao invalida',
      request_id: req.requestId,
    });
  };
}

function createApp({ db, logger }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(requestContext(logger));
  app.use(express.json({ limit: '16kb' }));

  app.get('/', (req, res) => {
    res.json({ message: 'API OK!', request_id: req.requestId });
  });

  // Liveness: nao consulta o banco.
  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });

  app.get('/connect', async (req, res) => {
    try {
      const result = await db.query('SELECT version()');
      res.json({
        message: 'Conectado ao banco',
        version: result.rows[0].version,
        request_id: req.requestId,
      });
    } catch (err) {
      logger.error('falha ao consultar o banco', { request_id: req.requestId, err });
      res.status(503).json({
        message: 'Erro ao se conectar ao banco',
        request_id: req.requestId,
      });
    }
  });

  app.use(errorHandler(logger));
  return app;
}

module.exports = { createApp, REQUEST_ID_PATTERN };
