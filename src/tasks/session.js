const fs = require("node:fs/promises");
const { chromium } = require("playwright");
const { config } = require("../config/config");


async function assertSessionFileExists() {
  try {
    await fs.access(config.sessionStatePath);
  } catch (error) {
    throw new Error(
      `No existe la sesión guardada en ${config.sessionStatePath}.`,
      { cause: error }
    );
  }
}

//Función genérica para ejecutar tareas que requieren una sesión guardada
async function runWithSavedSession(task) {
  await assertSessionFileExists();

  const browser = await chromium.launch({
    headless: config.headless, 
  });

  //Cargamos el browser.context de la sesión guardada previamente y que no haya vencido aún
  const context = await browser.newContext({
    ignoreHTTPSErrors: true, // Por si el sitio tiene certificados autofirmados o raros, 
    storageState: config.sessionStatePath // Carga la sesión guardada (cookies principalmente guardadas en session.json)
  });

  const page = await context.newPage();

  try {
    return await task({ browser, context, page }); //Ejecutamos la tarea asincrónica pasada como argumento
  } finally {
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
  }
}

module.exports = { runWithSavedSession };
