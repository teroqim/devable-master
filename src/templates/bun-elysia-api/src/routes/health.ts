import { Elysia } from 'elysia';

export const healthRoutes = new Elysia().get('/ping', () => ({
  status: 'ok',
  timestamp: new Date().toISOString(),
}));
