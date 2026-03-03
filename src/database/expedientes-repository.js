const sql = require("mssql");
const fs = require("node:fs/promises");

function sanitizeCedulas(values) {
  const seen = new Set();
  const result = [];

  for (const raw of values || []) {
    const value = String(raw || "").trim();
    if (!value) continue;
    if (seen.has(value)) continue;
    seen.add(value);
    result.push(value);
  }

  return result;
}

function parseIsoDate(value) {
  const text = String(value || "").trim();
  if (!text) return null;

  const asDate = new Date(`${text}T00:00:00`);
  if (Number.isNaN(asDate.getTime())) {
    throw new Error(`Fecha invalida: "${text}". Usa formato YYYY-MM-DD.`);
  }
  return asDate;
}

function bindQueryParams(request, { fecha, demandante }) {
  const parsedDate = parseIsoDate(fecha);
  if (!parsedDate) {
    throw new Error("Falta fecha para la query SQL (@pFecha).");
  }

  const demandanteText = String(demandante || "").trim();
  if (!demandanteText) {
    throw new Error("Falta demandante para la query SQL (@pDemandante).");
  }

  request.input("pFecha", sql.Date, parsedDate);
  request.input("pDemandante", sql.NVarChar(200), demandanteText);
}

function toNullableString(value) {
  const text = String(value ?? "").trim();
  return text ? text : null;
}

function buildExpedientesFromRecordset(recordset) {
  const byId = new Map();

  for (const row of recordset || []) {
    const idExpediente = String(row.ID_EXPEDIENTE ?? "").trim();
    const expediente = String(row.EXPEDIENTE ?? "").trim();
    const demandado1Documento = String(row.DEMANDADO1_DOCUMENTO ?? "").trim();

    if (!byId.has(idExpediente)) {
      byId.set(idExpediente, {
        idExpediente,
        expediente: expediente || null,
        demandado1Documento,
        actuaciones: []
      });
    }

    const hasActuacion =
      row.nombreTipoEtapa != null ||
      row.nombreSubEtapa != null ||
      row.fecActuacion != null ||
      row.observacionP1 != null;

    if (!hasActuacion) continue;

    byId.get(idExpediente).actuaciones.push({
      nombreTipoEtapa: toNullableString(row.nombreTipoEtapa),
      nombreSubEtapa: toNullableString(row.nombreSubEtapa),
      fecActuacion: toNullableString(row.fecActuacion),
      observacionP1: toNullableString(row.observacionP1)
    });
  }

  const expedientes = Array.from(byId.values());
  const cedulas = sanitizeCedulas(expedientes.map((item) => item.demandado1Documento));
  return { expedientes, cedulas };
}

async function resolveSqlText({ queryFilePath }) {
  const filePath = String(queryFilePath || "").trim();
  if (!filePath) {
    throw new Error("Falta query SQL. Define ICS_DB_QUERY_FILE_PATH.");
  }

  try {
    return String(await fs.readFile(filePath, "utf8") || "").trim();
  } catch (error) {
    throw new Error(`No se pudo leer el archivo SQL: ${filePath}`, { cause: error });
  }
}

async function fetchExpedientesFromSqlServer({
  connectionString,
  queryFilePath,
  commandTimeoutSec = 30,
  fecha,
  demandante
}) {
  if (!connectionString) {
    throw new Error("Falta ICS_DB_CONNECTION_STRING para consultar expedientes.");
  }

  const sqlText = await resolveSqlText({ queryFilePath });
  let pool = null;

  try {
    pool = await new sql.ConnectionPool(connectionString).connect();
    const request = pool.request();
    request.timeout = Math.max(5000, Number(commandTimeoutSec || 30) * 1000);
    bindQueryParams(request, { fecha, demandante });

    const data = await request.query(sqlText);
    const { expedientes, cedulas } = buildExpedientesFromRecordset(data.recordset || []);

    return {
      source: "sqlserver",
      count: cedulas.length,
      cedulas,
      expedientes
    };
  } catch (error) {
    throw new Error("No se pudieron cargar expedientes desde SQL Server.", {
      cause: error
    });
  } finally {
    if (pool) {
      await pool.close().catch(() => {});
    }
  }
}

module.exports = {
  fetchExpedientesFromSqlServer
};
