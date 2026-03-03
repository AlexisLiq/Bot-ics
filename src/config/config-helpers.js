function parseBoolean(value, fallback = false) {
  if (value == null || value === "") return fallback;
  return ["1", "true", "yes", "on"].includes(String(value).trim().toLowerCase());
}

function parseIntOr(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseList(value, fallback) {
  if (!value) return fallback;
  const parsed = value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return parsed.length > 0 ? parsed : fallback;
}

function parseSelectorList(value, fallback) {
  return parseList(value, fallback);
}

function required(name, env = process.env) {
  const value = env[name];
  if (!value) {
    throw new Error(`Falta variable requerida en .env: ${name}`);
  }
  return value;
}

module.exports = {
  parseBoolean,
  parseIntOr,
  parseList,
  parseSelectorList,
  required
};

