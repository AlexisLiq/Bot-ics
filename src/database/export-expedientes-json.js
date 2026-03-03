const { config } = require("../config/config");
const { fetchExpedientesFromSqlServer } = require("./expedientes-repository");
const { writeExpedientesJson } = require("./expedientes-json-store");

const DEFAULT_DEMANDANTE = "MI BANCO";

function getCliArg(name) {
  const args = process.argv.slice(2);
  const pref = `--${name}=`;
  const inline = args.find((arg) => arg.startsWith(pref));
  if (inline) return inline.slice(pref.length).trim();

  const idx = args.findIndex((arg) => arg === `--${name}`);
  if (idx >= 0 && args[idx + 1]) return String(args[idx + 1]).trim();

  return "";
}

function getTodayIsoDate() {
  const now = new Date();
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

async function main() {
  const fecha = getCliArg("fecha") || getTodayIsoDate();
  const demandante = getCliArg("demandante") || DEFAULT_DEMANDANTE;

  const result = await fetchExpedientesFromSqlServer({
    connectionString: config.cedulasDbConnectionString,
    queryFilePath: config.cedulasDbQueryFilePath,
    commandTimeoutSec: config.cedulasDbCommandTimeoutSec,
    fecha,
    demandante
  });

  const saved = await writeExpedientesJson(
    config.expedientesJsonPath,
    result.expedientes
  );

  console.log(`JSON generado: ${saved.path}`);
  console.log(`Expedientes: ${saved.count}`);
  console.log(`Cedulas unicas: ${result.count}`);
}

main().catch((error) => {
  console.error("Error exportando expedientes a JSON:");
  console.error(error.message || String(error));
  if (error.cause) {
    console.error("Causa:", error.cause.message || error.cause);
  }
  process.exitCode = 1;
});
