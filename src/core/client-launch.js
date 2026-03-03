const { runDownloadJnlpTask } = require("../tasks/download-jnlp");
const { runJnlpTask } = require("../tasks/run-jnlp");
const { runWaitIcsReadyTask } = require("../tasks/wait-ics-ready");
const { runLoadCedulasTask } = require("../tasks/load-cedulas");
const { runOpenGestionarMenuTask } = require("../tasks/open-gestionar-menu");
const { runIdentifyGestionarControlsTask } = require("../tasks/identify-gestionar-controls");
const { runExecuteGestionarSearchTask } = require("../tasks/execute-gestionar-search");
const { runSelectLegalTabTask } = require("../tasks/select-legal-tab");
const { runInspectLegalPanelTask } = require("../tasks/inspect-legal-panel");
const { runPostSearchGestionarTask } = require("../tasks/post-search-gestionar");
const { runExitGestionarTask } = require("../tasks/exit-gestionar");
const { runCloseIcsAppTask } = require("../tasks/close-ics-app");
const { config } = require("../config/config");

function getCliArg(name) {
  const args = process.argv.slice(2);
  const pref = `--${name}=`;
  const inline = args.find((arg) => arg.startsWith(pref));
  if (inline) {
    return inline.slice(pref.length).trim();
  }

  const idx = args.findIndex((arg) => arg === `--${name}`);
  if (idx >= 0 && args[idx + 1]) {
    return String(args[idx + 1]).trim();
  }

  return "";
}

