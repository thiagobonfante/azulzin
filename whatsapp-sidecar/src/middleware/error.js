/** Global error handler. */
const errorHandler = (err, req, res, _next) => {
  console.error('[ERROR]', new Date().toISOString(), err);
  const statusCode = err.statusCode || 500;
  const response = { error: err.message || 'Internal server error' };
  if (process.env.NODE_ENV !== 'production') response.stack = err.stack;
  res.status(statusCode).json(response);
};

/** 404 handler. */
const notFoundHandler = (req, res) => {
  res.status(404).json({ error: 'Route not found' });
};

module.exports = { errorHandler, notFoundHandler };
