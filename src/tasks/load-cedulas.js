const { config } = require("../config/config");
const { fetchExpedientesFromSqlServer } = require("../database/expedientes-repository");
const { writeExpedientesJson } = require("../database/expedientes-json-store");

const DEFAULT_DEMANDANTE = "MI BANCO";

function getTodayIsoDate() {
  const now = new Date();
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

async function runLoadCedulasTask(overrides = {}) {
  const fecha = String(overrides.fecha || getTodayIsoDate()).trim();
  const demandante = String(overrides.demandante || DEFAULT_DEMANDANTE).trim();

  const result = await fetchExpedientesFromSqlServer({
    connectionString: config.cedulasDbConnectionString,
    queryFilePath: config.cedulasDbQueryFilePath,
    commandTimeoutSec: config.cedulasDbCommandTimeoutSec,
    fecha,
    demandante
  });

  const expedientes = result.expedientes;
  await writeExpedientesJson(config.expedientesJsonPath, expedientes);

  const cedulas = result.cedulas || [];
  if (cedulas.length === 0) {
    throw new Error("No hay cedulas para procesar desde SQL Server.");
  }

  return {
    source: "sqlserver",
    cedulas,
    expedientes,
    fecha,
    demandante
  };
}

module.exports = { runLoadCedulasTask };