function validateBeforeMenuStep(launchResult) {
  const modal = launchResult.javaModalHandling?.summary;

  if (modal?.runPromptSeen && !modal.runPromptHandled) {
    throw new Error(
      "Se detecto un modal de seguridad de Java, pero no se pudo manejar automaticamente."
    );
  }

  if (launchResult.validation?.status === "not_detected") {
    throw new Error("No se detecto el aplicativo ICS despues de ejecutar el JNLP.");
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForIcsSettle(stageLabel) {
  try {
    await runWaitIcsReadyTask();
    if (config.icsPostActionDelayMs > 0) {
      await sleep(config.icsPostActionDelayMs);
    }
  } catch (error) {
    throw new Error(
      `ICS no se estabilizo despues de ${stageLabel}.`,
      { cause: error }
    );
  }
}

async function waitFastActionDelay(ms) {
  const delay = Number(ms) || 0;
  if (delay > 0) {
    await sleep(delay);
  }
}

async function main() {
  console.log("Paso 1/7: JNLP...");
  const downloadResult = await runDownloadJnlpTask();
  console.log(`JNLP: ${downloadResult.outputPath}`);

  console.log("\nPaso 2/7: lanzar cliente...");
  const launchResult = await runJnlpTask({ jnlpPath: downloadResult.outputPath });
  validateBeforeMenuStep(launchResult);

  console.log("\nPaso 3/7: esperar inicio estable...");
  const startupReady = await runWaitIcsReadyTask();
  if (startupReady.waitedMs > 0) {
    console.log(`Listo (${startupReady.waitedMs} ms).`);
  }

  console.log("\nPaso 4/7: cargar expedientes...");
  const fechaCli = getCliArg("fecha");
  const demandanteCli = getCliArg("demandante");
  const batch = await runLoadCedulasTask({
    fecha: fechaCli || undefined,
    demandante: demandanteCli || undefined
  });
  const expedientes = batch.expedientes;

  if (expedientes.length === 0) {
    throw new Error("No hay expedientes para procesar.");
  }

  console.log(
    `Expedientes: ${expedientes.length} | Cedulas unicas: ${batch.cedulas.length}.`
  );

  console.log("\nPaso 5/7: procesar lote...");
  const batchResults = [];

  for (let index = 0; index < expedientes.length; index += 1) {
    if (config.icsIterationPreDelayMs > 0) {
      await sleep(config.icsIterationPreDelayMs);
    }

    const expediente = expedientes[index];
    const cedula = expediente.demandado1Documento;
    const actuaciones = expediente.actuaciones;

    const itemResult = {
      cedula,
      expediente: expediente.expediente || expediente.idExpediente || null,
      actuacionesCount: actuaciones.length,
      ok: true,
      execute: null,
      legal: null,
      postSearch: null,
      error: null
    };

    process.stdout.write(
      `\n[${index + 1}/${expedientes.length}] ${cedula} (${actuaciones.length} act.) ... `
    );

    let gestionarWindowHwnd = null;

    try {
      await runOpenGestionarMenuTask();
      await waitForIcsSettle("abrir Gestionar");
      const controls = await runIdentifyGestionarControlsTask();
      const gestionarTitle = String(controls?.window?.title || "").toLowerCase();
      if (gestionarTitle.includes("informacion del deudor") || gestionarTitle === "deudor") {
        gestionarWindowHwnd = controls?.window?.hwnd || null;
      }

      const executeSummary = await runExecuteGestionarSearchTask({
        window: controls.window,
        controls: controls.controls,
        cedula
      });
      itemResult.execute = executeSummary;

      let legalDebugBefore = null;
      let legalDebugBeforeError = null;
      if (config.icsDebugLegalPanel) {
        try {
          legalDebugBefore = await runInspectLegalPanelTask({ window: controls.window });
        } catch (error) {
          legalDebugBefore = null;
          legalDebugBeforeError = error?.message || String(error);
        }
      }

      await waitFastActionDelay(config.icsBuscarToLegalDelayMs);

      const legalAttempts = Math.max(1, Number(config.icsLegalSelectAttempts) || 1);
      let legalSummary = null;
      let legalContext = controls;
      let lastLegalError = null;

      for (let attempt = 1; attempt <= legalAttempts; attempt += 1) {
        if (attempt > 1) {
          await waitForIcsSettle(`reintento Legal #${attempt}`);
          legalContext = await runIdentifyGestionarControlsTask();
        }

        try {
          legalSummary = await runSelectLegalTabTask({
            window: legalContext.window,
            controls: legalContext.controls
          });
          break;
        } catch (legalError) {
          lastLegalError = legalError;
        }
      }

      if (!legalSummary) {
        throw lastLegalError || new Error("No se pudo seleccionar la pestana Legal.");
      }

      itemResult.legal = legalSummary;
      await waitFastActionDelay(config.icsAfterLegalDelayMs);

      let legalDebugAfter = null;
      let legalDebugAfterError = null;
      if (config.icsDebugLegalPanel) {
        try {
          legalDebugAfter = await runInspectLegalPanelTask({ window: legalContext.window });
        } catch (error) {
          legalDebugAfter = null;
          legalDebugAfterError = error?.message || String(error);
        }
      }

      const postSearch = await runPostSearchGestionarTask({
        window: legalContext.window
      });
      itemResult.postSearch = postSearch;

      if (postSearch.errorModalSeen) process.stdout.write("OK (modal-error cerrado)");
      else process.stdout.write("OK (sin modal error)");

      if (legalSummary) {
        const selected = legalSummary.selected ? "si" : "no";
        process.stdout.write(` | Legal selected=${selected}`);
      }

      if (config.icsDebugLegalPanel && legalSummary) {
        const realClick = legalSummary.realClickTried
          ? (legalSummary.realClickHit ? "si" : "no")
          : "na";
        process.stdout.write(
          ` | dbg legal method=${legalSummary.method || "n/a"} realClick=${realClick} realMode=${legalSummary.realClickMode || "n/a"} attempts=${Number(legalSummary.realClickAttempts || 0)} candidates=${Number(legalSummary.realTabCandidates || 0)} tabUsed=${legalSummary.realTabHandleUsed || "n/a"} fallback=${legalSummary.fallbackReason || "none"} active=${legalSummary.activePageBefore || "n/a"}->${legalSummary.activePageAfter || "n/a"} handles(main=${legalSummary.mainWindowUsed || "n/a"},legal=${legalSummary.legalHandleUsed || "n/a"},deudor=${legalSummary.deudorHandleUsed || "n/a"})`
        );
      }

      if (config.icsDebugLegalPanel && legalDebugAfter) {
        const prePage = legalDebugBefore?.selectedPageTitle || "n/a";
        const postPage = legalDebugAfter?.selectedPageTitle || "n/a";
        const preText = Number(legalDebugBefore?.legalPanel?.visibleTextCount || 0);
        const postText = Number(legalDebugAfter?.legalPanel?.visibleTextCount || 0);
        const prePbdw = Number(legalDebugBefore?.legalPanel?.visiblePbdwCount || 0);
        const postPbdw = Number(legalDebugAfter?.legalPanel?.visiblePbdwCount || 0);
        const selectedSaysYes = !!legalSummary?.selected;
        const inspectorSaysLegal = String(postPage || "").toLowerCase().includes("legal");

        process.stdout.write(
          ` | dbg page:${prePage}->${postPage} legalText:${preText}->${postText} legalPbdw:${prePbdw}->${postPbdw}`
        );

        if (selectedSaysYes !== inspectorSaysLegal) {
          process.stdout.write(
            ` | dbg mismatch(selected=${selectedSaysYes ? "si" : "no"}, inspectorLegal=${inspectorSaysLegal ? "si" : "no"})`
          );
        }
      }

      if (config.icsDebugLegalPanel && (legalDebugBeforeError || legalDebugAfterError)) {
        const parts = [];
        if (legalDebugBeforeError) parts.push(`before:${legalDebugBeforeError}`);
        if (legalDebugAfterError) parts.push(`after:${legalDebugAfterError}`);
        process.stdout.write(` | dbg inspectErr=${parts.join(" ; ")}`);
      }

      if (config.icsDebugLegalPanel) {
        itemResult.legalDebug = {
          before: legalDebugBefore,
          after: legalDebugAfter,
          beforeError: legalDebugBeforeError,
          afterError: legalDebugAfterError
        };
      }
    } catch (error) {
      itemResult.ok = false;
      itemResult.error = error.message || String(error);
      process.stdout.write(`ERROR (${itemResult.error})`);
    }

    try {
      await runExitGestionarTask({ gestionarWindowHwnd });
      await waitForIcsSettle("Archivo -> Salir");
    } catch (exitError) {
      itemResult.ok = false;
      const exitText = exitError.message || String(exitError);
      itemResult.error = itemResult.error ? `${itemResult.error} | ${exitText}` : exitText;
      process.stdout.write(` | ERROR salida (${exitText})`);
    }

    batchResults.push(itemResult);

    if (index < expedientes.length - 1 && config.icsIterationGapMs > 0) {
      await sleep(config.icsIterationGapMs);
    }
  }

  console.log("\n\nPaso 6/7: cerrar aplicativo...");
  await runCloseIcsAppTask();

  console.log("\nPaso 7/7: resumen...");
  const failed = batchResults.filter((item) => !item.ok);
  console.log(`Procesados: ${batchResults.length}. Fallidos: ${failed.length}.`);

  if (failed.length > 0) {
    const detail = failed
      .map((item) => `${item.cedula}: ${item.error || "sin detalle"}`)
      .join(" | ");
    throw new Error(`Fallaron ${failed.length} expedientes. Detalle: ${detail}`);
  }

  console.log("\nFlujo completado.");
}

main().catch((error) => {
  console.error("\nError en run-ICS:");
  console.error(error.message || String(error));
  if (error.cause) {
    console.error("Causa:", error.cause.message || error.cause);
  }
  process.exitCode = 1;
});
