const fs = require("node:fs/promises");
const path = require("node:path");
const { config } = require("../config/config");
const { startSelectLegalTabWithWin32 } = require("../windows/ics-legal-selector-win32");

async function persistLegalDebugSnapshot({ window, controls, summary }) {
  try {
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const uniquePath = path.resolve(process.cwd(), "storage", `legal-selector-debug-${stamp}.json`);
    const lastPath = path.resolve(process.cwd(), "storage", "legal-selector-debug-last.json");
    const payload = {
      timestamp: new Date().toISOString(),
      window,
      controls,
      summary
    };
    await fs.mkdir(path.dirname(lastPath), { recursive: true });
    const text = `${JSON.stringify(payload, null, 2)}\n`;
    await fs.writeFile(uniquePath, text, "utf8");
    await fs.writeFile(lastPath, text, "utf8");
    return uniquePath;
  } catch {
    return null;
  }
}

function buildAttemptTail(summary) {
  const trace = Array.isArray(summary?.debug?.attemptTrace)
    ? summary.debug.attemptTrace
    : [];

  if (trace.length === 0) return "n/a";

  return trace
    .slice(-8)
    .map((row) => {
      const phase = row?.phase || "p";
      const mode = row?.mode || "m";
      const before = row?.activeBefore || "?";
      const after = row?.activeAfter || "?";
      const ok = row?.confirmed ? "1" : "0";
      const target = row?.targetHwnd || "0";
      return `${phase}/${mode}[${target}] ${before}->${after} ok=${ok}`;
    })
    .join(" | ");
}

async function runSelectLegalTabTask({ window, controls } = {}) {
  const runner = startSelectLegalTabWithWin32({
    mainWindowHwnd: window?.hwnd,
    legalTabHwnd: controls?.legalTab?.hwnd,
    identificationInputHwnd: controls?.identificationInput?.hwnd,
    buscarButtonHwnd: controls?.buscarButton?.hwnd,
    stepDelayMs: config.icsGestionarStepDelayMs,
    panelWaitMs: config.icsLegalPanelWaitMs,
    pollMs: config.icsLegalPanelPollMs
  });

  const result = await runner.result;

  if (!result.summary) {
    throw new Error("No se pudo leer la respuesta al seleccionar la pestana Legal.");
  }

  if (!result.summary.ok) {
    const s = result.summary || {};
    const debugPath = await persistLegalDebugSnapshot({ window, controls, summary: s });
    const attemptTail = buildAttemptTail(s);
    const pages = Array.isArray(s?.debug?.orderedPages) ? s.debug.orderedPages : [];
    const pagesVisible = pages.filter((p) => p?.visible).map((p) => p?.title).filter(Boolean);
    const directCandidates = Array.isArray(s?.debug?.directLegalClickCandidates)
      ? s.debug.directLegalClickCandidates.length
      : 0;
    const tabCandidates = Array.isArray(s?.debug?.tabCandidates)
      ? s.debug.tabCandidates.length
      : Number(s.realTabCandidates || 0);
    const detail =
      `method=${s.method || "n/a"} ` +
      `mode=${s.realClickMode || "n/a"} ` +
      `attempts=${Number(s.realClickAttempts || 0)} ` +
      `active=${s.activePageBefore || "n/a"}->${s.activePageAfter || "n/a"} ` +
      `fallback=${s.fallbackReason || "none"} ` +
      `cands(tab=${tabCandidates},direct=${directCandidates}) ` +
      `visiblePages=${pagesVisible.join(",") || "n/a"} ` +
      `tail=${attemptTail}` +
      (debugPath ? ` debugFile=${debugPath}` : "");
    throw new Error(
      `${result.summary.error || "No se pudo activar la pestana Legal en Gestionar."} (${detail})`
    );
  }

  return result.summary;
}

module.exports = { runSelectLegalTabTask };
