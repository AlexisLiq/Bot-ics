const dotenv = require("dotenv");
const path = require("node:path");
const { resolvePathSelectorConfig } = require("./paths-selectors");
const { parseBoolean, parseIntOr, parseList, required } = require("./config-helpers");

dotenv.config();

const config = {
  // ------------------------------------------------------------
  // Base del proyecto (credenciales, URLs, runtime general)
  // ------------------------------------------------------------
  loginUrl: required("ICS_LOGIN_URL"),
  targetUrl: required("ICS_TARGET_URL"),
  username: required("ICS_USERNAME"),
  password: required("ICS_PASSWORD"),
  headless: parseBoolean(process.env.HEADLESS, false),
  slowMoMs: parseIntOr(process.env.SLOW_MO_MS, 0),

  // Timeout base para TODO script PowerShell lanzado desde Node.
  // Si un script envia su propio TimeoutMs, el wrapper usa el mayor.
  icsPowerShellTimeoutMs: parseIntOr(process.env.ICS_POWERSHELL_TIMEOUT_MS, 15000),

  // ------------------------------------------------------------
  // Paso 1/7 - Login + descarga JNLP
  // ------------------------------------------------------------
  icsLaunchLinkText: process.env.ICS_LAUNCH_LINK_TEXT || "ics-mobile.mibanco.com.co",
  loginTimeoutMs: parseIntOr(process.env.LOGIN_TIMEOUT_MS, 30000),

  // ------------------------------------------------------------
  // Paso 2/7 - Lanzar JNLP + manejo de modales Java
  // ------------------------------------------------------------
  jnlpLauncher: process.env.ICS_JNLP_LAUNCHER || "javaws",
  jnlpLaunchTimeoutMs: parseIntOr(process.env.ICS_JNLP_LAUNCH_TIMEOUT_MS, 30000),
  handleJavaModals: parseBoolean(process.env.ICS_HANDLE_JAVA_MODALS, true),
  debugJavaModalLogs: parseBoolean(process.env.ICS_DEBUG_JAVA_MODAL_LOGS, false),
  javaModalWatchTimeoutMs: parseIntOr(process.env.ICS_JAVA_MODAL_WATCH_TIMEOUT_MS, 15000),
  javaModalPollMs: parseIntOr(process.env.ICS_JAVA_MODAL_POLL_MS, 250),

  // ------------------------------------------------------------
  // Paso 3/7 - Esperar que ICS termine de inicializar
  // ------------------------------------------------------------
  icsMainWindowTitleHint: process.env.ICS_MAIN_WINDOW_TITLE_HINT || "Internet Collection System",
  icsMainWindowTimeoutMs: parseIntOr(process.env.ICS_MAIN_WINDOW_TIMEOUT_MS, 60000),
  icsMainWindowPollMs: parseIntOr(process.env.ICS_MAIN_WINDOW_POLL_MS, 200),
  icsStartupReadyTimeoutMs: parseIntOr(process.env.ICS_STARTUP_READY_TIMEOUT_MS, 120000),
  icsStartupReadyPollMs: parseIntOr(process.env.ICS_STARTUP_READY_POLL_MS, 120),
  icsStartupReadyStablePolls: parseIntOr(process.env.ICS_STARTUP_READY_STABLE_POLLS, 2),

  // ------------------------------------------------------------
  // Paso 4/7 - Cargar expedientes desde SQL Server
  // ------------------------------------------------------------
  cedulasDbConnectionString: required("ICS_DB_CONNECTION_STRING"),
  cedulasDbCommandTimeoutSec: parseIntOr(process.env.ICS_DB_COMMAND_TIMEOUT_SEC, 30),
  cedulasDbQueryFilePath: path.resolve(
    process.cwd(),
    process.env.ICS_DB_QUERY_FILE_PATH || "src/database/sql/expedientes-routeB.sql"
  ),
  expedientesJsonPath: path.resolve(
    process.cwd(),
    process.env.ICS_EXPEDIENTES_JSON_PATH || "src/database/json/expedientes.json"
  ),

  // ------------------------------------------------------------
  // Paso 5/7 - Procesar lote dentro de Gestionar
  // ------------------------------------------------------------
  // 5.a) Abrir Gestion -> Gestionar
  icsGestionarOpenTimeoutMs: parseIntOr(process.env.ICS_GESTIONAR_OPEN_TIMEOUT_MS, 60000),
  icsGestionarOpenPollMs: parseIntOr(process.env.ICS_GESTIONAR_OPEN_POLL_MS, 80),
  icsGestionarCommandId: parseIntOr(process.env.ICS_GESTIONAR_COMMAND_ID, 10057),

  // 5.b) Cedula -> Buscar
  icsGestionarStepDelayMs: parseIntOr(process.env.ICS_GESTIONAR_STEP_DELAY_MS, 220),
  icsOperateGestionarTimeoutMs: parseIntOr(process.env.ICS_OPERATE_GESTIONAR_TIMEOUT_MS, 45000),

  // 5.c) Buscar -> Legal
  icsBeforeLegalDelayMs: parseIntOr(process.env.ICS_BEFORE_LEGAL_DELAY_MS, 500), // usado dentro de operate-ics-gestionar.ps1
  icsBuscarToLegalDelayMs: parseIntOr(process.env.ICS_BUSCAR_TO_LEGAL_DELAY_MS, 80), // usado en client-launch.js
  icsLegalSelectAttempts: parseIntOr(process.env.ICS_LEGAL_SELECT_ATTEMPTS, 2),
  icsLegalPanelWaitMs: parseIntOr(process.env.ICS_LEGAL_PANEL_WAIT_MS, 1200),
  icsLegalPanelPollMs: parseIntOr(process.env.ICS_LEGAL_PANEL_POLL_MS, 80),

  // 5.d) Validacion post-busqueda / salida del formulario Gestionar
  icsPostSearchTimeoutMs: parseIntOr(process.env.ICS_POST_SEARCH_TIMEOUT_MS, 30000),
  icsArchivoSalirCommandId: parseIntOr(process.env.ICS_ARCHIVO_SALIR_COMMAND_ID, 57665),
  icsExitGestionarTimeoutMs: parseIntOr(process.env.ICS_EXIT_GESTIONAR_TIMEOUT_MS, 12000),

  // 5.e) Ritmo entre expedientes / acciones
  icsIterationPreDelayMs: parseIntOr(process.env.ICS_ITERATION_PRE_DELAY_MS, 2500),
  icsIterationGapMs: parseIntOr(process.env.ICS_ITERATION_GAP_MS, 5000),
  icsPostActionDelayMs: parseIntOr(process.env.ICS_POST_ACTION_DELAY_MS, 2500),
  icsAfterLegalDelayMs: parseIntOr(process.env.ICS_AFTER_LEGAL_DELAY_MS, 12000),

  // ------------------------------------------------------------
  // Paso 6/7 - Cerrar aplicativo ICS
  // ------------------------------------------------------------gue 
  icsCloseAppTimeoutMs: parseIntOr(process.env.ICS_CLOSE_APP_TIMEOUT_MS, 5000),

  // ------------------------------------------------------------
  // Debug opcional (enfocado a pestaña Legal)
  // ------------------------------------------------------------
  icsDebugLegalPanel: parseBoolean(process.env.ICS_DEBUG_LEGAL_PANEL, false),
  icsDebugLegalPanelSampleLimit: parseIntOr(process.env.ICS_DEBUG_LEGAL_PANEL_SAMPLE_LIMIT, 10),
  icsDebugLegalPanelMaxNodes: parseIntOr(process.env.ICS_DEBUG_LEGAL_PANEL_MAX_NODES, 1200),
  icsDebugLegalInspectorTimeoutMs: parseIntOr(process.env.ICS_DEBUG_LEGAL_INSPECTOR_TIMEOUT_MS, 20000),

  // ------------------------------------------------------------
  // Selectores (no son tiempos, pero forman parte de la config)
  // ------------------------------------------------------------
  ...resolvePathSelectorConfig(process.env, process.cwd()),

  // ------------------------------------------------------------
  // Pistas de procesos cliente (deteccion de procesos Java/ICS)
  // ------------------------------------------------------------
  clientProcessHints: parseList(process.env.ICS_CLIENT_PROCESS_HINTS, [
    "ics_client",
    "jp2launcher",
    "javaws",
    "javaw",
    "java"
  ])
};

module.exports = { config };
