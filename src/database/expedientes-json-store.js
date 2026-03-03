const fs = require("node:fs/promises");
const path = require("node:path");

async function writeExpedientesJson(filePath, expedientes) {
  const items = Array.isArray(expedientes) ? expedientes : [];
  const payload = {
    stats: {
      expedientes: items.length
    },
    accepted: items
  };

  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(payload, null, 2), "utf8");

  return {
    path: filePath,
    count: items.length
  };
}

module.exports = {
  writeExpedientesJson
};
