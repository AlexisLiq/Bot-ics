const fs = require("node:fs/promises");
const path = require("node:path");
const { chromium } = require("playwright");
const { config } = require("../config/config");

async function ensureParentDir(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive:true });
}

async function tryFill(page, selectors, value, fieldLabel, timeoutMs) {
  let lastError;

  for (const selector of selectors) {
    try {
      const locator = page.locator(selector).first();
      await locator.waitFor({ state: "visible", timeout: 2500 });
      await locator.fill(value, { timeout: timeoutMs });
      return selector;
    } catch (error) {
      lastError = error;
    }
  }

  throw new Error(
    `No se encontro el campo "${fieldLabel}".`,
    { cause: lastError }
  );
}

async function tryClick(page, selectors, timeoutMs) {
  let lastError;

  for (const selector of selectors) {
    try {
      const locator = page.locator(selector).first();
      await locator.waitFor({ state: "visible", timeout: 2500 });
      await locator.click({ timeout: timeoutMs });
      return selector;
    } catch (error) {
      lastError = error;
    }
  }

  throw new Error("No se encontro el boton de login.", {
    cause: lastError
  });
}

async function waitForAuthenticatedRedirect(page, timeoutMs) {
  try {
    await page.waitForURL((url) => !/login\.xhtml/i.test(String(url)), {
      timeout: timeoutMs
    });
  } catch (error) {
    throw new Error(
      "No se detecto redireccion post-login dentro del tiempo esperado. Verifica credenciales o bloqueo del formulario.",
      { cause: error }
    );
  }
}

// En caso de error, guardar un screenshot para ayudar a diagnosticar el problema.
async function saveDebugScreenshot(page) {
  try {
    const screenshotPath = path.resolve(process.cwd(), "storage/last-error.png");
    await ensureParentDir(screenshotPath);
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.error(`Screenshot de error guardado en: ${screenshotPath}`);
  } catch {
  }
}

//Flujo Principal de Login:
async function runLoginFlow() {

  const browser = await chromium.launch({
    headless: config.headless,
    slowMo: config.slowMoMs
  });

  const context = await browser.newContext({
    ignoreHTTPSErrors: true
  });

  const page = await context.newPage();

  try {
    console.log("Abriendo pagina de login...");
    await page.goto(config.loginUrl, {
      waitUntil: "domcontentloaded",
      timeout: config.loginTimeoutMs
    });

    await tryFill(
      page,
      config.usernameSelectors,
      config.username,
      "usuario",
      config.loginTimeoutMs
    );
    await tryFill(
      page,
      config.passwordSelectors,
      config.password,
      "password",
      config.loginTimeoutMs
    );
    await tryClick(
      page,
      config.submitSelectors,
      config.loginTimeoutMs
    );

    // Esperamos que salgamos de la ventana de login para confirmar que ya ingresamos
    await waitForAuthenticatedRedirect(page, config.loginTimeoutMs);
    await page.waitForLoadState("domcontentloaded", { timeout: 5000 }).catch(() => {});

    if (/login\.xhtml/i.test(page.url())) {
      throw new Error("La sesión no quedó autenticada: se mantuvo en la pantalla de login.");
    }

    // Guardamos el estado de la sesión para usarlo en futuras ejecuciones y no tener que estar loggeando en cada momento
    await ensureParentDir(config.sessionStatePath);
    await context.storageState({ path: config.sessionStatePath });

    return {
      finalUrl: page.url(),
      sessionStatePath: config.sessionStatePath,
    };
  } catch (error) {
    await saveDebugScreenshot(page); //En caso de error, guardamos el error con un ss
    throw error;
  } finally {
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
  }
}

module.exports = { runLoginFlow };
