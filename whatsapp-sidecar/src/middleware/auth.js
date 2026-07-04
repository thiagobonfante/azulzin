/**
 * Bearer-token auth. Factory so the expected token is injected (testable).
 * Applied to every route except /health.
 */
module.exports = (config) => (req, res, next) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(' ')[1]; // "Bearer <token>"

  if (!token || token !== config.railsApiToken) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
};
