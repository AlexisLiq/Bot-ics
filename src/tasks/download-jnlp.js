const fs = require("node:fs/promises");
const path = require("node:path");
const { config } = require("../config/config");
const { runWithSavedSession } = require("./session");

function isLoginUrl(url) {
  return /login\.xhtml/i.test(url || "");
}

async function ensureParentDir(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
}

//Extraemos información relevante del contenido del JNLP para debug
function extractJnlpSummary(xmlText) {
  const pick = (regex) => xmlText.match(regex)?.[1] || ""; 

  return {
    title: pick(/<title>([^<]+)<\/title>/i),
    codebase: pick(/<jnlp[^>]*codebase="([^"]+)"/i),
    mainJar: pick(/<jar[^>]*href="([^"]+)"/i),
    server: pick(/<property\s+name="jnlp\.ics\.client\.server"\s+value="([^"]+)"/i),
    port: pick(/<property\s+name="jnlp\.ics\.client\.port"\s+value="([^"]+)"/i),
    execFile: pick(/<property\s+name="jnlp\.ics\.client\.execFile"\s+value="([^"]+)"/i),
    requiresAllPermissions: /<all-permissions\s*\/>/i.test(xmlText),
    hasExecArgsToken: /<property\s+name="jnlp\.ics\.client\.execArgs"\s+value="[^"]+"/i.test(xmlText)
  };
}

//Función principal
async function runDownloadJnlpTask() {
  return runWithSavedSession(async ({ page }) => {
    console.log("Abriendo ICSLight con sesion guardada...");
    await page.goto(config.targetUrl, { // Navegamos a la ventana donde se descarga el jnlp
      waitUntil: "domcontentloaded",
      timeout: config.loginTimeoutMs
    });

    if (isLoginUrl(page.url())) { 
      throw new Error(
        "La sesión guardada expiró y redirigió al login. Regenerar la sesión con npm run login..."
      );
    }
    
    const launchLink = page.getByRole("link", { name: config.icsLaunchLinkText }); // Definimos el link de descarga
    try {
      await launchLink.waitFor({ state: "visible", timeout: 10000 });
    } catch (error) {
      if (isLoginUrl(page.url())) {
        throw new Error(
          "La sesión guardada expiró y redirigió al login. Regenerar la sesión con npm run login."
        );
      }
      throw error;
    }

    const [download] = await Promise.all([ 
      page.waitForEvent("download", { timeout: 30000 }),
      launchLink.click()
    ]);

    await ensureParentDir(config.jnlpOutputPath);
    await download.saveAs(config.jnlpOutputPath);

    const jnlpContent = await fs.readFile(config.jnlpOutputPath, "utf8");
    const summary = extractJnlpSummary(jnlpContent);

    return {
      finalUrl: page.url(),
      suggestedFilename: download.suggestedFilename(),
      outputPath: config.jnlpOutputPath,
      summary
    };
  });
}

module.exports = { runDownloadJnlpTask };
